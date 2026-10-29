# v1.0.2 — Transfer capsule (in-app live downloads)

Running downloads / cuts are now visible INSIDE the app, in the title bar,
left of Help · Bell · Theme. The desktop live card (LiveActivityCard) is
untouched and still only appears when you leave the app.

## Files
- `app/qml/components/TransferCapsule.qml` (new): the compact capsule. One orb
  per job (thumbnail inside its own progress ring) + a tabular percentage.
  1 job → also speed / stage. 4+ jobs → first three, then "+N". The capsule's
  glass fills faintly to the average progress. Folds away when nothing runs.
- `app/qml/components/TransferPanel.qml` (new): click the capsule → panel with
  title, stage · quality, meter, speed · size · ETA, Pause / Resume / Stop.
  Clicking a row opens the page that owns the job.
- `app/qml/components/TitleBar.qml`: capsule + panel wired in.
- `app/qml_backend/desktop_notifier.py`: new `activity` / `activeCount`
  properties (coalesced ~6/s), `activityStop`, `activityOpen` slots. Fed by the
  same `_jobs` dict as the live cards, so downloads from every page, Cutter cuts
  and extension cuts all appear. A finished job keeps a short success / error
  beat before it leaves.

## Try it
Settings → desktop live card "Preview": the fake download also runs through
the capsule. Or start any two downloads.
