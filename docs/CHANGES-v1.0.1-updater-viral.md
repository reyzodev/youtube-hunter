# v1.0.1 — updater fixes, opt-in Viral Radar, Gold Score

## In-app updater (app/core/updater.py, vm/update_vm.py)

Checked against the live `reyzodev/youtube-hunter` release. The code path
(GitHub API → pick asset → stream to %TEMP% → SHA-256 → silent Inno Setup
with /relaunch=1) was sound, but the release itself could never update anyone:

* the release is **tagged `v1.0.0`** (only its *title* says 1.0.1). The tag is
  the version, so a 1.0.0 install saw "up to date".
* `YouTubeHunter-Setup-1.0.1-x64.exe` on that release is **4.9 MB with
  content type zip**: it is the source zip renamed. Had it been picked, the
  app would have run a zip as an installer.

Fixes:
* the asset picker skips anything that is not a real installer (zip/text
  content type, < 20 MB, unfinished upload, 32-bit) and any installer named
  for a *different* version than the tag (installing the 1.0.0 setup from a
  1.0.1 release loops forever);
* every download is checked for the `MZ` header before it can be launched;
* `parse_version("v1.1-x64")` was (1, 1, 64); now (1, 1, 0);
* clear errors for 404 (no release), 403/429 (rate limit, with minutes to
  wait), network failure;
* a newer tag with no usable installer shows "v1.0.1 is out but its installer
  isn't on GitHub yet" + the GitHub button, instead of "up to date";
* a failed background re-check no longer hides an update already found.

### Publishing a release that actually updates people
1. Bump `APP_VERSION` (app/constants.py) **and** `MyAppVersion` (installer.iss).
2. `build.bat` → `Output/YouTubeHunter-Setup.exe` (rename to
   `YouTubeHunter-Setup-1.0.1-x64.exe` if you like; the version in the name
   must match the tag).
3. New GitHub release, **tag `v1.0.1`**, attach that .exe. Not a draft, not a
   pre-release (`/releases/latest` ignores both).

## Viral Radar is opt-in (vm/niche_vm.py, ViralRadarBar.qml, NichePage.qml)

The radar runs on the user's own Google quota, so nothing fetches by itself:
* opening Niche Finder shows the radar **panel** (market, category, window,
  source) with the cost (`~16 units`, or `free · cached 12m`) and
  "N left on this key today · this run ≈ X%". One button: **Find viral videos**.
  Heavy runs (≥ 500 units, e.g. Breakouts · Global ≈ 1,632) are shown in warn colour.
* changing a pick on a loaded radar no longer re-fetches; it shows
  **Apply · ~N units**.
* "Load on open (spends quota)" switch: off by default. Stored under the new
  `viral_radar.auto_open` key (the old `autoload` defaulted to on and is ignored).
* a radar that is stopped / fails before showing anything returns to the panel.

## Gold Score (app/core/niche/gold.py)

0-100 per video: reach (views ÷ subs, log) 40 · speed vs pool median 25 ·
channel size 20 · engagement vs pool median 15. `gold` ≥ 70 and ≥ 5× subs,
`hot` ≥ 55. Computed in `compute_niche_metrics`, so every pool has it (cached
and archived rows are back-filled).
* new sort **Gold Score · steal-worthy first** (appended; saved indexes unchanged);
* radar **lens** chips with counts: All · ★ Gold · Hidden gems · Shorts ·
  Long-form (local, zero quota; Gold also switches the sort to Gold Score);
* "Gold 86" / "Hot 61" badge on cards; "Gold score" column in exports.

## Content Lab: section grid is paged (ContentLabPage.qml)

The landing grid rendered every section at once. It now pages like the
Search Archive: three full rows per page (4 columns → 12 cards, never under 6),
the app's own `Pager` under the grid plus a "13–24 of 37" counter, only shown
when there is a second page. Page 1 keeps the wide "latest" card and holds one
card fewer so its rows end flush. Changing the sort or the search goes back to
page 1; deleting sections or resizing the window never strands you on a page
that no longer exists.
