"""app.qml_backend.desktop_notifier - YouTube Hunter (QML).

v3.40 "Away notices": a premium desktop toast in the bottom-right corner of the
screen when a long job finishes while the user is somewhere else (another
Chrome tab, another app, the window minimised).

How it fits together
--------------------
* ViewModels call the module-level ``announce(...)`` from the GUI-thread slot
  that already handles their "job finished" signal (download done, scrape
  done, cut done, blueprint ready, ...). Cancellations never announce.
* ``announce`` checks the user's preference and whether the app is in front.
  If YouTube Hunter is the active app the in-page toast already said it, so
  nothing is shown; otherwise ``posted`` is emitted with a plain dict.
* ``DesktopToastHost.qml`` (instantiated once in Main.qml) turns each posted
  dict into its own small frameless, always-on-top, NON-ACTIVATING window and
  stacks them above the taskbar on the primary screen.
* Clicking a card calls ``activate(page)``: the main window is restored,
  raised, focused, and the page that produced the notice is opened.

The toast windows are created with ``_q_showWithoutActivating`` (see
``prepare``) and ``Qt.WindowDoesNotAcceptFocus``, so a notice appearing never
steals the keyboard from whatever the user is typing in.

v3.41 "Live activity"
---------------------
A download or a cut that is STILL RUNNING when the user leaves the app follows
them as a live card in the same corner (``LiveActivityCard.qml``): thumbnail
that "develops" from grey to colour as the bytes land, a big tabular percent,
speed · size · time left. The contract with the user is simple:

* leave the app while a job runs   → its live card slides in;
* come back to the app             → the card glides away (nothing lost);
* keep the card up until it ends   → the SAME card morphs into "Download
                                     complete" with Open / Show in folder, and
                                     no second notice is posted;
* close it with ✕                  → it stays closed for that job, and the
                                     normal completion notice fires at the end.

Jobs are fed from two places: the shared live download store
(``vm._dl_progress``, which every page that can download already publishes to)
and CutterVM (``live_begin / live_update / live_finish``). Updates are
coalesced to ~5 per second so a fragment storm never floods QML.
"""

import os
import re
import sys
import time

from PySide6.QtCore import (
    QObject, QRect, QTimer, QUrl, Property, Qt, Signal, Slot)
from PySide6.QtGui import QDesktopServices, QGuiApplication

from app.config import load_app_config, save_app_config

_CFG_ENABLED = "desktop_notify"
_CFG_SOUND = "desktop_notify_sound"
_CFG_LIVE = "desktop_live_progress"

# a live card is "on" while its job runs OR sits paused (v3.43 ⏸ / ▶)
_LIVE_STATES = ("running", "paused")
_RESUME_WATCH_MS = 6000  # ▶ that never turned into a running job → give up

# v3.44: a panel poll older than this means the YouTube panel was closed
_WATCH_TTL_S = 4.0
_WATCH_SYNC_MS = 700     # v3.47: re-check watched jobs this often
_LIVE_MAX = 3            # live cards on screen at once (oldest jobs first)
_LIVE_FLUSH_MS = 200     # update coalescing window

# 11-char YouTube id → we can show its thumbnail on the card
_YT_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

_INSTANCE = None


def notifier():
    """The app-wide DesktopNotifier, or None before main_qml created it."""
    return _INSTANCE


def announce(kind, title, message="", page=-1, path="", thumb_url="",
             icon="", source="", group="", force=False):
    """Fire-and-forget entry point for ViewModels. Never raises: a notice is a
    nicety and must not be able to break the job that just finished."""
    inst = _INSTANCE
    if inst is None:
        return False
    try:
        return inst.notify(kind, title, message, page, path, thumb_url,
                           icon, source, group, force)
    except Exception:
        return False


def youtube_thumb(video_id):
    """A thumbnail URL for a YouTube id, or "" when the id is not one."""
    vid = str(video_id or "")
    if _YT_ID.match(vid):
        return f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg"
    return ""


def announce_download(video_id, ok, message="", filepath=""):
    """Shared by every page that can download (Downloads, Niche Finder, Search
    Archive): the toast carries the video's title and thumbnail."""
    from app.i18n import tr
    title, thumb = "", ""
    try:
        from app.core.db.downloads import downloads_get
        row = downloads_get(video_id) or {}
        title = (row.get("title") or "").strip()
        thumb = (row.get("thumbnail_url") or "").strip()
    except Exception:
        pass
    if not title and filepath:
        title = os.path.splitext(os.path.basename(filepath))[0]
    thumb = thumb or youtube_thumb(video_id)
    inst = _INSTANCE
    # v3.44: the YouTube panel is open on this video and already showing the
    # "Saved" state — a desktop notice on top of it would be a twin.
    if inst is not None:
        try:
            if inst.watched(video_id):
                inst.live_finish("dl:" + str(video_id),
                                 "success" if ok else "error")
                return True
        except Exception:
            pass
    # v3.41: the live card that followed this download is still on screen →
    # it turns into the "done" notice itself; never post a twin.
    if inst is not None:
        try:
            if inst.live_finish("dl:" + str(video_id),
                                "success" if ok else "error",
                                title=title, message=message, path=filepath):
                return True
        except Exception:
            pass
    if ok:
        return announce("success", tr("Download complete"),
                        title or tr("Your video is saved and ready to watch."),
                        page=8, path=filepath, thumb_url=thumb,
                        icon="download_done", source=tr("Downloads"),
                        group="download")
    detail = (message or tr("Download failed")).strip()
    return announce("error", tr("Download failed"),
                    (title + " · " + detail) if title else detail,
                    page=8, thumb_url=thumb, icon="download",
                    source=tr("Downloads"), group="download-error")


class DesktopNotifier(QObject):
    """Owns the preference, the 'is the user away?' decision and the actions a
    toast card can trigger. QML context name: ``DesktopNotify``."""

    posted = Signal("QVariantMap")      # one notice for DesktopToastHost
    dismissAll = Signal()               # app came back to the front
    changed = Signal()                  # preference flipped
    workAreaChanged = Signal()

    def __init__(self, app_controller=None, parent=None):
        super().__init__(parent)
        global _INSTANCE
        _INSTANCE = self
        self._app = app_controller
        self._window = None
        self._seq = 0
        cfg = load_app_config()
        self._enabled = bool(cfg.get(_CFG_ENABLED, True))
        self._sound = bool(cfg.get(_CFG_SOUND, True))
        self._work_area = QRect(0, 0, 1920, 1040)
        self._live_on = bool(cfg.get(_CFG_LIVE, True))
        self._jobs = {}                # key -> job dict (insertion = start order)
        self._job_seq = 0
        self._dirty = set()
        self._flush_timer = QTimer(self)
        self._flush_timer.setSingleShot(True)
        self._flush_timer.setInterval(_LIVE_FLUSH_MS)
        self._flush_timer.timeout.connect(self._flush_live)
        self._sync_timer = QTimer(self)
        self._sync_timer.setSingleShot(True)
        self._sync_timer.timeout.connect(self._sync_live)
        self._preview_timer = None
        self._downloads = None         # DownloadsVM, for the card's ⏸ / ▶
        # v3.44: video id -> monotonic time the YouTube panel last polled it
        # while visible. A download someone is WATCHING in the browser gets
        # no desktop live card; close the panel and the card takes over.
        self._watch = {}
        # v3.47: a paused job sends no ticks, so nothing used to re-run
        # _sync_live when the panel opened (card stayed up over its own
        # panel) or closed (card never came back). A light steady re-check
        # while any job exists fixes both directions.
        self._watch_timer = QTimer(self)
        self._watch_timer.setInterval(_WATCH_SYNC_MS)
        self._watch_timer.timeout.connect(self._on_watch_tick)
        self._watch_timer.start()

        gui = QGuiApplication.instance()
        if gui is not None:
            gui.applicationStateChanged.connect(self._on_app_state)
            gui.primaryScreenChanged.connect(self._track_screen)
        self._screen = None
        self._track_screen()

        # every page that can download publishes its ticks to this store
        try:
            from app.qml_backend.vm import _dl_progress as dlp
            self._dlp = dlp
            dlp.add_listener(self._on_dl_live)
        except Exception:
            self._dlp = None

    # ── wiring from main_qml ─────────────────────────────────────────────
    def attach_window(self, window):
        """The main QQuickWindow, so activate() can restore and raise it."""
        self._window = window

    def attach_downloads(self, downloads_vm):
        """v3.43: the DownloadsVM, so a live card can pause / resume."""
        self._downloads = downloads_vm

    # ── preference ───────────────────────────────────────────────────────
    @Property(bool, notify=changed)
    def enabled(self):
        return self._enabled

    @Slot(bool)
    def setEnabled(self, on):
        on = bool(on)
        if on == self._enabled:
            return
        self._enabled = on
        self._persist(_CFG_ENABLED, on)
        self.changed.emit()
        if not on:
            self.dismissAll.emit()

    @Property(bool, notify=changed)
    def sound(self):
        return self._sound

    @Slot(bool)
    def setSound(self, on):
        on = bool(on)
        if on == self._sound:
            return
        self._sound = on
        self._persist(_CFG_SOUND, on)
        self.changed.emit()

    @staticmethod
    def _persist(key, value):
        # Read-modify-write: Settings' own save also re-reads config.json first,
        # so neither side can clobber the other's keys.
        try:
            cfg = load_app_config()
            cfg[key] = value
            save_app_config(cfg)
        except Exception:
            pass

    # ── where the stack sits ─────────────────────────────────────────────
    @Property(QRect, notify=workAreaChanged)
    def workArea(self):
        """Primary screen minus the taskbar, in logical pixels."""
        return self._work_area

    def _track_screen(self, *_):
        gui = QGuiApplication.instance()
        screen = gui.primaryScreen() if gui is not None else None
        if screen is self._screen and screen is not None:
            self._refresh_area()
            return
        if self._screen is not None:
            try:
                self._screen.availableGeometryChanged.disconnect(self._refresh_area)
            except Exception:
                pass
        self._screen = screen
        if screen is not None:
            screen.availableGeometryChanged.connect(self._refresh_area)
        self._refresh_area()

    def _refresh_area(self, *_):
        if self._screen is None:
            return
        area = self._screen.availableGeometry()
        if area != self._work_area:
            self._work_area = area
            self.workAreaChanged.emit()

    # ── the decision ─────────────────────────────────────────────────────
    @Property(bool, notify=changed)
    def userAway(self):
        return self._user_away()

    def _user_away(self):
        gui = QGuiApplication.instance()
        if gui is None:
            return False
        if gui.applicationState() != Qt.ApplicationActive:
            return True
        w = self._window
        if w is not None:
            try:
                if not w.isVisible() or (w.windowStates() & Qt.WindowMinimized):
                    return True
            except Exception:
                pass
        return False

    def _on_app_state(self, state):
        # Back in the app: the notices in the corner have done their job (they
        # are still in the bell tray), so they glide out on their own.
        if state == Qt.ApplicationActive:
            QTimer.singleShot(450, self._dismiss_if_active)
        # live cards: appear a beat after the user leaves (an alt-tab flick
        # through the app should not flash a card), leave when they're back
        self._sync_timer.start(450 if state == Qt.ApplicationActive else 320)
        self.changed.emit()

    def _dismiss_if_active(self):
        if not self._user_away():
            self.dismissAll.emit()

    # ── posting ──────────────────────────────────────────────────────────
    def notify(self, kind, title, message="", page=-1, path="", thumb_url="",
               icon="", source="", group="", force=False):
        if not force and (not self._enabled or not self._user_away()):
            return False
        kind = kind if kind in ("success", "error", "warn", "info") else "info"
        path = str(path or "")
        is_file = bool(path) and os.path.isfile(path)
        self._seq += 1
        thumb_id = ""
        if thumb_url:
            try:
                import base64
                thumb_id = base64.b64encode(
                    str(thumb_url).encode("utf-8")).decode("ascii")
            except Exception:
                thumb_id = ""
        self.posted.emit({
            "id": self._seq,
            "kind": kind,
            "title": str(title or ""),
            "message": str(message or ""),
            "page": int(page if page is not None else -1),
            "path": path if is_file else "",
            "folder": (os.path.dirname(path) if is_file
                       else (path if path and os.path.isdir(path) else "")),
            "thumb": thumb_id,
            "icon": str(icon or ""),
            "source": str(source or ""),
            "group": str(group or ""),
        })
        if self._sound:
            self._chime(kind)
        return True

    @Slot()
    def preview(self):
        """Settings → 'Preview': show a sample notice right now, even though
        the app is in front, so the user can see what they are switching on."""
        from app.i18n import tr
        self.notify("success", tr("Download complete"),
                    tr("Your video is saved and ready to watch."),
                    page=8, icon="download_done", source=tr("Downloads"),
                    group="preview", force=True)

    @staticmethod
    def _chime(kind):
        """The user's own Windows notification sound — the same one native
        toasts play — fired async so it never blocks the GUI thread."""
        if sys.platform != "win32":
            return
        try:
            import winsound
            alias = "SystemHand" if kind == "error" else "SystemNotification"
            winsound.PlaySound(alias, winsound.SND_ALIAS | winsound.SND_ASYNC
                               | winsound.SND_NODEFAULT)
        except Exception:
            pass

    # ══ v3.41 live activity ══════════════════════════════════════════════
    liveEvent = Signal("QVariantMap")   # {op: show|update|finish|hide, ...}

    @Property(bool, notify=changed)
    def liveEnabled(self):
        return self._live_on

    @Slot(bool)
    def setLiveEnabled(self, on):
        on = bool(on)
        if on == self._live_on:
            return
        self._live_on = on
        self._persist(_CFG_LIVE, on)
        self.changed.emit()
        self._sync_live()

    # ── job API (CutterVM calls these; downloads arrive via _on_dl_live) ──
    def live_begin(self, key, kind="download", title="", thumb_url="",
                   thumb_id="", page=-1, source="", subtitle=""):
        """A long job started (or resumed). Safe to call repeatedly."""
        if not key:
            return
        old = self._jobs.get(key)
        if old is not None and old.get("state") == "running":
            if title and not old.get("title"):
                old["title"] = str(title)
                self._mark(key)
            return
        if not thumb_id and thumb_url:
            try:
                import base64
                thumb_id = base64.b64encode(
                    str(thumb_url).encode("utf-8")).decode("ascii")
            except Exception:
                thumb_id = ""
        self._job_seq += 1
        job = {
            "key": key, "kind": kind, "title": str(title or ""),
            "subtitle": str(subtitle or ""),
            "thumb": str(thumb_id or ""), "page": int(page),
            "source": str(source or ""),
            "pct": 0, "stage": "", "speed": 0.0, "eta": 0,
            "done": 0, "total": 0, "indeterminate": True,
            "state": "running", "shown": False, "dismissed": False,
            "token": 0, "seq": self._job_seq, "forced": False,
        }
        if old is not None and old.get("shown"):
            # a finished card for the same key is still fading: let it go
            self.liveEvent.emit({"op": "hide", "key": key,
                                 "token": old.get("token", 0)})
        self._jobs.pop(key, None)
        self._jobs[key] = job
        self._sync_live()

    def live_update(self, key, **fields):
        job = self._jobs.get(key)
        if job is None or job.get("state") != "running":
            return
        job.update({k: v for k, v in fields.items() if v is not None})
        self._mark(key)

    def live_finish(self, key, outcome, title="", message="", path=""):
        """The job ended. Returns True when a live card was on screen and has
        become the completion notice (the caller must NOT announce again)."""
        job = self._jobs.get(key)
        if job is None:
            return False
        if job.get("state") not in _LIVE_STATES:
            return bool(job.get("shown"))
        outcome = outcome if outcome in ("success", "error", "stopped") else "error"
        job["state"] = outcome
        if title:
            job["title"] = str(title)
        visible = (job.get("shown") and not job.get("dismissed")
                   and (job.get("forced") or self._can_show()))
        if not visible:
            if job.get("shown"):
                self.liveEvent.emit({"op": "hide", "key": key,
                                     "token": job.get("token", 0)})
            self._jobs.pop(key, None)
            self._sync_live()
            return outcome == "stopped"     # a stop is never announced anyway
        path = str(path or "")
        is_file = bool(path) and os.path.isfile(path)
        payload = self._payload(job)
        payload.update({
            "op": "finish", "outcome": outcome,
            "message": str(message or ""),
            "path": path if is_file else "",
            "folder": os.path.dirname(path) if is_file else "",
        })
        self.liveEvent.emit(payload)
        if self._sound and outcome != "stopped":
            self._chime("error" if outcome == "error" else "success")
        return True

    @Slot(str, int, bool)
    def liveClosed(self, key, token, by_user):
        """A live card left the screen (✕, its timer, or the app came back)."""
        job = self._jobs.get(key)
        if job is None or int(job.get("token", 0)) != int(token):
            return
        job["shown"] = False
        if job.get("state") == "paused" and by_user:
            # ✕ on a paused card: the download stays parked on the Downloads
            # page (▶ there resumes it); the card itself is done.
            self._jobs.pop(key, None)
        elif job.get("state") not in _LIVE_STATES or job.get("forced"):
            self._jobs.pop(key, None)
            if job.get("forced") and self._preview_timer is not None:
                self._preview_timer.stop()
        elif by_user:
            job["dismissed"] = True      # ✕ = "not for this job", for good
        self._sync_live()

    @Slot()
    def previewLive(self):
        """Settings → 'Preview': run a fake download through a live card so the
        user sees it without leaving the app."""
        from app.i18n import tr
        key = "preview:live"
        if key in self._jobs:
            return
        self.live_begin(key, "download",
                        title=tr("How I built a channel in 30 days"),
                        page=8, source=tr("Downloads"), subtitle="1080p · MP4")
        job = self._jobs[key]
        job["forced"] = True
        job["total"] = 284 * 1024 * 1024
        job["stage"] = tr("Preparing…")
        self._sync_live()
        t = QTimer(self)
        t.setInterval(260)
        state = {"n": 0}

        def tick():
            j = self._jobs.get(key)
            if j is None:
                t.stop()
                return
            state["n"] += 1
            n = state["n"]
            if n < 4:
                return
            if n <= 34:
                pct = min(99, int((n - 4) * 3.4))
                done = int(j["total"] * pct / 100)
                self.live_update(key, pct=pct, done=done, indeterminate=False,
                                 speed=(11.2 + (n % 5) * 0.7) * 1024 * 1024,
                                 eta=max(1, int((99 - pct) / 13)),
                                 stage=tr("Downloading"))
            elif n <= 41:
                self.live_update(key, pct=99, indeterminate=True, speed=0.0,
                                 eta=0, stage=tr("Merging…"))
            else:
                t.stop()
                self._preview_timer = None
                self.live_finish(key, "success")
        t.timeout.connect(tick)
        self._preview_timer = t
        t.start()

    # ── v3.44: downloads followed in the YouTube panel ───────────────────
    def watch(self, video_id):
        """The browser panel is showing this download (called from the web
        bridge's handler thread — a plain dict write, safe under the GIL)."""
        if video_id:
            self._watch[str(video_id)] = time.monotonic()

    def watch_cut(self, job_id):
        if job_id:
            self._watch["cut:" + str(job_id)] = time.monotonic()

    def unwatch(self, video_id):
        """The panel stopped following this download (closed / tab left)."""
        if video_id:
            self._watch.pop(str(video_id), None)

    def unwatch_cut(self, job_id):
        if job_id:
            self._watch.pop("cut:" + str(job_id), None)

    def watched(self, video_id):
        t = self._watch.get(str(video_id or ""))
        if t is None:
            return False
        if time.monotonic() - t > _WATCH_TTL_S:
            self._watch.pop(str(video_id), None)
            return False
        return True

    def _on_watch_tick(self):
        if self._jobs:
            try:
                self._sync_live()
            except Exception:
                pass

    def _in_page(self, job):
        key = str(job.get("key") or "")
        if key.startswith("dl:"):
            return self.watched(key[3:])
        # Extension cuts are watched by /v1/cut/status while the panel is
        # visible. Once YouTube navigates away that heartbeat expires and the
        # same live card appears beside the new page.
        if key.startswith("ext-cut:"):
            return self.watched("cut:" + key[8:])
        return False

    # ── internals ────────────────────────────────────────────────────────
    def _can_show(self):
        return self._enabled and self._live_on and self._user_away()

    def _mark(self, key):
        self._dirty.add(key)
        if not self._flush_timer.isActive():
            self._flush_timer.start()

    def _sync_live(self):
        """Make the screen match the rules: cards for running, un-dismissed
        jobs while the user is away (max _LIVE_MAX), none otherwise."""
        away_ok = self._can_show()
        shown = 0
        for job in list(self._jobs.values()):
            if not job.get("shown"):
                continue
            keep = job.get("forced") or (away_ok and not job.get("dismissed")
                                         and not self._in_page(job))
            if keep or job.get("state") not in _LIVE_STATES:
                shown += 1
                continue
            job["shown"] = False
            self.liveEvent.emit({"op": "hide", "key": job["key"],
                                 "token": job.get("token", 0)})
        for job in list(self._jobs.values()):
            if shown >= _LIVE_MAX:
                break
            if job.get("shown") or job.get("state") not in _LIVE_STATES:
                continue
            if not (job.get("forced") or (away_ok and not job.get("dismissed")
                                          and not self._in_page(job))):
                continue
            self._job_seq += 1
            job["token"] = self._job_seq
            job["shown"] = True
            shown += 1
            payload = self._payload(job)
            payload["op"] = "show"
            self.liveEvent.emit(payload)

    def _flush_live(self):
        keys, self._dirty = self._dirty, set()
        for key in keys:
            job = self._jobs.get(key)
            if (job is None or not job.get("shown")
                    or job.get("state") not in _LIVE_STATES):
                continue
            if key.startswith("dl:") and not (job.get("title") and job.get("subtitle")):
                self._dl_fill_meta(job, key[3:])
            payload = self._payload(job)
            payload["op"] = "update"
            self.liveEvent.emit(payload)

    @staticmethod
    def _fmt_size(n):
        """Bytes → "182 MB" (same rules as the Downloads page), "" if unknown."""
        try:
            v = float(n)
        except (TypeError, ValueError):
            return ""
        if v <= 0:
            return ""
        units = ("B", "KB", "MB", "GB")
        i = 0
        while v >= 1024 and i < len(units) - 1:
            v /= 1024
            i += 1
        return (f"{round(v)} {units[i]}" if (v >= 100 or i == 0)
                else f"{v:.1f} {units[i]}")

    @staticmethod
    def _fmt_eta(seconds):
        """Seconds → "2m 40s"; "" when unknown (a stalled "0s" is a lie)."""
        try:
            s = int(seconds)
        except (TypeError, ValueError):
            return ""
        if s <= 0:
            return ""
        if s < 60:
            return f"{s}s"
        m, s = divmod(s, 60)
        if m < 60:
            return f"{m}m {s:02d}s"
        h, m = divmod(m, 60)
        return f"{h}h {m:02d}m"

    def _payload(self, job):
        from app.i18n import tr
        done, total = int(job.get("done") or 0), int(job.get("total") or 0)
        speed = float(job.get("speed") or 0)
        if done > 0 and total > 0:
            size = tr("{done} of {total}").format(
                done=self._fmt_size(done), total=self._fmt_size(total))
        else:
            size = self._fmt_size(done or total)
        eta = self._fmt_eta(job.get("eta") or 0)
        return {
            "key": job["key"], "token": int(job.get("token", 0)),
            "kind": job.get("kind", "download"),
            "title": job.get("title") or tr("Untitled"),
            "subtitle": job.get("subtitle", ""),
            "thumb": job.get("thumb", ""), "page": int(job.get("page", -1)),
            "source": job.get("source", ""),
            "pct": max(0, min(100, int(job.get("pct") or 0))),
            "indeterminate": bool(job.get("indeterminate")),
            "stage": job.get("stage", ""),
            "speedText": (self._fmt_size(speed) + "/s") if speed > 0 else "",
            "sizeText": size,
            "etaText": tr("{t} left").format(t=eta) if eta else "",
            # v3.43 pause / resume
            "paused": job.get("state") == "paused",
            "canPause": self._can_pause(job),
            "busy": bool(job.get("pausing") or job.get("resuming")),
            "pausing": bool(job.get("pausing")),
        }

    # ── v3.43: pause / resume from the card ──────────────────────────────
    def _can_pause(self, job):
        key = str(job.get("key") or "")
        vm = self._downloads
        if vm is None or not key.startswith("dl:") or job.get("forced"):
            return False
        if job.get("state") == "paused":
            return True                      # ▶ always available
        if job.get("post"):
            return False                     # merging / converting: nothing to pause
        return job.get("state") == "running" and (
            bool(job.get("pausing")) or bool(job.get("resuming"))
            or vm.owns(key[3:]))

    @Slot(str)
    def livePause(self, key):
        job = self._jobs.get(key)
        vm = self._downloads
        if (job is None or vm is None or job.get("state") != "running"
                or job.get("pausing") or not key.startswith("dl:")):
            return
        from app.i18n import tr
        if vm.pauseDownload(key[3:]):
            job["pausing"] = True
            job["resuming"] = False
            job.update(stage=tr("Pausing…"), speed=0.0, eta=0)
            self._mark(key)

    @Slot(str)
    def liveResume(self, key):
        job = self._jobs.get(key)
        vm = self._downloads
        if job is None or vm is None or not key.startswith("dl:"):
            return
        state = job.get("state")
        if not (state == "paused" or (state == "running" and job.get("pausing"))):
            return
        from app.i18n import tr
        job["state"] = "running"
        job["pausing"] = False
        job["resuming"] = True
        job["dismissed"] = False
        job.update(stage=tr("Resuming…"), speed=0.0, eta=0)
        self._mark(key)
        vm.resumeAfterPause(key[3:])
        QTimer.singleShot(_RESUME_WATCH_MS, lambda k=key: self._resume_watch(k))

    def _resume_watch(self, key):
        """▶ was pressed but no running download ever showed up (the row was
        deleted, the URL is gone…): don't leave a card saying "Resuming…"."""
        job = self._jobs.get(key)
        if job is None or not job.get("resuming"):
            return
        if self._dlp is not None and self._dlp.is_running(key[3:]):
            return
        job["resuming"] = False
        self.live_finish(key, "stopped")

    def _to_paused(self, job):
        from app.i18n import tr
        job["state"] = "paused"
        job["pausing"] = False
        job["resuming"] = False
        job.update(stage=tr("Paused"), speed=0.0, eta=0, indeterminate=False)
        self._mark(job["key"])

    # ── downloads: mirrored from the shared live store ───────────────────
    @staticmethod
    def _dl_title(video_id):
        try:
            from app.core.db.downloads import downloads_get
            return ((downloads_get(video_id) or {}).get("title") or "").strip()
        except Exception:
            return ""

    @staticmethod
    def _dl_fill_meta(job, video_id):
        """The row is written just AFTER the first tick, so the title / quality
        / thumbnail are filled in lazily on the next flushes."""
        try:
            from app.core.db.downloads import downloads_get
            row = downloads_get(video_id) or {}
        except Exception:
            return
        if not job.get("title"):
            job["title"] = (row.get("title") or "").strip()
        if not job.get("subtitle"):
            job["subtitle"] = (row.get("quality_label") or "").strip()

    def _on_dl_live(self, video_id, structural=False):
        from app.i18n import tr
        key = "dl:" + str(video_id)
        entry = self._dlp.get(video_id) if self._dlp is not None else None
        if entry is None:
            # Cleared. A real finish calls announce_download → live_finish in
            # the same slot; if nothing arrives by the next event-loop turn the
            # user stopped it (stops are never announced).
            if key in self._jobs and self._jobs[key].get("state") == "running":
                QTimer.singleShot(0, lambda k=key: self._dl_settle(k))
            return
        if not entry.get("running", True):
            return
        job = self._jobs.get(key)
        if job is not None and job.get("state") == "paused":
            # resumed from somewhere else (the Downloads page ▶): same card
            job["state"] = "running"
            job["dismissed"] = False
            job["resuming"] = True
            self._sync_live()
        if job is None or job.get("state") != "running":
            thumb = ""
            try:
                from app.core.db.downloads import downloads_get
                row = downloads_get(video_id) or {}
                thumb = (row.get("thumbnail_url") or "").strip()
                sub = (row.get("quality_label") or "").strip()
            except Exception:
                sub = ""
            self.live_begin(key, "download", title=self._dl_title(video_id),
                            thumb_url=thumb or youtube_thumb(video_id),
                            page=8, source=tr("Downloads"), subtitle=sub)
            job = self._jobs.get(key)
            if job is None:
                return
        # v3.44: the YouTube panel opened / closed on this download → hand the
        # progress over (panel open: no desktop card; closed: card slides in)
        in_page = self.watched(video_id)
        if bool(job.get("in_page")) != in_page:
            job["in_page"] = in_page
            self._sync_live()
        text = str(entry.get("text") or "")
        pct = int(entry.get("pct") or 0)
        done = int(entry.get("done") or 0)
        post = (text == tr("Merging…")
                or text.startswith(tr("Converting to {fmt}…").split("{")[0]))
        if job.get("resuming") and not entry.get("cancelling") and (
                pct > int(entry.get("floor") or 0) or done > 0
                or text == tr("Merging…")):
            job["resuming"] = False         # real bytes again
        job["post"] = bool(post)
        if entry.get("cancelling"):
            intent = entry.get("intent") or ""
            stage = (tr("Resuming…") if intent == "resume"
                     else tr("Pausing…") if intent == "pause"
                     else tr("Stopping…"))
            if intent == "pause":
                job["pausing"] = True
        elif job.get("resuming"):
            stage = tr("Resuming…")
        elif text.startswith(tr("Downloading… {pct}%").split("{")[0].strip()):
            stage = tr("Downloading")
        else:
            stage = text.replace(f"{pct}%", "").strip() or tr("Downloading")
        self.live_update(key, pct=pct, done=done,
                         total=int(entry.get("total") or 0),
                         speed=0.0 if post else float(entry.get("speed") or 0),
                         eta=0 if post else int(entry.get("eta") or 0),
                         stage=stage,
                         indeterminate=post or (pct <= 0 and done <= 0))

    def _dl_settle(self, key):
        job = self._jobs.get(key)
        if job is None or job.get("state") != "running":
            return
        vid = key[3:]
        if self._dlp is not None and self._dlp.get(vid) is not None:
            return                       # resumed in the meantime
        if job.get("resuming"):
            return                       # ▶ during unwind: restart is queued
        if job.get("pausing"):
            self._to_paused(job)         # ⏸: the card stays, now with ▶
            return
        self.live_finish(key, "stopped")

    # ── called by the toast windows ──────────────────────────────────────
    @Slot(QObject)
    def prepare(self, window):
        """Mark a toast window 'show without activating' BEFORE it is shown:
        Qt's Windows backend then uses SW_SHOWNOACTIVATE, so the notice never
        takes focus away from the browser tab the user is typing in."""
        try:
            window.setProperty("_q_showWithoutActivating", True)
        except Exception:
            pass

    @Slot(int)
    def activate(self, page=-1):
        """A card was clicked: bring YouTube Hunter back and open the page the
        notice came from."""
        w = self._window
        if w is not None:
            try:
                states = w.windowStates()
                if states & Qt.WindowMinimized:
                    w.setWindowStates(states & ~Qt.WindowMinimized)
                if not w.isVisible():
                    w.show()
                w.raise_()
                w.requestActivate()
                if sys.platform == "win32":
                    self._win_foreground(int(w.winId()))
            except Exception:
                pass
        if self._app is not None and page is not None and int(page) >= 0:
            try:
                self._app.goto(int(page))
            except Exception:
                pass
        self.dismissAll.emit()

    @staticmethod
    def _win_foreground(hwnd):
        # The click on the toast gave this process the last input event, so
        # Windows allows it to take the foreground.
        try:
            import ctypes
            user32 = ctypes.windll.user32
            if user32.IsIconic(hwnd):
                user32.ShowWindow(hwnd, 9)          # SW_RESTORE
            user32.SetForegroundWindow(hwnd)
        except Exception:
            pass

    @Slot(str)
    def openFile(self, path):
        if path and os.path.exists(path):
            QDesktopServices.openUrl(QUrl.fromLocalFile(path))

    @Slot(str)
    def revealFile(self, path):
        if not path:
            return
        from app.core.utils import reveal_in_file_manager
        if os.path.isfile(path):
            reveal_in_file_manager(path)
        elif os.path.isdir(path):
            QDesktopServices.openUrl(QUrl.fromLocalFile(path))
