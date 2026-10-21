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

import os
import re
import threading
import time
import traceback
from collections import deque
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutTimeout

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.config import load_app_config, save_app_config
from app.constants import FORMAT_EXT, SORT_MAP, SORT_SUFFIX
from app.core.exports import read_checkpoint_rows, write_export
from app.core.niche.helpers import detect_short
from app.core.quota import api_quota_remaining, quota_reset_local_str
from app.core.signals import SignalEmitter
from app.core.transcripts import (fetch_transcript, get_public_ip, reset_breaker,
                                  set_turbo)
from app.core.utils import local_path_from_url, parse_iso8601_duration
from app.core.youtube_api import (
    QuotaExceededError, ScrapeCancelled, _row_from_item, build_youtube_service,
    execute_with_retry, resolve_channel_id)
from app.crash import log_crash
from app.i18n import tr


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

    def __init__(self, parent=None):
        super().__init__(parent)
        cfg = load_app_config()
        self._api_key = cfg.get("api_key", "") or ""
        self._youtube_api_keys = [k for k in (cfg.get("youtube_api_keys") or []) if k] \
            or ([self._api_key] if self._api_key else [])
        self._save_folder = cfg.get("save_folder", "") or ""
        self._filename = cfg.get("output_filename", "youtube_data") or "youtube_data"
        self._export_format = cfg.get("export_format", "csv") or "csv"
        self._autosave_freq = int(cfg.get("autosave_freq", 500) or 500)
        self._thread_count = int(cfg.get("thread_count", 1) or 1)
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
        # second case instantly. Now the phase PAUSES on the first block.
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
        self._tr_ip_note_key = ""      # stored untranslated, like _status_key

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
            self._bump("found")
            self.transcriptStateChanged.emit()
            return status, text, err
        if err == "blocked" and not self._tr_skip_rest:
            self._bump("blocked")
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
                self._bump("found")
                self.transcriptStateChanged.emit()
                return status, text, err
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

    @Property(str, constant=True)
    def exportFormat(self):
        return self._export_format

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
        self.runningChanged.emit()
        self._set_status("Ready · Configure settings above and press Start.",
                         "secondary_container")

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
        keys = [k for k in (cfg.get("youtube_api_keys") or []) if k] \
            or ([fresh] if fresh else [])
        # Worker Threads / transcripts are edited on the Settings page, which
        # has its own VM: re-read them here (start of every scrape) so a new
        # value takes effect on the next run, not after a restart.
        try:
            self._thread_count = max(1, min(8, int(cfg.get("thread_count", self._thread_count) or 1)))
        except (TypeError, ValueError):
            pass
        self._transcripts_enabled = bool(cfg.get("transcripts_enabled", self._transcripts_enabled))
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
        if not self._save_folder:
            self.popup.emit(tr("Missing Field"), tr("Please select a Save Folder."), "error")
            return
        if not os.path.isdir(self._save_folder):
            self.popup.emit(tr("Invalid Folder"),
                            tr("The selected save folder does not exist anymore.\n"
                               "Please choose another folder."), "error")
            return

        resume_rows = []
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
        self._tr_ip_note_key = ""
        self.transcriptStateChanged.emit()

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

    def _checkpoint_path(self, sort_order):
        suffix = SORT_SUFFIX[sort_order]
        return os.path.join(self._save_folder, f"{self._filename}_{suffix}_checkpoint.jsonl")

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

    def _get_uploads_video_ids(self, yt, channel_id, max_results):
        resp = execute_with_retry(
            yt.channels().list(part="contentDetails", id=channel_id), self._stop_check)
        items = resp.get("items", [])
        if not items:
            return []
        uploads = (items[0].get("contentDetails", {})
                   .get("relatedPlaylists", {}).get("uploads"))
        if not uploads:
            return []
        ids, token = [], None
        while len(ids) < max_results:
            if self._stop_requested:
                raise ScrapeCancelled()
            resp = execute_with_retry(
                yt.playlistItems().list(part="contentDetails", playlistId=uploads,
                                        maxResults=min(50, max_results - len(ids)),
                                        pageToken=token), self._stop_check)
            for it in resp.get("items", []):
                vid = it.get("contentDetails", {}).get("videoId")
                if vid:
                    ids.append(vid)
            token = resp.get("nextPageToken")
            if not token:
                break
        return ids[:max_results]

    def _get_search_video_ids(self, yt, channel_id, max_results, order, query):
        ids, token = [], None
        while len(ids) < max_results:
            if self._stop_requested:
                raise ScrapeCancelled()
            kwargs = dict(part="id", channelId=channel_id,
                          maxResults=min(50, max_results - len(ids)),
                          order=order, type="video", pageToken=token)
            if query:
                kwargs["q"] = query
            resp = execute_with_retry(yt.search().list(**kwargs), self._stop_check)
            ids.extend(item["id"]["videoId"] for item in resp.get("items", [])
                       if item.get("id", {}).get("videoId"))
            token = resp.get("nextPageToken")
            if not token:
                break
        return ids[:max_results]

    def _get_oldest_video_ids(self, yt, channel_id, max_results):
        """The channel's OLDEST uploads, oldest first.

        The Data API has no ascending-date order, so this walks the uploads
        playlist to the END (it is newest-first) and takes the last `max_results`
        reversed. That means one playlistItems page per 50 videos of the whole
        channel — 1 quota unit each, so cheap, but it does have to see everything.
        A hard page cap keeps a 100k-video channel from paging forever.
        """
        resp = execute_with_retry(
            yt.channels().list(part="contentDetails", id=channel_id), self._stop_check)
        items = resp.get("items", [])
        if not items:
            return []
        uploads = (items[0].get("contentDetails", {})
                   .get("relatedPlaylists", {}).get("uploads"))
        if not uploads:
            return []
        emit = self._emit
        ids, token, pages = [], None, 0
        MAX_PAGES = 400          # 400 × 50 = 20 000 videos
        while pages < MAX_PAGES:
            if self._stop_requested:
                raise ScrapeCancelled()
            resp = execute_with_retry(
                yt.playlistItems().list(part="contentDetails", playlistId=uploads,
                                        maxResults=50, pageToken=token),
                self._stop_check)
            for it in resp.get("items", []):
                vid = it.get("contentDetails", {}).get("videoId")
                if vid:
                    ids.append(vid)
            pages += 1
            token = resp.get("nextPageToken")
            if not token:
                break
            if pages % 10 == 0:
                emit.log_signal.emit(
                    "   " + tr("Walking to the channel's start … {n} videos seen.")
                    .format(n=len(ids)))
        if pages >= MAX_PAGES and token:
            emit.log_signal.emit(
                "⚠️  " + tr("Channel is very large — stopped after {n} videos, so "
                            "'oldest' is the oldest of those.").format(n=len(ids)))
        # Playlist order is newest-first, so the tail is the oldest.
        oldest_first = list(reversed(ids))
        return oldest_first[:max_results]

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
        if format_index != 0:
            fetch_count = min(int(max_videos) * 6, int(max_videos) + 500)
        # Declared out here so the except/finally blocks can salvage finished
        # transcripts and shut the pool down on Stop, quota or error.
        tx_pool = None
        tx_queue = deque()
        try:
            emit.log_signal.emit("═" * 72)
            strategy_label = {"date": tr("Newest"), "viewCount": tr("Most Viewed"),
                              "relevance": tr("Most Relevant"),
                              "oldest": tr("Oldest first")}[sort_order]
            emit.log_signal.emit("  🚀  " + tr("Scraper Started  |  Strategy: {s}").format(s=strategy_label))
            emit.log_signal.emit("═" * 72)
            if self._stop_requested:
                raise ScrapeCancelled()

            yt = build_youtube_service(self._api_key)
            emit.log_signal.emit("\n📡  " + tr("Resolving channel: {u}").format(u=channel_url))
            channel_id = resolve_channel_id(yt, channel_url, stop_check=self._stop_check)
            if not channel_id:
                emit.log_signal.emit("❌  " + tr("Could not resolve Channel ID."))
                emit.popup_signal.emit(tr("Error"),
                                       tr("Could not resolve the channel from that URL."), "error")
                return
            emit.log_signal.emit("✅  " + tr("Channel ID: {id}").format(id=channel_id))
            if format_index != 0:
                fmt_label = tr("Shorts") if format_index == 2 else tr("Long-form")
                emit.log_signal.emit("\n🎯  " + tr("Filtering for {fmt}: scanning up to {scan} videos to find {want}.").format(
                    fmt=fmt_label, scan=fetch_count, want=match_target))
            emit.log_signal.emit("\n📥  " + tr("Fetching up to {n} video IDs  (order: {o}) …").format(
                n=fetch_count, o=sort_order))

            if sort_order == "oldest":
                # No API order exists for this — walk the uploads playlist to the
                # channel's start and reverse it. Only meaningful for a channel,
                # so a query is ignored here (and the UI hides the option).
                emit.log_signal.emit(
                    "   " + tr("Walking the uploads playlist backwards to find the "
                               "channel's first videos (1 quota unit per 50)."))
                video_ids = self._get_oldest_video_ids(yt, channel_id, fetch_count)
            elif sort_order == "date" and not query:
                emit.log_signal.emit("   " + tr("Using uploads playlist (quota-friendly mode)."))
                video_ids = self._get_uploads_video_ids(yt, channel_id, fetch_count)
            else:
                emit.log_signal.emit("   " + tr("Using search API (costs more quota: 100 units per 50 videos)."))
                video_ids = self._get_search_video_ids(yt, channel_id, fetch_count, sort_order, query or None)

            if not video_ids:
                emit.log_signal.emit("❌  " + tr("No videos found."))
                emit.popup_signal.emit(tr("No Results"),
                                       tr("No videos were found for this channel/query."), "warning")
                return

            total = len(video_ids)
            emit.log_signal.emit("✅  " + tr("{n} videos queued.").format(n=total) + "\n")

            # Progress is measured against the matched target when a format
            # filter is active (we may scan many more than we keep), else against
            # every queued id.
            progress_total = match_target if format_index != 0 else total

            done_ids = set()
            if resume_rows:
                data = list(resume_rows)
                done_ids = {r.get("video_id") for r in resume_rows}
            pending = [v for v in video_ids if v not in done_ids]
            processed = total - len(pending)
            if processed:
                emit.log_signal.emit("⏩  " + tr("Resuming: {done} videos restored from checkpoint, "
                                                 "{left} remaining.").format(done=processed, left=len(pending)))
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
            # Now up to 16 transcripts run at once, a slow one only holds
            # itself, and the next metadata page is fetched while the previous
            # page's transcripts are still downloading. Results are still
            # emitted strictly in queue order, so the export order is unchanged.
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

            def _enough():
                # in-flight transcripts already count as matched videos
                return format_index != 0 and matched + len(tx_queue) >= match_target

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

            def _emit_video_result(vid, row):
                nonlocal processed, failed, matched
                processed += 1
                denom = max(progress_total, 1)
                shown = matched if format_index != 0 else processed
                pct = min(100, int((shown / denom) * 100))
                prefix = f"[{shown:4d}/{denom}] ({pct:3d}%)  {vid}"
                if row is not None:
                    data.append(row)
                    matched += 1
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
                emit.progress_signal.emit(pct)
                elapsed = max(time.monotonic() - t0, 0.001)
                done_this_run = matched - baseline_done
                if done_this_run > 0:
                    rate = done_this_run / elapsed
                    remain = max(denom - shown, 0) / max(rate, 1e-6)
                    eta_txt = f"{int(remain // 60):02d}:{int(remain % 60):02d}"
                    emit.status_signal.emit(f"{shown}/{denom} · {rate * 60:.0f}/min · ETA {eta_txt}")

            for chunk_start in range(0, len(pending), 50):
                if self._stop_requested:
                    raise ScrapeCancelled()
                if _enough():
                    break
                chunk = pending[chunk_start:chunk_start + 50]
                resp = execute_with_retry(
                    yt.videos().list(part="snippet,statistics,contentDetails",
                                     id=",".join(chunk), maxResults=50), self._stop_check)
                items = {it.get("id"): it for it in resp.get("items", [])}
                rows_by_id = {vid: _row_from_item(vid, items[vid]) for vid in chunk if vid in items}
                # Drop rows that don't match the requested format — they never
                # reach _emit_video_result, so they don't count toward progress.
                if format_index != 0:
                    kept = {}
                    for vid, row in rows_by_id.items():
                        if self._matches_format(row, format_index):
                            kept[vid] = row
                        else:
                            skipped_format += 1
                    rows_by_id = kept
                available_vids = [v for v in chunk if v in rows_by_id]
                # Only report genuinely-unavailable ids as failures; format
                # mismatches are silently skipped.
                missing_vids = ([v for v in chunk if v not in items] if format_index != 0
                                else [v for v in chunk if v not in rows_by_id])
                # Don't overshoot the matched target: keep only as many matching
                # videos as we still need.
                if format_index != 0:
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

            _drain(keep=0)
            if tx_pool is not None:
                tx_pool.shutdown(wait=False)
                tx_pool = None
            emit.progress_signal.emit(100)
            emit.log_signal.emit("─" * 72)
            transcript_count = sum(1 for d in data
                                 if d.get("transcript_status", "").startswith("Available"))
            emit.log_signal.emit("  " + tr("✅ Success: {ok}   ❌ Failed: {fail}   📝 Transcripts: {tc}/{total}").format(
                ok=len(data), fail=failed, tc=transcript_count, total=max(len(data), 1)))
            if self._tr_skipped:
                emit.log_signal.emit("  ⏭  " + tr("Transcripts skipped: {n}").format(n=self._tr_skipped))

            if data:
                suffix = SORT_SUFFIX[sort_order]
                ext = FORMAT_EXT[self._export_format]
                out_path = os.path.join(self._save_folder, f"{self._filename}_{suffix}.{ext}")
                emit.log_signal.emit("\n💾  " + tr("Saving ({fmt}) → {path} …").format(
                    fmt=self._export_format.upper(), path=out_path))
                write_export(data, out_path, self._export_format)
                kb = os.path.getsize(out_path) / 1024
                emit.log_signal.emit("✅  " + tr("Saved  |  {kb} KB  |  {n} rows").format(kb=f"{kb:.1f}", n=len(data)))
                try:
                    ck = self._checkpoint_path(sort_order)
                    if os.path.exists(ck):
                        os.remove(ck)
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
            emit.popup_signal.emit(tr("Quota exhausted"),
                                   tr("Every configured YouTube API key has used up its daily quota.\n\n"
                                      "Everything scraped so far ({n} videos) was saved.").format(n=len(data)),
                                   "warning")
        except Exception as exc:
            log_crash("qml scrape_videos error:\n" + traceback.format_exc())
            emit.log_signal.emit("\n❌  " + tr("Unexpected error: {e}").format(e=exc))
            if data:
                self._save_checkpoint(data, sort_order)
            emit.popup_signal.emit(tr("Error"),
                                   tr("An error occurred:\n{e}\n\nScraped data was saved — you can "
                                      "resume this scrape later.").format(e=exc), "error")
        finally:
            if tx_pool is not None:
                tx_pool.shutdown(wait=False, cancel_futures=True)
            emit.finished_signal.emit()

    def _save_checkpoint(self, data, sort_order):
        try:
            path = self._checkpoint_path(sort_order)
            write_export(data, path, "json")
            self._emit.log_signal.emit("   💾  " + tr("Checkpoint saved ({n} rows) → {name}").format(
                n=len(data), name=os.path.basename(path)))
        except Exception as exc:
            self._emit.log_signal.emit("   ⚠️  " + tr("Checkpoint save failed: {e}").format(e=exc))

    def _save_settings(self):
        cfg = load_app_config()
        cfg["save_folder"] = self._save_folder
        cfg["output_filename"] = self._filename
        save_app_config(cfg)
