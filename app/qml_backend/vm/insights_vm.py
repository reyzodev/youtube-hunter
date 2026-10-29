"""app.qml_backend.vm.insights_vm - YouTube Hunter (QML).

ViewModel behind InsightsPage.qml — Niche Scan.

The gap it fills: Niche Finder and Search Archive are very good at ranking
individual videos and completely silent about the SET. A creator ends a search
looking at 50 sorted rows with no answer to "so what is this niche, and what
should I make?". Every number needed to answer that is already in the rows; it
just was never read.

Two halves, deliberately separable:

  * The deterministic half (app.core.analysis.snapshot) runs instantly, free, on
    the GUI thread. Median vs average, momentum, length and recency mix, channel
    concentration, coverage honesty, and a computed one-line verdict. This is
    shown on its own and is useful without any AI configured at all.
  * The written half (app.core.ai.insights) is one AI call on a worker thread,
    producing a brief where every statement is labelled observed / inferred /
    requires-Studio. Cached per snapshot in app.core.db.insights so re-opening a
    report never spends a second call.

Rows arrive from whichever page asked for the analysis (Niche Finder's live pool,
an Archive group's saved rows), so this VM never touches the YouTube API and
costs no quota of its own.
"""

import threading
import traceback
from datetime import datetime

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.config import load_app_config
from app.core.ai.profiles import resolve as resolve_ai_route, is_ready as ai_route_ready
from app.core.ai.clients import AIClient, api_mode_for
from app.core.ai.insights import generate_insights, parse_insights_response
from app.core.analysis.snapshot import (build_snapshot, duration_label,
                                        lift_group_label, lift_label,
                                        recency_label, size_label, verdict_line,
                                      DURATION_BUCKETS as _DURATION_BUCKETS,
                                      RECENCY_BUCKETS as _RECENCY_BUCKETS)
from app.core.db.insights import (insights_delete, insights_get, insights_list,
                                  insights_save)
from app.core.niche.helpers import format_multiplier
from app.core.net import explain_network_error
from app.core.utils import humanize_count, notif_relative_time
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm._idea_shape import mmss
from app.qml_backend.desktop_notifier import announce

# Above this share of the views held by one channel, the concentration reading
# stops being "spread out" and starts being "one incumbent owns this".
_DOMINANT_SHARE = 0.4

def _thumb_id(url):
    """Base64 id for the `image://thumbs/<id>` provider — same encoding the
    other grids use, done here so it stays off the QML binding path."""
    import base64
    if not url:
        return ""
    return base64.b64encode(str(url).encode("utf-8")).decode("ascii")

def _relative(stamp):
    """"3d ago" for one of this module's own stored timestamps.

    NOT days_ago_str(): that one parses YouTube's UTC "…Z" format and returns
    "N/A" for anything else, and insight_reports.created_at is a local
    isoformat(timespec="seconds") string. notif_relative_time takes the datetime
    object, which is what we have after parsing."""
    try:
        return notif_relative_time(datetime.fromisoformat(str(stamp)))
    except Exception:
        return str(stamp)[:10]

class InsightsVM(QObject):
    """Niche Scan: read a whole search result as one set."""

    snapshotChanged = Signal()      # the deterministic analytics + verdict
    aiChanged = Signal()            # the written brief
    busyChanged = Signal()
    changed = Signal()              # provider readiness, status line
    historyChanged = Signal()       # the saved-report strip
    labelsChanged = Signal()
    toast = Signal(str, str)
    ideas_sink = None   # v3.42: IdeasVM.addReferences, set in main_qml.py
    # Hand the analysed rows on to AI Ideas — Insights should feed the pipeline
    # that already exists rather than being a dead end.
    sendToIdeasDone = Signal(int)

    _aiDone = Signal("QVariant", str)     # (brief_or_None, error)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._reload_ai_config()

        self._rows = []
        self._snap = None
        self._open_key = ""     # saved report on screen (strip highlight)
        self._ai = None
        self._busy = False
        self._status = ""
        self._status_kind = "muted"
        self._from_cache = False
        self._generated_at = ""
        self._history = []

        self._aiDone.connect(self._on_ai_done)
        self.refreshHistory()

    # ── AI provider config (same shape as IdeasVM / ContentLabVM) ─────────
    def _reload_ai_config(self):
        # The provider / model / effort Settings routes "reports" to (AI routing),
        # falling back to the active provider — see app.core.ai.profiles.
        cfg = load_app_config()
        r = resolve_ai_route("reports", cfg)
        self._ai_route = r
        self._ai_provider = r["provider"]
        self._ai_key = r["api_key"]
        self._ai_model = r["model"]
        self._ai_base = r["base_url"]
        self._ai_path = r["path"]
        self._ai_name = r["custom_name"]
        self._ai_proxy = r["proxy"]
        self._ai_mode = api_mode_for(self._ai_provider, r["api_mode"] or None)
        self._ai_effort = r["effort"]

    def _make_client(self):
        return AIClient(self._ai_provider, self._ai_key, self._ai_model,
                        base_url=self._ai_base, proxy=self._ai_proxy,
                        path=self._ai_path, custom_name=self._ai_name,
                        api_mode=self._ai_mode,
                        effort=self._ai_effort)

    @Slot()
    def reloadConfig(self):
        self._reload_ai_config()
        self.changed.emit()

    @Slot()
    def retranslate(self):
        # Bucket labels and the verdict line are translated at read time, so a
        # language switch has to re-emit rather than rebuild.
        self.labelsChanged.emit()
        self.snapshotChanged.emit()
        self.aiChanged.emit()
        self.changed.emit()

    @Property(bool, notify=changed)
    def hasAiKey(self):
        # v1.1.3: same rule as every other AI page (profiles.is_ready): a
        # custom gateway is configured by its host, not necessarily by a key.
        try:
            return ai_route_ready(self._ai_route)
        except Exception:      # noqa: BLE001
            return bool(self._ai_key)

    @Property(str, notify=changed)
    def providerLabel(self):
        return self._make_client().label

    # ── state ────────────────────────────────────────────────────────────
    @Property(bool, notify=busyChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=changed)
    def status(self):
        return self._status

    @Property(str, notify=changed)
    def statusKind(self):
        return self._status_kind

    def _set_status(self, text, kind="muted"):
        self._status = text
        self._status_kind = kind
        self.changed.emit()

    def _set_busy(self, busy):
        if busy != self._busy:
            self._busy = busy
            self.busyChanged.emit()

    @Property(bool, notify=snapshotChanged)
    def hasSnapshot(self):
        return self._snap is not None

    @Property(bool, notify=aiChanged)
    def hasBrief(self):
        return self._ai is not None

    @Property(bool, notify=aiChanged)
    def fromCache(self):
        """Whether the brief on screen was loaded rather than generated. Shown
        plainly: a creator deciding whether to spend another call needs to know
        they are looking at yesterday's answer."""
        return self._from_cache

    @Property(str, notify=aiChanged)
    def generatedAt(self):
        return self._generated_at

    # ── the deterministic reading ────────────────────────────────────────
    @Slot("QVariant", str, str)
    def analyzeRows(self, rows, query, mode):
        """Take a set of rows and read it. Instant, free, no AI.

        Called by Niche Finder ("Analyze these results") and Search Archive
        ("Analyze this group"). Any cached AI brief for this exact snapshot is
        loaded at the same time, so re-opening a previously analysed set shows
        the full report without a call."""
        rows = [dict(r) for r in (rows or []) if isinstance(r, dict)]
        if not rows:
            self.toast.emit(tr("Nothing to analyze — run a search first."), "error")
            return
        self._rows = rows
        self._snap = build_snapshot(rows, query=query or "", mode=mode or "keyword")
        self._open_key = ""
        self._ai = None
        self._from_cache = False
        self._generated_at = ""
        if self._snap is None:
            self.toast.emit(tr("These rows have nothing measurable in them."),
                            "error")
            self.snapshotChanged.emit()
            return

        cached = insights_get(self._snap["snapshot_key"])
        if cached and cached.get("ai"):
            self._ai = self._rescue(cached["ai"])
            self._from_cache = True
            self._generated_at = cached.get("created_at", "")
            self._set_status(
                tr("Showing the saved brief for this exact result set."), "muted")
        else:
            # Persist the MEASURED half right away, with no AI brief attached.
            #
            # This is what makes the snapshot reusable elsewhere. The report
            # builder's "combine with research" picker lists stored snapshots
            # (app.core.db.insights.insights_list), and until this call only a
            # snapshot whose AI brief had been generated was ever written — so a
            # user whose provider refused the brief, or who simply hadn't asked
            # for one yet, found an empty picker and their snapshot data never
            # reached the channel report at all. The aggregates cost nothing to
            # compute and are the most trustworthy numbers in the feature; they
            # should not be gated behind a model call. generateBrief() upserts
            # over this row on the same snapshot_key when a brief does arrive.
            self._save_snapshot_only()
            self._set_status("", "muted")
        self.snapshotChanged.emit()
        self.aiChanged.emit()
        self.refreshHistory()

    def _rescue(self, brief):
        """v1.1.3: a brief saved by an older build as "not structured" is
        re-read with the tolerant parser, so reports that were stuck as raw
        JSON open as a real brief. Persisted again when the rescue works, so
        it only costs this once."""
        if not isinstance(brief, dict) or brief.get("ok") or not brief.get("fallback_text"):
            return brief
        allowed = [str(r.get("video_id") or "") for r in self._rows if r.get("video_id")]
        try:
            fixed = parse_insights_response(brief["fallback_text"], allowed)
        except Exception:      # noqa: BLE001
            return brief
        if not fixed.get("ok"):
            return brief
        if self._snap:
            try:
                insights_save(self._snap["snapshot_key"], self._snap.get("query", ""),
                              self._snap.get("mode", "keyword"), "", self._snap,
                              fixed, self._rows)
            except Exception:  # noqa: BLE001 — best-effort
                pass
        return fixed

    def _save_snapshot_only(self):
        """Store the deterministic snapshot with no brief. Never raises — a
        failed write just means this set isn't offered to the report builder
        until it is analysed again, which is not worth interrupting the user
        for."""
        if not self._snap:
            return
        try:
            insights_save(self._snap["snapshot_key"], self._snap.get("query", ""),
                          self._snap.get("mode", "keyword"), "", self._snap,
                          None, self._rows)
        except Exception:      # noqa: BLE001 — best-effort cache
            pass

    @Slot(str)
    def openSaved(self, snapshot_key):
        """Re-open a stored report, rows and all — no search, no API, no AI."""
        record = insights_get(str(snapshot_key))
        if not record:
            self.toast.emit(tr("That saved report is gone."), "error")
            self.refreshHistory()
            return
        self._rows = record.get("rows") or []
        self._snap = (build_snapshot(self._rows, query=record.get("query", ""),
                                     mode=record.get("mode", "keyword"))
                      if self._rows else record.get("analytics") or None)
        self._ai = self._rescue(record.get("ai") or None)
        self._from_cache = True
        self._generated_at = record.get("created_at", "")
        self._open_key = str(snapshot_key)
        self._set_status(tr("Saved report, reopened."), "muted")
        self.snapshotChanged.emit()
        self.aiChanged.emit()
        # v3.52: the strip's `isOpen` flags were only rebuilt on analyse/delete,
        # so re-opening a saved scan never showed as selected
        self.refreshHistory()

    @Property("QVariantMap", notify=snapshotChanged)
    def snap(self):
        """Raw aggregates, for anything the formatted properties below don't
        already cover."""
        return self._snap or {}

    @Property(str, notify=snapshotChanged)
    def query(self):
        return (self._snap or {}).get("query", "")

    @Property(str, notify=snapshotChanged)
    def verdict(self):
        """The computed one-liner. Deliberately NOT the AI's summary: it is true
        before any call is made, and it is arithmetic rather than opinion."""
        return verdict_line(self._snap)

    @Property("QVariantList", notify=snapshotChanged)
    def tiles(self):
        """The headline numbers, pre-formatted.

        `meter` is coverage — what fraction of the snapshot each number could
        actually be computed from — so a median drawn from 12 of 50 rows shows a
        third-full bar instead of implying the whole set. That is the honesty rule
        the whole feature rests on, rendered as a bar."""
        snap = self._snap
        if not snap:
            return []
        total = max(1, snap["total_videos"])
        coverage = snap["coverage"]

        median = snap.get("median_views")
        average = snap.get("avg_views")
        skew = snap.get("skew")
        # Median and average are ONE tile, never two: separating them is how a
        # dashboard ends up quoting the average alone.
        views_sub = (tr("average {a} · {n} of {t} rows").format(
            a=humanize_count(average or 0), n=coverage["views"], t=total)
            + (tr("  — outlier-driven") if skew and skew >= 1.5 else ""))

        # Shorts and long-form in one median describe neither format. When the
        # set mixes them, the tile says so and gives both medians.
        split = snap.get("format_split") or {}
        if split.get("mixed"):
            views_sub = (tr("Shorts {s} · long-form {l} · {n} of {t} rows").format(
                s=humanize_count(split.get("shorts_median") or 0),
                l=humanize_count(split.get("long_median") or 0),
                n=coverage["views"], t=total)
                + (tr("  — outlier-driven") if skew and skew >= 1.5 else ""))

        out = snap.get("outliers") or {}
        out_rows = out.get("rows") or 0
        small_rows = snap.get("small_rows") or 0
        sized = snap.get("sized_rows") or 0

        # "CHANNELS IN THIS SET" and "VISIBLE INTERACTION" used to sit here.
        # The first repeated the "Who holds this niche" panel right below it;
        # the second is ~95% likes and answers no decision. Both are still in
        # the snapshot and in the AI prompt. These two answer "can I win here?".
        return [
            {"caption": tr("TYPICAL VIEWS (MEDIAN)"), "icon": "visibility",
             "value": humanize_count(median) if median is not None else "—",
             "sub": views_sub,
             "meter": coverage["views"] / total},
            {"caption": tr("MOMENTUM / DAY"), "icon": "trending_up",
             "value": (humanize_count(snap["median_daily_views"])
                       if snap.get("median_daily_views") is not None else "—"),
             "sub": tr("median, age-normalised · {n} of {t} rows dated").format(
                 n=coverage["published"], t=total),
             "meter": coverage["published"] / total},
            {"caption": tr("OUTPERFORMED THEIR CHANNEL"), "icon": "bolt",
             "value": ("%d%%" % round(out["rate"] * 100)
                       if out.get("rate") is not None else "—"),
             "sub": (tr("{h} videos got 3×+ their channel's usual views · {n} of {t} rows").format(
                         h=out.get("hits", 0), n=out_rows, t=total)
                     if out_rows else tr("no public channel averages")),
             "meter": out_rows / total},
            {"caption": tr("SMALL CHANNELS WINNING"), "icon": "target",
             "value": (str(snap.get("small_beat_median", 0)) if sized else "—"),
             "sub": (tr("of {k} videos from channels under 10K subs beat the median · {n} of {t} sized").format(
                         k=small_rows, n=sized, t=total)
                     if sized else tr("no public subscriber counts")),
             "meter": sized / total},
        ]

    @Property("QVariantList", notify=snapshotChanged)
    def durationMix(self):
        """Length buckets as DonutChart slices.

        Shaped to that component's existing contract ({name, units, pct, pctText,
        tint}) rather than inventing a second one — it already animates its
        sweep, draws its legend and resolves `tint` through U.chartTint. Empty
        buckets are dropped so the legend never lists a length nothing landed in.
        """
        snap = self._snap
        if not snap:
            return []
        buckets = [(key, count) for key, count
                   in (snap.get("duration_mix") or {}).items() if count]
        total = max(1, sum(count for _key, count in buckets))
        return [{
            "name": duration_label(key),
            "units": count,
            "unitsText": str(count),
            "pct": count / total * 100.0,
            "pctText": "%d%%" % round(count / total * 100),
            "tint": index,
        } for index, (key, count) in enumerate(buckets)]

    @Property(str, notify=snapshotChanged)
    def durationTotalText(self):
        return str((self._snap or {}).get("duration_rows") or 0)

    @Property(bool, notify=snapshotChanged)
    def hasDurationMix(self):
        return bool((self._snap or {}).get("duration_rows"))

    @Property("QVariantList", notify=snapshotChanged)
    def recencyMix(self):
        snap = self._snap
        if not snap:
            return []
        total = max(1, sum((snap.get("recency_mix") or {}).values()))
        return [{"label": recency_label(key), "value": count,
                 "frac": count / total}
                for key, count in (snap.get("recency_mix") or {}).items()
                if count]

    @Property(str, notify=snapshotChanged)
    def medianDurationText(self):
        seconds = (self._snap or {}).get("median_duration_s")
        return mmss(seconds) if seconds else "—"

    @Property("QVariantList", notify=snapshotChanged)
    def topics(self):
        """Recurring terms with their real counts.

        Mapped from the snapshot's (label, count) tuples into named fields: a
        tuple crosses into QML as a positional list, and `modelData[1]` in a
        delegate is the kind of thing that breaks silently the day the tuple
        grows a third element."""
        topics = (self._snap or {}).get("topics") or {}
        chips = topics.get("chips", []) or []
        lifts = topics.get("lifts") or {}
        out = []
        for label, count in chips:
            lift = (lifts.get(label) or {}).get("lift")
            out.append({"label": label, "count": count,
                        # v1.0.2: does this term CARRY views, or is it just common?
                        "lift": float(lift) if lift else 0.0,
                        "liftText": ("%.1f×" % lift) if lift else ""})
        return out

    @Property(str, notify=snapshotChanged)
    def topicsSource(self):
        """Whether the chips came from real tags or from title words. Said out
        loud because "recurring tags" and "recurring title words" support
        different conclusions."""
        source = ((self._snap or {}).get("topics") or {}).get("source", "")
        return (tr("from the videos' own tags") if source == "tags"
                else tr("from word frequency across the titles"))

    def _leader_rows(self, key, value_fmt):
        out = []
        for leader in (self._snap or {}).get(key, []) or []:
            out.append({
                "videoId": leader.get("video_id", ""),
                "title": leader.get("title", ""),
                "channelTitle": leader.get("channel_title", ""),
                "thumbId": _thumb_id(leader.get("thumbnail_url", "")),
                "videoUrl": leader.get("video_url", ""),
                "views": humanize_count(leader.get("views", 0)),
                "value": value_fmt(leader),
            })
        return out

    @Property("QVariantList", notify=snapshotChanged)
    def velocityLeaders(self):
        """Fastest-moving, so a three-day-old video can beat an old giant."""
        return self._leader_rows(
            "velocity_leaders",
            lambda l: humanize_count(l.get("value", 0)) + tr("/h"))

    @Property("QVariantList", notify=snapshotChanged)
    def breakoutLeaders(self):
        """Widest reach beyond an existing audience — the closest public proxy
        for "this got pushed to people who don't follow the channel"."""
        return self._leader_rows(
            "breakout_leaders",
            lambda l: format_multiplier(l.get("value", 0)))

    @Property("QVariantList", notify=snapshotChanged)
    def topChannels(self):
        out = []
        for channel in (self._snap or {}).get("top_channels", []) or []:
            out.append({
                "title": channel.get("title", "—"),
                "videos": str(channel.get("videos", 0)),
                "views": humanize_count(channel.get("views", 0)),
                "share": channel.get("share", 0.0),
                "sharePct": "%d%%" % int((channel.get("share") or 0) * 100),
            })
        return out

    # ── v1.0.2 "what earns" (demand side) ───────────────────────────────
    @Property("QVariantList", notify=snapshotChanged)
    def earnRows(self):
        """Every choice with enough videos on both sides, strongest first.

        v1.0.3: built by app.core.analysis.earn_read, which adds the plain-
        language read (pct / verdict / strength / sentence) on top of the
        original fields (`pos` on a log2 scale clamped to ¼×…4×, `flat` for
        readings too close to 1× to act on)."""
        from app.core.analysis.earn_read import earn_rows
        lifts = (self._snap or {}).get("lifts") or {}
        return earn_rows(lifts, lift_group_label, lift_label)

    @Property("QVariantMap", notify=snapshotChanged)
    def earnPlan(self):
        """v1.0.3: the three cards over the chart — do more of / skip /
        doesn't matter — so the panel opens on advice, not on a chart."""
        from app.core.analysis.earn_read import earn_plan, earn_rows
        lifts = (self._snap or {}).get("lifts") or {}
        return earn_plan(earn_rows(lifts, lift_group_label, lift_label))

    @Property(str, notify=snapshotChanged)
    def earnBaseText(self):
        base = ((self._snap or {}).get("lifts") or {}).get("base_daily")
        return (humanize_count(base) + tr("/day")) if base else "—"

    @Property(int, notify=snapshotChanged)
    def earnDatedRows(self):
        return int(((self._snap or {}).get("lifts") or {}).get("rows") or 0)

    # ── v1.0.2 "can a newcomer get in?" (entry side) ────────────────────
    @Property("QVariantList", notify=snapshotChanged)
    def entryLadder(self):
        """Channel-size tiers, smallest first: how many videos each tier placed
        in this set, their typical views/day, and how many beat the set."""
        snap = self._snap or {}
        base = (snap.get("lifts") or {}).get("base_daily")
        tiers = snap.get("size_tiers") or []
        most = max([t.get("rows") or 0 for t in tiers] + [1])
        out = []
        for t in tiers:
            daily = t.get("median_daily")
            out.append({
                "label": size_label(t["key"]),
                "rows": int(t.get("rows") or 0),
                "frac": (t.get("rows") or 0) / most,
                "daily": (humanize_count(daily) + tr("/day")) if daily else "—",
                "beat": int(t.get("beat_daily") or 0),
                "dated": int(t.get("dated_rows") or 0),
                "vsTypical": ("%.1f×" % (daily / base)) if (daily and base) else "",
                "strong": bool(daily and base and daily >= base),
            })
        return out

    @Property("QVariantMap", notify=snapshotChanged)
    def entry(self):
        """Newcomers (channels under a year old) and the panel's verdict.

        verdict: "open" newcomers / small channels demonstrably beat the set ·
                 "closed" nobody small or new made the list ·
                 "rare" they are present but rarely keep up ·
                 "unknown" not enough public data to say."""
        snap = self._snap or {}
        new = snap.get("newcomers") or {}
        sized = int(snap.get("sized_rows") or 0)
        aged = int(new.get("aged_rows") or 0)
        small_beat = int(snap.get("small_beat_median") or 0)
        small_rows = int(snap.get("small_rows") or 0)
        if sized < 5 and aged < 5:
            verdict = "unknown"
        elif new.get("beat_typical", 0) >= 1 or small_beat >= 2:
            verdict = "open"
        elif small_rows == 0 and not new.get("rows"):
            verdict = "closed"
        else:
            verdict = "rare"
        best = new.get("best") or None
        months = int((best or {}).get("channel_age_days") or 0) // 30
        return {
            "verdict": verdict,
            "verdictText": {
                "open": tr("Newcomers get in"),
                "rare": tr("Possible, rarely"),
                "closed": tr("Incumbents only"),
                "unknown": tr("Not enough data"),
            }[verdict],
            "agedRows": aged,
            "newRows": int(new.get("rows") or 0),
            "newChannels": int(new.get("channels") or 0),
            "newBeat": int(new.get("beat_typical") or 0),
            "newDated": int(new.get("dated_rows") or 0),
            "newDaily": (humanize_count(new["median_daily"]) + tr("/day")
                         if new.get("median_daily") else "—"),
            "hasBest": bool(best),
            "bestTitle": (best or {}).get("title", ""),
            "bestChannel": (best or {}).get("channel_title", ""),
            "bestThumb": _thumb_id((best or {}).get("thumbnail_url", "")),
            "bestUrl": (best or {}).get("video_url", ""),
            "bestDaily": (humanize_count(best["daily"]) + tr("/day")) if best else "",
            "bestAge": (tr("{m} mo old channel").format(m=max(1, months)) if best else ""),
            "bestSubs": (humanize_count(best["subscriber_count"]) + " " + tr("subs")
                         if best and best.get("subscriber_count") else ""),
        }

    # ── v3.39.8 "shape of the set" redesign ─────────────────────────────
    # Unlike durationMix / recencyMix these keep EVERY bucket, in order, empty
    # ones included: "nothing between 1 and 10 minutes" is itself a finding,
    # and a scale that silently drops its empty steps cannot be read as a
    # scale. `top` marks the most common bucket so QML never re-derives it.
    @staticmethod
    def _ordered_mix(mix, keys, label_fn):
        mix = mix or {}
        total = sum(int(mix.get(k) or 0) for k in keys)
        best = max((int(mix.get(k) or 0) for k in keys), default=0)
        out = []
        for index, key in enumerate(keys):
            count = int(mix.get(key) or 0)
            frac = (count / total) if total else 0.0
            out.append({
                "key": key,
                "label": label_fn(key),
                "count": count,
                "frac": frac,
                "pctText": ("%d%%" % round(frac * 100)) if count else "—",
                "top": bool(count) and count == best,
                "index": index,
            })
        return out

    @Property("QVariantList", notify=snapshotChanged)
    def durationSpectrum(self):
        snap = self._snap
        if not snap:
            return []
        return self._ordered_mix(snap.get("duration_mix"),
                                 [k for _lo, _hi, k in _DURATION_BUCKETS],
                                 duration_label)

    @Property("QVariantList", notify=snapshotChanged)
    def recencyTimeline(self):
        snap = self._snap
        if not snap:
            return []
        return self._ordered_mix(snap.get("recency_mix"),
                                 [k for _lo, _hi, k in _RECENCY_BUCKETS],
                                 recency_label)

    @Property(int, notify=snapshotChanged)
    def datedRows(self):
        return int((self._snap or {}).get("dated_rows") or 0)

    @Property(int, notify=snapshotChanged)
    def totalVideos(self):
        return int((self._snap or {}).get("total_videos") or 0)

    @Property(int, notify=snapshotChanged)
    def channelCount(self):
        return int((self._snap or {}).get("unique_channels") or 0)

    @Property("QVariantList", notify=snapshotChanged)
    def coverageRows(self):
        """The honesty panel: what this snapshot could and could not see."""
        snap = self._snap
        if not snap:
            return []
        total = max(1, snap["total_videos"])
        coverage = snap["coverage"]
        labels = [
            ("views", tr("View count")),
            ("interaction", tr("Public likes AND comments")),
            ("subscribers", tr("Public subscriber count")),
            ("duration", tr("Duration")),
            ("published", tr("Publish date")),
            ("tags", tr("Tags")),
            ("captions", tr("Captions")),
            ("channel_baseline", tr("Channel average (outlier baseline)")),
            ("channel_age", tr("Channel creation date")),
        ]
        return [{"label": label, "value": "%d / %d" % (coverage.get(key, 0), total),
                 "frac": coverage.get(key, 0) / total}
                for key, label in labels]

    # ── the written brief ────────────────────────────────────────────────
    @Slot()
    @Slot(bool)
    def generateBrief(self, force=False):
        """One AI call on a worker thread.

        `force` re-runs even when a brief for this snapshot is already stored —
        the "Re-analyze" button. Without it, an existing brief short-circuits, so
        navigating back to a report is free."""
        if self._busy:
            return
        if not self._snap:
            self.toast.emit(tr("Analyze a result set first."), "error")
            return
        # v1.1.3: re-read the routing right before the call. The VM is built
        # once at startup, so a key added in Settings afterwards was never
        # seen here and the page kept saying "No AI provider configured".
        self._reload_ai_config()
        self.changed.emit()
        if not self.hasAiKey:
            self.toast.emit(
                tr("Add an AI provider key in Settings to generate the brief."),
                "error")
            return
        if self._ai and not force:
            return

        snap = self._snap
        rows = list(self._rows)
        client = self._make_client()
        self._set_busy(True)
        self._set_status(tr("Reading the snapshot with {p} …").format(
            p=client.label), "muted")

        def worker(_snap=snap, _rows=rows, _client=client):
            try:
                brief = generate_insights(_snap, _rows, _client)
                self._aiDone.emit(brief, "")
            except Exception as exc:
                log_crash("qml insights generate failed\n%s"
                          % traceback.format_exc())
                # A 300s call is prime territory for a proxy to cut the socket;
                # explain_network_error turns that into a sentence rather than a
                # bare "[WinError 10054] …".
                self._aiDone.emit(None, explain_network_error(exc, _client.label))

        threading.Thread(target=worker, daemon=True).start()

    @Slot("QVariant", str)
    def _on_ai_done(self, brief, error):
        self._set_busy(False)
        if error or not brief:
            self._set_status(error or tr("The brief could not be generated."),
                             "error")
            self.toast.emit(error or tr("The brief could not be generated."),
                            "error")
            announce("error", tr("The brief could not be generated."),
                     error or "", page=11, icon="page_insights",
                     source=tr("Niche Scan"))
            return
        self._ai = brief
        self._from_cache = False
        if self._snap:
            insights_save(self._snap["snapshot_key"], self._snap.get("query", ""),
                          self._snap.get("mode", "keyword"),
                          self._make_client().label, self._snap, brief, self._rows)
            self._generated_at = tr("just now")
        self.aiChanged.emit()
        self.refreshHistory()
        if brief.get("ok"):
            dropped = brief.get("dropped_claims", 0)
            if brief.get("partial"):
                self._set_status(
                    tr("Brief ready, but the reply was cut short — some sections may be missing."),
                    "warn")
            else:
                self._set_status(
                    tr("Brief ready. {n} claims cited videos outside this snapshot "
                       "and were dropped.").format(n=dropped) if dropped
                    else tr("Brief ready."),
                    "warn" if dropped else "success")
            self.toast.emit(tr("Snapshot brief ready."), "success")
            announce("success", tr("Snapshot brief ready."),
                     (self._snap or {}).get("query", "") if self._snap else "",
                     page=11, icon="page_insights",
                     source=tr("Niche Scan"))
        else:
            self._set_status(
                tr("{p} replied with something that isn't a structured brief — "
                   "the raw text is shown below.").format(
                       p=self._make_client().label), "error")

    @Property("QVariantMap", notify=aiChanged)
    def brief(self):
        return self._ai or {}

    @Property(int, notify=aiChanged)
    def droppedClaims(self):
        return (self._ai or {}).get("dropped_claims", 0)

    @Property("QVariantList", notify=aiChanged)
    def claims(self):
        """The evidence ledger, with each claim's citations resolved to real
        titles so a source chip is readable rather than an opaque id."""
        by_id = {str(r.get("video_id") or ""): r for r in self._rows}
        out = []
        for claim in (self._ai or {}).get("claims", []) or []:
            sources = []
            for vid in claim.get("source_video_ids", []) or []:
                row = by_id.get(str(vid)) or {}
                mult = row.get("multiplier")
                sources.append({
                    "videoId": str(vid),
                    "title": row.get("title", "") or str(vid),
                    "url": row.get("video_url", "")
                           or ("https://www.youtube.com/watch?v=%s" % vid),
                    # v1.0.2 ledger: the source tile shows the video itself
                    # (thumbnail, channel, reach) instead of a bare title chip.
                    "thumbId": _thumb_id(row.get("thumbnail_url", "")
                                         or ("https://i.ytimg.com/vi/%s/mqdefault.jpg" % vid)),
                    "channelTitle": row.get("channel_title", "") or "",
                    "views": (humanize_count(row.get("view_count") or 0)
                              if row.get("view_count") else ""),
                    "multiplier": (format_multiplier(mult)
                                   if mult is not None else ""),
                    "isShort": bool(row.get("is_short")),
                })
            cls = claim.get("evidence_class", "inferred")
            out.append({
                "claim": claim.get("claim", ""),
                "evidenceClass": cls,
                "classLabel": self.classLabel(cls),
                # Colour key, resolved in QML — observed is the brand accent
                # (it is measured), inferred green, requires-Studio amber.
                "classKey": ("primary" if cls == "observed"
                             else "secondary_container" if cls == "inferred"
                             else "warn"),
                "confidence": claim.get("confidence", "low"),
                "confidenceLabel": self.confidenceLabel(
                    claim.get("confidence", "low")),
                "limitations": claim.get("limitations", []) or [],
                "sources": sources,
            })
        return out

    @Slot(str, result=str)
    def classLabel(self, key):
        return {
            "observed": tr("Observed"),
            "inferred": tr("Inferred"),
            "requires_studio": tr("Needs YouTube Studio"),
        }.get(key, key)

    @Slot(str, result=str)
    def confidenceLabel(self, key):
        return {"low": tr("low"), "medium": tr("medium"),
                "high": tr("high")}.get(key, key)

    # ── saved reports ────────────────────────────────────────────────────
    @Property(str, notify=snapshotChanged)
    def openKey(self):
        """Key of the saved report on screen, for the strip's selected card.
        A re-opened report keeps the key it was stored under (its rebuilt
        snapshot could hash differently); a fresh analysis uses its own."""
        if not self._snap:
            return ""
        return self._open_key or str(self._snap.get("snapshot_key") or "")

    @Property("QVariantList", notify=historyChanged)
    def history(self):
        return self._history

    @Property(bool, notify=historyChanged)
    def hasHistory(self):
        return bool(self._history)

    @Slot()
    def refreshHistory(self):
        """Rebuild the "previously analysed" strip.

        Every stored snapshot appears, not only those with a brief: the
        deterministic half is saved the moment a result set is read (see
        analyzeRows), so a row can be numbers-only. `hasBrief` distinguishes the
        two, since re-opening one costs nothing while the other never spent an AI
        call at all.
        """
        self._history = [{
            "key": record["snapshot_key"],
            "query": record["query"] or tr("Untitled"),
            "mode": record["mode"],
            "videos": str(record.get("total_videos") or 0),
            "when": _relative(record.get("created_at") or ""),
            "hasBrief": bool(record.get("has_brief")),
            "isOpen": bool(self._snap
                           and (self._open_key or self._snap.get("snapshot_key")) == record["snapshot_key"]),
        } for record in insights_list(24)]
        self.historyChanged.emit()

    @Slot(str)
    def deleteSaved(self, snapshot_key):
        if insights_delete(str(snapshot_key)):
            if self._snap and self._snap.get("snapshot_key") == str(snapshot_key):
                self._ai = None
                self._from_cache = False
                self.aiChanged.emit()
            self.refreshHistory()
            self.toast.emit(tr("Saved report deleted."), "success")

    # ── handoff ──────────────────────────────────────────────────────────
    @Slot()
    def sendTopToIdeas(self):
        """Queue this snapshot's strongest performers on the AI Ideas board.

        Uses the breakout leaders (reach beyond subscribers) rather than raw
        views: those are the videos whose PATTERN is worth copying, which is
        exactly what AI Ideas reverse-engineers. Falls back to velocity when no
        row had a usable subscriber count."""
        if not self._snap:
            return
        leaders = (self._snap.get("breakout_leaders")
                   or self._snap.get("velocity_leaders") or [])
        wanted = {str(l.get("video_id")) for l in leaders if l.get("video_id")}
        if not wanted:
            self.toast.emit(tr("No standout videos to send."), "error")
            return
        rows = [dict(r) for r in self._rows if str(r.get("video_id")) in wanted]
        sink = self.ideas_sink
        if not callable(sink):
            self.toast.emit(tr("AI Ideas isn't ready yet — try again in a moment."), "error")
            return
        try:
            added, _already = sink(rows, tr("Niche Scan"))
        except Exception as exc:          # noqa: BLE001
            self.toast.emit(str(exc), "error")
            return
        self.toast.emit(
            tr("Sent {n} videos to AI Ideas.").format(n=added) if added
            else tr("Those videos are already on the AI Ideas board."),
            "success" if added else "info")
        self.sendToIdeasDone.emit(added)
