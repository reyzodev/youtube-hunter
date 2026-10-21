"""app.qml_backend.vm.cutter_vm - YouTube Hunter (QML).

ViewModel behind CutterPage.qml — cut a [start, end) segment out of a
YouTube link (streamed straight into the cut, the full video is never
downloaded) or out of a local file, at the video's own quality up to 4K.

Thin orchestration over app.core.cutter (probe + ffmpeg cut on worker
threads, results marshalled back over queued signals). The QWidgets app is
untouched.
"""

import collections
import os
import subprocess
import sys
import threading
import traceback

from PySide6.QtCore import QObject, Property, QUrl, Signal, Slot
from PySide6.QtGui import QGuiApplication

from app.config import load_app_config
from app.core.cutter import (
    DOWNLOAD_CANCELLED, cut_file, cut_link, extract_clip_thumb, fmt_clock,
    parse_clock, probe_file_with_error, probe_link)
from app.core.db.clips import (
    clips_add, clips_clear, clips_delete, clips_list, clips_update_channel)
from app.core.db.ideas import DATA_DB_PATH
from app.core.db.downloads import file_size_of
from app.core.utils import desktop_download_dir, local_path_from_url
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm.niche_vm import _thumb_id
from app.qml_backend.desktop_notifier import announce, notifier

_AUDIO_EXTS = (".mp3", ".m4a", ".aac", ".opus", ".ogg", ".wav", ".flac")

# v3.16-p4: one cover frame per clip, cached next to the database.
_CLIP_THUMB_DIR = os.path.join(os.path.dirname(DATA_DB_PATH), "clip_thumbs")


def _clip_thumb_path(clip_id):
    return os.path.join(_CLIP_THUMB_DIR, f"{int(clip_id)}.jpg")


def _size_text(n):
    if not n or n <= 0:
        return ""
    units = ("B", "KB", "MB", "GB")
    v = float(n)
    i = 0
    while v >= 1024 and i < len(units) - 1:
        v /= 1024
        i += 1
    return (f"{round(v)} {units[i]}" if (v >= 100 or i == 0)
            else f"{v:.1f} {units[i]}")


class CutterVM(QObject):
    """Segment-cut state machine for the QML cutter page."""

    changed = Signal()                 # form / info / status
    # The trim range gets its OWN notify signal. It used to ride on `changed`,
    # which also notifies ~30 other properties (the quality list among them),
    # so every pixel of a bracket drag rebuilt the quality pills and re-ran
    # most of the page's bindings. The event queue backed up and the brackets
    # trailed the pointer by 1-3 s. A drag now only touches the range props.
    rangeChanged = Signal()
    progressChanged = Signal()         # live cut percentage
    labelsChanged = Signal()           # UI language changed
    clipsChanged = Signal()            # persisted clips history changed
    toast = Signal(str, str)           # (message, kind)
    audioChanged = Signal()            # v1.2: dub list / picked dub
    # worker → GUI bridges (queued automatically across threads)
    _probed = Signal(bool, "QVariant", str)   # (ok, info, error)
    # (ok, preview_url, has_audio, is_av1, px, audio_url)
    _previewReady = Signal(bool, str, bool, bool, int, str)
    _cutStatus = Signal(str)
    _cutProgress = Signal(int, int)    # (pct, written_bytes)
    _cutDone = Signal(bool, str, str)  # (ok, message_or_path, filepath)
    _cutResolved = Signal(int, str)    # (height_px, label)
    _channelAvatar = Signal(str, str)  # (video_id, avatar_url) — probe side
    _clipAssets = Signal()             # covers / channel backfill landed

    def __init__(self, parent=None):
        super().__init__(parent)
        # Anything that rewrites the whole form (a probe, a reset) still emits
        # `changed`; forward it so the range props refresh with it.
        self.changed.connect(self.rangeChanged)
        self._mode = 0                 # 0 YouTube link, 1 local file
        self._link = ""
        self._file_path = ""
        self._probing = False
        self._status = tr("Paste a link or pick a file, then read it.")
        self._status_kind = "muted"

        # probed source info
        self._has_info = False
        self._title = ""
        self._thumb_id = ""
        self._duration = 0.0
        self._video_id = ""
        self._qualities = []
        self._quality_index = 0
        self._start = 0.0
        self._end = 0.0
        # preview stream (link mode): direct URLs expire, so the page asks
        # for a silent re-probe when one goes stale — once per probe, then it
        # must say so out loud instead of looping forever.
        self._preview_url = ""
        self._preview_audio_url = ""
        self._preview_audio = False
        self._preview_av1 = False
        self._preview_px = 0
        self._preview_refreshed = False
        # True when YouTube only showed 360p-or-less for this read (throttled
        # extraction) — the page banners a fix instead of pretending 360p is
        # all the video has.
        self._thin = False
        # v1.2: audio languages of a dubbed video + the user's pick
        # ("" = original). The preview plays the picked language too.
        self._audio_tracks = []
        self._audio_track = ""
        self._vfmt = "mp4"
        self._afmt = "mp3"
        self._audio_only = False
        self._preview_audio_base = ""     # the original preview sound URL
        self._preview_audio_by_lang = {}

        # cut run state
        self._cutting = False
        self._cancel = False
        self._cut_pct = 0
        self._cut_written = 0
        self._result_path = ""
        self._result_label = ""
        # The segment this run is cutting — remembered so the finished clip
        # can be recorded into the persisted history with its real range.
        self._cut_start = 0.0
        self._cut_end = 0.0

        # persisted clips history (survives page switches + restarts)
        self._clips = []
        # source video's channel identity (link mode), recorded with each clip
        self._channel = {}
        # background lane for clip covers + channel backfill (one thread,
        # sequential, each item tried once per session)
        self._asset_jobs = collections.deque()
        self._asset_lock = threading.Lock()
        self._asset_running = False
        self._asset_tried = set()

        self._probed.connect(self._on_probed)
        self._previewReady.connect(self._on_preview_ready)
        self._cutStatus.connect(self._on_cut_status)
        self._cutProgress.connect(self._on_cut_progress)
        self._cutDone.connect(self._on_cut_done)
        self._cutResolved.connect(self._on_cut_resolved)
        self._channelAvatar.connect(self._on_channel_avatar)
        self._clipAssets.connect(self.refreshClips)
        self.refreshClips()

    @Slot()
    def retranslate(self):
        self.labelsChanged.emit()
        self.changed.emit()
        self.progressChanged.emit()
        self.clipsChanged.emit()

    # ── form ─────────────────────────────────────────────────────────────
    @Property(int, notify=changed)
    def mode(self):
        return self._mode

    @mode.setter
    def mode(self, v):
        v = 1 if int(v) == 1 else 0
        if v != self._mode:
            self._mode = v
            self._reset_info(tr("Paste a link or pick a file, then read it."))
            self.changed.emit()

    @Property(str, notify=changed)
    def link(self):
        return self._link

    @link.setter
    def link(self, v):
        v = v or ""
        if v != self._link:
            self._link = v
            self.changed.emit()

    @Slot()
    def pasteLink(self):
        clip = QGuiApplication.clipboard()
        text = (clip.text() if clip is not None else "") or ""
        text = text.strip().split()[0] if text.strip() else ""
        if not text:
            self.toast.emit(tr("Clipboard is empty."), "error")
            return
        self._link = text
        self.changed.emit()

    @Property(str, notify=changed)
    def filePath(self):
        return self._file_path

    @Property(str, notify=changed)
    def fileName(self):
        return os.path.basename(self._file_path) if self._file_path else ""

    @Slot(str)
    def setFile(self, path):
        # Arrives as a percent-encoded file:// URL from QtQuick.Dialogs. It must
        # be decoded, not just stripped: "Son%20of%20Love" is not a folder.
        path = local_path_from_url(path)
        if path != self._file_path:
            self._file_path = path
            self._reset_info(tr("Read the file to see its length."))
            self.changed.emit()

    def _reset_info(self, status):
        self._has_info = False
        self._title = ""
        self._thumb_id = ""
        self._duration = 0.0
        self._video_id = ""
        self._qualities = []
        self._quality_index = 0
        self._start = 0.0
        self._end = 0.0
        self._preview_url = ""
        self._preview_audio_url = ""
        self._preview_audio = False
        self._preview_av1 = False
        self._preview_px = 0
        self._preview_refreshed = False
        self._thin = False
        self._audio_tracks = []
        self._audio_track = ""
        self._vfmt = "mp4"
        self._afmt = "mp3"
        self._audio_only = False
        self._preview_audio_base = ""
        self._preview_audio_by_lang = {}
        self.audioChanged.emit()
        self._channel = {}
        self._result_path = ""
        self._result_label = ""
        self._set_status(status, "muted")

    def _set_status(self, text, kind="muted"):
        self._status = text
        self._status_kind = kind
        self.changed.emit()

    @Property(bool, notify=changed)
    def probing(self):
        return self._probing

    @Property(str, notify=changed)
    def statusText(self):
        return self._status

    @Property(str, notify=changed)
    def statusKind(self):
        return self._status_kind      # muted | ok | warn | error

    # ── probed info ──────────────────────────────────────────────────────
    @Property(bool, notify=changed)
    def hasInfo(self):
        return self._has_info

    @Property(str, notify=changed)
    def title(self):
        return self._title

    @Property(str, notify=changed)
    def thumbId(self):
        return self._thumb_id

    @Property(float, notify=changed)
    def durationSec(self):
        return self._duration

    @Property(str, notify=changed)
    def durationText(self):
        return fmt_clock(self._duration) if self._duration > 0 else ""

    @Property(str, notify=changed)
    def previewUrl(self):
        """What the page's preview player plays: the probed light stream for
        links, the file itself for local mode."""
        if self._mode == 1:
            if not self._file_path:
                return ""
            try:
                from PySide6.QtCore import QUrl
                return QUrl.fromLocalFile(self._file_path).toString()
            except Exception:  # noqa: BLE001
                return ""
        return self._preview_url

    @Property(str, notify=changed)
    def previewAudioUrl(self):
        """Separate sound track for a video-only (HD) link preview — YouTube
        ships every tier above 360p without audio. The page plays it in a
        second player kept in lock-step with the picture. "" = the picture
        carries its own sound (progressive stream, or a local file)."""
        if self._mode == 1:
            return ""
        return self._preview_audio_url

    @Property(bool, notify=changed)
    def previewHasAudio(self):
        return self._mode == 1 or self._preview_audio

    @Property(bool, notify=changed)
    def previewCodecWarning(self):
        """True when the link preview is an AV1 stream: it may not decode on
        PCs without AV1 hardware (black preview + decoder errors in the log),
        while Cut & Download is unaffected (ffmpeg handles it directly)."""
        return self._mode == 0 and self._has_info and self._preview_av1

    @Property(str, notify=changed)
    def previewLabel(self):
        """Picked preview height ("720p") for the page's quality badge."""
        try:
            px = int(self._preview_px or 0)
        except (TypeError, ValueError):
            px = 0
        return f"{px}p" if px > 0 else ""

    @Property(bool, notify=changed)
    def thinProbe(self):
        """True when the read only saw 360p-or-less (throttled extraction).
        The page shows a fix-it banner (deno / cookies / re-read) instead of
        presenting 360p as the video's whole quality range."""
        return self._mode == 0 and self._has_info and self._thin

    # ── audio track (dubbed videos, v1.2) ────────────────────────────────
    @Property("QVariantList", notify=changed)
    def audioTracks(self):
        """[{key, lang, code, name, native, nameFa, kind, kbps, rtl}], the
        original first — empty for a single-language video or a local file."""
        return self._audio_tracks if self._mode == 0 else []

    @Property(str, notify=changed)
    def audioTrack(self):
        return self._audio_track

    # ── v3.47: output — video (MP4/MKV/WEBM) or audio only (MP3/…) ───────
    _VFMTS = ("mp4", "mkv", "webm")
    _AFMTS = ("mp3", "m4a", "opus", "wav", "flac")

    @property
    def _output_format(self):
        return self._afmt if self._audio_only else self._vfmt

    @Property(str, notify=changed)
    def outputFormat(self):
        return self._output_format

    @Property(str, notify=changed)
    def videoFormat(self):
        return self._vfmt

    @Property(str, notify=changed)
    def audioFormat(self):
        return self._afmt

    @Property(bool, notify=changed)
    def audioOnly(self):
        return self._audio_only

    @Slot(str)
    def setVideoFormat(self, key):
        key = str(key or "").lower()
        if self._cutting or key not in self._VFMTS:
            return
        self._vfmt = key
        self._audio_only = False      # a video format means a video clip
        self.changed.emit()

    @Slot(str)
    def setAudioFormat(self, key):
        key = str(key or "").lower()
        if self._cutting or key not in self._AFMTS:
            return
        self._afmt = key
        self._audio_only = True       # an audio format means audio only
        self.changed.emit()

    @Slot(str)
    def setOutputFormat(self, key):
        key = str(key or "").lower()
        if key in self._AFMTS:
            self.setAudioFormat(key)
        else:
            self.setVideoFormat(key)

    @Slot(bool)
    def setAudioOnly(self, on):
        on = bool(on)
        if self._cutting or on == self._audio_only:
            return
        self._audio_only = on
        self.changed.emit()

    @Slot(str)
    def setAudioTrack(self, key):
        """Pick the clip's audio language ("" = original). Takes effect in the
        preview at once and in the next cut."""
        key = str(key or "")
        if self._cutting or key == self._audio_track:
            return
        if key and not any(t.get("key") == key for t in self._audio_tracks):
            return
        self._audio_track = key
        self._apply_preview_audio()
        self.audioChanged.emit()
        self.changed.emit()

    def _apply_preview_audio(self):
        url = (self._preview_audio_by_lang.get(self._audio_track)
               if self._audio_track else "") or self._preview_audio_base
        self._preview_audio_url = url or ""
        if url:
            self._preview_audio = True

    def _audio_track_label(self):
        for t in self._audio_tracks:
            if t.get("key") == self._audio_track and self._audio_track:
                return t.get("code") or self._audio_track.upper()
        return ""

    @Property("QVariantList", notify=changed)
    def qualities(self):
        """[{label, sub}] for the quality pills (link mode only)."""
        return [{"label": q.get("label", ""), "sub": q.get("sub", "")}
                for q in self._qualities]

    @staticmethod
    def _default_quality_index(qualities):
        """Pre-selected cut quality: 1080p, never above it by default.

        The list is [Best, 2160, 1440, 1080, 720, ...]. A 4K video starts on
        1080p; a video that tops out lower starts on its own best (720p, ...).
        Anything higher is still one click away."""
        best_i, best_h = 0, -1
        for i, q in enumerate(qualities or []):
            try:
                h = int(q.get("height") or 0)
            except (TypeError, ValueError):
                h = 0
            if 0 < h <= 1080 and h > best_h:
                best_i, best_h = i, h
        return best_i

    @Property(int, notify=changed)
    def qualityIndex(self):
        return self._quality_index

    @qualityIndex.setter
    def qualityIndex(self, i):
        try:
            i = int(i)
        except (TypeError, ValueError):
            return
        if self._qualities:
            i = max(0, min(len(self._qualities) - 1, i))
        else:
            i = 0
        if i != self._quality_index:
            self._quality_index = i
            self.changed.emit()

    # ── segment ──────────────────────────────────────────────────────────
    def _range_moved(self, could_cut):
        """Notify a range edit cheaply: only the range props, plus the full
        `changed` in the rare case the edit flipped whether a cut is possible."""
        self.rangeChanged.emit()
        if self.canCut != could_cut:
            self.changed.emit()

    @Property(float, notify=rangeChanged)
    def startSec(self):
        return self._start

    @startSec.setter
    def startSec(self, v):
        try:
            v = float(v)
        except (TypeError, ValueError):
            return
        v = max(0.0, min(v, self._end if self._has_info else v))
        if v != self._start:
            could_cut = self.canCut
            self._start = v
            self._range_moved(could_cut)

    @Property(float, notify=rangeChanged)
    def endSec(self):
        return self._end

    @endSec.setter
    def endSec(self, v):
        try:
            v = float(v)
        except (TypeError, ValueError):
            return
        if self._has_info:
            v = max(self._start, min(v, self._duration))
        if v != self._end:
            could_cut = self.canCut
            self._end = v
            self._range_moved(could_cut)

    @Property(str, notify=rangeChanged)
    def startLabel(self):
        return fmt_clock(self._start)

    @Property(str, notify=rangeChanged)
    def endLabel(self):
        return fmt_clock(self._end)

    @Property(str, notify=rangeChanged)
    def clipText(self):
        if not self._has_info or self._end <= self._start:
            return ""
        return tr("Clip: {d}").format(d=fmt_clock(self._end - self._start))

    @Slot(str)
    def setStartText(self, text):
        v = parse_clock(text, self._duration if self._has_info else 0.0)
        if v is None:
            self._set_status(tr("Use seconds or M:SS — e.g. 90 or 1:30."),
                             "warn")
            return
        self.startSec = v

    @Slot(str)
    def setEndText(self, text):
        v = parse_clock(text, self._duration if self._has_info else 0.0)
        if v is None:
            self._set_status(tr("Use seconds or M:SS — e.g. 90 or 1:30."),
                             "warn")
            return
        self.endSec = v

    @Slot(float)
    def nudgeStart(self, delta):
        if self._has_info:
            self.startSec = self._start + float(delta)

    @Slot(float)
    def nudgeEnd(self, delta):
        if self._has_info:
            self.endSec = self._end + float(delta)

    # ── probe ────────────────────────────────────────────────────────────
    @Slot()
    def fetchInfo(self):
        if self._probing or self._cutting:
            return
        if self._mode == 0:
            url = (self._link or "").strip()
            if not url:
                self._set_status(tr("Paste a YouTube link first."), "error")
                return
        else:
            if not self._file_path or not os.path.isfile(self._file_path):
                self._set_status(tr("Pick a video file first."), "error")
                return
        self._probing = True
        self._result_path = ""
        self._result_label = ""
        self._set_status(tr("Reading…"), "muted")
        mode, link, path = self._mode, (self._link or "").strip(), self._file_path
        cfg = load_app_config()
        proxy = (cfg.get("ai_proxy", "") or "").strip()
        cookies = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        def worker():
            try:
                if mode == 0:
                    ok, info, err = probe_link(link, proxy_url=proxy,
                                               cookies_browser=cookies)
                else:
                    dur, why = probe_file_with_error(path)
                    if dur > 0:
                        ok, info, err = True, {
                            "video_id": "",
                            "title": os.path.basename(path),
                            "duration": dur,
                            "thumb_url": "",
                            "qualities": [],
                        }, ""
                    else:
                        ok, info, err = False, {}, {
                            "missing": tr("That file is no longer there — pick it again."),
                            "no-ffmpeg": tr("The video engine isn't ready yet. "
                                            "Open the Downloads page once so it can "
                                            "set itself up, then try again."),
                            "timeout": tr("That file took too long to read — it may be "
                                          "on a slow or disconnected drive."),
                        }.get(why, tr("Couldn't read that file — it may be damaged, or "
                                      "in a format the video engine can't open."))
                self._probed.emit(ok, info, err)
            except Exception as exc:  # noqa: BLE001 — surfaced, not raised
                log_crash("CutterVM probe failed:\n" + traceback.format_exc())
                self._probed.emit(False, {}, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot(bool, "QVariant", str)
    def _on_probed(self, ok, info, error):
        self._probing = False
        if not ok:
            self._reset_info("")
            self._set_status(error or tr("Couldn't read that video."),
                             "error")
            self.toast.emit(error or tr("Couldn't read that video."),
                            "error")
            return
        info = dict(info or {})
        try:
            dur = max(0.0, float(info.get("duration") or 0))
        except (TypeError, ValueError):
            dur = 0.0
        self._has_info = True
        self._title = info.get("title") or tr("Untitled")
        self._thumb_id = _thumb_id(info.get("thumb_url") or "")
        self._duration = dur
        self._video_id = info.get("video_id") or ""
        self._qualities = [dict(q) for q in (info.get("qualities") or [])]
        self._quality_index = self._default_quality_index(self._qualities)
        self._preview_url = info.get("preview_url") or ""
        self._preview_audio_url = info.get("preview_audio_url") or ""
        self._preview_audio = bool(info.get("preview_has_audio"))
        # v1.2: dubs. A re-read of the same video keeps the picked language.
        same_video = bool(self._video_id) and \
            getattr(self, "_last_tracks_vid", "") == self._video_id
        self._last_tracks_vid = self._video_id
        self._audio_tracks = [dict(t) for t in (info.get("audio_tracks") or [])]
        self._preview_audio_base = self._preview_audio_url
        self._preview_audio_by_lang = dict(info.get("preview_audio_by_lang") or {})
        keys = {t.get("key") for t in self._audio_tracks}
        if not same_video or self._audio_track not in keys:
            self._audio_track = ""
        self._apply_preview_audio()
        self.audioChanged.emit()
        self._preview_av1 = bool(info.get("preview_is_av1"))
        try:
            self._preview_px = int(info.get("preview_px") or 0)
        except (TypeError, ValueError):
            self._preview_px = 0
        self._thin = bool(info.get("thin"))
        self._preview_refreshed = False
        self._preview_refreshing = False
        self._channel = dict(info.get("channel") or {})
        self._fetch_channel_avatar()
        self._start = 0.0
        self._end = dur
        if self._thin:
            self._set_status(
                tr("Only 360p was visible — YouTube limited this read. "
                   "See the Quality section below to unlock HD."), "warn")
        else:
            self._set_status(
                tr("Ready — pick a segment, then cut it."), "ok")
        self.changed.emit()

    # ── cut ──────────────────────────────────────────────────────────────
    @Property(bool, notify=changed)
    def canCut(self):
        return (self._has_info and not self._probing and not self._cutting
                and self._end > self._start
                and (self._mode == 1 or len(self._qualities) > 0))

    @Property(bool, notify=changed)
    def cutting(self):
        return self._cutting

    @Property(int, notify=progressChanged)
    def cutPct(self):
        return self._cut_pct

    @Property(str, notify=progressChanged)
    def cutDetail(self):
        if not self._cutting and not self._result_path:
            return ""
        size = _size_text(self._cut_written)
        if self._result_path:
            return size
        if size:
            return tr("{done} · {pct}%").format(done=size, pct=self._cut_pct)
        return tr("{pct}%").format(pct=self._cut_pct)

    @Property(bool, notify=changed)
    def hasResult(self):
        return bool(self._result_path)

    @Property(str, notify=changed)
    def resultName(self):
        if self._result_label:
            return f"{os.path.basename(self._result_path)}  ·  {self._result_label}"
        return os.path.basename(self._result_path)

    # v3.39.9: the finished clip's full path, so the "Your clip is ready"
    # dock can be dragged out of the app like any file.
    @Property(str, notify=changed)
    def resultPath(self):
        return self._result_path if (self._result_path
                                     and os.path.isfile(self._result_path)) else ""

    @Slot()
    def startCut(self):
        if not self.canCut:
            return
        if self._mode == 0:
            url = (self._link or "").strip()
            if not url:
                self._set_status(tr("Paste a YouTube link first."), "error")
                return
            try:
                cap = int((self._qualities[self._quality_index] or {}).get(
                    "key") or 0)
            except (IndexError, TypeError, ValueError, AttributeError):
                cap = 0
        else:
            url, cap = "", 0
            if not self._file_path or not os.path.isfile(self._file_path):
                self._set_status(tr("Pick a video file first."), "error")
                return
        cfg = load_app_config()
        # Clips are videos: the Settings "Videos" folder wins, then the older
        # general save folder, then Desktop/YouTube.
        target = (cfg.get("video_save_folder") or "").strip()
        if not target or not os.path.isdir(target):
            target = (cfg.get("save_folder") or "").strip()
        if not target or not os.path.isdir(target):
            target = desktop_download_dir("YouTube")
        try:
            os.makedirs(target, exist_ok=True)
        except OSError as exc:
            self._set_status(str(exc), "error")
            return
        proxy = (cfg.get("ai_proxy", "") or "").strip()
        cookies = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        self._cutting = True
        self._cancel = False
        self._cut_pct = 0
        self._cut_written = 0
        self._result_path = ""
        self._result_label = ""
        self._cut_start, self._cut_end = self._start, self._end
        self._set_status(tr("Cutting…"), "muted")
        self.changed.emit()
        self.progressChanged.emit()
        mode, start, end = self._mode, self._start, self._end
        path, link = self._file_path, (self._link or "").strip()
        audio_lang = self._audio_track if mode == 0 else ""
        self.toast.emit(
            tr("Cut started — {a} → {b}").format(a=fmt_clock(start),
                                                 b=fmt_clock(end)),
            "download")
        # v3.41: follows the user as a live card if they leave the app
        live = notifier()
        if live is not None:
            try:
                live.live_begin(
                    "cut", "cut",
                    title=(self._title or tr("Untitled")) if mode == 0
                    else (os.path.basename(path) or tr("Untitled")),
                    thumb_id=self._thumb_id if mode == 0 else "",
                    page=12, source=tr("Video Cutter"),
                    subtitle=f"{fmt_clock(start)} → {fmt_clock(end)}")
                live.live_update("cut", stage=tr("Cutting…"))
            except Exception:
                pass

        def worker():
            try:
                if mode == 0:
                    ok, msg, fp = cut_link(
                        url, cap, start, end, target,
                        on_status=lambda t: self._cutStatus.emit(t),
                        on_progress=lambda p, w: self._cutProgress.emit(p, w),
                        proxy_url=proxy, cookies_browser=cookies,
                        should_cancel=lambda: self._cancel,
                        on_resolved=lambda px, lbl: self._cutResolved.emit(
                            px, lbl),
                        audio_lang=audio_lang,
                        output_format=self._output_format,
                        audio_only=self._audio_only)
                else:
                    ok, msg, fp = cut_file(
                        path, start, end, target,
                        on_status=lambda t: self._cutStatus.emit(t),
                        on_progress=lambda p, w: self._cutProgress.emit(p, w),
                        should_cancel=lambda: self._cancel,
                        output_format=self._output_format,
                        audio_only=self._audio_only)
                self._cutDone.emit(ok, msg, fp)
            except Exception as exc:  # noqa: BLE001
                log_crash("CutterVM cut failed:\n" + traceback.format_exc())
                self._cutDone.emit(False, str(exc), "")

        threading.Thread(target=worker, daemon=True).start()

    @Slot()
    def cancelCut(self):
        if self._cutting:
            self._cancel = True
            self._set_status(tr("Stopping…"), "warn")

    @Slot()
    def refreshPreview(self):
        """Silently re-resolve the preview stream (direct URLs expire). Called
        by the page when the player reports an error, and safe to call
        anytime: link mode only, never while probing/cutting, and only once
        per probe — a second stale URL means telling the user to re-read
        instead of looping re-probes forever."""
        if (self._mode != 0 or not self._has_info or self._probing
                or self._cutting):
            return
        # The picture and its separate sound track expire together, so both
        # players report it — one re-probe answers both.
        if getattr(self, "_preview_refreshing", False):
            return
        if self._preview_refreshed:
            self._set_status(
                tr("Preview expired — press Read video again."), "warn")
            return
        self._preview_refreshed = True
        url = (self._link or "").strip()
        if not url:
            return
        self._preview_refreshing = True
        cfg = load_app_config()
        proxy = (cfg.get("ai_proxy", "") or "").strip()
        cookies = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        def worker():
            try:
                ok, info, _err = probe_link(url, proxy_url=proxy,
                                            cookies_browser=cookies)
                if ok:
                    try:
                        px = int(info.get("preview_px") or 0)
                    except (TypeError, ValueError):
                        px = 0
                    self._preview_audio_by_lang = dict(
                        info.get("preview_audio_by_lang") or {})
                    self._previewReady.emit(
                        True, info.get("preview_url") or "",
                        bool(info.get("preview_has_audio")),
                        bool(info.get("preview_is_av1")), px,
                        info.get("preview_audio_url") or "")
                else:
                    self._previewReady.emit(False, "", False, False, 0, "")
            except Exception:             # noqa: BLE001
                log_crash("CutterVM preview refresh failed:\n"
                          + traceback.format_exc())
                self._previewReady.emit(False, "", False, False, 0, "")

        threading.Thread(target=worker, daemon=True).start()

    @Slot(bool, str, bool, bool, int, str)
    def _on_preview_ready(self, ok, url, has_audio, is_av1, px, audio_url=""):
        self._preview_refreshing = False
        if ok and url:
            self._preview_url = url
            self._preview_audio_url = audio_url or ""
            self._preview_audio = has_audio
            self._preview_audio_base = self._preview_audio_url
            self._apply_preview_audio()
            self._preview_av1 = is_av1
            try:
                self._preview_px = int(px or 0)
            except (TypeError, ValueError):
                self._preview_px = 0
            self.changed.emit()
        else:
            self._set_status(
                tr("Preview expired — press Read video again."), "warn")

    @Slot(str)
    def _on_cut_status(self, text):
        if text:
            self._status = text
            self._status_kind = "muted"
            self.changed.emit()
            live = notifier()
            if live is not None:
                live.live_update("cut", stage=text.rstrip(" …").rstrip("…").strip()
                                 or tr("Cutting…"))

    @Slot(int, int)
    def _on_cut_progress(self, pct, written):
        self._cut_pct = max(0, min(100, int(pct)))
        self._cut_written = max(0, int(written))
        self.progressChanged.emit()
        live = notifier()
        if live is not None:
            live.live_update("cut", pct=self._cut_pct, done=self._cut_written,
                             indeterminate=self._cut_pct <= 0)

    @Slot(int, str)
    def _on_cut_resolved(self, px, label):
        self._result_label = label or ""
        dub = self._audio_track_label()
        if dub and self._result_label:
            self._result_label = f"{self._result_label} · {dub}"
        self.changed.emit()

    @Slot(bool, str, str)
    def _on_cut_done(self, ok, message, filepath):
        self._cutting = False
        self._cancel = False
        # v3.41: a live card still on screen becomes the "done" notice itself
        live = notifier()
        consumed = False
        if live is not None:
            try:
                consumed = live.live_finish(
                    "cut",
                    "stopped" if message == DOWNLOAD_CANCELLED
                    else ("success" if ok else "error"),
                    message="" if ok else (message or tr("Cut failed.")),
                    path=filepath if ok else "")
            except Exception:
                consumed = False
        if message == DOWNLOAD_CANCELLED:
            self._cut_pct = 0
            self._cut_written = 0
            self._set_status(tr("Cut stopped."), "warn")
            self.toast.emit(tr("Cut stopped."), "info")
        elif ok:
            self._result_path = filepath or ""
            self._set_status(tr("Saved."), "ok")
            self.toast.emit(tr("Clip saved — {p}").format(
                p=os.path.basename(filepath or "")), "success")
            self._record_clip(filepath)
            if not consumed:
                announce("success", tr("Clip ready"),
                         os.path.basename(filepath or ""), page=12,
                         path=filepath, icon="scissors",
                         source=tr("Video Cutter"))
        else:
            self._cut_pct = 0
            self._set_status(message or tr("Cut failed."), "error")
            self.toast.emit(message or tr("Cut failed."), "error")
            if not consumed:
                announce("error", tr("Cut failed."), message or "", page=12,
                         icon="scissors", source=tr("Video Cutter"))
        self.changed.emit()
        self.progressChanged.emit()

    def _record_clip(self, filepath):
        """Persist one finished clip into the history (best effort)."""
        try:
            if not filepath or not os.path.isfile(filepath):
                return
            if self._mode == 0:
                title = self._title or tr("Untitled")
                source = self._title or (self._link or "").strip()
            else:
                title = os.path.basename(self._file_path) or tr("Untitled")
                source = self._file_path or title
            clips_add(
                title, source_label=source, video_id=self._video_id,
                start_sec=self._cut_start, end_sec=self._cut_end,
                quality_label=self._result_label,
                filepath=filepath, file_size=file_size_of(filepath),
                channel=self._channel if self._mode == 0 else None)
        except Exception:                 # noqa: BLE001 — history is auxiliary
            log_crash("CutterVM record clip failed:\n"
                      + traceback.format_exc())
        self.refreshClips()

    # ── persisted clips history ──────────────────────────────────────
    @Slot()
    def refreshClips(self):
        """Rebuild the Clips list from the database (newest first)."""
        rows = []
        for item in clips_list():
            fp = item.get("filepath") or ""
            try:
                start = float(item.get("start_sec") or 0)
            except (TypeError, ValueError):
                start = 0.0
            try:
                end = float(item.get("end_sec") or 0)
            except (TypeError, ValueError):
                end = 0.0
            rows.append({
                "id": int(item.get("id") or 0),
                "title": item.get("title") or tr("Untitled"),
                "rangeText": (f"{fmt_clock(start)} → {fmt_clock(end)}"
                              if end > start else ""),
                "quality": item.get("quality_label") or "",
                "sizeText": _size_text(item.get("file_size") or 0),
                "fileName": os.path.basename(fp) if fp else "",
                "filepath": fp,
                "exists": bool(fp) and os.path.isfile(fp),
                "videoId": item.get("video_id") or "",
                "isAudio": os.path.splitext(fp)[1].lower() in _AUDIO_EXTS,
                "startSec": start,
                "endSec": end,
                "spanText": fmt_clock(end - start) if end > start else "",
                "channelTitle": (item.get("channel_title") or "").strip(),
                "channelId": (item.get("channel_id") or "").strip(),
                "channelUrl": (item.get("channel_url") or "").strip(),
                "channelThumbUrl": (item.get("channel_thumb_url") or "").strip(),
                "subscriberCount": item.get("subscriber_count"),
            })
            row = rows[-1]
            # Card cover: the clip's own frame (cached) → the source video's
            # YouTube thumbnail while that is being made → the scissors.
            cover = _clip_thumb_path(row["id"]) if row["id"] else ""
            row["thumbUrl"] = (QUrl.fromLocalFile(cover).toString()
                               if cover and os.path.isfile(cover) else "")
            row["ytThumbId"] = (_thumb_id(f"https://i.ytimg.com/vi/{row['videoId']}/mqdefault.jpg")
                                if row["videoId"] else "")
        self._clips = rows
        self.clipsChanged.emit()
        self._queue_clip_assets(rows)

    # ── clip covers + channel backfill (background) ─────────────────
    def _queue_clip_assets(self, rows):
        jobs = []
        for r in rows:
            cid = r["id"]
            if (cid and r["exists"] and not r["thumbUrl"] and not r["isAudio"]
                    and ("thumb", cid) not in self._asset_tried):
                self._asset_tried.add(("thumb", cid))
                span = max(0.0, r["endSec"] - r["startSec"])
                jobs.append(("thumb", cid, r["filepath"], span * 0.4))
        for r in rows:
            vid = r["videoId"]
            needs = vid and (not r["channelTitle"] or not r["channelThumbUrl"]
                            # v3.24 — the hover card on the channel logo needs
                            # the subscriber count too; older clips lack it.
                            or r.get("subscriberCount") in (None, "", 0))
            if needs and ("channel", vid) not in self._asset_tried:
                self._asset_tried.add(("channel", vid))
                jobs.append(("channel", vid, r["channelId"], 0))
        if not jobs:
            return
        with self._asset_lock:
            # covers first: they are local and fast; network lookups after
            self._asset_jobs.extend(j for j in jobs if j[0] == "thumb")
            self._asset_jobs.extend(j for j in jobs if j[0] == "channel")
            if self._asset_running:
                return
            self._asset_running = True
        threading.Thread(target=self._asset_worker, daemon=True).start()

    def _asset_worker(self):
        dirty = False
        last_kind = ""
        while True:
            with self._asset_lock:
                job = self._asset_jobs.popleft() if self._asset_jobs else None
                if job is None:
                    self._asset_running = False
            if job is None:
                break
            kind = job[0]
            # flush covers as one batch before the slower channel lookups
            if dirty and last_kind and kind != last_kind:
                self._clipAssets.emit()
                dirty = False
            last_kind = kind
            try:
                if kind == "thumb":
                    _k, cid, path, at = job
                    dirty |= extract_clip_thumb(path, _clip_thumb_path(cid), at)
                else:
                    _k, vid, known_cid, _ = job
                    meta = self._channel_for_video(vid, known_cid)
                    if meta and clips_update_channel(vid, meta):
                        dirty = True
            except Exception:             # noqa: BLE001 — cosmetic lane
                log_crash("CutterVM clip asset job failed:\n"
                          + traceback.format_exc())
        if dirty:
            self._clipAssets.emit()

    @staticmethod
    def _channel_for_video(vid, known_cid=""):
        """Channel identity for a clip's source video (worker thread)."""
        from app.core.download import _channel_avatar_url, channel_meta_for_video
        # 1) the Downloads library may already know it (free, offline)
        try:
            from app.core.db.downloads import downloads_list
            d = next((x for x in downloads_list()
                      if (x.get("video_id") or "") == vid), None) or {}
        except Exception:                 # noqa: BLE001
            d = {}
        meta = {k: d.get(k) for k in ("channel_title", "channel_url",
                                      "channel_thumb_url", "subscriber_count")
                if d.get(k) not in (None, "")}
        if (meta.get("channel_title") and meta.get("channel_thumb_url")
                and meta.get("subscriber_count") not in (None, "", 0)):
            return meta
        # 2) we know the channel id, only the avatar is missing
        if known_cid:
            url = _channel_avatar_url(known_cid)
            if url:
                meta.setdefault("channel_thumb_url", url)
            # v3.51: only stop here when the count is known too — otherwise fall
            # through to the page read, which is where the count comes from
            if meta and meta.get("subscriber_count") not in (None, "", 0):
                return meta
        # 3) one light read of the watch page
        fresh = channel_meta_for_video(vid)
        for k, v in fresh.items():
            if v and not meta.get(k):
                meta[k] = v
        return meta

    def _fetch_channel_avatar(self):
        """Avatar for the just-probed link, off the GUI thread."""
        vid = self._video_id
        cid = (self._channel.get("channel_id") or "").strip()
        if self._mode != 0 or not vid or not cid:
            return

        def worker():
            try:
                from app.core.download import _channel_avatar_url
                url = _channel_avatar_url(cid)
            except Exception:             # noqa: BLE001
                url = ""
            if url:
                self._channelAvatar.emit(vid, url)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, str)
    def _on_channel_avatar(self, vid, url):
        if vid and vid == self._video_id:
            self._channel["channel_thumb_url"] = url
        # a clip may already have been cut before the avatar arrived
        if any(r["videoId"] == vid and not r["channelThumbUrl"] for r in self._clips):
            if clips_update_channel(vid, {"channel_thumb_url": url}):
                self.refreshClips()

    @Property("QVariantList", notify=clipsChanged)
    def clips(self):
        """Newest-first finished clips for the page's Clips section."""
        return self._clips

    @Property(int, notify=clipsChanged)
    def clipsCount(self):
        return len(self._clips)

    @Slot(int)
    def deleteClip(self, clip_id):
        try:
            clip_id = int(clip_id)
        except (TypeError, ValueError):
            return
        if clips_delete(clip_id):
            try:
                os.remove(_clip_thumb_path(clip_id))
            except OSError:
                pass
            self.refreshClips()
            self.toast.emit(tr("Clip removed from history."), "success")

    @Slot()
    def clearClips(self):
        if clips_clear():
            try:
                for name in os.listdir(_CLIP_THUMB_DIR):
                    if name.endswith(".jpg"):
                        os.remove(os.path.join(_CLIP_THUMB_DIR, name))
            except OSError:
                pass
            self.refreshClips()
            self.toast.emit(tr("Clips history cleared."), "success")

    @Slot(int, result="QVariantMap")
    def clipPlayInfo(self, clip_id):
        """What the in-app VideoPlayer needs for one finished clip (same shape
        as DownloadsVM.playInfo, minus the channel block a clip doesn't have)."""
        row = next((r for r in self._clips if r["id"] == int(clip_id or 0)), None)
        if row is None:
            return {}
        path = row.get("filepath") or ""
        if not path or not os.path.isfile(path):
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return {}
        vid = row.get("videoId") or ""
        url = QUrl.fromLocalFile(path).toString()
        thumb = f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg" if vid else ""
        # v3.16-p4: the source video's channel (logo, name, link, subs) as
        # recorded with the clip itself; the downloads record of the same
        # video id is only the fallback now (p3 relied on it alone, so clips
        # cut straight from a link still showed a "C" initial).
        ch = {
            "channel_title": row.get("channelTitle") or "",
            "channel_url": row.get("channelUrl") or (
                f"https://www.youtube.com/channel/{row['channelId']}"
                if row.get("channelId") else ""),
            "channel_thumb_url": row.get("channelThumbUrl") or "",
            "subscriber_count": row.get("subscriberCount"),
        }
        if vid and not (ch["channel_title"] and ch["channel_thumb_url"]
                        and ch.get("subscriber_count") not in (None, "", 0)):
            try:
                from app.core.db.downloads import downloads_list
                d = next((d for d in downloads_list()
                          if (d.get("video_id") or "") == vid), {}) or {}
            except Exception:             # noqa: BLE001 — identity is cosmetic
                d = {}
            for k, v in d.items():
                if v not in (None, "") and not ch.get(k):
                    ch[k] = v
        ch_title = (ch.get("channel_title") or ch.get("channel") or "").strip()
        subs = ch.get("subscriber_count")
        # open YouTube exactly where the clip starts
        start = int(max(0.0, float(row.get("startSec") or 0)))
        watch = ""
        if vid:
            watch = f"https://www.youtube.com/watch?v={vid}" + (f"&t={start}s" if start > 0 else "")
        return {
            "videoId": vid,
            "title": row.get("title") or tr("Untitled"),
            "filePath": path,
            "fileUrl": url,
            "quality": row.get("quality") or "",
            "isAudio": bool(row.get("isAudio")),
            "thumbId": _thumb_id(thumb) if thumb else "",
            # the line under the title: what part of the source this clip is
            "channelTitle": ch_title or " · ".join(x for x in (tr("Clip"), row.get("rangeText") or "") if x),
            "channelThumbId": _thumb_id(ch.get("channel_thumb_url") or ""),
            "channelUrl": ch.get("channel_url") or "",
            "subscriberCount": int(subs) if subs not in (None, "") else 0,
            "subsHidden": bool(ch.get("subs_hidden")),
            "watchUrl": watch,
            "startSec": start,
            "qualities": [{"label": row.get("quality") or tr("Clip"), "key": "",
                           "filePath": path, "fileUrl": url}],
        }

    @Slot(str)
    def openClipFile(self, path):
        if not path or not os.path.isfile(path):
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return
        self._reveal(path)

    @Slot(str)
    def openClipFolder(self, path):
        folder = os.path.dirname(path) if path else ""
        if not folder or not os.path.isdir(folder):
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return
        self._reveal(folder)

    @Slot()
    def openResult(self):
        self._reveal(self._result_path)

    @Slot()
    def openResultFolder(self):
        self._reveal(os.path.dirname(self._result_path)
                     if self._result_path else "")

    def _reveal(self, target):
        if not target:
            return
        try:
            if sys.platform.startswith("win"):
                os.startfile(target)  # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", target])
            else:
                subprocess.Popen(["xdg-open", target])
        except Exception as e:        # noqa: BLE001
            self.toast.emit(tr("Could not open: {e}").format(e=e), "error")

    @Slot()
    def newClip(self):
        """Back to a fresh cut on the same source (keeps the probed info)."""
        self._result_path = ""
        self._result_label = ""
        self._cut_pct = 0
        self._cut_written = 0
        self._start = 0.0
        self._end = self._duration
        self._set_status(tr("Ready — pick a segment, then cut it."),
                         "ok" if self._has_info else "muted")
        self.changed.emit()
        self.progressChanged.emit()
