# Changelog

Release notes, newest first. Detailed extension notes live in
[`docs/`](docs/) (`CHANGES-v3.4x-extension.md`).

Version numbering restarted at **1.0.0** for the public release.

---

## Unreleased — Archive: no blank frame on entry, none when a section opens

- Entering Search Archive used to fade the whole page stack in from opacity 0,
  but the page you came from is already gone in that frame, so the window
  showed its bare background — black in the dark theme, white in the light —
  until the archive appeared. The entrance now starts at 0.9: the same 240 ms
  settle and 8 px rise, without ever exposing the page wash.
- Opening a keyword or channel section was a second flash: the master view was
  hidden in the same frame the detail view began a 120 ms fade from 0, so both
  were half-transparent over the wash. The master/detail swap is instant now,
  and the cold-open skeleton cards are up on the first frame instead of after
  a 120 ms grace period — the deck still cross-fades in when its pictures are
  ready, but the slot is never a page-coloured hole.

## Unreleased — HunterCore: an eclipse theme switch, and an archive built for 10,000 rows

- **The theme switch is now an eclipse.** The old wipe is replaced by a
  full-screen transition: the outgoing palette drains into a curtain, a
  tick-ringed sun rises, a moon in the incoming palette glides in from the
  side you clicked and covers it, and totality flashes a rim, corona and
  diamond-ring bead around the mark before the moon opens as an iris onto the
  new theme. All motion runs on the render thread; a slow frame can delay the
  cover but never strand the swap.
- **The Dashboard leads with the Hunter Core.** A 204 px LED gauge: 48 ring
  segments fill with the run's progress, the head segment glows and the next
  one blinks while scraping, a precision arc and bead track the exact
  percentage, and the core dish sweeps a radar beam behind the mark. The
  read-out underneath states videos per run and percent scraped.
- **Niche Finder's radar is one component now** (`HunterRadar`), rebuilt
  around the brand: a bezel of 72 ticks, orbit arcs, a beam painted once and
  rotated, contact blips that light as the beam crosses them, hero LOCK
  brackets on the best hit, and a sonar ring on the mark. The search panel and
  the empty state use the same component at different sizes.
- **Video cards have a channel "lock-on" hover.** Hovering the channel row
  grows a frosted accent capsule out of the avatar, scales the avatar, orbits
  a comet around it, draws an underline beneath the name and slides in an
  open-arrow. It costs nothing while you scroll: only the hovered card
  animates, the comet arc is painted once and only rotated, and every moving
  part freezes while the grid is gliding or Reduce motion is on.
- **Archive sections open off the GUI thread.** Reading a section's rows and
  computing its metrics used to run on the click; a 10,000-video section held
  the window for a beat. The read now happens on a worker, the header and
  skeleton cards land immediately, and the grid fills when the rows arrive —
  a superseded read is dropped by token. The constructor also no longer scans
  every download on disk synchronously.
- **A stopped scrape is saved in your format.** Stop a run halfway and the
  videos scraped so far are written beside the checkpoint in the format you
  picked (CSV, XLSX or SQLite, with a `_partial` suffix), and the modal tells
  you where. The JSONL checkpoint is still kept for resume; a later completed
  export deletes the stale partial. Quota and failure exits save the partial
  too.

## Unreleased — Scraper: the whole subtitle, not the first 3,000 characters

- A scraped video's Transcript column stopped after 3,000 characters — roughly
  five minutes of speech — so a podcast or a long tutorial exported a subtitle
  that ended mid-sentence with an ellipsis and nothing after it, no matter how
  long the video was. The column now carries the entire caption track, first
  line to last, for any runtime.
- The transcript cache that feeds both the scraper and AI Chat also cut entries
  at 120,000 characters. It now keeps the full track, and entries written by
  older builds at that cap count as missing, so one re-scrape replaces them
  with the complete text.
- XLSX exports still obey Excel's own 32,767-character cell limit; CSV, JSONL
  and SQLite exports carry the full transcript.

## Unreleased — UI pass: My channel, greenlights, and transfers you can see

- **AI Ideas now knows who is making the video.** A new "My channel" card takes
  the niche, the audience, hard constraints (Faceless, Solo creator, Phone only,
  Quick edits, No voiceover, Clip channel) and a forced output language. It is
  saved in `config.json`, rides along with every run and every single-greenlight
  rebuild, and is printed as a hard-facts block in the prompt, so ideas that
  ignore the creator (a face-cam plan for a faceless channel, a drone shot for a
  phone shooter) stop arriving.
- **Blueprints are now "greenlights"** in every page, toast, tip and tour step —
  the same saved records and DB schema, only the name the interface uses.
- **Running downloads and cuts are visible inside the app.** A compact capsule
  in the title bar shows one orb per job (thumbnail in its own progress ring)
  and a percentage; clicking it opens a panel with stage, meter, speed, ETA and
  Pause / Resume / Stop, and a click on a row opens the page that owns the job.
  Downloads from every page, Cutter cuts and extension cuts all feed it. The
  desktop live card is unchanged and still covers the window-closed case.
- **Browser cookies are strictly opt-in.** A bot check no longer makes the app
  borrow every installed browser's signed-in session on its own. Only the
  browser picked in Settings is ever used, and picking one opens a hold-to-
  confirm account-ban warning; "None" applies immediately.
- **Window controls are drawn, not borrowed** (`WindowGlyph`): minimise,
  maximise, restore (two stacked windows) and a close that spins on hover, with
  tooltips — the maximised state no longer reuses the video player's
  fullscreen glyphs.
- **Niche Scan now reads demand, not just supply.** "What earns the views"
  (length, format and title habits ranked by views/day vs. the set, with trust
  dots and plain-sentence reads), "Can a newcomer get in?" (channel-size ladder
  vs. the set's pace and the under-a-year-old channels that broke in, with a
  best-newcomer card), a ×lift badge on each recurring term, and a richer AI
  brief: game plan, five video ideas, reusable title formulas, keywords, what
  to avoid and a competition read.
- **Greenlights gained a v7 audit pack:** packaging brief (thumbnail words,
  focal point, title/thumbnail split, stand-out), fact check with tick-off
  verification, a "short on time" fast version and a format funnel. Duplicated
  fields were dropped from the ask (execution audio, packaging timing, the A/B
  "watch" line, playbook and SEO keywords — the SEO section now shows the
  discovery queries); old saved records still render their old sections.
- **Donate window, wide layout:** a brand rail (accent tile with the beating
  heart, perks, secure-checkout card, version) beside the page, a Safari-style
  address bar, rounded page frame, and a language control in the header that
  clicks the page's own ENG/FA switch.
- **Hunter's chat mark** is now an accent squircle tile (`HunterAvatar`) that
  orbits and breathes while thinking, and a Persian answer puts its header row
  on the right (mark → Hunter → model chip → time) to match the text.

## Unreleased — Cutter: pause stays put, live streams cut, and the picker knows what you already own

- **Pause no longer kills the cut.** Pausing used to stop reading ffmpeg's
  progress while the muxer kept running; the bar froze and the job ended as a
  truncated failure. The whole worker tree is now actually suspended in place
  (Windows `NtSuspendProcess` on yt-dlp and its ffmpeg children, plus a
  cooperative gate for the Python phases), the stall watchdog ignores paused
  time, and Resume continues from the same byte — verified on a 1080p
  re-encode and on a live-buffer cut.
- **Live streams are cuttable.** Paste a live link and the timeline becomes
  YouTube's DVR buffer (≈60 min): pick a window, and the cut is served from the
  locally stitched HLS segments with stream copy — no re-encode, no waiting on
  the live edge. The selection is remembered as "this window, N seconds before
  the live edge", so a stream that keeps sliding while you decide still delivers
  the moment you picked; a window that has already slid out of the buffer, or
  one right at the edge that is not published yet, says which of the two it is.
  The quality list, audio tracks and the IP/VPN note all come from the same
  probe as a normal video.
- **Cuts started in the browser extension are visible in the app.** The Cutter
  page's strip lists extension cuts live — progress, pause/resume, cancel and
  Play — and the desktop live card still takes over when the window is closed.
  They share the same job store, so a pause in either place is the same pause.
- **The quality dialog says which qualities you already have.** Each ladder
  column whose file is already on disk wears a check, and choosing it shows
  "Already downloaded — 48.2 MB on this device" with a **Play** button that
  opens the in-app player right there, with every other saved quality of that
  video in its gear menu. Files are matched from the downloads folder by
  `[video-id]` + quality key, so downloads from older builds count too; "Best"
  and the top resolution are recognised as the same file. Markers also appear
  when the probe fails, so the existing files are never hidden by a bad network.
- **Downloads: the last silent step says what it is doing.** A VP9/AV1 → H.264
  remux or an MP3 conversion held the row at "Merging…" for 10-30 s; the live
  phase text ("Converting to MP3…") now replaces it in the Downloads list as
  well, instead of the row dropping back to a determinate 99 % "downloading".

## Unreleased: Monetize Checker — revenue priced per format, not per sample

- The Shorts/long-form split was taken from the last 50 uploads and applied to
  **every** projected view, back catalogue included. On a channel that now
  posts Shorts that priced decades of long-form views at the Shorts pool rate:
  MrBeast (81.5% of his recent views are Shorts) read $494K/month when the same
  views at his long-form band are worth ~$1.3M; Nas Daily read $10K/month
  against ~$200K. The next 30 days are now split by each upload's **own**
  format, and the back catalogue by a Shorts share capped at the part of the
  channel's life in which Shorts existed at all.
- A sub-3-minute upload published **before Shorts existed** is long-form, not a
  Short. The duration-only rule was pricing a 2015 six-second clip at the
  Shorts pool rate.
- YouTube returns `topicCategories` in a varying order, and a tied niche score
  fell back to whichever topic arrived first: the same channel could read
  "Education" (≈$7 RPM) on one check and "Entertainment" (≈$1.65) on the next.
  Ties now break on match specificity, then match count, then a fixed table
  order — the same inputs always give the same band.
- The Partner-Program estimate uses the current projected Shorts share for its
  90-day window and a lifetime Shorts share for lifetime averages, instead of
  one recent-sample share for both.

## Unreleased: Monetize Checker — seconds, not minutes

- A long-form check fetched the channel page and then four watch pages **one
  after another**. Each of those pages is ~1.4 MB, so on a slow connection one
  check could sit for 3-5 minutes doing nothing but waiting. The channel page
  and every video probe now start together (`check_signals`) and the check
  waits for the slowest request instead of the sum.
- The pages are requested with `Accept-Encoding: gzip`: measured on a watch
  page, 1,426,904 bytes of HTML travel as 334,224 bytes — **4.3x less data**.
  A proxy that mangles the stream falls back to the raw bytes instead of
  losing the page. The same fetch backs the channel avatar and video-identity
  lookups in Downloads, which get the smaller transfer too.
- Two video probes per check instead of four (a Shorts channel: two Shorts
  plus one long-form upload, instead of four plus three). Ads, Super Thanks
  and mid-roll breaks are still read, and the checklist names how many videos
  were actually checked.
- Scraped signals are cached for 20 minutes, so re-checking the same channel —
  or switching the UI language — makes no page request at all. A failed fetch
  is never cached, so a network hiccup retries on the next check.

## Unreleased: Search Archive — cold open without a black grid

- The 24-card deck was armed by a blind 1.5 s timer after the page was
  built, then incubated in slices (~1.6 s) and held at opacity 0 for up to
  900 ms waiting for thumbnails. Opening a keyword / channel section early
  in a session showed an empty, page-coloured (black in the dark theme) slot
  for 1-3 s. The deck is now armed 250 ms after the page is actually in the
  window, a `VideoCardSkeleton` stand-in covers the slot while it builds or
  waits (and is skipped entirely on a warm cached switch), and the reveal cap
  is 450 ms.
- Thumbnails are released as a batch: `ArchiveVideoCard.holdPicture` keeps
  every picture behind its skeleton until all cards on screen have theirs
  (cap 1.5 s), then they land in one frame. `_pictureOn` is an imperative
  latch set by `_syncPicture()` rather than a binding, which removes the
  binding loop and stops the first row from appearing one card at a time.
- The paint-culling switch now depends on the cell position (`cell.y`,
  `deckLoader.y`, `detailCol.y`) instead of `mapToItem()` alone, so stale
  positions no longer make the first row pop in individually.
- Opening a section no longer replays the grid entrance: the entrance belongs
  to the deck's first build, and a section switch re-binds the data in place.
- `Archive.refreshDownloaded()` now scans finished downloads on a worker
  thread and applies the result with a token, so a long history on a slow or
  network drive cannot stall the first frame of Search Archive.

## Unreleased: Niche Finder — smooth first paint

- Result cards are created a few per frame while the grid is still invisible,
  and the grid appears once, whole, when the first two rows have their
  pictures (900 ms cap). A shorter page hides spare slots instead of
  destroying them and rebuilding them on the next search.
- Cards paint only within one card-row of the viewport, like Search Archive,
  so a long result set no longer composites every card on every scroll frame.

## Unreleased: Search Archive — viewport-only card painting

- Scrolling a section with 1,200+ videos painted all 24 cards every frame.
  Each card carries a layered thumbnail, a clip mask, a MultiEffect and a
  9-slice shadow, so the cards far outside the viewport were the whole GPU
  cost of the scroll. Cards now paint only within one card-row of the
  viewport; all 24 stay alive for paging, and `opacity` (not `visible`) is
  the off switch so the Layout keeps its geometry and never reflows. On the
  1,397-row group at 1280×820: 55 → 66 fps, p95 frame 36 → 26 ms, frames
  over 33 ms 13 → 4 per 3 s.
- Hover lift, cover zoom, elevation and quick actions now honour `scrollIdle`
  too — only the play disc / dim / glow did before, so the three heaviest
  hover effects kept firing under the cursor mid-scroll.

## Unreleased: Launch speed — QML precompile

- Main.qml and every page compile on Qt's QML loader thread while Python sets
  up the databases and ViewModels, so the existing in-window BrandSplash
  appears sooner. The launch screen itself is unchanged. Off switch:
  `YH_NO_PRECOMPILE=1`.
- Qt's FFmpeg backend log chatter is silenced at the source; media errors
  still reach the UI through `MediaPlayer.error`.

## Unreleased: Transcripts switch — no more red blink

- The Transcripts card faded its fill between `rgba(primary, 0.06)` and the
  opaque `input_bg`. ColorAnimation interpolates alpha and RGB together, so
  the middle of the fade was a stronger red than either state — the card
  visibly blinked on every flip. The wash now sits on its own layer and fades
  by opacity, so it moves straight between the two real states.

## Unreleased: Scraper results — 8 videos, then "Show more"

- The results board lists 8 videos before the Show more button (was 24).
  Each click adds 8; changing the sort tab or the title search starts at 8
  again. "Top 10 → AI Ideas" still picks from the full sorted/filtered list,
  not only the visible page.

## Unreleased: v3.54.1 — scraper gate corrections

- **False "IP blocked" on the first scrape.** `GeoVM.apiBlocked` was judged on
  a `www.youtube.com/generate_204` probe, but the scraper talks to
  `youtube.googleapis.com`: many VPN exits answer 403 / time out on the web
  frontend while the Data API keeps working. It now uses only the country
  check and a total outage, so the probe can no longer park the first run
  behind the dialog. The launch modal is shown only for a restricted country;
  offline / unreachable stay in the title-bar pill.
- **Transcript pause needs 3 consecutive refusals**, not one. A single
  video-specific bot check no longer pauses the whole run.

## Unreleased: Scraper "Fast lane" + calmer offline handling

- Ids are streamed: metadata downloads in parallel (3 pages in flight) while
  the id list is still loading. New module `app/core/scrape_pipeline.py`.
- Backup API keys are actually used: a key that runs out hands over to the
  next one mid-run (before, the run died on the primary key).
- Long-form / Shorts filter stops fetching ids once it has enough matches
  (search mode: ~half the quota in tests).
- Partial responses (`fields=`), 25 s request timeout (was 60 s), automatic
  fallback if the field mask is ever rejected.
- Internet drop mid-scrape: the run waits up to 5 min and resumes by itself.
- GUI updates throttled (progress only on % change, status ≤ 4/s).
- Connection lost mid-session no longer opens a modal; the title-bar pill +
  tray handle it. Plain "offline" at launch: pill only.

## Unreleased: Niche Scan saved-scan cards redesigned

**Bug fix.** Re-opening a saved scan never showed as selected: `openSaved()`
loaded the report but never rebuilt the strip's `isOpen` flags. It now refreshes
them, and the page reads a new `Insights.openKey` so the card flips the moment
it is clicked (a re-opened report keeps the key it was stored under).

**Redesign.** Fixed-width cards (272 x 64) with a kind tile (Keyword / Channel /
Viral icon), title, and a mono meta line. The open card gets an accent fill,
1.5px accent border + outer ring, a leading indicator bar, a solid accent tile,
"Viewing" in the meta line and a check badge (hover swaps it for delete). The
unexplained green dot is now an "AI" badge with a tooltip. Hover lifts, press
squeezes. Files: `pages/InsightsPage.qml`, `qml_backend/vm/insights_vm.py`.

## Unreleased: AI Chat is now "Hunter"

**AI Chat rebrand.** The assistant is now "Hunter" (was "Scope"), and its
iris icon is replaced by `HunterSigil.qml`: the crest inside lock-on brackets
that hunt while thinking and lock on while answering.

## Unreleased — Downloads no longer hang on "Updating downloader… 0%"

**Downloader refresh (the "works on my PC, stuck at 0% on theirs" bug).** When
YouTube answers a download with a bot check / 403 (common on flagged IPs and
VPN exits), the ladder refreshes yt-dlp from PyPI once per session. That
refresh ran inline with no overall deadline: `requests.get(timeout=120)` only
bounds each socket read, so on a filtered or throttled connection the wheel
trickled in forever and the row sat on "Updating downloader… 0%" while also
holding one of the two global download slots.

- The refresh runs on its own thread; a download waits for it **at most 35 s**
  (and stops waiting at once on Stop), then continues down the ladder with the
  engine it has, so the user gets a real result or a real error.
- It first compares versions and **skips** the download when the running
  yt-dlp is already the newest.
- `update_yt_dlp()` streams the wheel with a wall-clock budget, a watchdog that
  closes a stalled connection, cancel support and a live percentage
  ("Updating downloader… 42%").
- The new engine is unpacked beside the old one and swapped in only when
  complete; a failed update can no longer leave a half-deleted engine.

---

## Unreleased — First run: the setup dialog keeps its buttons inside the card

The one-time download-setup card ("deno + PO Token") was 460 px wide, but its
own footer needs 470 px — Skip (104) + From file… (135) + Download and install
(207) + the gaps — so the green button hung out of the card's right edge, and
the row's "Not installed" chip was squeezed 14 px out of its file row. The
width was capped at 460 while the card's *implicit* content width was 1091 px
(a wrapping `AppText` reports its un-wrapped width), which is why nothing
resized itself to fit.

- **The card is 560 px** — the footer gets 516 px for its 470 px of buttons,
  with ~46 px of slack for the "Try again" state. (The minimum window is
  980 px, so the cap never bites.)
- The dialog also carries `objectName: "denoDialog"` so a headless check can
  open it and measure.
- Audited every other first-run surface with the same measurement — open each
  modal popup and walk its item tree for anything leaving its parent's rect:
  message / unsaved-changes / confirm dialogs, the geo gate, the browser
  extension guide, the update dialog and the onboarding tour. All clean; what
  they do report is intentional bleed (drop shadows, glow blobs, scrollable
  guide content).

---

## Unreleased — Feel: the Search Archive stops looking "heavy"

Opening a saved section and turning its pages ran *smooth* but read as heavy: the
grid blanked itself, faded back in, and then played a staggered entrance across
24 cards — every single time, including on a page turn that only swapped the
data. Nothing was slow; too much was moving, for too long.

- **The grid never blanks any more.** It used to hide all 24 cards behind
  `opacity: 0` until the first two rows of thumbnails had arrived (650 ms cap)
  and put a second, full-card skeleton grid in their place. But a card already
  carries the title, the numbers, the channel and its own `ThumbSkeleton` over
  the media area the moment a section opens — only the picture is missing. So
  the cards now appear at once and the pictures fade into them. The whole
  reveal-gate (`_thumbLoading`, the ready map, both timers, the skeleton Loader)
  is gone with it.
- **A page turn is a data swap, not an arrival.** The staggered entrance now
  plays when you open a different section (`Archive.detailId` changes) and not
  when you page inside one. Paging used to re-run 24 full-card fades — each one
  a layer over a card that already owns three — which is what made it feel like
  the grid was reloading.
- **The arrival itself is shorter**: 8 ms per slot (capped at the first row) and
  a 150 ms fade / 200 ms rise, so the grid has landed in ~250 ms instead of
  ~460 ms.
- **Faster cross-fades**: a thumbnail lands in 180 ms (was 320), the skeleton
  hands over in 140 ms (was 190), and the master ⇄ detail switch is a 120 ms
  settle instead of a 190 ms dissolve.
- **The card's hover zoom is 300 ms, not 720.** It is the single most expensive
  thing a grid of these does — every frame re-renders that card's layered
  thumbnail and its mask — and it used to keep running for most of a second
  after the pointer had already moved on.

Measured on the real database: the motion after opening a section ends at
~290 ms (was ~460), and after a page turn at 0 ms (was ~460).

---

## Unreleased — Speed: the app stops stalling on its own database

The "small lag" that showed up everywhere — switching pages, opening the Search
Archive, coming back to Content Lab — was not the QML. It was **one line of
SQLite behaviour**, repeated a few times per click.

Every helper in `app/core/db` opens a connection, runs a statement and closes
it. Closing the last connection to a WAL database makes SQLite run a
checkpoint: it copies the write-ahead log back into the main `.db` and unmaps
both. On the real 23 MB `ideas.db` in `%APPDATA%\Roaming` that close measured
**70–130 ms**, and it landed on the GUI thread — so the QML profiler reported
"polish: 0 ms, render: 3 ms" while a single frame took **250–750 ms**.

- **One connection per database file is now held open for the life of the
  process** (`app/core/db/_sqlite.py`). The short-lived connections are never
  the last one out, so no checkpoint runs on close: the same close is now
  **0.1 ms**, and a full `archive_list_groups_full()` went from **75 ms to 5 ms**.
  The WAL still checkpoints on commit (`wal_autocheckpoint`, 1000 pages), so it
  stays bounded at ~4 MB.
- **`iso_age_hours()` tries `fromisoformat` first** instead of `strptime` and a
  fallback. The YouTube API always sends fractional seconds, so every archived
  row used to pay for a *failed* `strptime` parse (~16 µs): 1200 rows = 20 ms of
  GUI thread on every section open, again on every filter change. Now 1.6 ms.
- **Content Lab reads its library in one query.** The grid and the "combine with
  my blueprints" picker used to call `content_lab_get_ideas()` once per section
  — a connection, a statement and a WAL attach each time. `content_lab_ideas_by_entry()`
  returns the lot in one JOIN; opening Content Lab went from **~100 ms to ~28 ms**.
- **The archive grid keeps a fixed 24 cells.** Growing the model from 0 on the
  first section open built all 24 card trees (layers, masks, MultiEffects)
  inside the click; they are now built with the page during the background
  warm-up and opening a section only re-binds them: **~990 ms → ~250 ms**.
- **Thumbnail skeletons stop animating when the image fails.** `active` only
  checked `status !== Ready`, so a blocked / unreachable `i.ytimg.com` left every
  card shimmering forever — a permanent per-frame cost on exactly the networks
  where the app is already slow.
- **Exit is quiet again.** Teardown re-evaluates `Theme.*` / `I18n.tr()` bindings
  after their context properties are released; the two extra wordings
  ("Cannot call method … of null", "Value is null …") are muted only after
  `aboutToQuit`, like the original one.

Measured on the real database, 14 pages, worst frame during a page switch:
`Archive 255 → 34 ms`, `Content Lab 743 → 19 ms`, everything else ≤ 35 ms
(was up to 45 ms). Page-to-page `click → visible` is 13–36 ms.

---

## Unreleased — Search Archive: filters on a saved section

A saved section used to be read-only: the only knobs were the quick text box and
the timeframe, and anything sharper meant going back to Niche Finder.

- **A Filters sheet on any open section**, with the same vocabulary as Niche
  Finder's "Refine current results": subscriber and view ranges, duration /
  channel age / upload-count / sort picks, and minimum outlier, velocity and
  engagement. The pipeline is the same code path (`apply_niche_filters` →
  `sort_niche_rows`), so a saved section cuts exactly like the search it came
  from — and the bounds that mean nothing for a single channel (subscriber
  ranges, subscriber sorts) are hidden there instead of pretending to work.
- **The active count is on the button**, so a section never looks empty because
  of a filter you forgot about.
- **Dialog backdrops fade instead of snapping.** The modal scrim had no
  `Behavior on opacity`, so it appeared instantly and vanished in a single frame
  while the card was still animating out — a stutter on every close. It now
  fades both ways, and re-captures the frozen app behind it on each open, so the
  second dialog does not show the app as it looked the first time.

---

## Unreleased — Niche Finder: a country means that country's content

Picking **Germany** used to return Indian uploads. `regionCode` only says "can be
watched in Germany", and a search with no query is "the most-watched uploads on
all of YouTube" — so the Country filter was labelling, not filtering.

- **The picker now means content made for that market**: a breakout search sends
  `relevanceLanguage` (the market's main language) with the region, and the
  language detector (v4, rebuilt with each language's real function words and
  title staples) decides whether a title belongs to that market. The old
  separate Language dropdown and the Broad/Smart/Strict dial are gone — one
  Country picker, one sentence from the VM explaining exactly what it does.
- **Keywords are translated for non-English markets** (`app/core/niche/translate.py`):
  "king" + France searched nothing because French titles say *roi*. Each
  comma-separated keyword is translated on its own (Google's public endpoint,
  then your AI provider, then as typed), memoised for the session, and switched
  off with `"niche_translate_kw": false`. A failed translation never fails the
  search.
- **New sort: "Outlier · vs channel average"** — views ÷ the channel's own
  average video, the cleanest outlier read there is. Appended to the sort table,
  so every saved Search Archive sort index keeps its meaning; Niche Finder shows
  the subset that makes sense there.
- **Channel age** is captured from the same `channels.list` call, and the
  **engagement** sort no longer crowns a 40-view upload with 8 likes: under 1K
  views a row sinks below every row that has an audience.
- **Insights:** the brief's claims are now a proper evidence ledger — each claim
  resolves its cited videos, carries an evidence class with its own colour, and
  the page counts what it could and could not cite.
- **Archive cards** show the channel-outlier multiplier for Niche Finder rows
  (Search Archive cards keep their three columns).

---

## Unreleased — Cutter: the clip size you see is the clip you get

A 1080p cut used to come out at ~12 Mbit/s against a 2–5 Mbit/s source, so the
"≈ 44 MB" the Cut panel showed for a 2½-minute clip landed as 166 MB.

- **Cuts are bitrate-targeted now** (ABR with a peak cap, the same approach the
  downloader's H.264 conversion uses) instead of a fixed CRF. The target is
  derived from the source stream's own bitrate, the codec it is in (VP9/AV1/HEVC
  need more bits than H.264 for the same picture) and the chosen level, and the
  estimate in the Cut panel is computed from those exact numbers — so the size
  shown before cutting is the size you get.
- **Three levels**, `"cut_quality"` in config.json: **High** (editing/archiving),
  **Balanced** (default — visually the same for sharing, roughly half the size),
  **Small** (a little softer on fine detail). The CRF table stays as the fallback
  when a source bitrate is unknown. Exposed in Settings → Cutter.
- **Hardware H.264** (NVENC / Quick Sync / AMF) is picked once per process by a
  3-frame test encode, with libx264 as the guaranteed fallback — a long 1440p/4K
  cut no longer pins the CPU.
- **Up to 2 s of dead time removed from every cut**: the stall watchdog naps on an
  Event instead of `sleep(2)`, so it wakes the moment ffmpeg exits.
- **The extension's Cut tab** shows the same estimate, from the same numbers.

## Unreleased — Downloads: a shorter ladder, fewer dead ends

- The client ladder is down from 12 rungs to 5. With a JS runtime and PO tokens
  required before any download, `android`/`ios` (DroidGuard), `visionos` and the
  duplicates could only fail — each one a 2–6 s round trip on the failure path.
- Cookie browsers trimmed to the stores that actually decrypt on Windows
  (Firefox, Edge, Chrome, Brave); Chrome 127+ App-Bound Encryption refuses
  yt-dlp outright, so walking the forks only added failing rungs.
- The JS-runtime search is cached for 60 s and invalidated when deno is
  installed or removed, so the first download after setup no longer re-scans.

## Unreleased — smaller things

- The onboarding tour is versioned (`TOUR_VERSION`): a redesigned tour shows
  itself once more, even for installs whose config already said "seen". It also
  gained a Downloads step and the arrow/Esc hint.
- Search Archive: the groups listener uses the signal that actually fires
  (`changed`), so the list refreshes after a rescrape.
- Packaging: Chromium's debug resource packs and 52 of its 53 locale packs are
  trimmed from the build (~130 MB). Installer is now ~235 MB.

---

## Unreleased — "Part of this app has been blocked"

Windows 11 Smart App Control refuses to run `bgutil-pot.exe`, the bundled PO Token helper,
because it is not digitally signed: *"we can't confirm who published bgutil-pot.exe that the app
tried to load"*. The file was present, so the app still reported the helper as ready and the
only symptom was a download failing later for an unrelated-looking reason.

- `pot.py` now keeps the reason a start attempt failed (WinError 225/226/4551 and the
  policy/access-denied codes read as a security block, anything else as a broken helper) and
  clears it when the helper comes up.
- Settings → PO Token helper says **"Blocked by Windows"** with the full explanation instead of
  "Ready", and a one-time notice says it out loud a few seconds after startup.
- The text names the only two real answers: turn Smart App Control off, or sign the build. Code
  signing is the only fix that does not ask the user to change a Windows setting.

---

## Unreleased — Monetize Checker: Shorts fixes

- **The 10M Shorts bar is judged the way YouTube judges it.** The bar is checked once, at
  application; an accepted channel stays in the Partner Program when views dip. The check now
  passes when EITHER the last-90-days estimate OR the channel's lifetime average per 90 days
  clears 10M (the busiest 90-day stretch can never be below the average one). Same for the
  4,000 watch-hour route, and either route counts whatever format the channel posts most.
- **Back catalogue counted.** The 90-day estimate only saw the fetched uploads, so a channel
  with 295.7M lifetime views read "~2.4M, not monetized". Views outside the fetched uploads
  are now spread over the channel's age and their 90-day slice is added.
- **50 recent uploads instead of 15**, at the same quota cost (still 1 playlistItems + 1
  videos.list call).
- **No more fake "Ads: NOT FOUND" on Shorts channels.** A Short has no ad slot of its own
  (Shorts ads run between Shorts in the feed and are pooled), so probing Shorts for ads could
  never find anything. Shorts are still read for Super Thanks; the ad probe goes to up to 3 of
  the channel's long-form uploads, and when there are none the row is shown as an info note
  that does not count against the channel.

---

## Unreleased — Viral Radar (Niche Finder)

**Niche Finder now opens on what is viral right now.** No keyword needed: the page reads
YouTube's trending charts on first open and ranks them **Views ÷ Subs** by default, so
huge videos from small channels float to the top. Type a keyword and the normal search
replaces it; the **Viral now** button brings it back.

- **Market** (Global = 8 big markets merged, or one country), **Category**, **Window**
  (24h / 48h / 7d / 30d), **Source** and **Rank by**, all on the radar header.
- **Sources:** *Trending chart* (videos.list `chart=mostPopular`, ~1 unit per 50 videos)
  or *Breakouts* (keyword-less `search.list` ordered by views in the window, 100 units/page,
  surfaces small channels that never make the chart).
- Every Tuner cut (subs / views / multiplier / format / language) applies live, zero quota.
- Cards show their chart position (**#3 US**).
- **Never auto-archived.** *Save to Archive* merges the radar into a growing
  `Viral · <market> · <category>` section (labelled **VIRAL**); starring one card files it
  there too (the section is created on demand).
- Radar runs are cached for an hour. *Refresh* skips the cache. *Open with Viral now*
  toggles the auto-load (saved in config under `viral_radar`).

Files: `app/core/niche/viral.py` (new), `app/qml/components/ViralRadarBar.qml` (new),
`app/qml_backend/vm/niche_vm.py`, `app/qml/pages/NichePage.qml`,
`app/qml/components/ArchiveVideoCard.qml`, `app/qml_backend/vm/archive_vm.py`.

---

## 1.0.0 — 2026-10-22  *(internal: 3.52)*

First public release. One Windows app that does the whole loop — research a channel, find the
outliers, write the brief, download the video, cut the clip — plus a **Hunter button inside
YouTube** that does the last two from the browser.

**In-app updates — no trip to GitHub.** The app asks GitHub Releases for the newest
published version 6 s after launch and every 6 hours. When there is one:

- **Update button** next to the tour (?) button in the title bar: it pulses while an update
  waits, turns into a progress ring while it downloads, and into a restart icon when ready.
- **Update popup**: version from -> to, date, size, Markdown release notes, live percent,
  speed and time left.
- **Verified and automatic**: the installer is checked against GitHub's SHA-256 digest, then
  the app closes, installs silently and reopens itself. The user never leaves the app.
- `"auto_update": false` in `config.json` turns the checks off; `docs/UPDATES.md` explains how
  to publish a release.

**Search Archive pages twelve at a time.** A library of forty saved searches was one
endless wall with no sense of place. The section grid now shows twelve cards a page under the
app's own pager, with a "13-24 of 37" counter beside the search box; search and the Favorites
tab page through their own filtered result, and a section you delete can no longer leave you
stranded on a page that no longer exists.

**Fixed in this build.**

- The completion notice no longer lands on top of the YouTube panel. While the panel is on
  screen for that download or clip, the desktop card waits: navigate away (or close the panel)
  and it slides in on the page you moved to. Nothing is duplicated, nothing is covered.
- The extension stopped logging console errors on every page. Its webfonts were built from
  `chrome-extension://` URLs, which the browser refuses to load from a youtube.com document
  ("Domains, protocols and ports must match"), so the panel had quietly been falling back to a
  system font; the bytes are read through the extension and handed to `FontFace` directly now.
  The stylesheet is only ever injected as text, never as a cross-scheme `<link>`.
- The Donate pill is back and opens `https://donofa.com/youtube_hunter` inside the app.
- The monetization check no longer under-reports Shorts. It only counted videos *published*
  in the last 90 days, so a channel with 32M lifetime views that had gone quiet was told it
  "hasn't got the 10M" — directly under the 32M printed in its own header. It now projects
  views *earned* in the window from every recent upload, says in the row that the figure is a
  projection, and when the Join button settles the verdict on its own it explains why the
  estimate underneath can still sit below the bar. Notes are also no longer counted as
  signals in the "2 of 6 found" line.

**Support window — the Donate pill opens the page inside the app.** No more throwing the
user out to a browser tab: a single card over the blurred app, with the donation page live
inside it (QtWebEngine), so picking an amount, filling the form and paying all happen
without leaving YouTube Hunter.

- Header with the brand mark, the page's host, Back (once you have navigated), Reload, Open in
  browser and Close. A loader covers the first load instead of a blank rectangle, and a failed
  load offers Try again / Open in browser rather than dying silently.
- The page frame is sized so the whole form fits on a maximised window; the header chip and the
  footer lock line make it obvious whose page you are on.
- Payment gateway pop-ups (`window.open`) are taken over by the same view instead of being
  swallowed.
- The address is one line: `DONATE_URL` in `app/constants.py`, overridable per install with
  `donate_url` in `config.json`.
- With no address set the app never loads Chromium: the Support window (and QtWebEngine with
  it) is only built when there is a page to open, and the Donate pill hides itself. Verified
  in the packaged build: zero WebEngine modules in the process, and no page is ever loaded
  until the card is opened.
- The build now keeps QtWebEngine (`QtWebEngineCore.dll`, ~195 MB) in the bundle, and the
  Google API discovery-cache trim that used to live beside the WebEngine trim is back.

**Premium pass.**

- Arrival: the card rises and settles with a slight overshoot, then an accent halo blooms from
  behind its top edge and keeps breathing while it is open; leaving is quicker and quieter.
- The card is a lit object: soft drop shadow, accent-warm rim fading to a hairline, faint accent
  wash from the top, specular top line.
- Header: beating-heart glass tile (races on hover), bolder title, a live security chip (lock +
  Secure / Not secure + the host the view is on right now), Back / Reload / Open grouped in one
  pill (Reload spins while loading), separate Close.
- A thin load beam under the header shows progress for gateway steps after the first load.
- Keyboard: Ctrl+R / F5 reload, Alt+Left back, Esc close; keycap hints in the footer.

**Loading + offline.**

- New loader, "Heartline" (`components/DonateLoader.qml`): the brand mark assembles, then beats
  lub-dub with echo rings; a ring around it fills with the page's real load progress (with an
  honest trickle so it never looks frozen), a comet orbits on the render thread, two accent
  glows drift behind, and the status line follows the stage of the load. It blooms out when the
  page lands.
- Internet drops while the card is open: the "Signal lost" gate now opens **behind** the card
  (card `z: 50`, keyboard stays with the card) instead of covering the donation page.
- Chromium's own error page is disabled inside the card, and the failure panel is opaque, so a
  browser error never bleeds through. Offline gets its own state ("You're offline" + waiting chip)
  that reloads the page by itself once the connection is back (Geo restore or a small HEAD probe).
- The app behind the card now actually blurs (18 px, deeper dim). The card had `dim: false`,
  which stopped Qt from ever creating its DialogScrim, so there was no blur or dim at all.
- Log noise from the donation page is muted: its JS console messages (Next.js preload warnings)
  are swallowed, and Chromium's own net logging runs at `--log-level=3`.
- Aborted loads (`-3`, e.g. Reload replacing a load) no longer flash the failure panel.

**Fixes.**

- **Esc closes the card.** `closePolicy: CloseOnEscape` was the whole bug: on this Qt build the
  popup item answers the key's shortcut-override and then never acts on the press, so the key was
  swallowed in every focus state (reproduced with a bare `Popup`). The card now uses
  `NoAutoClose` plus an explicit window-level `Shortcut`, which is dispatched before the focused
  item — it works with the card focused and after clicking into the page.
- **Tooltips inside the card show in the right place.** A tip declared inside a Popup is built
  while the popup is closed, when there is no window overlay to reparent onto, so it stayed a
  child of its button: drawn under the card's own content, clipped, and positioned in the wrong
  coordinate space. `AppTooltip` now adopts the window overlay lazily on first show.
- **Only `mailto:` and `tel:` are handed to the OS.** A page can no longer make the app launch an
  arbitrary scheme handler (`file:`, `smb:`, a custom protocol) through a link or a pop-up;
  everything that is not a web page and not one of those two is dropped.
- **The backdrop is frozen while the card is open** (`DialogScrim.frozen`). `live: true`
  re-rendered the whole window into a texture every frame, and at 18 px of blur the difference is
  invisible; this was the heaviest thing on screen during a donation.
- **The donation address is not published in this tree.** `DONATE_URL` ships empty and the Donate
  pill hides itself while it is empty, so the app never shows a button that goes nowhere. Set the
  constant, or `donate_url` in `config.json`, to turn it on.


**Research**
- Channel and keyword scraper with quota-aware pacing, depth control, sorting and continuation.
- Outlier scoring against the channel's own baseline (3×–30× videos surface instead of raw view counts).
- Niche Finder with automatic query widening, Search Archive in SQLite, and a channel **Snapshot Insights** brief.
- **Brief (Dossier)** redesign: statement hero, confidence bands (Observed / Inferred / Needs Studio), intent sheet, signals with a sliding segmented control, openings / questions / experiments.

**Creation**
- AI Ideas that turn an outlier into hooks and angles, using your own provider.
- Content Lab: a four-part blueprint (hook → structure → beats → CTA) exported as a styled PDF, Persian or English.
- **AI Chat**: conversational prompt (no fixed Verdict/Findings template), local turn classification, **batch links (up to 50 at once)**, saved-brief analysis, resource digests on a bounded worker pool.

**Production**
- **Downloads**: quality presets with real sizes, container choice (MP4 / MKV / WEBM), audio-only with format choice (MP3 / M4A / OPUS / WAV / FLAC), **audio-track / dub selection** (original, creator dubs, auto-dubs), pause & resume, subtitles, thumbnails, and a client-ladder retry chain with optional browser cookies.
- **Video Cutter**: frame-accurate In/Out, live preview, stream-copy or re-encode, video **or** audio output in the same eight formats, local files, dubbed audio, and drag-out to Explorer / Premiere / Telegram.
- **Hunter button (Chrome/Edge, Manifest V3)**: a Download tab and a Cut tab on the YouTube page itself, with a zoomed ruler, an overview strip, format and dub pickers, a live progress capsule with pause/resume, Play / Show in folder, and a desktop live card that takes over when you leave the page. Launches the app through `youtubehunter://` when it is not running.
- **Live activity cards** for every download and cut, in-app or from the browser.
- **Connection guard**: probes YouTube itself (not a country list), re-tests every 60 s (10 s while blocked) and on network changes, and reopens the gate the moment a VPN drops.
- **Transcripts** with two engines and proxy/cookie support.

**Under the hood**
- PO Token helper (bgutil-pot 0.8.1, GPL-3.0) bundled and required, so downloads keep full quality on flagged VPN / datacenter IPs.
- The quality probe judges every client answer (a thin 360p-only list no longer wins) and sticks to the client that gave the real one for 30 minutes.
- The pre-flight extraction is reused for the download itself (`process_ie_result`), probe results are cached for 15 minutes, and the link read is reused between paste and cut — that is where most of "Preparing…" went.
- Text selection no longer ghost-doubles (`TextLayout` bridge applies the real line height to the hidden editor).
- Page switching no longer rebuilds every card; archive paging, favourite toggling and download ticks are O(page) instead of O(all videos).
- Persian UI audited end to end (2347/2347 strings translated), RTL-correct in every new panel.

## Earlier releases

1.0.0 is the first public release. The 3.x numbers were internal builds of the same
application (3.51 = 1.0.0); their notes are summarised in the sections above.
