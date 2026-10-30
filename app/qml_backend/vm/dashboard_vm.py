"""app.qml_backend.vm.dashboard_vm - YouTube Hunter (QML).

ViewModel behind DashboardPage.qml. Owns the "New Extraction Task" form state
and drives a real scrape on a worker thread, reporting progress/log/status back
to QML through notifying properties and signals.

Business logic is reused straight from app.core (build_youtube_service,
resolve_channel_id, the uploads/search id fetchers, fetch_transcript,
write_export, quota helpers) — this file only orchestrates them and marshals
results onto the GUI thread via app.core.signals.SignalEmitter, exactly like the
legacy app.ui.window.scrape_mixin does. The QWidgets app is untouched.
"""

import base64
import hashlib
import os
import re
import threading
import time
import traceback
from collections import deque
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutTimeout

from datetime import datetime, timedelta, timezone

from PySide6.QtCore import QObject, Property, QTimer, Signal, Slot

from app.config import load_app_config, save_app_config
from app.constants import FORMAT_EXT, SORT_MAP, SORT_SUFFIX
from app.core.exports import read_checkpoint_rows, write_export
from app.core.niche.helpers import detect_short
from app.core.quota import (api_quota_remaining, clean_api_keys,
                            key_quota_remaining, quota_reset_local_str)
from app.core.scrape_pipeline import (ChunkFeed, KeyRing, MetadataAhead,
                                      Throttle, channel_info,
                                      iter_oldest_pages, iter_search_pages,
                                      iter_upload_pages)
from app.core.signals import SignalEmitter
from app.core.transcripts import (fetch_transcript, get_public_ip,
                                  reset_breaker,
                                  set_throttle_listener, set_turbo,
                                  transcript_stats)
from app.core.utils import local_path_from_url, parse_iso8601_duration
from app.core.youtube_api import (
    QuotaExceededError, ScrapeCancelled, _row_from_item, resolve_channel_id)
from app.crash import log_crash
from app.i18n import tr


# v3.54 results board: the thumbnail provider (image://thumbs/<id>) takes a
# base64 of the image URL as its id, same as niche_vm / ideas_vm.
_THUMB_URL = "https://i.ytimg.com/vi/{vid}/mqdefault.jpg"
_THUMB_URL_HQ = "https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
# "Published" window on the Scraper page (days; 0 = any time)
_PUBLISHED_CHOICES = (0, 7, 30, 90, 365)
_RECENT_MAX = 8
# A "blocked" transcript answer pauses the whole run only after this many
# consecutive videos were refused. fetch_transcript has already walked the
# library, the InnerTube player and the yt-dlp ladder for each of them, so one
# refusal is often a video-specific bot check — pausing on it made the first
# scrape look IP-banned when the rest of the channel was fine.
_TR_BLOCK_CONFIRM = 3


def _as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return int(float(v))
        except (TypeError, ValueError):
            return 0


def _result_row(row):
    """The compact, QML-ready view of one scraped row (results board).

    Numbers go out as floats: a JS number is a double either way, and a view
    count past 2^31 must never be squeezed through a 32-bit int on the way."""
    vid = row.get("video_id") or ""
    secs = parse_iso8601_duration(row.get("duration", "")) or 0
    try:
        short = bool(detect_short(secs, row.get("title", ""), row.get("description", "")))
    except Exception:              # noqa: BLE001 — cosmetic flag only
        short = False
    thumb = ""
    if vid:
        thumb = base64.b64encode(_THUMB_URL.format(vid=vid).encode("utf-8")).decode("ascii")
    return {
        "vid": vid,
        "title": str(row.get("title") or ""),
        "views": float(_as_int(row.get("view_count"))),
        "likes": float(_as_int(row.get("like_count"))),
        "comments": float(_as_int(row.get("comment_count"))),
        "pub": str(row.get("publish_date") or ""),
        "secs": int(secs),
        "short": short,
        "tx": str(row.get("transcript_status") or "").startswith("Available"),
        "thumb": thumb,
    }


class _ResultBus(QObject):
    """Worker thread -> GUI thread hop for the results board. Created on the
    GUI thread, so a connection to a VM slot is queued automatically."""
    row = Signal(object)       # (compact_row, full_row)
    info = Signal(object)      # {"title", "id", "videos"}


class DashboardVM(QObject):
    """Scrape orchestration + form state for the QML Dashboard page."""

    # form-echo (QML two-way binds these; kept so a scrape reads a single
    # source of truth and settings persist)
    saveFolderChanged = Signal()
    filenameChanged = Signal()

    # run lifecycle
    runningChanged = Signal()
    statusChanged = Signal()           # (text, colorKey) via properties below
    progressChanged = Signal()
    logLine = Signal(str)              # append one line to the QML log view
    logCleared = Signal()
    labelsChanged = Signal()           # UI language changed
    popup = Signal(str, str, str)      # (title, message, kind)
    donePopup = Signal(str, str, str)  # (title, message, outputPath)
    # Transcript gate: the scrape pauses the transcript phase the moment
    # YouTube starts refusing it, so the user can either skip the rest or
    # switch their VPN node and continue. Properties below notify QML.
    transcriptStateChanged = Signal()
    transcriptIpChecked = Signal(bool)  # worker → GUI: (ip differs from the blocked one)

    # v3.54 — results board, pre-flight and quick picks (Scraper page)
    resultsReset = Signal()
    resultsAppended = Signal("QVariantList")   # batches of _result_row dicts
    resultCountChanged = Signal()
    runInfoChanged = Signal()
    lastExportChanged = Signal()
    recentChanged = Signal()
    quotaChanged = Signal()
    exportFormatChanged = Signal()
    publishedWithinChanged = Signal()
    toast = Signal(str, str)                   # mirrored into the tray
    # same contract as Niche / Archive: Main.qml routes it to Niche Scan
    analyzeRequested = Signal("QVariantList", str, str)

    def __init__(self, parent=None):
        super().__init__(parent)
        cfg = load_app_config()
        self._api_key = cfg.get("api_key", "") or ""
        self._youtube_api_keys = clean_api_keys(
            [self._api_key] + list(cfg.get("youtube_api_keys") or []))
        self._save_folder = cfg.get("save_folder", "") or ""
        self._filename = cfg.get("output_filename", "youtube_data") or "youtube_data"
        self._export_format = cfg.get("export_format", "csv") or "csv"
        self._autosave_freq = int(cfg.get("autosave_freq", 500) or 500)
        # v3.53: new installs start at level 3 (3 transcript workers, paced by
        # the shared caption pacer). Level 1 made a first 50-video run feel
        # stuck; an existing config keeps whatever the user chose.
        self._thread_count = int(cfg.get("thread_count", 3) or 3)
        self._transcripts_enabled = bool(cfg.get("transcripts_enabled", True))

        self._is_running = False
        self._stop_requested = False
        self._progress = 0
        # Stored UNTRANSLATED and run through tr() when read, so a language
        # switch actually re-translates it. (Storing the translated string meant
        # "Ready to scrape" stayed Persian after switching back to English.)
        self._status_key = "Ready to scrape"
        self._status_color = "secondary_container"
        self._scrape_thread = None
        # v3.53: which run a checkpoint belongs to (channel + filter + format),
        # so Stop on channel A can never be "resumed" into channel B.
        self._ckpt_tag = ""
        # IP gate (see startScraping). `_geo` is set by main_qml once the GeoVM
        # exists; without it scrapes start exactly as before.
        self._geo = None
        self._geo_waiting = False

        self._emit = SignalEmitter()
        self._emit.log_signal.connect(self._on_log)
        self._emit.finished_signal.connect(self._on_finished)
        self._emit.progress_signal.connect(self._on_progress)
        self._emit.status_signal.connect(self._on_status)
        self._emit.popup_signal.connect(self.popup)
        self._emit.done_popup_signal.connect(self.donePopup)
        self.transcriptIpChecked.connect(self._on_ip_checked)

        # ── transcript gate (pause on a blocked IP) ───────────────────────
        # Open = fetch transcripts freely. YouTube rate-limits / IP-blocks the
        # transcript endpoint; the old behaviour marked every remaining row
        # "Not Available" and carried on, so the user could not tell "this
        # video simply has no captions" from "YouTube just blocked you" — and
        # had no way to react, even though switching the VPN node fixes the
        # second case instantly. Now the phase pauses once _TR_BLOCK_CONFIRM
        # videos in a row are refused (one is not a verdict).
        self._tr_gate = threading.Event()
        self._tr_gate.set()
        self._tr_paused = False
        self._tr_skip_rest = False
        self._tr_checking = False
        self._tr_blocked_ip = ""       # the public IP YouTube was refusing
        self._tr_lock = threading.Lock()     # counters are bumped from up to 16 workers
        self._tr_found = 0
        self._tr_blocked = 0
        self._tr_none = 0
        self._tr_skipped = 0
        self._tr_block_streak = 0      # consecutive refusals, see _TR_BLOCK_CONFIRM
        self._tr_ip_note_key = ""      # stored untranslated, like _status_key

        # ── v3.54 results board ───────────────────────────────────────────
        # Every kept row is streamed to the page while the run is going, in
        # small batches (one QML update per ~quarter second, not per video).
        self._results = []             # compact rows, run order
        self._full = {}                # video_id -> full export row
        self._pending = []
        self._run_channel = ""
        self._run_channel_id = ""
        self._run_channel_videos = 0
        self._last_export = ""
        self._published_within = 0     # days, 0 = any time (not persisted)
        self._run_days = 0
        self._recent = [u for u in (cfg.get("scrape_recent") or [])
                        if isinstance(u, str) and u.strip()][:_RECENT_MAX]
        self._quota_left = -1
        self.ideas_sink = None         # set by main_qml (IdeasVM.addReferences)
        self._bus = _ResultBus()
        self._bus.row.connect(self._on_result_row)
        self._bus.info.connect(self._on_run_info)
        self._flush_timer = QTimer(self)
        self._flush_timer.setSingleShot(True)
        self._flush_timer.setInterval(240)
        self._flush_timer.timeout.connect(self._flush_results)
        self.donePopup.connect(self._on_done_path)
        self._refresh_quota()

    # ── log panel helpers ──────────────────────────────────────────────
    # The terminal panel keeps its own line list (QML side, so it can colour
    # each line), and calls back here for the two actions that need the app:
    # copying the buffer out and clearing it.
    @Slot(str)
    def copyLog(self, text):
        """Put the whole log buffer on the clipboard."""
        if not text:
            return
        from PySide6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        if cb is not None:
            cb.setText(text)
            self.popup.emit(tr("Live Logs"), tr("Log copied to clipboard."), "success")

    @Slot()
    def clearLog(self):
        """Empty the log view. Purely cosmetic — it does not touch a running
        scrape, which keeps appending from wherever it got to."""
        self.logCleared.emit()

    # ── transcript gate (the pause banner's state) ──────────────────────
    @Property(bool, notify=transcriptStateChanged)
    def transcriptPaused(self):
        return self._tr_paused

    @Property(bool, notify=transcriptStateChanged)
    def transcriptChecking(self):
        return self._tr_checking

    @Property(int, notify=transcriptStateChanged)
    def transcriptFound(self):
        return self._tr_found

    @Property(int, notify=transcriptStateChanged)
    def transcriptBlocked(self):
        return self._tr_blocked

    @Property(int, notify=transcriptStateChanged)
    def transcriptNone(self):
        return self._tr_none

    @Property(str, notify=transcriptStateChanged)
    def transcriptIpNote(self):
        return tr(self._tr_ip_note_key) if self._tr_ip_note_key else ""

    @Slot()
    def transcriptSkipRest(self):
        """"Keep going WITHOUT transcripts" — releases the paused workers and
        short-circuits every later fetch for this run."""
        self._tr_skip_rest = True
        self._tr_paused = False
        self._tr_ip_note_key = ""
        self._reset_block_streak()
        self._tr_gate.set()
        self._emit.log_signal.emit("⏭  " + tr("Skipping transcripts for the rest of this run."))
        self.transcriptStateChanged.emit()

    @Slot()
    def transcriptRetryIp(self):
        """"I changed my VPN node" — verify the public IP really changed before
        resuming. YouTube only unblocks a DIFFERENT IP, so resuming on the same
        one would just burn the whole run against a block."""
        if self._tr_checking or not self._tr_paused:
            return
        self._tr_checking = True
        self._tr_ip_note_key = ""
        self.transcriptStateChanged.emit()
        threading.Thread(target=self._ip_check_worker, daemon=True).start()

    def _ip_check_worker(self):
        ip = ""
        try:
            ip = get_public_ip() or ""
        except Exception:              # noqa: BLE001 — surfaced as "unchanged"
            ip = ""
        same = bool(self._tr_blocked_ip) and ip == self._tr_blocked_ip
        self.transcriptIpChecked.emit(not same)

    @Slot(bool)
    def _on_ip_checked(self, changed):
        self._tr_checking = False
        if changed:
            reset_breaker()        # new IP: give the fast library path another go
            self._tr_paused = False
            self._tr_ip_note_key = ""
            self._reset_block_streak()
            self._tr_gate.set()
            self._emit.log_signal.emit("🌐  " + tr("IP changed — resuming transcripts."))
        else:
            self._tr_ip_note_key = ("Still the same IP — switch the VPN node, "
                                    "then press New IP again.")
            self._emit.log_signal.emit("⚠️  " + tr(self._tr_ip_note_key))
        self.transcriptStateChanged.emit()

    def _pause_transcripts(self, vid):
        """Flip to paused ONCE per block wave, from a worker thread."""
        # Up to 16 workers can hit the block at the same moment: only the
        # first one flips the state and writes the log.
        with self._tr_lock:
            if self._tr_paused:
                return
            self._tr_paused = True
            self._tr_gate.clear()
        self._tr_blocked_ip = get_public_ip() or ""
        self._emit.log_signal.emit("─" * 72)
        self._emit.log_signal.emit(
            "📝  " + tr("Transcripts so far: {found} found · {none} without.").format(
                found=self._tr_found,
                none=self._tr_none + self._tr_blocked + self._tr_skipped))
        self._emit.log_signal.emit(
            "🚫  " + tr("YouTube has stopped answering transcripts for this IP (at {vid}).")
            .format(vid=vid))
        self._emit.log_signal.emit(
            "    " + tr("Switch the VPN node and press New IP, or skip the rest without transcripts."))
        self.transcriptStateChanged.emit()

    def _bump(self, which):
        with self._tr_lock:
            setattr(self, "_tr_" + which, getattr(self, "_tr_" + which) + 1)

    def _reset_block_streak(self):
        with self._tr_lock:
            self._tr_block_streak = 0

    def _transcript_of(self, vid):
        """fetch_transcript + the gate. Runs on scrape worker threads.

        Returns ("Skipped", "N/A", "") for rows the user chose to skip, so the
        export can tell them apart from videos that were actually attempted."""
        if self._tr_skip_rest:
            self._bump("skipped")
            self.transcriptStateChanged.emit()
            return ("Skipped", "N/A", "")
        status, text, err = fetch_transcript(vid)
        if status.startswith("Available"):
            self._reset_block_streak()
            self._bump("found")
            self.transcriptStateChanged.emit()
            return status, text, err
        if err == "blocked" and not self._tr_skip_rest:
            self._bump("blocked")
            with self._tr_lock:
                self._tr_block_streak += 1
                confirmed = self._tr_block_streak >= _TR_BLOCK_CONFIRM
            self.transcriptStateChanged.emit()
            if not confirmed:
                # This video was refused by every path, but the next one may
                # answer: only a run of refusals is an IP-level block.
                return ("Not Available", "N/A", "blocked")
            self._pause_transcripts(vid)
            # Hold this worker (and the rest of the wave) until the user
            # decides. Polled so Stop still works while paused.
            while self._tr_paused and not self._stop_requested:
                if self._tr_gate.wait(0.25):
                    break
            if self._tr_skip_rest:
                self._bump("skipped")
                self.transcriptStateChanged.emit()
                return ("Skipped", "N/A", "")
            if self._stop_requested:
                self.transcriptStateChanged.emit()
                return ("Not Available", "N/A", "blocked")
            # Resumed on a NEW IP: retry this very video, then carry on.
            status, text, err = fetch_transcript(vid)
            if status.startswith("Available"):
                self._reset_block_streak()
                self._bump("found")
                self.transcriptStateChanged.emit()
                return status, text, err
        if err != "blocked":
            # A real answer (captions or "none") proves the endpoint is alive.
            self._reset_block_streak()
        self._bump("none")
        self.transcriptStateChanged.emit()
        return status, text, err

    # ── form properties ────────────────────────────────────────────────
    @Property(str, notify=saveFolderChanged)
    def saveFolder(self):
        return self._save_folder
    @saveFolder.setter
    def saveFolder(self, v):
        if v != self._save_folder:
            self._save_folder = v or ""
            self.saveFolderChanged.emit()

    @Property(str, notify=filenameChanged)
    def filename(self):
        return self._filename

    @filename.setter
    def filename(self, v):
        # Stored verbatim, INCLUDING empty: clearing the box used to snap back to
        # "youtube_data" on every keystroke, so it could never be retyped. The
        # default is applied once at startup and again at scrape time (see
        # startScraping), which is where it actually matters.
        v = v or ""
        if v != self._filename:
            self._filename = v
            self.filenameChanged.emit()

    @Property(str, notify=exportFormatChanged)
    def exportFormat(self):
        return self._export_format

    # ── v3.54: results board / pre-flight properties ─────────────────────
    @Property(int, notify=resultCountChanged)
    def resultCount(self):
        return len(self._results)

    @Slot(result="QVariantList")
    def results(self):
        """Everything streamed so far (the page asks once when it is built)."""
        return list(self._results)

    @Property(str, notify=runInfoChanged)
    def runChannel(self):
        return self._run_channel

    @Property(int, notify=runInfoChanged)
    def runChannelVideos(self):
        return int(self._run_channel_videos or 0)

    @Property(str, notify=lastExportChanged)
    def lastExport(self):
        return self._last_export

    @Property("QStringList", notify=recentChanged)
    def recentSources(self):
        return list(self._recent)

    @Property(int, notify=quotaChanged)
    def quotaLeft(self):
        """Units left today across every configured key; -1 = unknown."""
        return int(self._quota_left)

    @Property(int, notify=quotaChanged)
    def keyCount(self):
        return len(self._youtube_api_keys or ([self._api_key] if self._api_key else []))

    @Property(int, notify=publishedWithinChanged)
    def publishedWithin(self):
        return int(self._published_within)

    @publishedWithin.setter
    def publishedWithin(self, days):
        try:
            days = int(days)
        except (TypeError, ValueError):
            days = 0
        if days not in _PUBLISHED_CHOICES:
            days = 0
        if days != self._published_within:
            self._published_within = days
            self.publishedWithinChanged.emit()

    def _refresh_quota(self):
        keys = self._youtube_api_keys or ([self._api_key] if self._api_key else [])
        try:
            left = int(api_quota_remaining(keys)) if keys else -1
        except Exception:          # noqa: BLE001 — display only
            left = -1
        if left != self._quota_left:
            self._quota_left = left
        self.quotaChanged.emit()

    @Slot()
    def refreshQuota(self):
        """Re-read keys + today's ledger (the page calls it when shown)."""
        self.refreshApiKeys()
        self._refresh_quota()

    @Slot(str)
    def forgetRecent(self, url):
        url = (url or "").strip()
        lst = [u for u in self._recent if u != url]
        if lst != self._recent:
            self._recent = lst
            self._persist_recent()
            self.recentChanged.emit()

    def _remember_source(self, url):
        url = (url or "").strip()
        if not url:
            return
        norm = url.lower().rstrip("/")
        lst = [u for u in self._recent if u.strip().lower().rstrip("/") != norm]
        lst.insert(0, url)
        self._recent = lst[:_RECENT_MAX]
        self._persist_recent()
        self.recentChanged.emit()

    def _persist_recent(self):
        try:
            cfg = load_app_config()
            cfg["scrape_recent"] = list(self._recent)
            save_app_config(cfg)
        except Exception:          # noqa: BLE001 — a convenience list
            pass

    @Slot(str)
    def copyText(self, text):
        """Clipboard for the results board (a title, a link, a list)."""
        if not text:
            return
        from PySide6.QtGui import QGuiApplication
        cb = QGuiApplication.clipboard()
        if cb is not None:
            cb.setText(text)

    # ── worker -> GUI (queued through _ResultBus) ──
    @Slot(object)
    def _on_result_row(self, payload):
        try:
            compact, full = payload
        except (TypeError, ValueError):
            return
        vid = compact.get("vid")
        if vid and vid in self._full:
            return                 # a resumed row seen twice
        if vid:
            self._full[vid] = full
        self._results.append(compact)
        self._pending.append(compact)
        if not self._flush_timer.isActive():
            self._flush_timer.start()

    @Slot()
    def _flush_results(self):
        if not self._pending:
            return
        batch, self._pending = self._pending, []
        self.resultsAppended.emit(batch)
        self.resultCountChanged.emit()

    @Slot(object)
    def _on_run_info(self, info):
        if not isinstance(info, dict):
            return
        self._run_channel = str(info.get("title") or self._run_channel or "")
        self._run_channel_id = str(info.get("id") or self._run_channel_id or "")
        self._run_channel_videos = _as_int(info.get("videos")) or self._run_channel_videos
        self.runInfoChanged.emit()

    def _on_done_path(self, _title, _msg, path):
        self._last_export = path or ""
        self.lastExportChanged.emit()

    def _niche_rows(self, picks):
        """Scraped rows in the shape Niche Scan / AI Ideas read (the Niche
        Finder row). `picks` = [{"vid", "mult"}] or None for every row."""
        if picks is None:
            picks = [{"vid": r.get("vid")} for r in self._results]
        out = []
        for p in picks:
            if not isinstance(p, dict):
                continue
            vid = p.get("vid") or ""
            full = self._full.get(vid)
            if not full:
                continue
            secs = parse_iso8601_duration(full.get("duration", "")) or 0
            try:
                short = bool(detect_short(secs, full.get("title", ""), full.get("description", "")))
            except Exception:      # noqa: BLE001
                short = False
            row = {
                "video_id": vid,
                "title": full.get("title", ""),
                "channel_title": self._run_channel or "",
                "channel_id": self._run_channel_id or "",
                "video_url": full.get("url") or f"https://www.youtube.com/watch?v={vid}",
                "thumbnail_url": _THUMB_URL_HQ.format(vid=vid),
                "view_count": _as_int(full.get("view_count")),
                "like_count": _as_int(full.get("like_count")),
                "comment_count": _as_int(full.get("comment_count")),
                "published_at": full.get("publish_date", ""),
                "duration_s": int(secs),
                "is_short": short,
                "tags": full.get("tags", ""),
                "description": full.get("description", ""),
                "subscriber_count": None,
                "channel_video_count": int(self._run_channel_videos or 0) or None,
            }
            if p.get("mult") is not None:
                try:
                    row["multiplier"] = float(p.get("mult"))
                except (TypeError, ValueError):
                    pass
            tx = full.get("transcript") or ""
            if str(full.get("transcript_status", "")).startswith("Available") and tx and tx != "N/A":
                row["transcript"] = tx
            out.append(row)
        return out

    @Slot("QVariantList")
    def sendToIdeas(self, picks):
        """Tick the chosen results as references on AI Ideas."""
        sink = self.ideas_sink
        rows = self._niche_rows(list(picks or []))
        if sink is None or not rows:
            self.toast.emit(tr("Nothing to send yet."), "error")
            return
        try:
            added, already = sink(rows, tr("Scraper"))
        except Exception:          # noqa: BLE001
            log_crash("scraper -> ideas:\n" + traceback.format_exc())
            self.toast.emit(tr("Could not send to AI Ideas."), "error")
            return
        self.toast.emit(tr("{n} video(s) sent to AI Ideas.").format(n=added or 0)
                        + ((" " + tr("{n} were already there.").format(n=already)) if already else ""),
                        "success")

    @Slot()
    def analyzeResults(self):
        """Hand the whole result set to Niche Scan (free, no quota, no AI)."""
        rows = self._niche_rows(None)
        if not rows:
            self.toast.emit(tr("Nothing to analyze yet."), "error")
            return
        self.analyzeRequested.emit(rows, self._run_channel or "", "channel")

    # Translated, so NOT constant: the UI language can change while running.
    @Property("QStringList", notify=labelsChanged)
    def sortOptions(self):
        return [tr("Most Recent"), tr("Most Popular"), tr("Most Relevant"),
                tr("Oldest first")]

    @Slot()
    def retranslate(self):
        """UI language changed — re-read every translated label. The status line
        is rebuilt too, since it was translated when it was set."""
        self.labelsChanged.emit()
        self.statusChanged.emit()

    # ── run-state properties ───────────────────────────────────────────
    @Property(bool, notify=runningChanged)
    def isRunning(self):
        return self._is_running

    @Property(int, notify=progressChanged)
    def progress(self):
        return self._progress

    @Property(str, notify=statusChanged)
    def statusText(self):
        # Translated on read (not on set) so a live language switch re-renders it.
        return tr(self._status_key)

    @Property(str, notify=statusChanged)
    def statusColorKey(self):
        return self._status_color

    def _set_status(self, text, color_key):
        """`text` is an UNTRANSLATED source string (or an already-formatted
        runtime line like the ETA counter, which tr() passes through unchanged)."""
        self._status_key = text
        self._status_color = color_key
        self.statusChanged.emit()

    # ── GUI-thread slots (queued from worker via SignalEmitter) ─────────
    @Slot(str)
    def _on_log(self, message):
        self.logLine.emit(message)

    @Slot(int)
    def _on_progress(self, value):
        self._progress = value
        self.progressChanged.emit()

    @Slot(str)
    def _on_status(self, text):
        # keep the same "PROCESSING_x" convention the old queue label used,
        # but expose it as a readable status line
        self._set_status(text, "primary")

    @Slot()
    def _on_finished(self):
        self._is_running = False
        self._stop_requested = False
        self._scrape_thread = None
        self._flush_timer.stop()
        self._flush_results()
        self.runningChanged.emit()
        self._set_status("Ready · Configure settings above and press Start.",
                         "secondary_container")
        self._refresh_quota()

    # ── actions from QML ────────────────────────────────────────────────
    @Slot()
    def refreshApiKeys(self):
        """Re-read the YouTube API keys from config (they may have changed on
        Settings). Called at the start of every scrape so a freshly-saved key
        works immediately without restarting the app. Also callable from QML."""
        try:
            cfg = load_app_config()
        except Exception:
            return
        fresh = (cfg.get("api_key", "") or "").strip()
        keys = clean_api_keys([fresh] + list(cfg.get("youtube_api_keys") or []))
        # Worker Threads / transcripts are edited on the Settings page, which
        # has its own VM: re-read them here (start of every scrape) so a new
        # value takes effect on the next run, not after a restart.
        try:
            self._thread_count = max(1, min(8, int(cfg.get("thread_count", self._thread_count) or 1)))
        except (TypeError, ValueError):
            pass
        self._transcripts_enabled = bool(cfg.get("transcripts_enabled", self._transcripts_enabled))
        # v3.54: the export format used to be read once at startup, so a
        # format picked in Settings only applied after a restart.
        fmt = cfg.get("export_format", self._export_format) or "csv"
        if fmt in FORMAT_EXT and fmt != self._export_format:
            self._export_format = fmt
            self.exportFormatChanged.emit()
        if fresh != (self._api_key or ""):
            self._api_key = fresh
        if keys != (self._youtube_api_keys or []):
            self._youtube_api_keys = keys

    @Slot(str, str, int, int, int)
    def startScraping(self, channel_url, query, max_videos, sort_index, format_index=0):
        """Validate + kick off a scrape on a worker thread. Mirrors
        app.ui.window.scrape_mixin.start_scraping's validation, minus the
        widget wiring.

        format_index: 0 = all formats, 1 = long-form only, 2 = shorts only. When
        a format is chosen, max_videos caps the number of MATCHING videos, so the
        scraper over-fetches and filters until it has that many (or the channel
        runs dry).
        """
        if self._is_running:
            self.popup.emit(tr("Warning"), tr("Scraping is already running!"), "warning")
            return
        if self._geo_waiting:
            # Already waiting on the IP check / the "your IP is in Iran" dialog.
            return

        channel_url = (channel_url or "").strip()
        query = (query or "").strip()
        sort_order = SORT_MAP.get(int(sort_index), "date")
        self._filename = re.sub(r'[\\/*?:"<>|]', "_", (self._filename or "").strip() or "youtube_data")
        self._save_settings()
        # The keys are cached at construction; Settings saves to config.json
        # while the app runs, so re-read them here — otherwise the first scrape
        # after saving a key still sees the old (empty) value until a restart.
        self.refreshApiKeys()

        api_key = (self._api_key or "").strip()
        if not api_key:
            self.popup.emit(tr("Missing Field"),
                            tr("Please enter your YouTube API Key in Settings."), "error")
            return
        configured_keys = self._youtube_api_keys or ([api_key] if api_key else [])
        try:
            if configured_keys and api_quota_remaining(configured_keys) <= 0:
                self.popup.emit(
                    tr("No quota left"),
                    tr("Every configured YouTube API key has already used up its daily "
                       "quota.\n\nAdd a new key in Settings, or wait — quota resets at "
                       "{t} your time.").format(t=quota_reset_local_str()), "warning")
                return
        except Exception:
            pass
        if not channel_url:
            self.popup.emit(tr("Missing Field"), tr("Please enter a YouTube Channel URL."), "error")
            return
        if int(max_videos) < 1:
            self.popup.emit(tr("Missing Field"),
                            tr("Set how many videos to scrape (at least 1)."), "error")
            return
        if not self._save_folder:
            self.popup.emit(tr("Missing Field"), tr("Please select a Save Folder."), "error")
            return
        if not os.path.isdir(self._save_folder):
            self.popup.emit(tr("Invalid Folder"),
                            tr("The selected save folder does not exist anymore.\n"
                               "Please choose another folder."), "error")
            return

        resume_rows = []
        # v3.53: a checkpoint is only resumed by the SAME run (same channel,
        # same filter, same format). It used to be keyed on file name + order
        # alone, so with the default file name a stopped scrape of one channel
        # was silently merged into the next channel's export.
        self._run_days = int(self._published_within or 0)
        self._ckpt_tag = self._run_tag(channel_url, query, format_index, self._run_days)
        ckpt = self._checkpoint_path(sort_order)
        if os.path.exists(ckpt):
            previous = read_checkpoint_rows(ckpt)
            if previous:
                resume_rows = previous  # QML slice: resume silently rather than a modal Yes/No

        args = (api_key, channel_url, query, int(max_videos), sort_order,
                resume_rows, int(format_index))
        geo_vm = getattr(self, "_geo", None)
        if geo_vm is None:
            self._begin_scrape(*args)
            return
        # IP gate: from an Iranian IP (or any country where YouTube is
        # filtered) the YouTube API refuses every request, so the scrape would
        # run, fail on the first call and save nothing. Check the route first;
        # GeoVM runs `proceed` straight away when the connection is clean.
        self._geo_waiting = True
        self._set_status("Checking your connection …", "primary")

        def proceed():
            self._geo_waiting = False
            self._begin_scrape(*args)

        def cancelled():
            self._geo_waiting = False
            self._set_status("Ready to scrape", "secondary_container")

        geo_vm.gate("scrape", proceed, on_cancel=cancelled)

    def geoBlocked(self):
        """GeoVM parked the scrape: say so where the user is looking."""
        if self._geo_waiting:
            self._set_status("Paused · this IP can't reach YouTube", "warn")

    def _begin_scrape(self, api_key, channel_url, query, max_videos, sort_order,
                      resume_rows, format_index):
        """The part of startScraping that actually starts the run — split out
        so the IP gate can call it later, after the user decided."""
        if self._is_running:
            return
        self._api_key = api_key
        self._stop_requested = False
        self._is_running = True
        self.runningChanged.emit()
        self.logCleared.emit()
        self._on_progress(0)
        self._set_status("Scraping in progress …", "primary")
        # Fresh transcript gate every run (a previous run may have ended paused
        # or in skip mode; a new scrape starts optimistic).
        self._tr_gate.set()
        self._tr_paused = False
        self._tr_skip_rest = False
        self._tr_checking = False
        self._tr_blocked_ip = ""
        self._tr_found = self._tr_blocked = self._tr_none = self._tr_skipped = 0
        self._tr_block_streak = 0
        self._tr_ip_note_key = ""
        self.transcriptStateChanged.emit()
        # fresh results board
        self._flush_timer.stop()
        self._results, self._full, self._pending = [], {}, []
        self._run_channel = self._run_channel_id = ""
        self._run_channel_videos = 0
        self._last_export = ""
        self.resultsReset.emit()
        self.resultCountChanged.emit()
        self.runInfoChanged.emit()
        self.lastExportChanged.emit()
        self._remember_source(channel_url)

        self._scrape_thread = threading.Thread(
            target=self._scrape_entry,
            args=(channel_url, query, int(max_videos), sort_order, resume_rows,
                  int(format_index)),
            daemon=True)
        self._scrape_thread.start()

    @Slot()
    def stopScraping(self):
        if self._is_running:
            self._stop_requested = True
            self._emit.log_signal.emit("\n⚠️  " + tr("Stop requested — canceling operation …"))

    @Slot(str)
    def setSaveFolder(self, path):
        # path may arrive as a (percent-encoded) file:// URL from QtQuick.Dialogs
        path = local_path_from_url(path)
        self.saveFolder = path
        self._save_settings()

    # ── open / reveal an export file (from the "Done" popup) ─────────────
    @Slot(str)
    def openFile(self, path):
        """Open the export in its default app."""
        self._reveal(path)

    @Slot(str)
    def openFolder(self, path):
        """Open the folder the export was saved into."""
        target = os.path.dirname(path) if path else self._save_folder
        self._reveal(target)

    def _reveal(self, target):
        import subprocess
        import sys
        if not target:
            return
        try:
            if sys.platform.startswith("win"):
                os.startfile(target)  # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", target])
            else:
                subprocess.Popen(["xdg-open", target])
        except Exception as e:
            self.popup.emit(tr("Could not open"), str(e), "error")

    # ── worker ───────────────────────────────────────────────────────────
    def _stop_check(self):
        return self._stop_requested

    @staticmethod
    def _run_tag(channel_url, query, format_index, days=0):
        src = (channel_url or "").strip().lower().rstrip("/")
        src = re.sub(r"^https?://(www\.|m\.)?", "", src)
        key = f"{src}|{(query or '').strip().lower()}|{int(format_index)}"
        if days:
            # only when set, so v3.53 checkpoints keep their tag
            key += f"|d{int(days)}"
        return hashlib.sha1(key.encode("utf-8")).hexdigest()[:8]

    def _checkpoint_path(self, sort_order):
        suffix = SORT_SUFFIX[sort_order]
        tag = f"_{self._ckpt_tag}" if self._ckpt_tag else ""
        return os.path.join(self._save_folder,
                            f"{self._filename}_{suffix}{tag}_checkpoint.jsonl")

    def _export_path(self, sort_order):
        """`<name>_<order>.<ext>`; if that file already exists (an earlier
        run), add the date and time instead of silently overwriting it."""
        suffix = SORT_SUFFIX[sort_order]
        ext = FORMAT_EXT[self._export_format]
        base = os.path.join(self._save_folder, f"{self._filename}_{suffix}")
        path = f"{base}.{ext}"
        if os.path.exists(path):
            stamp = time.strftime("%Y%m%d-%H%M%S")
            path = f"{base}_{stamp}.{ext}"
            n = 2
            while os.path.exists(path):
                path = f"{base}_{stamp}-{n}.{ext}"
                n += 1
        return path

    def _partial_path(self, sort_order):
        """Where a stopped run's usable snapshot goes: the user's CHOSEN
        format, not the JSONL resume checkpoint. The tag keeps two different
        channels on the same file name from overwriting each other."""
        suffix = SORT_SUFFIX[sort_order]
        ext = FORMAT_EXT[self._export_format]
        tag = f"_{self._ckpt_tag}" if self._ckpt_tag else ""
        return os.path.join(self._save_folder,
                            f"{self._filename}_{suffix}{tag}_partial.{ext}")

    def _scrape_entry(self, *args):
        try:
            self._scrape_videos(*args)
        except Exception:
            log_crash("qml scrape worker crashed:\n" + traceback.format_exc())
            try:
                self._emit.log_signal.emit(
                    "❌  " + tr("Worker crashed — details were written to the crash log."))
            finally:
                self._emit.finished_signal.emit()

    # The id fetchers (uploads / search / oldest-first) moved to
    # app.core.scrape_pipeline in v3.52: they are generators now, streamed
    # into the metadata pipeline instead of being collected up front.

    def _matches_format(self, row, format_index):
        """format_index: 0 all · 1 long-form · 2 shorts. Reuses the same
        duration parse + short detection the Niche Finder uses."""
        if format_index == 0:
            return True
        secs = parse_iso8601_duration(row.get("duration", ""))
        is_short = detect_short(secs, row.get("title", ""), row.get("description", ""))
        return is_short if format_index == 2 else (not is_short)

    def _scrape_videos(self, channel_url, query, max_videos, sort_order,
                       resume_rows=None, format_index=0):
        emit = self._emit
        data, processed, total = [], 0, 0
        # When a format is selected, max_videos caps the number of MATCHING
        # videos, so over-fetch ids and filter until we have that many (or run
        # out). Bounded so a channel with none of the requested format can't page
        # forever.
        match_target = int(max_videos)
        fetch_count = int(max_videos)
        # v3.54 "Published" window: only videos newer than `cutoff` are kept.
        # It counts against the maximum exactly like the format filter does.
        days = int(getattr(self, "_run_days", 0) or 0)
        cutoff = ""
        if days > 0:
            cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime(
                "%Y-%m-%dT%H:%M:%SZ")
        filtering = format_index != 0 or bool(cutoff)
        use_search = not (sort_order == "oldest" or (sort_order == "date" and not query))
        if format_index != 0:
            fetch_count = min(int(max_videos) * 6, int(max_videos) + 500)
        elif cutoff and not use_search:
            # the uploads playlist is newest-first, and the run stops the moment
            # a whole page is older than the window, so this bound is cheap
            fetch_count = min(int(max_videos) * 20, int(max_videos) + 5000)
        # Declared out here so the except/finally blocks can salvage finished
        # transcripts and shut the pool down on Stop, quota or error.
        tx_pool = None
        tx_queue = deque()
        meta = None
        try:
            emit.log_signal.emit("═" * 72)
            strategy_label = {"date": tr("Newest"), "viewCount": tr("Most Viewed"),
                              "relevance": tr("Most Relevant"),
                              "oldest": tr("Oldest first")}[sort_order]
            emit.log_signal.emit("  🚀  " + tr("Scraper Started  |  Strategy: {s}").format(s=strategy_label))
            emit.log_signal.emit("═" * 72)
            if self._stop_requested:
                raise ScrapeCancelled()

            keys = list(self._youtube_api_keys or [])
            if self._api_key and self._api_key not in keys:
                keys.insert(0, self._api_key)

            def _rotated(number, count):
                emit.log_signal.emit(
                    "⚠️  " + tr("API key {a} is out of quota — switched to key "
                                "{b} of {n}.").format(a=number - 1, b=number, n=count))

            def _offline(lost):
                if lost:
                    emit.log_signal.emit(
                        "⚠️  " + tr("Connection lost — waiting for the internet "
                                    "(up to 5 min). The scrape resumes on its own."))
                    emit.status_signal.emit(tr("Waiting for the internet …"))
                else:
                    emit.log_signal.emit("✅  " + tr("Connection is back — resuming."))

            ring = KeyRing(keys, remaining=key_quota_remaining,
                           on_rotate=_rotated, on_offline=_offline)
            if ring.key_count > 1:
                emit.log_signal.emit(
                    "   " + tr("{n} API keys ready — a key that runs out of quota "
                               "hands over to the next one.").format(n=ring.key_count))
            emit.log_signal.emit("\n📡  " + tr("Resolving channel: {u}").format(u=channel_url))
            channel_id = ring.run(
                lambda yt: resolve_channel_id(yt, channel_url, stop_check=self._stop_check),
                self._stop_check)
            if not channel_id:
                emit.log_signal.emit("❌  " + tr("Could not resolve Channel ID."))
                emit.popup_signal.emit(tr("Error"),
                                       tr("Could not resolve the channel from that URL."), "error")
                return
            emit.log_signal.emit("✅  " + tr("Channel ID: {id}").format(id=channel_id))
            self._bus.info.emit({"title": "", "id": channel_id, "videos": 0})
            if cutoff:
                emit.log_signal.emit("\n📅  " + tr("Only videos published in the last {d} days.").format(d=days))
            if format_index != 0:
                fmt_label = tr("Shorts") if format_index == 2 else tr("Long-form")
                emit.log_signal.emit("\n🎯  " + tr("Filtering for {fmt}: scanning up to {scan} videos to find {want}.").format(
                    fmt=fmt_label, scan=fetch_count, want=match_target))
            emit.log_signal.emit("\n📥  " + tr("Fetching up to {n} video IDs  (order: {o}) …").format(
                n=fetch_count, o=sort_order))

            # Ids are STREAMED into the metadata pipeline (see
            # app.core.scrape_pipeline): the first rows appear while the id
            # list is still loading, and a format filter stops paying for id
            # pages as soon as it has enough matches.
            stop = self._stop_check
            channel_videos = 0
            if use_search:
                emit.log_signal.emit("   " + tr("Using search API (costs more quota: 100 units per 50 videos)."))
                if fetch_count > 500:
                    # search.list stops paging at roughly 500 results per query
                    emit.log_signal.emit(
                        "ℹ️  " + tr("YouTube search returns at most ~500 videos per query, "
                                    "so this run may stop before {n}. For a full channel, "
                                    "use Most Recent or Oldest first.").format(n=fetch_count))
                # the window is applied by YouTube itself here (publishedAfter),
                # so no search page is spent on videos that would be dropped
                pages = iter_search_pages(ring, channel_id, fetch_count, sort_order,
                                          query or None, stop,
                                          published_after=cutoff or None)
            else:
                uploads, channel_videos = channel_info(ring, channel_id, stop)
                if channel_videos:
                    self._bus.info.emit({"title": "", "id": channel_id,
                                         "videos": channel_videos})
                if not uploads:
                    pages = iter(())
                elif sort_order == "oldest":
                    # No API order exists for this — walk the uploads playlist to
                    # the channel's start and reverse it. Only meaningful for a
                    # channel, so a query is ignored here (the UI hides it).
                    emit.log_signal.emit(
                        "   " + tr("Walking the uploads playlist backwards to find the "
                                   "channel's first videos (1 quota unit per 50)."))

                    def _walk_log(what, n):
                        if what == "walk":
                            emit.log_signal.emit(
                                "   " + tr("Walking to the channel's start … {n} videos seen.").format(n=n))
                        else:
                            emit.log_signal.emit(
                                "⚠️  " + tr("Channel is very large — stopped after {n} videos, so "
                                            "'oldest' is the oldest of those.").format(n=n))
                    pages = iter_oldest_pages(ring, uploads, fetch_count, stop, log=_walk_log)
                else:
                    emit.log_signal.emit("   " + tr("Using uploads playlist (quota-friendly mode)."))
                    pages = iter_upload_pages(ring, uploads, fetch_count, stop)

            done_ids = set()
            if resume_rows:
                data = list(resume_rows)
                done_ids = {r.get("video_id") for r in resume_rows}
                for _r in resume_rows:
                    if isinstance(_r, dict) and _r.get("video_id"):
                        self._bus.row.emit((_result_row(_r), _r))
            feed = ChunkFeed(pages, skip=done_ids)
            # search + format filter: every extra id page costs 100 units, so
            # nothing is fetched ahead there.
            lazy = use_search and format_index != 0
            meta = MetadataAhead(ring, feed, stop, depth=1 if lazy else 3,
                                 prefetch=not lazy)
            first = meta.next()
            if first is None and not data:
                meta.close()
                emit.log_signal.emit("❌  " + tr("No videos found."))
                emit.popup_signal.emit(tr("No Results"),
                                       tr("No videos were found for this channel/query."), "warning")
                return

            # The full id count is only known once the stream ends; until then
            # the channel's own video count (or the requested maximum) stands in.
            def _estimate():
                if feed.exhausted:
                    return max(feed.seen, 1)
                if channel_videos:
                    return max(1, min(fetch_count, channel_videos))
                return max(1, fetch_count)
            total = _estimate()
            emit.log_signal.emit("✅  " + tr("Streaming up to {n} videos — metadata downloads "
                                            "in parallel while the list loads.").format(n=total) + "\n")

            # Progress is measured against the matched target when a format
            # filter is active (we may scan many more than we keep), else against
            # every queued id.
            progress_total = match_target if filtering else total
            processed = len(done_ids)
            if processed:
                emit.log_signal.emit("⏩  " + tr("Resuming: {done} videos restored from checkpoint.").format(
                    done=processed))
            emit.log_signal.emit("─" * 72)

            failed = 0
            matched = len(data)   # rows kept so far (resume rows count)
            skipped_format = 0    # scanned but wrong format
            transcripts_on = bool(self._transcripts_enabled)
            if not transcripts_on:
                emit.log_signal.emit("ℹ️  " + tr("Transcript fetching is disabled in Settings — metadata only."))
            t0 = time.monotonic()
            baseline_done = matched
            last_autosave = len(data)

            # ── transcript pipeline (Worker Threads → turbo) ──
            # One pool for the whole scrape, fed continuously: the old code ran
            # transcripts in waves of ≤4 and every wave waited for its slowest
            # video, then the next 50-id metadata page waited for the last wave.
            # Up to 10 transcripts run at once (see transcripts._TURBO), a slow
            # one only holds itself, and the next metadata page is fetched while
            # the previous page's transcripts are still downloading. Results are
            # still emitted strictly in queue order, so the export order is
            # unchanged.
            tx_prof = set_turbo(self._thread_count)
            reset_breaker()
            tx_workers = tx_prof["workers"] if transcripts_on else 0
            tx_pool = (ThreadPoolExecutor(max_workers=tx_workers, thread_name_prefix="tx")
                       if tx_workers > 1 else None)
            tx_queue.clear()                    # (vid, row, future), submit order
            tx_window = max(8, tx_workers * 3)  # in-flight cap (memory + fairness)
            if transcripts_on:
                emit.log_signal.emit(
                    ("⚡  " if tx_prof["turbo"] else "📝  ")
                    + tr("Transcripts: {n} in parallel{t}").format(
                        n=max(1, tx_workers),
                        t=("  ·  TURBO" if tx_prof["turbo"] else "")))
                set_throttle_listener(
                    lambda gap: emit.log_signal.emit(
                        "⏳  " + tr("YouTube is limiting caption downloads — pacing "
                                   "to about one every {s:.1f}s, then continuing.").format(s=gap)))
                emit.log_signal.emit(
                    "⏳  " + tr("YouTube rate-limits caption downloads per IP — "
                               "live captions are paced, so a large uncached "
                               "channel still takes a while (cached ones finish instantly)."))

            def _enough():
                # in-flight transcripts already count as matched videos
                return filtering and matched + len(tx_queue) >= match_target

            def _drain(keep=0):
                """Emit finished transcripts from the head of the queue, in
                order. Blocks (Stop-aware) until at most `keep` are left;
                keep=None only takes what is already done."""
                while tx_queue:
                    vid, row, fut = tx_queue[0]
                    if not fut.done():
                        if keep is None or len(tx_queue) <= keep:
                            return
                        try:
                            fut.result(timeout=0.25)
                        except FutTimeout:
                            if self._stop_requested:
                                raise ScrapeCancelled()
                            continue
                        except Exception:
                            pass
                    tx_queue.popleft()
                    try:
                        status, text, _err = fut.result()
                    except Exception:
                        status, text = "Not Available", "N/A"
                    row["transcript_status"] = status
                    row["transcript"] = text
                    _emit_video_result(vid, row)

            status_gate = Throttle(0.25)   # status line: ≤ 4 updates / s
            last_pct = [-1]

            def _emit_video_result(vid, row):
                nonlocal processed, failed, matched
                processed += 1
                shown_now = (matched + (1 if row is not None else 0)
                             if filtering else processed)
                denom = max(progress_total, shown_now, 1)
                shown = matched if filtering else processed
                pct = min(100, int((shown / denom) * 100))
                prefix = f"[{shown:4d}/{denom}] ({pct:3d}%)  {vid}"
                if row is not None:
                    data.append(row)
                    matched += 1
                    try:
                        self._bus.row.emit((_result_row(row), row))
                    except Exception:      # noqa: BLE001 — board is cosmetic
                        pass
                    ts = row.get("transcript_status", "")
                    if not transcripts_on:
                        status_tag = tr("✅ Metadata Saved")
                    elif ts.startswith("Available"):
                        status_tag = tr("✅ Transcript Found")
                    else:
                        status_tag = tr("⚠️ No Transcript (Video Saved)")
                    emit.log_signal.emit(f"   📹 {prefix}  {status_tag}")
                else:
                    failed += 1
                    emit.log_signal.emit(f"   📹 {prefix}  ❌ " + tr("Unavailable (private/deleted)"))
                # The bar and the status line used to be re-sent for EVERY
                # video (thousands of queued GUI updates on a metadata-only
                # run). Now: the bar only when the percentage moves, the
                # status line a few times a second.
                if pct != last_pct[0]:
                    last_pct[0] = pct
                    emit.progress_signal.emit(pct)
                if not status_gate.ready(force=shown >= denom):
                    return
                elapsed = max(time.monotonic() - t0, 0.001)
                done_this_run = matched - baseline_done
                if done_this_run > 0:
                    rate = done_this_run / elapsed
                    remain = max(denom - shown, 0) / max(rate, 1e-6)
                    eta_txt = f"{int(remain // 60):02d}:{int(remain % 60):02d}"
                    emit.status_signal.emit(f"{shown}/{denom} · {rate * 60:.0f}/min · ETA {eta_txt}")

            channel_named = [False]
            aged_out = False

            def _keep(row):
                if format_index != 0 and not self._matches_format(row, format_index):
                    return False
                if cutoff and str(row.get("publish_date") or "") < cutoff:
                    return False
                return True

            nxt = first
            while True:
                if self._stop_requested:
                    raise ScrapeCancelled()
                if _enough():
                    break
                if nxt is None:
                    nxt = meta.next()
                    if nxt is None:
                        break
                chunk, items = nxt
                nxt = None
                if not filtering:
                    total = progress_total = _estimate()
                if not channel_named[0]:
                    for _vid in chunk:
                        _t = (((items.get(_vid) or {}).get("snippet") or {})
                              .get("channelTitle"))
                        if _t:
                            channel_named[0] = True
                            self._bus.info.emit({"title": _t, "id": channel_id,
                                                 "videos": channel_videos})
                            break
                rows_by_id = {vid: _row_from_item(vid, items[vid]) for vid in chunk if vid in items}
                # Newest-first uploads + a date window: a page where EVERY video
                # is older than the window means the rest of the channel is too.
                if (cutoff and sort_order == "date" and not use_search and rows_by_id
                        and all(str(r.get("publish_date") or "") < cutoff
                                for r in rows_by_id.values())):
                    aged_out = True
                # Drop rows that don't match the requested format / window —
                # they never reach _emit_video_result, so they don't count
                # toward progress.
                if filtering:
                    kept = {}
                    for vid, row in rows_by_id.items():
                        if _keep(row):
                            kept[vid] = row
                        else:
                            skipped_format += 1
                    rows_by_id = kept
                available_vids = [v for v in chunk if v in rows_by_id]
                # Only report genuinely-unavailable ids as failures; format
                # mismatches are silently skipped.
                missing_vids = ([v for v in chunk if v not in items] if filtering
                                else [v for v in chunk if v not in rows_by_id])
                # Don't overshoot the matched target: keep only as many matching
                # videos as we still need.
                if filtering:
                    room = max(0, match_target - matched - len(tx_queue))
                    available_vids = available_vids[:room]
                    rows_by_id = {v: rows_by_id[v] for v in available_vids}
                    missing_vids = []

                if transcripts_on and available_vids and not self._stop_requested:
                    if tx_pool is None:
                        for vid in available_vids:
                            if self._stop_requested:
                                break
                            row = rows_by_id[vid]
                            status, text, _err = self._transcript_of(vid)
                            row["transcript_status"] = status
                            row["transcript"] = text
                            _emit_video_result(vid, row)
                    else:
                        for vid in available_vids:
                            if self._stop_requested:
                                raise ScrapeCancelled()
                            tx_queue.append((vid, rows_by_id[vid],
                                             tx_pool.submit(self._transcript_of, vid)))
                            _drain(keep=None)
                            if len(tx_queue) >= tx_window:
                                _drain(keep=tx_window - tx_workers)
                        _drain(keep=None)
                else:
                    if tx_queue:
                        _drain(keep=0)      # keep the export order
                    for vid in available_vids:
                        if self._stop_requested:
                            break
                        _emit_video_result(vid, rows_by_id[vid])

                if missing_vids and tx_queue:
                    _drain(keep=0)          # keep log/progress order
                for vid in missing_vids:
                    _emit_video_result(vid, None)

                if (self._autosave_freq and data
                        and len(data) - last_autosave >= self._autosave_freq):
                    self._save_checkpoint(data, sort_order)
                    last_autosave = len(data)

                if aged_out:
                    emit.log_signal.emit(
                        "📅  " + tr("Reached videos older than {d} days — the rest of "
                                   "the channel is outside the window.").format(d=days))
                    break

            _drain(keep=0)
            meta.close()
            if tx_pool is not None:
                tx_pool.shutdown(wait=False)
                tx_pool = None
            if not filtering:
                total = progress_total = _estimate()
            emit.progress_signal.emit(100)
            emit.log_signal.emit("─" * 72)
            transcript_count = sum(1 for d in data
                                 if d.get("transcript_status", "").startswith("Available"))
            emit.log_signal.emit("  " + tr("✅ Success: {ok}   ❌ Failed: {fail}   📝 Transcripts: {tc}/{total}").format(
                ok=len(data), fail=failed, tc=transcript_count, total=max(len(data), 1)))
            if self._tr_skipped:
                emit.log_signal.emit("  ⏭  " + tr("Transcripts skipped: {n}").format(n=self._tr_skipped))
            if transcripts_on:
                tr_stats = transcript_stats()
                if tr_stats["cache"] or tr_stats["live"]:
                    emit.log_signal.emit(
                        "  ⚡  " + tr("Transcripts this run: {c} from cache · "
                                    "{l} fetched live.").format(
                            c=tr_stats["cache"], l=tr_stats["live"]))
                if tr_stats.get("throttled"):
                    emit.log_signal.emit(
                        "  ⏳  " + tr("YouTube rate-limited {n} caption requests; "
                                    "the scraper slowed down and retried them.").format(
                            n=tr_stats["throttled"]))

            if data:
                suffix = SORT_SUFFIX[sort_order]
                out_path = self._export_path(sort_order)
                emit.log_signal.emit("\n💾  " + tr("Saving ({fmt}) → {path} …").format(
                    fmt=self._export_format.upper(), path=out_path))
                write_export(data, out_path, self._export_format)
                kb = os.path.getsize(out_path) / 1024
                emit.log_signal.emit("✅  " + tr("Saved  |  {kb} KB  |  {n} rows").format(kb=f"{kb:.1f}", n=len(data)))
                try:
                    ck = self._checkpoint_path(sort_order)
                    if os.path.exists(ck):
                        os.remove(ck)
                    # a full export supersedes the snapshot an earlier stop left
                    pt = self._partial_path(sort_order)
                    if os.path.exists(pt):
                        os.remove(pt)
                except Exception:
                    pass
                emit.log_signal.emit("\n" + "═" * 72)
                emit.log_signal.emit("  🎉  " + tr("Scraping completed successfully!"))
                emit.log_signal.emit("═" * 72)
                emit.done_popup_signal.emit(
                    tr("Done!"),
                    tr("Scraped {n} videos ({suffix})  ·  Transcripts: {tc}/{n}").format(
                        n=len(data), suffix=suffix, tc=transcript_count),
                    out_path)
            else:
                emit.log_signal.emit("❌  " + tr("No data to save."))
                emit.popup_signal.emit(tr("Error"), tr("No data was extracted."), "error")

        except ScrapeCancelled:
            emit.log_signal.emit("\n⚠️  " + tr("Stopped at video {i}/{n}").format(i=processed, n=total or "?"))
            # finished-but-not-yet-emitted transcripts still belong in the save
            while tx_queue and tx_queue[0][2].done():
                _v, _row, _f = tx_queue.popleft()
                try:
                    _st, _tx, _e = _f.result()
                except Exception:
                    _st, _tx = "Not Available", "N/A"
                _row["transcript_status"], _row["transcript"] = _st, _tx
                data.append(_row)
            if data:
                self._save_checkpoint(data, sort_order)
                partial = self._save_partial(data, sort_order)
                if partial:
                    emit.done_popup_signal.emit(
                        tr("Stopped — results saved"),
                        tr("{n} videos were scraped before you stopped. They are saved in "
                           "your chosen format ({fmt}).\n\nThe checkpoint was kept as well, "
                           "so starting the same scrape again resumes from here.").format(
                               n=len(data), fmt=self._export_format.upper()),
                        partial)
        except QuotaExceededError:
            emit.log_signal.emit("\n❌  " + tr("YouTube API daily quota exhausted."))
            # finished-but-not-yet-emitted transcripts still belong in the save
            while tx_queue and tx_queue[0][2].done():
                _v, _row, _f = tx_queue.popleft()
                try:
                    _st, _tx, _e = _f.result()
                except Exception:
                    _st, _tx = "Not Available", "N/A"
                _row["transcript_status"], _row["transcript"] = _st, _tx
                data.append(_row)
            if data:
                self._save_checkpoint(data, sort_order)
                self._save_partial(data, sort_order)
            emit.popup_signal.emit(tr("Quota exhausted"),
                                   tr("Every configured YouTube API key has used up its daily quota.\n\n"
                                      "Everything scraped so far ({n} videos) was saved.").format(n=len(data)),
                                   "warning")
        except Exception as exc:
            log_crash("qml scrape_videos error:\n" + traceback.format_exc())
            emit.log_signal.emit("\n❌  " + tr("Unexpected error: {e}").format(e=exc))
            if data:
                self._save_checkpoint(data, sort_order)
                self._save_partial(data, sort_order)
            emit.popup_signal.emit(tr("Error"),
                                   tr("An error occurred:\n{e}\n\nScraped data was saved — you can "
                                      "resume this scrape later.").format(e=exc), "error")
        finally:
            set_throttle_listener(None)
            # Leave the shared pacer at its safe start, not on a cool-down left
            # over from this run: the AI Chat fetches transcripts through the
            # same gate between scrapes.
            reset_breaker()
            if meta is not None:
                meta.close()
            if tx_pool is not None:
                tx_pool.shutdown(wait=False, cancel_futures=True)
            emit.finished_signal.emit()

    def _save_checkpoint(self, data, sort_order):
        try:
            path = self._checkpoint_path(sort_order)
            write_export(data, path, "json")
            self._emit.log_signal.emit("   💾  " + tr("Checkpoint saved ({n} rows) → {name}").format(
                n=len(data), name=os.path.basename(path)))
            return path
        except Exception as exc:
            self._emit.log_signal.emit("   ⚠️  " + tr("Checkpoint save failed: {e}").format(e=exc))
            return ""

    def _save_partial(self, data, sort_order):
        """A stopped or failed run's data in the USER'S chosen format.

        The JSONL checkpoint exists to resume the run; this file exists so the
        50 videos already scraped can be opened in Excel / Sheets / SQLite
        right away, without waiting for the remaining 50. When the chosen
        format already IS JSONL the checkpoint is that file.
        """
        if not data:
            return ""
        if self._export_format in ("json", "jsonl"):
            return self._checkpoint_path(sort_order)
        try:
            path = self._partial_path(sort_order)
            write_export(data, path, self._export_format)
            self._emit.log_signal.emit(
                "   💾  " + tr("Partial export saved ({fmt}, {n} rows) → {name}").format(
                    fmt=self._export_format.upper(), n=len(data),
                    name=os.path.basename(path)))
            return path
        except Exception as exc:
            self._emit.log_signal.emit(
                "   ⚠️  " + tr("Partial export failed: {e}").format(e=exc))
            return ""

    def _save_settings(self):
        cfg = load_app_config()
        cfg["save_folder"] = self._save_folder
        cfg["output_filename"] = self._filename
        save_app_config(cfg)
