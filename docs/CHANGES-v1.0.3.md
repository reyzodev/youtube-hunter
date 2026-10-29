# v1.0.3 — premium pass

## Window controls
- New `components/WindowGlyph.qml`: minimise / maximise / restore / close drawn live. Restore is two stacked windows (the back one slides out on maximise); close spins on hover. The maximised state no longer borrows the video player's `fullscreen_exit` corners.

## Browser cookies are opt-in only
- `download.py` / `cutter.py` no longer try every installed browser's cookies on a bot check. Only the browser picked in Settings is ever used.
- Picking a browser opens `components/CookieRiskDialog.qml` (account-ban warning, hold-to-confirm). "None" applies at once.

## Niche Scan
- "What earns the views" → `components/EarnBoard.qml`: do-more / skip / doesn't-matter cards, +/-% instead of ×, trust dots by sample size, category filter, a plain sentence for the hovered row, "How to read this". Data from `core/analysis/earn_read.py` (`Insights.earnRows` gains pct/verdict/strength/sentence, new `Insights.earnPlan`). Fixes the clipped "… videos" counts.
- AI brief: the prompt now sends each video's age + views/day (and vs. typical), the terms that EARN views and the fastest risers. New output: game_plan, video_ideas (5), title_formulas (example ids validated against the snapshot), keywords, avoid, competition. Shown by `components/BriefPlaybook.qml` under the intent sheet. Token budget 14k → 17k.

## Blueprint → Greenlight (UI text only; files, DB and config keys unchanged)

## Greenlight schema v7
- Dropped duplicates from the ask: execution.audio, packaging.timing, ab_plan.watch, playbook, seo.keywords (SEO shows discovery.search_queries instead).
- publish_plan must use the creator's CSV data or say to confirm the slot in Studio.
- New sections: Packaging (thumbnail text, focal point, title/thumbnail split, stand-out), Fast version, Fact check (tickable), Format funnel.
- Pacing is hidden when the Timeline (which already draws it) is shown.
