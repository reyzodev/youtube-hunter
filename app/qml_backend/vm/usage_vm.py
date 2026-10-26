"""app.qml_backend.vm.usage_vm - YouTube Hunter (QML).

ViewModel behind UsagePage.qml. Surfaces the local quota ledger from
app.core.quota — today's API units, the search.list bucket, an estimated
runway from the measured burn rate, the last-7-days history, per-key spend,
and the cache stats — exactly like the legacy UsagePageMixin, minus the
painted QWidgets.

Everything here is read straight from app.core.quota (stdlib + sqlite under
the hood), so nothing depends on QtWidgets and the old app stays untouched.
The page drives a refresh timer in QML and calls refresh() on tick; the VM
only reads, it never mutates the ledger.
"""

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.config import load_app_config
from app.core.quota import (API_QUOTA_PER_KEY, QUOTA_KINDS,
                            SEARCH_QUOTA_DAILY_LIMIT,
                            _mix_from_history, _untracked_from_history,
                            api_quota_burn_rate, api_quota_capacity,
                            api_quota_history_by_kind, clean_api_keys,
                            keys_quota_used, niche_cache_stats,
                            quota_reset_local_str, search_quota_remaining,
                            search_quota_used)
from app.core.utils import humanize_count
from app.i18n import tr


# Human labels for the four tracked kinds + the pre-tracking remainder, shown
# in the call-mix donut and the daily-mix stacked chart. A function rather than
# a module dict so i18n.LANG (set from config after import) is honoured.
def _kind_label(kind):
    return {
        "search": tr("Keyword search"),
        "video": tr("Video stats"),
        "channel": tr("Channel lookup"),
        "other": tr("Other calls"),
        # NOT "Untracked", which read as "the app lost these". These are days
        # recorded before per-kind tracking existed: the total is known, the split
        # is not. Named for what it is so a large slice stops looking like a bug.
        "unclassified": tr("Before tracking"),
    }.get(kind, kind)


# What each kind actually costs, in the units YouTube bills. Shown in the donut's
# legend rows because "37% of units" and "1 unit per 50 videos" answer two
# different questions, and the second is the one that explains the first: a
# handful of keyword searches outweighs thousands of video lookups.
def _kind_cost(kind):
    return {
        "search": tr("100 units per search page"),
        "video": tr("1 unit per 50 videos"),
        "channel": tr("1 unit per 50 channels"),
        "other": tr("1 unit per call"),
        "unclassified": tr("total known, split not recorded"),
    }.get(kind, "")


# Chart-ramp index per kind (fed to Utils.chartTint in QML); unclassified is -1
# so it renders neutral grey. Keeps colour policy in one place shared by both
# the donut and the stacked bars, so a kind is the same colour in both.
_KIND_TINT = {"search": 0, "video": 1, "channel": 2, "other": 3,
              "unclassified": -1}


class UsageVM(QObject):
    """Read-only view over the quota ledger for the QML Usage & Quota page."""

    changed = Signal()

    @Slot()
    def retranslate(self):
        """UI language changed. Every string here is built in refresh(), so the
        signature has to be dropped first — otherwise the recompute produces the
        same signature as before and the emit is suppressed."""
        self._sig = None
        self.refresh()

    def __init__(self, parent=None):
        super().__init__(parent)
        # headline units
        self._units_used = 0
        self._units_capacity = API_QUOTA_PER_KEY
        self._units_frac = 0.0
        self._units_value = "—"
        self._units_sub = ""
        # search bucket
        self._search_used = 0
        self._search_frac = 0.0
        self._search_value = "—"
        self._search_sub = ""
        # runway
        self._runway_value = "—"
        self._runway_sub = ""
        # misc
        self._reset_text = ""
        self._keys = []          # [{name, tail, used, frac, state, tint}]
        self._cache_text = ""
        # v11 savings strip: the two numbers inside cacheText, kept apart
        self._cache_count = 0
        self._cache_saved_text = "0"
        # trend chart range (7 or 30) + the derived series
        self._range_days = 7
        self._trend = []
        self._trend_axis = []
        self._trend_cum_axis = []
        self._peak_text = "—"
        # v10 trend header: range total, daily average, active days, peak date
        self._trend_total_text = "—"
        self._trend_avg_text = "—"
        self._trend_active_days = 0
        self._peak_label = ""
        # call-mix donut
        self._mix = []
        self._mix_total_text = "—"
        # One line under the donut explaining the "Before tracking" slice when
        # there is one — see api_quota_untracked_days.
        self._mix_note = ""
        # gauge centre + caption
        self._capacity_text = ""
        self._units_pct_text = ""
        self._units_left_text = ""
        # Signature of everything the page renders, so refresh() can skip the
        # `changed` emit when nothing actually moved. The page polls on a timer;
        # emitting unconditionally re-evaluated every QVariantList property,
        # which QML sees as a new model — every chart replayed its grow-in
        # animation and every meter re-eased from zero, so the page looked like
        # it was permanently loading.
        self._sig = None
        self.refresh()

    # ── configured keys (re-read each refresh; Settings may change them) ──
    def _configured_keys(self):
        """Primary + backups, deduped — the same set the API layer actually
        rotates through. The old version only fell back to the primary when
        the backup list was empty, so a config that kept both undercounted
        the primary key's spend as a second, separate budget."""
        cfg = load_app_config()
        return clean_api_keys([cfg.get("api_key", "")] +
                              list(cfg.get("youtube_api_keys") or []))

    # ── properties ───────────────────────────────────────────────────────
    @Property(str, notify=changed)
    def unitsValue(self):
        return self._units_value

    @Property(str, notify=changed)
    def unitsSub(self):
        return self._units_sub

    @Property(float, notify=changed)
    def unitsFrac(self):
        return self._units_frac

    @Property(str, notify=changed)
    def searchValue(self):
        return self._search_value

    @Property(str, notify=changed)
    def searchSub(self):
        return self._search_sub

    @Property(float, notify=changed)
    def searchFrac(self):
        return self._search_frac

    @Property(str, notify=changed)
    def runwayValue(self):
        return self._runway_value

    @Property(str, notify=changed)
    def runwaySub(self):
        return self._runway_sub

    @Property(str, notify=changed)
    def resetText(self):
        return self._reset_text

    @Property("QVariantList", notify=changed)
    def keys(self):
        """[{name, tail, used, frac, state, tint}] per configured key."""
        return self._keys

    @Property(bool, notify=changed)
    def hasKeys(self):
        return len(self._keys) > 0

    @Property(str, notify=changed)
    def cacheText(self):
        return self._cache_text

    # ── trend chart (7/30) ────────────────────────────────────────────────
    @Property(int, notify=changed)
    def rangeDays(self):
        return self._range_days

    @rangeDays.setter
    def rangeDays(self, d):
        d = 30 if int(d) >= 30 else 7
        if d != self._range_days:
            self._range_days = d
            self.refresh()

    @Property("QVariantList", notify=changed)
    def trend(self):
        """[{label, total, totalText, frac, cumFrac, cumText, peak}] for the
        picked range. Bars are pre-scaled to the chart top and the cumulative
        line to its own right axis, so QML draws 0..1 and never back-computes
        an axis from raw/frac."""
        return self._trend

    @Property("QVariantList", notify=changed)
    def trendAxis(self):
        return self._trend_axis

    @Property("QVariantList", notify=changed)
    def trendCumAxis(self):
        return self._trend_cum_axis

    @Property(str, notify=changed)
    def peakText(self):
        return self._peak_text

    # v10 headline figures for the redesigned consumption card. Derived from
    # the same series as `trend`, so they can never disagree with the bars.
    @Property(str, notify=changed)
    def trendTotalText(self):
        return self._trend_total_text

    @Property(str, notify=changed)
    def trendAvgText(self):
        return self._trend_avg_text

    @Property(int, notify=changed)
    def trendActiveDays(self):
        return self._trend_active_days

    @Property(str, notify=changed)
    def peakLabel(self):
        """mm/dd of the busiest day in the window ("" when nothing was spent)."""
        return self._peak_label

    # ── call mix (donut) + daily mix (stacked) + avg sparkline ────────────
    @Property("QVariantList", notify=changed)
    def mix(self):
        """[{name, units, unitsText, pct, pctText, cost, tint}] over the last 30
        days, zero buckets dropped, `unclassified` kept when non-zero. `tint` is a
        ramp index for Utils.chartTint — colours stay in QML."""
        return self._mix

    @Property(str, notify=changed)
    def mixTotalText(self):
        return self._mix_total_text

    @Property(str, notify=changed)
    def mixNote(self):
        """Why there is a "Before tracking" slice, when there is one. A quiet line
        under the donut rather than a footnote nobody reads: a 62% grey slice with
        no explanation is the single most confusing thing on this page."""
        return self._mix_note

    @Property(bool, notify=changed)
    def hasMix(self):
        return len(self._mix) > 0

    # ── gauge centre ──────────────────────────────────────────────────────
    @Property(str, notify=changed)
    def capacityText(self):
        return self._capacity_text

    # ── v11: keys header + savings strip ──
    @Property(str, notify=changed)
    def unitsLeftText(self):
        """Units still spendable today across every configured key."""
        return self._units_left_text

    @Property(int, notify=changed)
    def cacheCount(self):
        return self._cache_count

    @Property(str, notify=changed)
    def cacheSavedText(self):
        return self._cache_saved_text

    # ── refresh ────────────────────────────────────────────────────────────
    @Slot()
    def refresh(self):
        keys = self._configured_keys()

        capacity = api_quota_capacity(keys) if keys else API_QUOTA_PER_KEY
        # Perf: per-key spend is read ONCE (one query) and reused for both the
        # headline total and the per-key rows below. Same arithmetic as
        # api_quota_remaining(): sum of each key's own remainder.
        key_used = keys_quota_used(keys) if keys else []
        remaining = sum(max(0, API_QUOTA_PER_KEY - u) for u in key_used) if keys else 0
        used = max(0, capacity - remaining) if keys else 0
        frac = (used / float(capacity)) if capacity else 0.0

        # card 1 — raw units
        self._units_used = used
        self._units_capacity = capacity
        self._units_frac = frac
        self._units_value = "%s / %s" % (humanize_count(used), humanize_count(capacity))
        # Gauge centre + caption pieces (template shows raw used + "of NK units"
        # + a "N% spent · M left across K keys" line).
        self._capacity_text = humanize_count(capacity)
        self._units_pct_text = "%d%%" % int(round(frac * 100))
        self._units_left_text = humanize_count(remaining)
        if keys:
            self._units_sub = tr("{p}% spent · {r} units left across {n} key(s) · one search = 100 units, any other call = 1").format(
                p=int(round(frac * 100)), r=humanize_count(remaining), n=len(keys))
            if len(keys) > 1:
                # Google's 10k/day is per Cloud project, and a key string does
                # not carry its project. Stating the assumption is the only
                # honest option; silently summing per-key would overstate a
                # multi-key setup that shares one project.
                self._units_sub += " " + tr(
                    "Each key is counted as its own project; keys from the same Google Cloud project share one 10,000/day budget.")
        else:
            self._units_sub = tr("No API key yet — add one in Settings to start tracking.")

        # card 2 — search.list calls. They draw on the same unit pool, so
        # "left" is the remaining units ÷ 100, per key (no separate bucket).
        s_used = search_quota_used()
        s_left = search_quota_remaining(keys) if keys else 0
        s_max = (capacity // 100) if capacity else SEARCH_QUOTA_DAILY_LIMIT
        self._search_used = s_used
        self._search_frac = min(1.0, s_used / float(max(1, s_max)))
        self._search_value = "%d / %d" % (s_used, s_max)
        self._search_sub = tr(
            "{n} more searches fit in today's remaining units · every search.list "
            "call adds one, Niche Finder Web-scrape adds none (100 units each, "
            "from the same 10,000/day pool)").format(n=s_left)

        # card 3 — runway
        rate = api_quota_burn_rate(7)
        if not keys:
            self._runway_value = "—"
            self._runway_sub = tr("Needs a key before it can guess.")
        elif rate <= 0:
            self._runway_value = tr("Untouched")
            self._runway_sub = tr("No spend recorded this week — nothing to burn through yet.")
        else:
            days = remaining / rate
            if days >= 1:
                self._runway_value = tr("{d} days").format(d=int(days)) if days < 999 else tr("Ages")
            else:
                self._runway_value = tr("{h} hours").format(h=max(1, int(days * 24)))
            self._runway_sub = tr(
                "At {r} units/day, your recent average. Roughly {s} more "
                "keyword searches.").format(r=humanize_count(int(rate)),
                                            s=int(remaining // 100))

        # reset countdown
        self._reset_text = tr("Resets at {t} your time").format(t=quota_reset_local_str())

        # ── trend chart (7 or 30) — bars pre-scaled to the top, cumulative
        # line pre-scaled to its own right axis ──
        # Perf: the 30-day history is fetched once and sliced for the 7-day
        # chart, the donut and the untracked count (it used to be read three
        # times per refresh).
        hist30 = api_quota_history_by_kind(30)
        by_kind = hist30[-self._range_days:]
        totals = [t for _d, t, _k in by_kind]
        t_peak = max(totals or [0])
        t_top = max(t_peak, API_QUOTA_PER_KEY // 10, 1)
        cum = 0
        cum_total = sum(totals) or 1
        self._trend = []
        for day, total, _kinds in by_kind:
            cum += total
            self._trend.append({
                "label": day[5:].replace("-", "/"),
                "total": total,
                "totalText": humanize_count(total),
                "frac": max(0.0, min(1.0, total / float(t_top))),
                "cumFrac": max(0.0, min(1.0, cum / float(cum_total))),
                "cumText": humanize_count(cum),
                "peak": bool(total == t_peak and t_peak > 0),
            })
        # 5 evenly-spaced tick labels for each axis, bottom→top.
        self._trend_axis = [humanize_count(int(t_top * i / 4.0)) for i in range(5)]
        self._trend_cum_axis = [humanize_count(int(cum_total * i / 4.0)) for i in range(5)]
        self._peak_text = humanize_count(t_peak)
        range_total = sum(totals)
        n_days = max(1, len(totals))
        self._trend_total_text = humanize_count(range_total)
        self._trend_avg_text = humanize_count(int(round(range_total / float(n_days))))
        self._trend_active_days = sum(1 for t in totals if t > 0)
        self._peak_label = next((p["label"] for p in self._trend if p["peak"]), "")

        # ── call mix over 30 days (donut) ──
        mix_raw = _mix_from_history(hist30)
        mix_total = sum(mix_raw.values())
        order = list(QUOTA_KINDS) + ["unclassified"]
        self._mix = []
        for kind in order:
            v = mix_raw.get(kind, 0)
            if v <= 0:
                continue
            pct = (v / float(mix_total) * 100) if mix_total else 0.0
            self._mix.append({
                "name": _kind_label(kind),
                "units": v,
                "unitsText": humanize_count(v),
                "pct": pct,
                # One decimal, because the interesting slices here are routinely
                # under 1% and "0%" beside 34 real units reads as a rounding bug.
                "pctText": "%.1f%%" % pct,
                # What this kind bills, so the share reads as a consequence of a
                # price rather than as an unexplained proportion.
                "cost": _kind_cost(kind),
                "tint": _KIND_TINT.get(kind, -1),
            })
        self._mix_total_text = humanize_count(mix_total)
        untracked_days = _untracked_from_history(hist30)
        if untracked_days and mix_raw.get("unclassified"):
            self._mix_note = tr(
                "“Before tracking” is {n} day(s) recorded before this app split "
                "spend by call type — the totals are right, the breakdown for "
                "those days was never stored. They drop out of this window on "
                "their own.").format(n=untracked_days)
        else:
            self._mix_note = ""

        # keys
        self._keys = []
        for i, k in enumerate(keys[:6]):
            ku = key_used[i]
            kf = min(1.0, ku / float(API_QUOTA_PER_KEY))
            if kf >= 0.95:
                state, tint = tr("Exhausted"), "primary"
            elif kf >= 0.75:
                state, tint = tr("Heavy use"), "warn"
            else:
                state, tint = tr("Healthy"), "secondary_container"
            self._keys.append({
                "name": tr("Key {n}").format(n=i + 1),
                "tail": "•••• " + (k or "")[-4:],
                "used": "%s / %s %s" % (humanize_count(ku),
                                        humanize_count(API_QUOTA_PER_KEY), tr("units")),
                # v11 key card: the same numbers, unformatted into one string
                "usedText": humanize_count(ku),
                "leftText": humanize_count(max(0, API_QUOTA_PER_KEY - ku)),
                "capText": humanize_count(API_QUOTA_PER_KEY),
                "frac": kf,
                "state": state,
                "tint": tint,
            })

        # cache line
        cached, saved = niche_cache_stats()
        self._cache_count = int(cached or 0)
        self._cache_saved_text = humanize_count(saved or 0)
        if cached:
            self._cache_text = tr(
                "{n} searches are cached locally. Reopening any of them from the "
                "Search Archive costs nothing — that is {u} units of quota you "
                "never have to spend twice.").format(n=cached, u=humanize_count(saved))
        else:
            self._cache_text = tr(
                "Nothing cached yet. Every search you run gets stored, and "
                "reopening it later is free.")

        # Only notify when something the page renders actually changed. Without
        # this the poll re-emitted identical data, QML treated each list
        # property as a fresh model, and every chart/meter replayed its
        # grow-in animation on a loop.
        sig = (self._units_value, self._units_sub, self._units_frac,
               self._search_value, self._search_sub, self._search_frac,
               self._runway_value, self._runway_sub, self._reset_text,
               self._capacity_text, self._units_pct_text, self._units_left_text,
               self._peak_text, self._mix_total_text, self._mix_note,
               self._cache_text, self._range_days,
               self._cache_count, self._cache_saved_text,
               tuple(tuple(sorted(d.items())) for d in self._trend),
               tuple(self._trend_axis), tuple(self._trend_cum_axis),
               tuple(tuple(sorted(d.items())) for d in self._mix),
               tuple(tuple(sorted(d.items())) for d in self._keys))
        if sig == self._sig:
            return
        self._sig = sig
        self.changed.emit()
