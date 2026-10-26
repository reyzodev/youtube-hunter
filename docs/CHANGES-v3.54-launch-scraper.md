# v3.54 Launch speed + Scraper backend

Launch
- main_qml.py: Main.qml and every page now compile on Qt's QML loader thread
  WHILE Python does the imports / DB setup (they used to compile after, on the
  GUI thread). Off switch: env YH_NO_PRECOMPILE=1.
- The in-window BrandSplash is unchanged — this build keeps the existing
  launch screen.

Scraper (DashboardVM) — backend for the results board
- Live results stream: resultsReset / resultsAppended(batch) / results() /
  resultCount, runChannel, runChannelVideos, lastExport.
- "Published" window: publishedWithin (0/7/30/90/365 days). Search runs pass
  publishedAfter to YouTube (no wasted 100-unit pages); uploads runs stop as
  soon as a page is fully older than the window.
- Recent sources (recentSources, forgetRecent), quotaLeft / keyCount /
  refreshQuota for a pre-flight cost line, copyText.
- sendToIdeas(picks) -> AI Ideas references; analyzeResults() -> Niche Scan
  (routed in Main.qml), free, no quota.
- Bug fix: export format picked in Settings now applies without a restart.
- SettingsVM.applyScrapePrefs(transcripts, formatIndex) for quick toggles.
- VIDEO_FIELDS now includes snippet.channelTitle.

## Round 2: the UI

Scraper page (DashboardPage.qml + new components/ScrapeResults.qml)
- Recent channels: one-click chips under the link (hover × to forget).
- Published window: Any time / 7 / 30 / 90 days / 12 months.
- Output: file type chips + Transcripts switch (Settings.applyScrapePrefs).
- Run card: Published + Transcripts rows, and a pre-flight cost line
  ("≈ N quota units · X left today") with a budget bar; turns amber when the
  run would not fit.
- Results board (streams while scraping):
  - Videos · Total views · Median · Engagement · Hit rate (2×+)
  - Top outlier hero card
  - Upload rhythm, strongest weekday, sweet-spot length, transcripts
  - Sort: Outliers · Momentum (views/day) · Views · Newest · Engagement
  - Title search, 24 at a time + "Show more"
  - Row: click opens on YouTube; hover → copy link / send to AI Ideas
  - Header: Deep scan (Niche Scan), Top 10 → AI Ideas, Open sheet
- Outlier score = views ÷ median of the ~14 videos published around it
  (era-adjusted, so a channel's slow years still surface their hits).
