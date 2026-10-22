"""app.qml_backend.vm.monetize_vm - YouTube Hunter (QML).

ViewModel behind MonetizePage.qml — the migrated Monetize Checker.

Given a channel URL / @handle / name it resolves the channel, decides whether
it is monetized (MONETIZED / NOT_MONETIZED, with a certainty score and an
evidence checklist), estimates its RPM/CPM band by niche + audience market, and
projects daily / monthly / yearly ad revenue.

All the heavy lifting is the shared, UI-free core: app.core.monetization scrapes
YouTube's public pages for the hard Partner-Program-only signals,
app.core.rpm models the RPM tables, app.core.youtube_api handles resolution and
the Data API call. This VM re-homes the algorithm that the legacy
MonetizePageMixin ran inline (minus the QtWidgets rendering) and drives it from a
worker thread, reporting back over a queued Qt signal — same worker→GUI pattern
as the other VMs.
"""

import threading
import traceback

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.config import load_app_config
from app.core.monetization import (check_channel_page_signals,
                                   check_video_monetization_signal)
from app.core.niche.helpers import SHORT_MAX_SECONDS
from app.core.rpm import SHORTS_LONG_VALUE_RATIO
from app.core.rpm import detect_channel_niche, estimate_rpm
from app.core.rpm import earnings_range, money_compact
from app.core.utils import (days_since, hours_since, humanize_count,
                            parse_iso8601_duration)
from app.core.youtube_api import build_youtube_service, resolve_channel_id
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.desktop_notifier import announce

# format-mode index (segmented control) → the string the algorithm expects
_FMT_MODES = {0: "auto", 1: "long", 2: "short"}

# revenue tiers, low→high, so the page can render them in a fixed order
_REV_TIERS = ("low", "mid", "high")

# What each tier actually means. Spelled out because "LOW / MID / HIGH" alone
# reads as a confidence interval, which it is not — these are three RPM points
# from the niche's published band, and the spread between them is the honest
# uncertainty in what advertisers pay for this audience.
_TIER_LABELS = {
    "low": "Conservative",
    "mid": "Likely",
    "high": "Optimistic",
}
_TIER_NOTES = {
    "low": "Bottom of this niche's RPM band",
    "mid": "Middle of the band — the figure to plan against",
    "high": "Top of the band, in a good ad season",
}


def _money(v):
    """A revenue figure as a compact $ string: $2.40 / $1.2K / $340K / $1.4M."""
    if v is None:
        return "$0"
    v = float(v)
    if v < 100:
        return f"${v:.2f}"
    if v < 1_000:
        return f"${v:.0f}"
    if v < 1_000_000:
        return f"${v / 1_000:.1f}K"
    return f"${v / 1_000_000:.2f}M"


class MonetizeVM(QObject):
    """Monetization checker for the QML page."""

    changed = Signal()            # form / status
    busyChanged = Signal()
    resultChanged = Signal()      # a fresh result (or cleared)
    toast = Signal(str, str)      # (message, kind)

    @Slot()
    def retranslate(self):
        """UI language changed — re-render the result in the new language.

        Re-emitting alone is NOT enough: the verdict, the checklist and the
        revenue labels are translated strings baked into `_result` when the
        check ran, so a signal just re-delivers the old language. The raw inputs
        are cached (`_ctx`, no translated text in it) and the result is rebuilt
        from them — no network, no re-scrape.
        """
        if self._ctx:
            self._result = self._assemble(self._ctx)
        self.changed.emit()
        self.resultChanged.emit()

    # worker → GUI bridge (auto-queued across threads)
    _done = Signal("QVariant", str)   # (data_or_None, error)
    # Which step the worker is on, so the loader can show REAL progress
    # instead of a loop. 0 resolve · 1 channel + uploads · 2 signal scrape ·
    # 3 pricing. Emitted from the worker thread, delivered queued.
    _stage_sig = Signal(int)
    stageChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        cfg = load_app_config()
        self._api_key = cfg.get("api_key", "") or ""
        self._query = ""
        self._format_mode = 0       # 0 auto, 1 long, 2 short
        self._busy = False
        self._status = tr("Paste a channel URL, @handle or name and press Check.")
        self._status_kind = "muted"
        self._result = {}           # flattened dict for QML, or {}
        # Raw inputs behind `_result`, with no translated text in them, so the
        # result can be re-rendered in another language (see retranslate).
        self._ctx = None
        self._stage = 0
        self._done.connect(self._on_done)
        self._stage_sig.connect(self._on_stage)

    # ── form properties ──────────────────────────────────────────────────
    @Property(str, notify=changed)
    def query(self):
        return self._query

    @query.setter
    def query(self, v):
        if v != self._query:
            self._query = v
            self.changed.emit()

    @Property(int, notify=changed)
    def formatMode(self):
        return self._format_mode

    @formatMode.setter
    def formatMode(self, i):
        i = max(0, min(2, int(i)))
        if i != self._format_mode:
            self._format_mode = i
            self.changed.emit()

    @Property(bool, notify=busyChanged)
    def busy(self):
        return self._busy

    @Property(int, notify=stageChanged)
    def stage(self):
        """0..3 — the pipeline step a running check is on (see _stage_sig)."""
        return self._stage

    @Slot(int)
    def _on_stage(self, n):
        n = max(0, min(3, int(n)))
        if n != self._stage:
            self._stage = n
            self.stageChanged.emit()

    @Property(str, notify=changed)
    def status(self):
        return self._status

    @Property(str, notify=changed)
    def statusKind(self):
        return self._status_kind

    @Property(bool, notify=changed)
    def hasKey(self):
        return bool((self._api_key or "").strip())

    # ── result properties ────────────────────────────────────────────────
    @Property(bool, notify=resultChanged)
    def hasResult(self):
        return bool(self._result)

    @Property("QVariantMap", notify=resultChanged)
    def result(self):
        """Flattened result for QML: profile, verdict, checks, revenue, rpm."""
        return self._result

    # ── actions ──────────────────────────────────────────────────────────
    @Slot()
    def reloadKey(self):
        """Re-read the API key from config (it may have changed on Settings)."""
        cfg = load_app_config()
        self._api_key = cfg.get("api_key", "") or ""
        self.changed.emit()

    def _set_status(self, text, kind="muted"):
        self._status = text
        self._status_kind = kind
        self.changed.emit()

    def _set_busy(self, busy):
        if busy != self._busy:
            self._busy = busy
            self.busyChanged.emit()

    @Slot()
    def check(self):
        # The key is cached at construction; Settings saves to config.json while
        # the app runs, so re-read it here — otherwise the first check after
        # saving a key still sees the old (empty) value until a restart.
        self.reloadKey()
        text = (self._query or "").strip()
        if not text:
            self._set_status(tr("Enter a channel URL, @handle or name first."), "error")
            return
        if not (self._api_key or "").strip():
            self._set_status(
                tr("Add a YouTube API key in Settings first."), "error")
            self.toast.emit(tr("No YouTube API key — set one in Settings."), "error")
            return
        self._on_stage(0)
        self._set_busy(True)
        self._set_status(tr("Resolving channel…"))
        mode = _FMT_MODES.get(self._format_mode, "auto")

        def worker(_text=text, _mode=mode):
            try:
                data = self._compute(_text, _mode)
                self._done.emit(data, "")
            except Exception as exc:      # noqa: BLE001 — surfaced to user
                log_crash("MonetizeVM.check failed:\n" + traceback.format_exc())
                self._done.emit(None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot("QVariant", str)
    def _on_done(self, data, error):
        self._set_busy(False)
        if error or not data:
            self._result = {}
            self._ctx = None
            self.resultChanged.emit()
            self._set_status("✗ " + (error or tr("Something went wrong.")), "error")
            self.toast.emit(error or tr("Monetization check failed."), "error")
            announce("error", tr("Monetization check failed."), error or "",
                     page=3, icon="monetization_on",
                     source=tr("Monetize Checker"))
            return
        self._result = data
        self.resultChanged.emit()
        self._set_status(
            tr("✓ Loaded data for {name}").format(name=data["profile"]["title"]),
            "success")
        announce("success", tr("Monetization check complete"),
                 data["profile"]["title"], page=3, icon="monetization_on",
                 source=tr("Monetize Checker"))

    # PLACEHOLDER_COMPUTE

    # ── format detection (mirrors the legacy _detect_channel_format) ─────
    @staticmethod
    def _is_probably_short(v):
        secs = parse_iso8601_duration(
            v.get("contentDetails", {}).get("duration", ""))
        # App-wide 3-minute line (SHORT_MAX_SECONDS): under 3 min is a Short,
        # at or over is long-form — same rule as detect_short everywhere else.
        return 0 < secs < SHORT_MAX_SECONDS

    @staticmethod
    def _views_of(v):
        try:
            return int(v.get("statistics", {}).get("viewCount", 0))
        except (TypeError, ValueError):
            return 0

    @classmethod
    def _detect_format(cls, recent, mode):
        """Decide long-form vs Shorts by weighing ESTIMATED REVENUE, not
        uploads or raw views (a long-form channel that also posts Shorts
        stays long-form, and a Shorts channel that posts an occasional
        compilation stays Shorts — one long-form view is worth roughly
        SHORTS_LONG_VALUE_RATIO Shorts views, see app.core.rpm)."""
        if mode == "long":
            return "long", False
        if mode == "short":
            return "short", True
        if not recent:
            return "long", False
        longs = [v for v in recent if not cls._is_probably_short(v)]
        shorts = [v for v in recent if cls._is_probably_short(v)]
        if not longs:
            return "short", True
        if not shorts:
            return "long", False
        sv = sum(cls._views_of(v) for v in shorts)
        lv = sum(cls._views_of(v) for v in longs)
        if sv or lv:
            is_short = sv > lv * SHORTS_LONG_VALUE_RATIO
        else:
            is_short = len(shorts) > len(longs)
        return ("short", True) if is_short else ("long", False)

    def _estimate_ypp(self, recent):
        """Rough public watch hours/year and Shorts views in 90 days — neither
        is exposed by any API, so both are projected from recent uploads.

        v1.2 — the 90-day figure used to add up the views of videos *published*
        inside the last 90 days. That is the wrong question: YouTube counts
        views *earned* in the window, not views of videos released in it. A
        channel with 32M lifetime views that has posted little lately came out
        at a few hundred thousand and the panel told the user it "hasn't got the
        10M" — a number that contradicted the 32M printed right above it. Now a
        video's lifetime views are spread over its own age and only the slice
        that falls inside the window is counted, so an older Short that is still
        being watched keeps contributing. Still an estimate (it says "~" for a
        reason), but no longer a systematic undercount of exactly the channels
        the check is usually pointed at.
        """
        watch_sec_day = 0.0
        shorts_90d = 0.0
        for v in recent:
            views = self._views_of(v)
            dur = parse_iso8601_duration(
                v.get("contentDetails", {}).get("duration", ""))
            age_days = max(hours_since(
                v.get("snippet", {}).get("publishedAt", "")) / 24, 1.0)
            # Share of this video's lifetime views earned inside the window.
            # Uniform accrual is a first-order model: a two-day-old video
            # counts in full, a two-year-old one counts its last 90 days.
            share = 1.0 if age_days <= 90 else min(1.0, 90.0 / age_days)
            if dur and dur < SHORT_MAX_SECONDS:
                shorts_90d += views * share
            else:
                watch_sec_day += (views * dur * 0.45) / age_days
        return watch_sec_day * 365 / 3600.0, shorts_90d

    def _gather_signals(self, channel_id, recent, is_shorts):
        """The two page scrapes the verdict needs — run ONCE per check.

        Kept separate from the verdict so that a LANGUAGE SWITCH can rebuild
        every translated string from these already-gathered numbers without
        hitting YouTube again (see _verdict / _assemble / retranslate). Returns
        plain numbers only — no translated text — so it is safe to cache.
        """
        page = check_channel_page_signals(channel_id)
        if not is_shorts:
            candidates = [v for v in recent if parse_iso8601_duration(
                v.get("contentDetails", {}).get("duration", "")) > 240]
        else:
            candidates = [v for v in recent if self._is_probably_short(v)]
        check_list = (candidates or recent)[:4]
        super_thanks = midrolls = ads_seen = 0
        checked_any = False
        for v in check_list:
            vid = v.get("id")
            if not vid:
                continue
            sig = check_video_monetization_signal(vid, is_shorts)
            checked_any = checked_any or sig["ok"]
            super_thanks += 1 if sig.get("super_thanks") else 0
            midrolls += 1 if sig.get("midroll") else 0
            ads_seen += 1 if sig.get("ads") else 0
        return {"page": page, "checked_any": checked_any,
                "super_thanks": super_thanks, "midrolls": midrolls,
                "ads_seen": ads_seen, "n_checked": max(1, len(check_list))}

    def _verdict(self, subs, recent, mode, format_used, is_shorts, sig,
                 total_views=None):
        """Decide monetized / not, always answering, with a certainty score and
        an evidence checklist. Ported from the legacy algorithm.

        PURE — every input is already in hand (see _gather_signals), so this can
        be re-run on a language switch to rebuild the translated text. That is
        the whole reason the network scrape is a separate function: the old
        single-pass version translated its strings once, at check time, and a
        switch to Persian left the entire verdict panel in English.
        """
        checks = []

        def add(ok, key, found, missing=None, kind="proof"):
            checks.append({"ok": bool(ok), "key": key, "kind": kind,
                           "text": found if ok else (missing or found)})

        # hard floor: cannot even apply below 500 subs
        if subs is not None and subs < 500:
            add(False, "subs_gate",
                tr("{n} subscribers — the Partner Program needs 500 to apply, "
                   "1,000 for ads.").format(n=humanize_count(subs)), kind="odds")
            add(False, "no_ads_possible",
                tr("Ads can't run on this channel yet, so there was nothing to "
                   "look for on its videos."), kind="odds")
            return {"status": "NOT_MONETIZED", "certainty": 97, "checks": checks,
                    "format_used": format_used,
                    "headline": tr("This channel is not monetized."),
                    "reason": tr("It is still under the 500-subscriber floor for "
                                 "applying to the Partner Program.")}

        # PROOF · channel page
        page = sig["page"]
        checked_any = sig["checked_any"]
        add(page["membership"], "membership",
            tr("Channel Memberships (the Join button) are switched on."),
            tr("No Join button — Channel Memberships are off, or not offered."))
        add(page["merch"], "merch",
            tr("A Store / merch shelf is switched on."),
            tr("No Store tab — no merch shelf on the channel."))

        # PROOF · recent videos
        n_checked = sig["n_checked"]
        add(sig["super_thanks"] > 0, "super_thanks",
            tr("Super Thanks (fan funding) is enabled on recent uploads."),
            tr("No Super Thanks button on the recent uploads checked."))
        add(sig["ads_seen"] > 0, "ads",
            tr("YouTube served ad slots on {n} of {m} recent videos checked.").format(
                n=sig["ads_seen"], m=n_checked),
            tr("No ad slots came back on the {m} recent videos checked — the "
               "logged-out player skips ads for its own reasons, so this alone "
               "doesn't mean the channel isn't monetized.").format(m=n_checked))
        if not is_shorts:
            add(sig["midrolls"] >= 2, "midroll",
                tr("Creator-placed mid-roll ad breaks on {n} recent videos.").format(
                    n=sig["midrolls"]),
                tr("No creator-placed mid-roll ad breaks found."))

        proof_hits = [c for c in checks if c["kind"] == "proof" and c["ok"]]

        # ODDS · the thresholds YouTube actually applies
        watch_hours, shorts_90d = self._estimate_ypp(recent)
        subs_ok = subs is not None and subs >= 1000
        subs_txt = humanize_count(subs) if subs is not None else tr("Hidden")
        add(subs_ok, "subs_1k",
            tr("{n} subscribers — past the 1,000 needed for ads.").format(n=subs_txt),
            tr("{n} subscribers — still short of the 1,000 needed for ads.").format(
                n=subs_txt), kind="odds")
        if is_shorts:
            # v1.2: say where the number comes from and what it is not. The old
            # line stated a hard "short of the 10M" next to a channel showing
            # 32M views in the hero, which reads as the app contradicting
            # itself. YouTube publishes no 90-day view count, so this is a
            # projection — and a back catalogue still being watched can put the
            # real figure well above it.
            short_txt = humanize_count(shorts_90d)
            add(shorts_90d >= 10_000_000, "shorts_views",
                tr("~{n} Shorts views in the last 90 days — past the 10M that opens "
                   "the Shorts route in.").format(n=short_txt),
                tr("~{n} Shorts views in the last 90 days — under the 10M the Shorts "
                   "route needs. Projected from the {m} recent uploads, so a back "
                   "catalogue that is still being watched can put the real figure "
                   "higher.").format(n=short_txt, m=max(1, len(recent))),
                kind="odds")
        else:
            add(watch_hours >= 4000, "watch_hours",
                tr("~{n} public watch hours a year (estimated) — past the 4,000 "
                   "bar.").format(n=humanize_count(watch_hours)),
                tr("~{n} public watch hours a year (estimated) — under the 4,000 "
                   "bar.").format(n=humanize_count(watch_hours)), kind="odds")

        threshold_ok = (shorts_90d >= 10_000_000 if is_shorts else watch_hours >= 4000)

        if not page["html_ok"] or not checked_any:
            add(False, "fetch_failed",
                tr("Some of YouTube's pages wouldn't load for this check, so the "
                   "verdict leans more on the numbers than on the page signals."),
                kind="note")

        # verdict — proof settles it
        if proof_hits:
            weights = {"membership": 99, "super_thanks": 98, "ads": 94,
                       "merch": 93, "midroll": 90}
            certainty = max(weights.get(c["key"], 90) for c in proof_hits)
            if len(proof_hits) > 1:
                certainty = min(99, certainty + 2)
            if not threshold_ok:
                # v1.2: this is the case that confused people. A Join button is
                # proof on its own, but the odds row above can still read "under
                # the 10M" on a channel with tens of millions of views — so say
                # out loud why both are true instead of leaving the two numbers
                # sitting next to each other looking like a contradiction.
                add(False, "odds_gap",
                    tr("The evidence above decides it on its own — a feature only "
                       "Partner Program channels can switch on is live here. The "
                       "estimate under it is projected from recent uploads and can "
                       "sit below the bar on a channel with {v} lifetime views, "
                       "because older videos still earn views today.").format(
                           v=humanize_count(total_views or 0)),
                    kind="note")
            return {"status": "MONETIZED", "certainty": certainty, "checks": checks,
                    "format_used": format_used,
                    "headline": tr("This channel is monetized."),
                    "reason": tr("{n} monetization feature(s) that only Partner "
                                 "Program channels can switch on were found live on "
                                 "the channel.").format(n=len(proof_hits))}

        # no proof — price the odds
        score = 0
        if subs_ok:
            score += 42
        if subs is not None and subs >= 10_000:
            score += 12
        if subs is not None and subs >= 100_000:
            score += 12
        if threshold_ok:
            score += 26
        if len(recent) >= 8:
            score += 6
        if not checked_any:
            score -= 6

        if score >= 60:
            certainty = min(88, 55 + score // 3)
            return {"status": "MONETIZED", "certainty": certainty, "checks": checks,
                    "format_used": format_used,
                    "headline": tr("This channel is monetized."),
                    "reason": tr("It meets the subscriber and watch-time bars and "
                                 "shows an active upload history; no opt-in feature "
                                 "is public, which is a display choice.")}

        missing = (tr("its 90-day Shorts views are short of 10M") if is_shorts
                   else tr("its estimated public watch hours are short of 4,000"))
        if not subs_ok:
            certainty = 93 if (subs is None or subs >= 700) else 96
        else:
            certainty = max(62, min(90, 90 - score))
        gap = (tr("the channel is under 1,000 subscribers") if not subs_ok else missing)
        return {"status": "NOT_MONETIZED", "certainty": certainty, "checks": checks,
                "format_used": format_used,
                "headline": tr("This channel is not monetized."),
                "reason": tr("Nothing that requires the Partner Program is switched "
                             "on, and {gap} — so ad revenue is very unlikely to be "
                             "running.").format(gap=gap)}

    # ── the API call + flatten (mirrors the legacy _compute_monetization) ─
    def _compute(self, channel_text, mode):
        api_key = (self._api_key or "").strip()
        yt = build_youtube_service(api_key)
        channel_id = resolve_channel_id(yt, channel_text)
        if not channel_id:
            raise RuntimeError(tr("Could not resolve that channel. Try pasting "
                                  "the full channel URL."))
        self._stage_sig.emit(1)

        resp = yt.channels().list(
            part="snippet,statistics,contentDetails,brandingSettings,topicDetails",
            id=channel_id).execute()
        if not resp.get("items"):
            raise RuntimeError(tr("Channel not found."))
        item = resp["items"][0]
        snip, stats, cdet = item["snippet"], item["statistics"], item["contentDetails"]

        hidden_subs = bool(stats.get("hiddenSubscriberCount", False))
        subs = None if hidden_subs else int(stats.get("subscriberCount", 0))
        total_views = int(stats.get("viewCount", 0))
        video_count = int(stats.get("videoCount", 0))

        recent = []
        try:
            uploads_id = cdet["relatedPlaylists"]["uploads"]
            pl = yt.playlistItems().list(
                part="contentDetails", playlistId=uploads_id, maxResults=15).execute()
            vids = [i["contentDetails"]["videoId"] for i in pl.get("items", [])]
            if vids:
                vresp = yt.videos().list(
                    part="snippet,statistics,contentDetails",
                    id=",".join(vids)).execute()
                recent = vresp.get("items", [])
        except Exception:      # noqa: BLE001 — recent uploads are best-effort
            recent = []

        # ── monthly-views projection ──────────────────────────────────────
        # The old model was max(recent-velocity, lifetime-average) where the
        # "recent velocity" priced EVERY recent upload at its lifetime average
        # (views ÷ age). For a channel with infrequent uploads that is wildly
        # high: an 80-day-old video's CURRENT daily views are a small fraction
        # of its lifetime average, yet 15 such videos summed into a daily rate
        # 3-10× reality. Measured: Kurzgesagt projected 200M views/month
        # against the ~60-80M it actually does; "Likely" income 3-7× high.
        #
        # The model now separates the two things a single snapshot can say:
        #   * the BACK CATALOGUE (every upload NOT among the recent list)
        #     earns its lifetime-average daily rate — the only rate a snapshot
        #     can attribute to it;
        #   * each RECENT upload is priced by what it will add in the NEXT 30
        #     days, under a power-law view decay (V(t) ∝ t^0.25, the shape
        #     tracker tools fit to YouTube): a video at age t earns
        #     views × ((t+30)^p − t^p) / t^p more this month — NOT another
        #     month of its lifetime average. Fresh uploads earn the most
        #     (a 5-day-old video ~62% of its lifetime so far), old ones
        #     taper (a 60-day-old video ~11%).
        # The recent uploads' LIFETIME views are excluded from the catalogue
        # base, so nothing is counted twice.
        _P = 0.25                      # view-decay exponent (fitted shape)
        recent_views = sum(self._views_of(v) for v in recent)
        future30 = 0.0
        for v in recent:
            views = self._views_of(v)
            if views <= 0:
                continue
            age = days_since(v["snippet"]["publishedAt"])
            if age is None:
                continue               # undateable upload: not projectable
            age = max(float(age), 0.5)
            future30 += views * (((age + 30.0) ** _P - age ** _P)
                                 / (age ** _P))
        catalogue_daily = 0.0
        age_days = days_since(snip.get("publishedAt"))
        if age_days is not None and total_views > recent_views:
            # Lifetime average over the channel's whole age, for the videos
            # OUTSIDE the recent list. days_since(), NOT hours_since(): the
            # channel's own publishedAt can be unreadable (fractional seconds,
            # see parse_iso_utc) and the old failure turned into "30 days old"
            # — billions of views a month for a channel doing a fraction of
            # that. Unreadable → the catalogue term is dropped rather than
            # guessed; the recent uploads still carry the estimate.
            catalogue_daily = ((total_views - recent_views)
                               / max(age_days, 30.0))
        daily = catalogue_daily + future30 / 30.0
        monthly, yearly = daily * 30.0, daily * 30.0 * 12.0

        # revenue priced off niche + audience market (RPM, not one flat CPM)
        # Fixed: split Shorts vs long-form views instead of pricing every view
        # at one format's RPM. Pricing 8M Shorts views at a long-form $5 RPM
        # overstates by ~100x (the bug behind "$46K/mo for a Shorts channel"
        # that external checkers priced at a few hundred). Each side is now
        # priced at its own pool rate and summed.
        format_used, is_shorts = self._detect_format(recent, mode)
        revenue_format_used = format_used
        branding = (item.get("brandingSettings", {}).get("channel", {}) or {})
        # Hand the RAW topicCategories through, not their words appended to the
        # description. They are YouTube's own niche label for the channel and
        # detect_channel_niche weights them far above anything guessed from the
        # blurb — appending them as loose words is what let a stray "language"
        # in T-Series' About outvote its actual Music/Music_of_Asia/Pop_music
        # topics and file the channel under "Education".
        topics = item.get("topicDetails", {}).get("topicCategories", []) or []
        niche_row = detect_channel_niche(
            snip.get("title", ""),
            snip.get("description", "") or "",
            branding.get("keywords", "") or "",
            topics=topics)
        rpm_short = estimate_rpm(niche_row, snip.get("country", ""), True)
        rpm_long = estimate_rpm(niche_row, snip.get("country", ""), False)
        # view-share per format from recent uploads (view-weighted, not
        # count-weighted). Forced modes lock the share; auto falls back to
        # the detected dominant format when there is no recent data.
        if mode == "short":
            short_share = 1.0
        elif mode == "long":
            short_share = 0.0
        elif recent:
            sv = sum(self._views_of(v) for v in recent if self._is_probably_short(v))
            lv = sum(self._views_of(v) for v in recent if not self._is_probably_short(v))
            tot = sv + lv
            short_share = (sv / tot) if tot else (1.0 if revenue_format_used == "short" else 0.0)
        else:
            short_share = 1.0 if revenue_format_used == "short" else 0.0
        # The verdict needs two page scrapes; do them ONCE here and cache the
        # result, so a language switch can rebuild every translated string
        # without touching YouTube again (see _assemble / retranslate).
        self._stage_sig.emit(2)
        signals = self._gather_signals(channel_id, recent, is_shorts)
        self._stage_sig.emit(3)

        # Everything the result is rendered from, as plain values — no
        # translated text. Cached so retranslate() can re-render in another
        # language. `recent`/`snip` are referenced, not copied: this is a
        # read-only context that lives as long as the displayed result.
        self._ctx = {
            "channel_id": channel_id, "snip": snip, "subs": subs,
            "total_views": total_views, "video_count": video_count,
            "recent": recent, "mode": mode,
            "format_used": format_used, "is_shorts": is_shorts,
            "signals": signals,
            "daily": daily, "monthly": monthly, "yearly": yearly,
            "short_share": short_share,
            "revenue_format_used": revenue_format_used,
            "rpm_short": rpm_short, "rpm_long": rpm_long,
        }
        return self._assemble(self._ctx)

    # ── result assembly (PURE — re-runnable on a language switch) ────────
    def _assemble(self, ctx):
        """Flatten raw inputs into the map QML binds to.

        Pure and cheap: it only formats numbers and calls tr(). That is exactly
        what lets retranslate() re-render the whole panel in another language.
        The previous single-pass version translated once, at check time, so
        switching to Persian left the verdict, the evidence checklist and the
        revenue table — every word of the panel — in English.
        """
        snip = ctx["snip"]
        channel_id = ctx["channel_id"]
        subs = ctx["subs"]
        total_views = ctx["total_views"]
        video_count = ctx["video_count"]
        recent = ctx["recent"]
        mode = ctx["mode"]
        daily, monthly, yearly = ctx["daily"], ctx["monthly"], ctx["yearly"]
        short_share = ctx["short_share"]
        revenue_format_used = ctx["revenue_format_used"]
        rpm_short, rpm_long = ctx["rpm_short"], ctx["rpm_long"]
        # display model stays the dominant format, but the money is blended
        rpm_model = rpm_short if revenue_format_used == "short" else rpm_long

        def _blended(tier):
            return (monthly * short_share / 1000 * rpm_short["rpm"][tier]
                    + monthly * (1.0 - short_share) / 1000 * rpm_long["rpm"][tier])

        def _blended_daily(tier):
            return (daily * short_share / 1000 * rpm_short["rpm"][tier]
                    + daily * (1.0 - short_share) / 1000 * rpm_long["rpm"][tier])

        def _blended_yearly(tier):
            return (yearly * short_share / 1000 * rpm_short["rpm"][tier]
                    + yearly * (1.0 - short_share) / 1000 * rpm_long["rpm"][tier])

        revenue_rows = []
        for tier in _REV_TIERS:
            # Effective blended rate shown on the chip so the row stays
            # checkable: views ÷ 1000 × this = the figure beside it.
            eff_rate = (short_share * rpm_short["rpm"][tier]
                        + (1.0 - short_share) * rpm_long["rpm"][tier])
            revenue_rows.append({
                "tier": tier.upper(),
                # A word rather than a bare "LOW/MID/HIGH" chip: the three rows
                # are one band's floor, middle and ceiling, not three scenarios,
                # and the label is what says so.
                "label": tr(_TIER_LABELS.get(tier, tier)),
                "note": tr(_TIER_NOTES.get(tier, "")),
                # The RPM each row was actually computed from. Printing it turns
                # the row from a number to trust into a calculation to check:
                # views ÷ 1000 × this = the figure beside it.
                "rpmText": "$%.2f" % eff_rate,
                "isMid": tier == "mid",
                "daily": _money(_blended_daily(tier)),
                "monthly": _money(_blended(tier)),
                "yearly": _money(_blended_yearly(tier)),
            })

        # The headline RANGE ("$644 - $10K a month"): wider than the three tier
        # cards on purpose — see EARNINGS RANGE in app.core.rpm for what each
        # bound accounts for. Raw floats ride along so the page can count up
        # to them; the strings are what it lands on.
        def _span(views):
            lo, mid, hi = earnings_range(views, short_share, rpm_short, rpm_long)
            return {"low": lo, "mid": mid, "high": hi,
                    "lowText": money_compact(lo), "midText": money_compact(mid),
                    "highText": money_compact(hi),
                    "text": "%s - %s" % (money_compact(lo), money_compact(hi))}

        earnings = {"daily": _span(daily), "monthly": _span(monthly),
                    "yearly": _span(yearly)}

        monetization = self._verdict(subs, recent, mode, ctx["format_used"],
                                     ctx["is_shorts"], ctx["signals"],
                                     total_views=total_views)

        thumbs = snip.get("thumbnails", {})
        thumb_url = (thumbs.get("high") or thumbs.get("medium")
                     or thumbs.get("default") or {}).get("url", "")
        desc = (snip.get("description", "") or "").strip()
        if len(desc) > 240:
            desc = desc[:240].rsplit(" ", 1)[0] + "…"

        return {
            "profile": {
                "title": snip["title"],
                "handle": snip.get("customUrl", "") or channel_id,
                "description": desc,
                "country": snip.get("country", "") or tr("N/A"),
                "joined": (snip.get("publishedAt") or "")[:10] or tr("N/A"),
                "thumbnailUrl": thumb_url,
                "subs": humanize_count(subs) if subs is not None else tr("Hidden"),
                "totalViews": humanize_count(total_views),
                "videoCount": humanize_count(video_count),
            },
            "verdict": {
                "monetized": monetization["status"] == "MONETIZED",
                "headline": monetization["headline"],
                "reason": monetization["reason"],
                "certainty": monetization["certainty"],
            },
            "checks": monetization["checks"],
            "revenue": revenue_rows,
            "earnings": earnings,
            # The one figure this whole panel exists to produce, pulled out of the
            # table so it can be read without scanning a 3×3 grid. The MID row on
            # purpose: it is the middle of the niche's published band, which is
            # what a creator should plan against.
            "headline": {
                "value": _money(_blended("mid")),
                "label": tr("Likely per month"),
                # The range around it, so the headline is never mistaken for a
                # precise number.
                "range": "%s – %s" % (_money(_blended("low")), _money(_blended("high"))),
                "yearly": _money(_blended_yearly("mid")),
            },
            "views": {
                "daily": humanize_count(int(daily)),
                "monthly": humanize_count(int(monthly)),
                "yearly": humanize_count(int(yearly)),
                "shortShare": round(short_share, 3),
            },
            "rpm": {
                "nicheLabel": rpm_model["niche_label"],
                "nicheIcon": rpm_model["niche_icon"],
                "tier": rpm_model["tier"],
                "formatUsed": revenue_format_used,
                "shortShare": round(short_share, 3),
                "rpmLow": f"${rpm_short['rpm']['low']:.3f} / ${rpm_long['rpm']['low']:.2f}",
                "rpmHigh": f"${rpm_short['rpm']['high']:.3f} / ${rpm_long['rpm']['high']:.2f}",
                "cpmLow": f"${rpm_model['cpm']['low']:.2f}",
                "cpmHigh": f"${rpm_model['cpm']['high']:.2f}",
            },
        }


