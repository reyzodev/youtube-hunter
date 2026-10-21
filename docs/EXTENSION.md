# The Hunter button — browser extension guide


The extension puts **YouTube Hunter** on the YouTube page: a *Hunter* button next to Like/Share that opens a panel for downloading the video you are watching or cutting a clip out of it. The desktop app does the actual work — the browser only asks it.

Supported browsers: **Chrome, Edge, Brave, Opera, Vivaldi** (anything Chromium-based with Manifest V3).

## 1. Install (30 seconds)

The installer already put the extension on your disk:

```
%LOCALAPPDATA%\Programs\YouTube Hunter\browser-extension
```

1. Open `chrome://extensions` (or `edge://extensions`).
2. Turn on **Developer mode** — the toggle in the top-right corner.
3. Click **Load unpacked**.
4. Select the `browser-extension` folder above.
5. Open any YouTube video and **reload the tab** once. The **Hunter** button appears next to Like / Share, and inside Shorts.

> The extension is unpacked rather than installed from the Chrome Web Store, so Chrome keeps it in place and updates nothing by itself. After you update the desktop app, the copy in the app folder is replaced — open `chrome://extensions` and press **Reload** on *YouTube Hunter*.

## 2. The first click

If the desktop app is **not running**, clicking Hunter launches it through the `youtubehunter://` protocol (registered by the installer) — minimised, so it does not steal focus. The browser asks *"Open YouTube Hunter?"* the first time: tick **Always allow** and confirm.

If launching fails, the panel shows a *"The app is closed"* card with **Start** / **Retry**.

If the app is already running, nothing is launched — the panel talks to it directly on `127.0.0.1:47391`.

## 3. Download tab

| | |
|---|---|
| **Video** | Every real quality the video has (up to 4K/8K where available) with its real file size, computed from the actual streams — not a guess. |
| **Video format** | MP4 / MKV / WEBM. Sizes are recomputed for the chosen container. |
| **Audio only** | Download the soundtrack instead of the video. |
| **Audio format** | MP3 / M4A / OPUS / WAV / FLAC. |
| **Audio track** | Original, or any dub the video has (creator dubs and YouTube's auto-dubs). The dropdown shows the language code, the native name and a colour tag: **Original** / **Dub** / **Auto**. |
| **Download** | Turns the row into a live capsule: percent, status, quality, speed with a sparkline, size, time remaining, and **⏸ / ▶** pause & resume (the `.part` file is kept). |
| **When it finishes** | The capsule offers **▶ Play** and **Show in folder**. A saved quality keeps its ▶ button, so you can switch to another quality and back without losing it. |

The panel stays open after you press Download — you can start another quality or another video.

## 4. Cut tab

| | |
|---|---|
| **In / Out** | Drag the handles on the ruler (the YouTube player seeks as you drag), type a timecode, or press `[` / `]` at the current position. |
| **Ruler** | Zoomed around your clip (clip + 60% each side, minimum 12 s), with an overview strip for the whole video. *Whole video / Zoom to clip* switches the scale. |
| **Output** | **Video** (MP4 / MKV / WEBM) or **Audio only** (MP3 / M4A / OPUS / WAV / FLAC). Only the options for the chosen output are shown. |
| **Audio track** | Pick a dub for the clip, same as the download tab. |
| **Cut** | Only the selected range is downloaded and cut — not the whole video. The progress capsule shows percent, speed, size and ETA, with a ■ stop button. |

Finished clips appear in the app's **Cutter** history with their own card, ready to play, reveal or re-cut.

## 5. What happens when you leave the page

While the panel is open it keeps the desktop **live activity card** away (the panel is already showing the job). Close the panel, switch tabs, or navigate away and the desktop card takes over within a few seconds and follows the job to the end — same as an in-app download or cut.

## 6. Security

The bridge is a local HTTP server:

- Binds **`127.0.0.1:47391`** only — not reachable from your network or the internet.
- Accepts a request only when it carries the extension's `Origin` **and** the `X-YTH-Bridge` header. A random website cannot start a download.
- Accepts only the documented endpoints (`/v1/ping`, `/v1/qualities`, `/v1/download`, `/v1/status`, `/v1/pause`, `/v1/resume`, `/v1/cut`, `/v1/cut/status`, `/v1/cut/cancel`, `/v1/reveal`, `/v1/play`, `/v1/watch`).
- Can be switched off completely: set `"browser_bridge": false` in `%APPDATA%\YoutubeScrapperCyber\config.json` and restart the app. The extension then reports that the app is unreachable.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| No Hunter button | Reload the tab after installing; check the extension is enabled and has no errors; whitelist YouTube in ad-blockers. |
| *"Waiting for the extension"* in the app | `chrome://extensions` → **Reload**; click Hunter once; or press **Mark as connected** in Settings → Download Engine. |
| *"The app is closed"* even though it is open | A second copy of the app may be running, or the port is taken. Close all copies and start one. |
| Panel opens but lists no qualities | The video may be region-locked, members-only, or the app is not connected to YouTube (the connection gate explains which). |
| Cut fails immediately | Make sure In < Out and the clip is at least 1 second. If the app shows an error, the panel now waits and retries instead of reporting a false failure. |
| Everything worked, then stopped after an app update | Reload the extension (`chrome://extensions` → **Reload**) so it picks up the new panel. |

---
