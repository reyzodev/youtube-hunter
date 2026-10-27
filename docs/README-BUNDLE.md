# YouTube Hunter — source bundle

A trimmed copy of the project: everything needed to **run and read** the app,
with the build output and the 139 MB ffprobe binary left out.

**Version: 1.0.1** (internal 3.58) — rebranded from Niche Scope (new logo,
`YouTubeHunter.exe`, `YouTubeHunter-Setup.exe`). Internals kept on purpose so existing installs keep
working: the QML module is still `NicheScope`, the per-user runtime folder is
still `NicheScope`, the config folder is still `%APPDATA%\YoutubeScrapperCyber`
and the installer AppId is unchanged (so it upgrades an existing install in
place). The changelog (`CHANGELOG.md`) has the full history; the rebrand is
written up in `docs/CHANGES-rebrand-youtube-hunter.md`.

## What the app is

A Windows desktop app (Python + PySide6 / Qt Quick QML) for YouTube research:
scrape a channel, find outlier videos, turn them into content blueprints,
download them, and cut clips. Entry point is **`main_qml.py`**.

The interface is **English only** — there is no language switch and no
translation table to update.

## The Support (donation) window

The **Donate** pill in the sidebar opens `components/DonateOverlay.qml`: a card
over the blurred app with the donation page loaded live inside it by
QtWebEngine. Nothing about a payment touches the app — the web view is a window
onto the provider's own page.

**The address is not published in this tree.** `DONATE_URL` ships empty, and
while it is empty the Donate pill is hidden — no button that goes nowhere. To
turn it on, either edit one line in `app/constants.py`:

```python
DONATE_URL = "https://your-page.example"
```

…or, without rebuilding, put

```json
"donate_url": "https://your-page.example"
```

in `%APPDATA%\YoutubeScrapperCyber\config.json`. The value there wins over
`DONATE_URL`, and only `http(s)` addresses are accepted. The chip in the
window's header shows whatever host that resolves to.

Because the window hosts a real browser, the build must keep QtWebEngine
(`QtWebEngineCore.dll`, ~195 MB) — `YoutubeScrapper.spec` no longer trims it,
and `main_qml.py` calls `QtWebEngineQuick.initialize()` before the QML engine
starts. If QtWebEngine is missing, the Donate pill falls back to the system
browser.

## How to run it

```bash
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python main_qml.py
```

Needs Python 3.11+ (built and tested against 3.13) and a desktop session —
it is a Qt window, not a web app. On Linux/macOS set
`QT_QPA_PLATFORM=offscreen` only if you want a headless smoke test.

A YouTube Data API key is entered inside the app (Settings) and stored in the
user's config; no keys are in the source.

## What is NOT in this bundle

| Missing | Why | Effect |
|---|---|---|
| `assets/bin/ffprobe.exe` | 139 MB, larger than everything else combined | Everything runs; only **mp3 audio downloads**, the **local-file probe** in the video cutter, and the quality probe need it. Drop it back in and those work. |
| `assets/bin/deno.exe` | 93 MB JS runtime (yt-dlp's YouTube challenge solver) | Everything runs; the app **downloads it on demand** the first time a YouTube download needs it — the built installer carries it pre-bundled, so end users never fetch it. |
| `assets/bin/bgutil-pot.exe` | 45 MB PO Token helper (bgutil-pot 0.8.1, GPL-3.0) | Everything runs, but **downloads, resumes and YouTube cut-links stay locked** — since 3.41.5 it is a required part of the download engine. Put it back (plus `bgutil-pot-NOTICE.txt` and `bgutil-pot-GPL-3.0.txt`) or install it from the app's setup dialog; the built installer carries it. |
| `dist/`, `build/`, `Output/` | PyInstaller + Inno Setup output (~670 MB) | Regenerate with `build.bat`. |
| `.build-venv/` | the isolated build venv (~870 MB) | Create your own; see above. |
| `__pycache__/`, `*.pyc` | compiled copies of the `.py` files that are here | none. |

## Layout

```
main_qml.py            the app entry point
app/                   all source: Python backend + QML UI
  qml/                 every screen (Main.qml + pages/ + components/)
  qml_backend/         the ViewModels the QML talks to
  core/                the actual logic (YouTube API, niche search, cutter, AI)
  ui/                  icons / fonts / theme helpers (remixicon map, palettes)
fonts/                 the bundled Latin + Persian (Vazir) fonts
assets/                icons (v8 SVG set + app icon) — no binaries
tools/                 build_icons.py / scale_nav_icons.py (icon art) and
                       check_hover_flicker.py — the hover "blink" lint
docs/                  BUILD, INSTALL, EXTENSION and the per-release notes
screenshots/           current UI, for reference
```

## Conventions worth knowing before changing anything

These are the ones that silently produce wrong output rather than an error:

- **Icons:** every `IconGlyph`/`IconButton` `name` must exist in
  `app/ui/icons.py` → `ICON_MAP`. A name that is not in the map renders as
  *nothing* and raises no error at all.
- **Never strip `file:///` off a path by hand.** QML file dialogs hand over
  percent-encoded URLs; use `app.core.utils.local_path_from_url()`.
- **Qt 6 QML has no `Item.cursor`** — use `MouseArea.cursorShape` or
  `HoverHandler.cursorShape`.
- **Version lives in three places** and they must agree: `app/constants.py`
  (`APP_VERSION`), `version_info.txt`, `installer.iss` (`MyAppVersion`).
- **Pages are built lazily.** `Main.qml`'s `StackLayout` holds one `Loader` per
  page; a page is instantiated the first time it is shown and then kept, so
  navigating back is instant and page state survives. Building every page up
  front cost 3.4 s of the ~5 s startup, which is why this changed. The indices
  still matter: Downloads = 8, Snapshot Insights = 11, Video Cutter = 12,
  AI Chat = 13 (see `PAGE_*` in
  `app/qml_backend/app_controller.py`). A new page goes at the END of the stack
  so no existing index moves. Verify with `.workbuddy-ai/verify-lazy-pages.py`,
  which counts the built Loaders rather than trusting a screenshot.
- Design tokens (spacing/radius/type/motion) live in `app/qml/Tokens.qml`;
  colours come from the live `Theme` bridge. Do not hardcode spacing.
- **`YoutubeScrapper.spec` trims the Qt payload.** PyInstaller's Qt hook collects
  every Qt module, not the ones the app imports. Before adding to
  `_DEAD_QT_DLL_PREFIXES` / `_DEAD_QML_PATHS` there, read the note in the spec —
  a DLL that `Qt6Quick` links against statically would stop the process starting
  at all. QtWebEngine is deliberately **kept** (~195 MB): the Support window is a
  real browser view. Trimming it again makes the Donate pill fall back to the
  system browser, silently.

## Checking a change without a display

```bash
# instantiates every page; any QML load error prints here. 124 = still running = OK
QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py
# lint one file (expect a few hundred pre-existing warnings; look for NEW lines)
python -m PySide6.qmllint -I app/qml app/qml/pages/NichePage.qml
```

`qmllint` ships with PySide6. There is no unit-test suite in this project.
