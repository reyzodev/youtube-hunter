# Changelog

Release notes, newest first. Detailed extension notes live in
[`docs/`](docs/) (`CHANGES-v3.4x-extension.md`).

Version numbering restarted at **1.0.0** for the public release.

---

## 1.0.0 — 2026-10-21  *(internal: 3.51)*

First public release. One Windows app that does the whole loop — research a channel, find the
outliers, write the brief, download the video, cut the clip — plus a **Hunter button inside
YouTube** that does the last two from the browser.

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
