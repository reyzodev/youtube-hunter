# Changelog

Release notes, newest first. Detailed extension notes live in
[`docs/`](docs/) (`CHANGES-v3.4x-extension.md`).

Version numbering restarted at **1.0.0** for the public release.

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
