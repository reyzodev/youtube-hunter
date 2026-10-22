# Extension 1.2.0 — live button, designed loaders, launch moment

## Fixes
- `lang` was a `const` but `adopt()` assigns it: a TypeError the moment STR gets a 2nd language. Now `let`.
- Two functions named `shade` (colour shade + scroll fade) in nested scopes. The scroll one is now `edgeFade`.
- Video-strip thumbnail used an inline `onerror=""`. YouTube's CSP blocks inline handlers and logged a violation on every render. Now a real listener.
- `state.live.pct` could be read while `state.live` was null (resume race in the poll). Guarded.
- `chrome.runtime.getURL` throws "Extension context invalidated" in an orphaned tab after the extension reloads. `ASSET()` is guarded, and the panel now says "Reload this tab" (with a button) instead of the wrong "app isn't running".
- Reopening the panel during the "linked" moment could freeze it. Reset list includes it.
- `web_accessible_resources` now also matches `https://youtube.com/*` (the content script already did).

## Hunter button (watch page + Shorts)
- New idle look: gradient hairline edge, light sweep on hover, Hanken label.
- Live states per half: Download = fill + progress ring + falling arrow + percent; Starting (spinning arc, hatch); Paused; Saved (green pop + drawn tick); Failed (red shake). Cut = closing blades over a dashed cut line + percent; Clipped.
- `Live` module keeps the button current after the panel closes (plain `/v1/status`, no `watch=1`, so the desktop card still takes over). Probes once per watch page for a download already running.

## Loaders
- Connecting: tab ↔ app handshake pulse.
- Download "reading formats": scanner beam over a ghost ladder, staged status line, stopwatch, 3-step pips.
- Cut: ruler drawing in, breathing ghost clip with handles, sweeping playhead, ghost timecodes.

## Launching the app
- Chrome's "Open YouTube Hunter?" prompt is browser UI; no page or extension can restyle it. The panel now stages it: soft page dim, waking orb, 3 steps (prompt → app starting → connected), an animated replica of the prompt showing "tick Always allow, press Open" for the first 3 launches, and a 30 s timeout bar.
- To remove the prompt entirely, the app would need a Native Messaging host (installer registry entry + `nativeMessaging` permission + fixed extension `key`). Not done here.
