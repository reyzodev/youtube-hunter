# v3.45 — Chrome extension: Play, formats, dubs + Donate pill fix

## Desktop app
- **Donate pill (sidebar footer)**: the pill is now sized from explicit font
  metrics of its label (rounded up) + fixed padding, and the label renders with
  QtRendering so drawn glyphs match the measurement on scaled displays. The cup
  and the word no longer spill out of the pill. (`app/qml/components/SupportFooter.qml`)
- **Bridge** (`app/qml_backend/web_bridge.py`):
  - `GET /v1/qualities` accepts `vf` (mp4|mkv|webm), `af` (mp3|m4a|opus|wav|flac),
    `lang` (dub). Every row gets `id` (`"720p@mkv~ar"`), `container`, `saved`.
    Response also carries `formats`, `tracks` (original + dubs) and `saved` ids.
  - `POST /v1/download` accepts `vf` / `af` / `lang` (applied exactly like the
    in-app picker: format saved as the user's choice, dub remembered per video).
  - `POST /v1/play {v, id}` opens a saved file in the system player. Only files
    found on disk for that video id (`"<title> [<id>] <key>[ <lang>].<ext>"`).
  - `POST /v1/reveal` accepts `id` to show that exact file.
  - `/v1/status` returns `id` of the finished file; `/v1/ping` advertises
    `formats: true, play: true`.

## Extension (1.1.1)
- A saved quality keeps a **▶ Play** button: switch to another quality and back,
  the footer shows Play (+ Show in folder) instead of Download. Saved state is
  read from disk too, so it survives a page reload.
- **Video format chips** (MP4 / MKV / WEBM) under the video qualities and
  **audio format chips** (MP3 / M4A / OPUS / WAV / FLAC) under Audio; sizes are
  re-computed per format.
- **Audio track picker** on dubbed videos (original, dubs, auto-dubs). Applies
  to both video and audio downloads; a dub saves beside the original.
- Works with an older app: without the new fields the panel behaves as before.
