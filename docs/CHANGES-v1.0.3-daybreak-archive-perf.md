# v1.0.3 — "Daybreak" theme switch + Search Archive speed pass

## Theme switch
- `components/ThemeWipe.qml` rewritten ("Daybreak"): the title-bar switch blooms
  into a hero copy of itself, the thumb flips across (old glyph spins out, new
  spins in, face turns into the new palette), ripples + stars / sun rays on
  landing, then the new palette floods out OF THE THUMB as the iris.
  Same API (`run`, `warmUp`, `running`, `radius`), same perf rules: only
  Animators move, no snapshot, no MultiEffect, no colour animation.
- Label is now legible (0.88 ink instead of 0.7, 13 px).
- `components/ThemeSwitch.qml`: the thumb is a raised disc (white by day,
  graphite at night) with the sun / crescent on its face; the track fills with
  an accent dusk at night.

## Search Archive — the black flash
Root cause: `grid._screenReady()` returned TRUE while the section's rows were
still being read (no rows → nothing to wait for), so the deck was "revealed"
empty, the skeleton stand-in left, and the slot was empty (black in dark mode)
until the worker finished. The 450 ms `revealTimer` did the same on slow reads.
Fix: `_dataReady` gate (rows landed + not loading); the reveal timers start
from data arrival, never on an empty deck.

## Search Archive — speed
- First filter + sort pass of a section runs on the open worker
  (`_run_pipeline`, pure); the GUI thread only slices 24 rows. Falls back to
  the GUI pass if the user changed a filter mid-read.
- Skeleton stand-in is built once with the deck (it was built synchronously
  inside the click), with a fixed model (was rebuilt when rows landed).
- Card thumbnail: no layer + mask + MultiEffect (2 FBOs + 1 shader pass per
  card, 48 FBOs per page, re-rendered every hover-zoom frame). Plain clip +
  a card-coloured corner-cap ring; zero offscreen passes.
- Channel avatar: provider serves pre-cut round images (`image://thumbs/circle/…`),
  so the per-card mask layer + MultiEffect is gone too. Requested at 2x.
- Comet Canvas on the channel row built lazily (first hover of the card)
  instead of 24 Canvases per grid.
- Picture hold cap 1500 → 900 ms, reveal cap 450 → 320 ms.
These card changes also apply to the Niche Finder grid (same card).
