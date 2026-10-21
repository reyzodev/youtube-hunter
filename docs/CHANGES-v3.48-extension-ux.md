# v3.48: Extension UX pass — Download + Cut tabs

Only `browser-extension/` changed (content.js, panel.css, manifest 1.1.2, +2 Vazirmatn weights). No bridge / app change.

## Both tabs
- **Real bold mono.** JetBrains Mono is a variable font (100–800) but was registered as weight 400 only, so every bold number (1080p, sizes, timecodes, pills) was faux-bold. Now registered 100–800. Vazirmatn Medium + SemiBold are registered too.
- **Scroll edge.** The body fades at whichever edge hides content, and the footer gets a hairline while more is below.
- **Duration badge** on the thumbnail.
- **Audio track select:** custom chevron, proper height, hover state.
- **Format chips → segmented control** (label + one track). Never wraps (FLAC used to fall to a second line).

## Download tab
- Tighter ladder (4 px bars, less padding): the panel fits on a laptop screen without scrolling.
- "VIDEO" head added, so Video / Audio groups read the same.
- The format row that doesn't apply to the picked rung is dimmed. Picking an audio format switches to **Audio only**; picking a video format goes back to the last video quality.
- Sparkline moved under the "speed" label (it overlapped the number).

## Cut tab
- **Zoomed ruler.** The ruler is a window around the clip (clip + 60% each side, min 12 s), so a 30 s clip on a 10 min video is a wide, draggable range instead of two handles on top of each other. It refits only when the clip is cramped, clipped or hugging an edge, never mid-drag.
- **Overview strip** under the ruler (whole video, clip, zoom window, playhead). Press / drag it to slide the window.
- **"Whole video / Zoom to clip"** switch in the scale row; the scale shows the window's start / end.
- **Output: Video | Audio only** segmented switch. Only the options for the chosen output are shown (qualities + video format, or audio format). Audio-only size estimate sits on the switch.
- `[` / `]` keycaps on the In here / Out here buttons; the separate hint line and the "video cut keeps audio" note are gone. One info line remains (keyframe note, or the audio-only note).
- Cut progress uses the same live capsule as Download (percent, fill, ■ stop).

## Fix: Hunter button landed inside the playlist / Mix panel
- With a playlist or Mix open, the panel's header menu has its own `#top-level-buttons-computed`. The bare fallback selector matched it before YouTube had rendered the real actions row, and the "already have a visible button" check then kept it there until the playlist was closed.
- Now: rows inside the playlist panel, `#secondary`, engagement panels, the miniplayer and popups are never used. A button already on the page is moved as soon as the real actions row under the video appears, and an open panel stays anchored to the moved button.
