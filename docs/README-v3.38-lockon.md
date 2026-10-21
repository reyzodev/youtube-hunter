# v3.38 — Lock-on theme motion

Drop-in: copy these 3 files over the same paths in the project.

- app/qml/components/ThemeWipe.qml — the new motion (same run() signature, Main.qml call unchanged)
- app/qml/Main.qml — 2 small edits: passes the window radius, removes the >1440p "skip the effect" shortcut (no snapshot anymore, so it is cheap at any size). See Main.qml.diff.
- app/locales/fa.py — 2 new strings: "Dark mode" / "Light mode"

Timeline (~1.2 s): curtain + mark assembles with neon trace, viewfinder brackets lock on,
palette swaps at 150 ms behind the opaque curtain, play pops with a ring burst + sheen,
then an iris opens from the logo and reveals the new theme.

Perf: no window grab, no MultiEffect, no full-window shader. One Shape (rounded rect with
an even-odd hole), a few rectangles, the vector BrandMark. Input is never blocked.

Check: QT_QPA_PLATFORM=offscreen timeout 30 python main_qml.py
Remember to bump the version in constants.py / version_info.txt / installer.iss.
