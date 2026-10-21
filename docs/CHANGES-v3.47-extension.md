# v3.47: Pause no longer locks the panel, layout order, no card over its own panel

- Extension: a PAUSED download no longer locks the ladder / format chips / dub picker. Picking another
  row parks the paused job (tagged "⏸ paused"); picking it again brings back the paused capsule with ▶.
- Extension Download tab order: video rows → Video format │ Audio → Audio only → Audio format.
- Extension Cut tab order: Video qualities → Video format │ Audio → Audio only → Audio format (+ dub).
  The Cut button pill shows "720p · MKV" or "Audio only · MP3".
- Desktop Cutter page: same order inside "Quality & output" (Video format, Audio only tile, Audio format);
  the VM remembers the video and audio format separately.
- No desktop live card while the panel shows that job: the panel sends a 1 s heartbeat (`POST /v1/watch`)
  for its video and running cut job, and the notifier re-checks watched jobs every 700 ms (a paused job
  sends no ticks, which is why the card used to stay up over the open panel). Close the panel or leave
  the page and the card comes back within ~4 s.
