# v1.0.2 — Niche Scan: what EARNS, and can a newcomer get in

The Measured lens described supply (what got made: length mix, freshness,
who holds the views, recurring terms). It never answered the two questions a
creator decides with: *which choices earn views here* and *is it too late to
start*. Both are now computed (no API, no AI, no quota) from the same rows.

## New
- **What earns the views** (after the headline tiles): for each choice
  (length bucket, Shorts vs long-form, number / question / bracket titles,
  short vs long titles, captions) the median views/day of its videos ÷ the
  set's median views/day. Diverging log bar (½× and 2× equally far from 1×).
  Hidden unless the group AND the rest each have ≥4 dated videos.
- **Can a newcomer get in?** (after "Who holds this niche"): channel-size
  ladder with each tier's pace vs. typical and "k of n beat typical"; channels
  under a year old that made the list, how many of their videos beat the
  typical pace, and the best newcomer video (click opens it).
  Verdict tag: Newcomers get in / Possible, rarely / Incumbents only / Not
  enough data.
- **Terms**: each chip now carries a ×lift badge (views/day of videos using the
  term vs. the set, 3+ videos), so "common" and "carries views" are separate.
- **Verdict line**: new readings for newcomers and for a strong (≥1.8×) choice.
- **AI brief prompt**: WHAT EARNS and NEWCOMERS lines, so the brief can tell
  supply from demand.
- **Limits**: coverage row for channel creation date.

## Files
- `app/core/analysis/snapshot.py`: `_daily`, `_lift_groups`, `_term_lifts`,
  `_newcomers`, size tiers gain views/day, `lift_label`, `lift_group_label`.
- `app/qml_backend/vm/insights_vm.py`: `earnRows`, `earnBaseText`,
  `earnDatedRows`, `entryLadder`, `entry`; `topics` gains `lift` / `liftText`.
- `app/core/ai/insights.py`: overview block lines.
- `app/qml/pages/InsightsPage.qml`: two panels + term lift badge.

Saved reports are rebuilt from their stored rows, so old scans get the new
panels too.
