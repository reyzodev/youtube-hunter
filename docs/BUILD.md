# Build & packaging

How `YouTubeHunter-Setup.exe` is produced, and what to check when a build
behaves differently on someone else's machine.

## One command

```bat
build.bat
```

It does six things, in this order, and stops with a clear message when an input
is missing:

1. **Finds Python** (3.11+ 64-bit).
2. **Creates `.build-venv`** — an isolated build environment, so the machine's
   own Python install is never touched.
3. **Installs the pinned dependencies** from `requirements.txt`, plus `yt-dlp`,
   `imageio-ffmpeg` and `pyinstaller`, and forces imageio to fetch its FFmpeg
   binary now (the spec bundles it).
4. **Verifies every build input** before spending minutes in PyInstaller:
   `main_qml.py`, `app/qml/Main.qml`, `app/qml/qmldir`, `fonts/`,
   `assets/bin/ffprobe.exe`, `assets/bin/deno.exe`, `assets/bin/bgutil-pot.exe`,
   the Qt/QML runtime in the venv, the Google discovery documents, and that
   `APP_VERSION` imports.
5. **Runs PyInstaller** with `YoutubeScrapper.spec` (onedir) and then verifies
   the output — the Qt QML modules, the QtMultimedia **backend plugin**, the
   bundled app QML, the three binaries, the fonts and the YouTube discovery
   document. These are the pieces that go missing silently and only fail on a
   machine that has no Qt.
6. **Compiles the installer** with Inno Setup 6 (`installer.iss`), if it is
   installed.

Output:

```
dist\YouTubeHunter\YouTubeHunter.exe     the app (onedir — ship the whole folder)
Output\YouTubeHunter-Setup.exe           the installer (~170 MB)
```

## The three binaries that are not in the repository

| File | Size | Needed for |
|---|---|---|
| `assets/bin/ffprobe.exe` | ~145 MB | mp3/audio-only downloads, the cutter's local-file probe, quality probing |
| `assets/bin/deno.exe` | ~93 MB | the JavaScript runtime yt-dlp uses to solve YouTube's download challenge |
| `assets/bin/bgutil-pot.exe` | ~45 MB | the PO Token helper (bgutil-pot 0.8.1, GPL-3.0). **Required** since 1.0.0: without it YouTube serves a 360p-only format list or answers 403 on VPN/datacenter IPs |

`bgutil-pot.exe` is downloaded from the upstream release and verified against the
SHA-256 pinned in `app/core/pot.py`; its licence text and notice sit next to it
in `assets/bin/`. It runs as its own process on `127.0.0.1`, never imported.

## What the installer adds

- Copies `dist\YouTubeHunter\*` into `%LOCALAPPDATA%\Programs\YouTube Hunter`.
- Copies `browser-extension\*` into `{app}\browser-extension` and adds a Start-menu
  shortcut to it (the extension is loaded unpacked from there).
- Registers `youtubehunter://` (`HKCU\Software\Classes\youtubehunter`) so the
  browser extension can start the app minimised.
- Deletes the previous version's `_internal` folder first, so an upgrade cannot
  leave stale Qt DLLs behind.
- Keeps `%APPDATA%\YoutubeScrapperCyber` (config, API keys, archive) untouched —
  also on uninstall.

## Traps worth knowing

These fail silently rather than raising:

- **The QtMultimedia backend plugin is not collected automatically.** Nothing
  imports `PySide6.QtMultimedia` from Python, so PyInstaller misses the plugin
  and every Cutter preview is black. `YoutubeScrapper.spec` appends the plugin
  directory and the FFmpeg DLLs by hand.
- **Move `dist\YouTubeHunter` aside before a rebuild.** PyInstaller's COLLECT
  step removes the old folder first; if a file in it is locked, the build still
  reports success and the installer packages the previous build.
- **Qt's own translations** are trimmed to English only — the app draws its
  labels itself and never installs a QTranslator.
- **Version lives in three places** and they must agree: `app/constants.py`
  (`APP_VERSION`), `version_info.txt`, `installer.iss` (`MyAppVersion`).
- **The interface is English only.** There is no language switch and no
  translation table; `app.i18n.tr()` returns the string unchanged.

## Verifying a build without a display

```bash
# instantiates every page; any QML load error prints here. 124 = still running = OK
QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py

# lint one file (a few hundred pre-existing warnings; look for NEW lines)
python -m PySide6.qmllint -I app/qml app/qml/pages/SettingsPage.qml
```

There is no unit-test suite. `tools/check_hover_flicker.py` is the one lint that
catches a real class of bug (colour-fade hover states that blink), so run it
before shipping.
