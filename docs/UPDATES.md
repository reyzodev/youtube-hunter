# In-app updates

The app checks GitHub Releases of `reyzodev/youtube-hunter` 6 s after launch and every 6 h.

## Publishing an update
1. Bump the version in **three** places: `app/constants.py` (`APP_VERSION`), `installer.iss` (`MyAppVersion`), `version_info.txt`.
2. Run `build.bat` -> `Output\YouTubeHunter-Setup.exe`.
3. On GitHub: **Releases -> Draft a new release**, tag `v1.0.1` (must be higher than the installed version), write the notes (Markdown, shown in the popup), attach the installer, **Publish** (not draft, not pre-release).

   Name the asset `YouTubeHunter-Setup-<version>-x64.exe` so the download says what it is. The app picks the release asset whose name contains `YouTubeHunter-Setup` (see `UPDATE_ASSET_HINT` in `app/constants.py`), so the version in the file name is fine.

That's it. Every installed copy sees it on next launch / within 6 h.

## What the user sees
- A notification ("Update available: v1.0.1") in the bell tray, plus a desktop card once per version.
- A download button next to the **?** (tour) button in the title bar, with a pulsing dot.
- Click -> popup: version from -> to, date, size, release notes -> **Download & install**.
- Live progress (percent, MB, speed, time left). The file is SHA-256 verified against GitHub's asset digest.
- When done: 5 s countdown -> the app closes, Setup installs silently, and the app reopens by itself (`/relaunch=1`, see `installer.iss`).
- Running from source (`python main_qml.py`): the installer opens as a normal wizard instead.

## Settings
- `"auto_update": false` in `%APPDATA%\YoutubeScrapperCyber\config.json` turns checks off.
- The repo and asset name live in `app/constants.py` (`UPDATE_REPO`, `UPDATE_ASSET_HINT`).

## Note
The repo must be **public** (the unauthenticated GitHub API cannot see private releases). Limit: 60 checks/hour per IP, far above what the app uses.
