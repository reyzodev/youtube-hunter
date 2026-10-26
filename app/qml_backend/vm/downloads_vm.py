"""app.qml_backend.vm.downloads_vm - YouTube Hunter (QML).

ViewModel behind DownloadsPage.qml — the migrated Downloads page.

A persisted, live-updating list of every video downloaded through the app,
plus a "paste a link" box that looks up a URL's title/thumbnail with oEmbed
(no API key, no quota), shows the quality picker, and funnels the download
through the SAME app.core.download ladder every other page uses.

All logic is UI-free (yt-dlp + a bundled ffmpeg + stdlib), so nothing here
imports QtWidgets — this runs under the QGuiApplication QML app. It mirrors the
worker-thread → GUI-thread signal pattern established in NicheVM: the blocking
download runs on a daemon thread and reports back over queued Qt signals.
"""

import base64
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

from PySide6.QtCore import QObject, Property, QTimer, QUrl, Signal, Slot

from app.config import load_app_config
from app.core.db.downloads import (downloads_apply_channel_meta,
                                    downloads_delete, downloads_get, downloads_list,
                                    downloads_upsert, file_size_of)
from app.core.download import (DOWNLOAD_CANCELLED, DOWNLOAD_QUALITY_PRESETS,
                               clear_cancel, download_video, is_cancelled,
                               quality_by_key, quality_display_label,
    quality_storage_key, request_cancel, with_audio_lang, with_container)
from app.core.net import extract_video_id, fetch_youtube_oembed
from app.core.utils import video_download_dir, reveal_in_file_manager
from app.crash import log_crash
from app.i18n import tr
from app.qml_backend.vm import _dl_progress as dlp
from app.qml_backend.vm.quality_probe import default_quality_rows
from app.qml_backend.desktop_notifier import announce, announce_download


# v14 Downloads: the library is grouped by day ("Today", "Yesterday", "Earlier
# this week", "Older"), and each finished row shows WHEN it landed. Computed
# here because the DB stores UTC ISO strings with microseconds, which the QML
# JS Date parser does not reliably read.
_WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def _when(iso):
    """(day bucket, short label) for a row's added_at timestamp."""
    try:
        dt = datetime.fromisoformat(str(iso or ""))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        dt = dt.astimezone()
    except (TypeError, ValueError):
        return "earlier", ""
    days = (datetime.now().astimezone().date() - dt.date()).days
    if days <= 0:
        return "today", dt.strftime("%H:%M")
    if days == 1:
        return "yesterday", dt.strftime("%H:%M")
    if days < 7:
        return "week", tr(_WEEKDAYS[dt.weekday()])
    return "earlier", dt.strftime("%Y-%m-%d")


def _size_text(n):
    """Bytes as a short human string, or "" when unknown. Mirrors the picker's
    helper so a row and its dialog never disagree about a file's size."""
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


def _eta_text(seconds):
    """Seconds remaining as a compact string ("2m 40s"). Empty when unknown —
    an ETA of "0s" on a stalled download reads as a lie."""
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


def _live_tip(pct, done_text, total_text, remaining_n, speed_text, eta_text,
              frag_text, merging=False):
    """The running row's tooltip: the same figures the row shows, spelled out.

    The visible line is a compact run of numbers — "1.9 MB of 124 MB ·
    Downloading 2% · 471 KB/s · 4m 24s left" — which a first-time viewer had no
    way to decode: which figure was the size, which was the speed, and what the
    trailing "2/97 frags" even meant. This says it in words, and it is where the
    internal part position lives now that the visible line no longer carries it.
    Empty lines are skipped, so a download with no speed sample yet still reads
    cleanly instead of showing blank rows.
    """
    lines = [tr("Merging the audio and video into one file…") if merging
             else tr("Downloading video")]
    if pct > 0:
        lines.append(tr("{pct}% complete").format(pct=pct))
    size = (tr("{done} of {total}").format(done=done_text, total=total_text)
            if done_text and total_text else (done_text or total_text))
    if size:
        lines.append(tr("{size} · {left} left").format(
            size=size, left=_size_text(remaining_n)) if remaining_n else size)
    if speed_text:
        lines.append(tr("Speed {s} · {t} left").format(s=speed_text, t=eta_text)
                     if eta_text else tr("Speed {s}").format(s=speed_text))
    elif eta_text:
        lines.append(tr("{t} left").format(t=eta_text))
    if frag_text:
        lines.append(frag_text)
    return "\n".join(lines)


def _thumb_id(url):
    """Encode a thumbnail URL as the id half of `image://thumbs/<id>` (same
    scheme NicheVM uses, so the shared ThumbImageProvider serves both)."""
    if not url:
        return ""
    return base64.b64encode(url.encode("utf-8")).decode("ascii")


# The quality key baked into a download's filename ("… [id] 1080p.mp4") mapped to
# a human label for the player's gear menu. An unknown key is shown verbatim.
_QUALITY_KEY_LABELS = {
    "best": "Best", "2160p": "2160p", "1440p": "1440p", "1080p": "1080p",
    "720p": "720p", "480p": "480p", "360p": "360p", "audio": "Audio",
}

# Containers that hold sound only. An "Audio only" pick is converted to mp3, but
# a file that arrived another way (or was re-named by hand) still has to open in
# the music player rather than a video player with nothing to show, so the
# extension is checked as well as the quality key.
_AUDIO_EXTS = frozenset({
    ".mp3", ".m4a", ".aac", ".opus", ".ogg", ".oga", ".wav", ".flac", ".wma",
})


def _is_audio_download(filepath, quality_key=""):
    """True when this download has no picture and should open as music."""
    key = str(quality_key or "").strip().lower().split("@", 1)[0]
    if key == "audio" or key.startswith("audio_"):
        return True
    return os.path.splitext(str(filepath or ""))[1].lower() in _AUDIO_EXTS


# DB status values have drifted between call sites (the legacy page wrote
# "complete"/"failed"; NicheVM wrote "done"/"error"). Normalise on read so the
# page only ever deals with four canonical states.
_STATUS_ALIASES = {"done": "complete", "error": "failed"}


class DownloadsVM(QObject):
    """Download queue + history for the QML Downloads page."""

    changed = Signal()            # list model changed
    progressChanged = Signal()    # live per-id progress ticked (cheap)
    busyChanged = Signal()        # url-lookup in flight
    hintChanged = Signal()        # url box hint text/kind
    toast = Signal(str, str)      # (message, kind)
    # oEmbed lookup finished → the page should open the quality picker.
    readyToPick = Signal(str, str, str)   # (video_id, title, thumb_id)

    @Slot()
    def retranslate(self):
        """UI language changed — rebuild the rows so their translated text is
        re-read instead of served from the cache it was built in.

        `refresh()` is a plain SQLite read, so doing it on a language switch is
        cheap. Re-emitting alone would NOT have been enough: `_rows` holds
        strings translated when it was built (the "Untitled" fallback, the
        status line), and a signal only re-delivers those same old strings.
        """
        self.refresh()
        self.hintChanged.emit()

    # worker → GUI bridges (auto-queued across threads)
    _metaDone = Signal("QVariant", str)   # (row_or_None, error)
    _dlStatus = Signal(str, str)          # (video_id, status text)
    _dlProgress = Signal(str, int)        # (video_id, percent)
    # (video_id, bytes_done, bytes_total, bytes_per_sec, eta_seconds,
    #  frag_done, frag_total) — the raw numbers the row's live progress UI needs;
    # a percentage can't express speed, and frag_done/total drive "part 32 of 93".
    _dlDetail = Signal(str, int, int, float, int, int, int)
    _dlDone = Signal(str, bool, str, str)  # (video_id, ok, message, filepath)
    # (video_id, height_px, label) — the resolution actually delivered, so the
    # row's quality label describes the file on disk instead of the tier that was
    # requested. Fired at most once per download.
    _dlResolved = Signal(str, int, str)
    # Channel identity harvested from the download's own metadata, marshalled
    # onto the GUI thread before it touches the DB (see _on_dl_meta).
    _dlMeta = Signal(str, "QVariantMap")

    def __init__(self, parent=None):
        super().__init__(parent)
        self._rows = []                 # cached list of dicts for QML
        # Rows awaiting a quality choice, keyed by video id (metadata fetched,
        # picker not yet confirmed).
        self._pending = {}
        self._busy = False
        self._hint = ""
        self._hint_error = False
        # Bumped on every progress update; QML reads it as a scalar dependency so
        # the live map's contents are never served from a stale cache.
        self._tick = 0
        # Throttle for the DB-persisted percentage: the live store + the cheap
        # progressChanged signal move the bar every tick, but a SQLite write on
        # EVERY tick (many per second with concurrent fragments) blocked the GUI
        # thread and made the whole page stutter. Persist at most every ~2s or
        # on a visible jump — the DB is only the reopen/resume starting point.
        self._last_db_write = {}      # video_id -> (monotonic_s, pct)
        # v3.43: downloads whose worker THIS VM launched. Only these can be
        # paused / resumed from the live card: their _on_dl_done is ours.
        self._owned = set()

        self._metaDone.connect(self._on_meta_done)
        self._dlStatus.connect(self._on_dl_status)
        self._dlProgress.connect(self._on_dl_progress)
        self._dlDetail.connect(self._on_dl_detail)
        self._dlDone.connect(self._on_dl_done)
        self._dlResolved.connect(self._on_dl_resolved)
        self._dlMeta.connect(self._on_dl_meta)
        # Live progress is published to a SHARED store so downloads started from
        # the Niche Finder / Search Archive grids show up here too, not just the
        # paste-a-link ones. Listening means this page updates for all of them.
        dlp.add_listener(self._on_live_change)
        self._reconcile_orphaned_rows()
        self.refresh()

    def _on_live_change(self, video_id, structural):
        """A download anywhere in the app published new progress.

        `structural` changes (a download starting/finishing or changing status)
        need the row list rebuilt; a plain progress tick only needs the cheap
        signal, so the row delegates aren't recreated mid-animation.
        """
        self._tick += 1
        if structural:
            self.refresh()
        self.progressChanged.emit()

    # ── properties ─────────────────────────────────────────────────────
    @Property("QVariantList", notify=changed)
    def entries(self):
        """Newest-first list of download rows for the page."""
        return self._rows

    @Property(bool, notify=changed)
    def isEmpty(self):
        return len(self._rows) == 0

    @Property(int, notify=changed)
    def totalCount(self):
        return len(self._rows)

    @Property(int, notify=changed)
    def completedCount(self):
        return sum(1 for r in self._rows if r["status"] == "complete")

    @Property(int, notify=changed)
    def activeCount(self):
        return sum(1 for r in self._rows
                   if r["status"] in ("downloading", "merging"))

    @Property(bool, notify=busyChanged)
    def busy(self):
        return self._busy

    @Property(str, notify=hintChanged)
    def hint(self):
        return self._hint

    @Property(bool, notify=hintChanged)
    def hintIsError(self):
        return self._hint_error

    @Property("QVariantList", constant=True)
    def qualityOptions(self):
        """Fallback rows for the shared QualityPicker. The picker normally shows
        QualityProbe.options — the real formats THIS video has — and falls back
        to this generic ladder only when the probe couldn't run."""
        return default_quality_rows()

    # ── list building ───────────────────────────────────────────────────
    @Slot()
    def _reconcile_orphaned_rows(self):
        """Rows still marked downloading/merging at STARTUP are leftovers.

        The download workers are daemon threads: they die with the process, so a
        row that still claims to be downloading or merging when the app opens
        belongs to a run that never finished. The merge step is the usual place
        that happens — yt-dlp hands the two streams to ffmpeg and, if ffmpeg is
        missing, blocked, or the disk fills, the row sat on "merging" forever
        with no way out. Parking it as "stopped" gives the user back the resume
        / delete controls instead of a row that pretends to be busy.
        """
        # No need to consult the live store: the workers are daemon threads, so
        # by the time this VM exists nothing can legitimately be in flight.
        for row in downloads_list():
            vid = (row.get("video_id") or "").strip()
            if not vid:
                continue
            if row.get("status") not in ("downloading", "merging"):
                continue
            resumable = bool((row.get("video_url") or "").strip())
            downloads_upsert(
                vid, status="stopped" if resumable else "failed",
                create_if_missing=False)
            dlp.clear(vid)

    @Slot()
    def refresh(self):
        """Rebuild the STRUCTURAL list from the database. Deliberately carries
        no live per-tick values (percent / speed / bytes) — those live in the
        separate `live` map and update via progressChanged. Mixing them in here
        meant every progress sample rebuilt the whole Repeater, which destroyed
        and recreated each row delegate and reset its animated progress bar to
        zero on every tick (the "bar never moves" bug)."""
        rows = []
        for item in downloads_list():
            status = (item.get("status") or "downloading").lower()
            status = _STATUS_ALIASES.get(status, status)
            vid = item.get("video_id") or ""
            day_key, when_text = _when(item.get("added_at"))
            rows.append({
                "videoId": vid,
                "title": item.get("title") or tr("Untitled"),
                "thumbId": _thumb_id(item.get("thumbnail_url") or ""),
                "quality": item.get("quality_label") or "",
                "status": status,
                # The REAL on-disk size of a finished file ("" while running —
                # the live map owns the in-flight numbers). Persisted at
                # completion so the row never shows an estimated total.
                "totalText": _size_text(item.get("file_size") or 0),
                # DB-persisted percent — a stable starting point; the live map
                # overrides it while a download is actually running.
                "pct": int(item.get("progress") or 0),
                "filepath": item.get("filepath") or "",
                "error": item.get("error_message") or "",
                "channelTitle": item.get("channel_title") or "",
                "dayKey": day_key,
                "whenText": when_text,
            })
        self._rows = rows
        self.changed.emit()

    @Property("QVariantMap", notify=progressChanged)
    def live(self):
        """Per-video live transfer state, keyed by video id.

        Reads the SHARED progress store, not a private dict — a download started
        from the Niche Finder or Search Archive grid publishes its ticks there
        too, so this page shows live progress for those as well. (Previously each
        VM kept its own dict and a grid download sat at 0% here until you left
        the page and came back, which re-read the slower DB percentage.)

        Kept as a SEPARATE property from `entries` so a progress tick updates it
        without rebuilding the row list — otherwise every delegate is recreated
        and its animating progress bar snaps back to zero.
        """
        out = {}
        for vid, d in dlp.snapshot().items():
            speed = float(d.get("speed") or 0)
            frag_total = int(d.get("fragTotal") or 0)
            frag_done = int(d.get("fragDone") or 0)
            done_n = int(d.get("done") or 0)
            total_n = int(d.get("total") or 0)
            pct = int(d.get("pct") or 0)
            # Remaining bytes, cutter-style ("72.6 MB left"): only when the real
            # total is known and ahead of what's on disk — never from a guess.
            remaining_n = total_n - done_n if total_n > done_n > 0 else 0
            done_text = _size_text(done_n)
            total_text = _size_text(total_n)
            speed_text = (_size_text(speed) + "/s") if speed > 0 else ""
            eta_text = _eta_text(d.get("eta") or 0)
            # The internal fragment position, worded for a human ("part 32 of
            # 93"). Deliberately NOT on the row's visible line any more: yt-dlp
            # splits the file into ~100 DASH chunks, and "32/93 frags" was
            # jargon a first-time viewer could not read. It lives in the row's
            # tooltip instead. Empty when the download isn't fragmented.
            frag_text = (tr("part {i} of {n}").format(i=frag_done, n=frag_total)
                         if frag_total > 0 else "")
            out[vid] = {
                "running": bool(d.get("running")),
                "pct": pct,
                "text": d.get("text") or "",
                "doneText": done_text,
                "totalText": total_text,
                "remainingText": _size_text(remaining_n),
                "hasTotal": total_n > 0,
                "speedText": speed_text,
                "etaText": eta_text,
                "fragText": frag_text,
                # The row's tooltip: the same figures, spelled out in words so
                # the numbers on the line are self-explanatory on first sight.
                "tipText": _live_tip(
                    pct, done_text, total_text, remaining_n, speed_text,
                    eta_text, frag_text,
                    merging=(d.get("text") or "") == tr("Merging…")),
            }
        return out

    @Property(int, notify=progressChanged)
    def progressTick(self):
        """A counter that increments on every progress update.

        QML caches a QVariantMap property's *contents* aggressively: a row
        binding that only reads `Downloads.live[id]` could keep showing the
        first sample even though the map behind it had changed. Referencing this
        integer in the same binding gives QML a scalar dependency it always
        re-reads, which is what actually makes the percentage move live."""
        return self._tick

    # ── paste-a-link flow ────────────────────────────────────────────────
    def _set_hint(self, text, error=False):
        self._hint = text
        self._hint_error = error
        self.hintChanged.emit()

    def _set_busy(self, busy):
        if busy != self._busy:
            self._busy = busy
            self.busyChanged.emit()

    @Slot(str)
    def fetchFromUrl(self, raw):
        """Validate a pasted YouTube link, then look up its public metadata on
        a worker thread. On success the page is told to open the quality picker
        via readyToPick(); the actual download starts from startDownload()."""
        if self._busy:       # a double Enter must not open two pickers
            return
        raw = (raw or "").strip()
        if not raw:
            return
        video_id = extract_video_id(raw)
        if not video_id:
            self._set_hint(
                tr("That doesn't look like a YouTube video link."), error=True)
            return
        if dlp.is_running(video_id):
            self._set_hint(tr("This video is already downloading."), error=True)
            return
        self._set_busy(True)
        self._set_hint(tr("Looking up video…"))
        cfg = load_app_config()
        proxy = (cfg.get("ai_proxy", "") or "").strip()

        def worker(_vid=video_id, _proxy=proxy):
            try:
                row = fetch_youtube_oembed(_vid, proxy=_proxy or None)
                self._metaDone.emit(row, "")
            except Exception as exc:      # noqa: BLE001 — surfaced to the user
                self._metaDone.emit(None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot("QVariant", str)
    def _on_meta_done(self, row, error):
        self._set_busy(False)
        if not row:
            self._set_hint(
                tr("Couldn't fetch that video's details — check the link or "
                   "your connection/proxy and try again."), error=True)
            return
        self._set_hint("")
        video_id = row.get("video_id") or ""
        self._pending[video_id] = row
        self.readyToPick.emit(
            video_id, row.get("title") or "",
            _thumb_id(row.get("thumbnail_url") or ""))

    # ── download ─────────────────────────────────────────────────────────
    @Slot(str, int)
    def startDownload(self, video_id, quality_index):
        """Download the pending video at the chosen quality. Called by the
        quality picker after fetchFromUrl() resolved the metadata."""
        row = self._pending.get(video_id)
        if not row:
            self.toast.emit(tr("That video is no longer queued."), "error")
            return
        url = row.get("video_url") or (
            f"https://www.youtube.com/watch?v={video_id}" if video_id else "")
        if not url:
            self.toast.emit(tr("This item has no video URL."), "error")
            return
        if dlp.is_running(video_id):
            return

        quality = (DOWNLOAD_QUALITY_PRESETS[quality_index]
                   if 0 <= quality_index < len(DOWNLOAD_QUALITY_PRESETS)
                   else quality_by_key("best"))
        # Attach the output format picked in the quality dialog (MP4/MKV/WEBM,
        # or MP3/M4A/OPUS/WAV/FLAC for audio).
        quality = with_container(quality)
        # v1.2: the audio track picked in the quality dialog (dubbed videos)
        quality = with_audio_lang(quality, video_id=video_id)
        target_dir = video_download_dir("YouTube")
        try:
            os.makedirs(target_dir, exist_ok=True)
        except OSError as exc:
            self.toast.emit(str(exc), "error")
            return

        cfg = load_app_config()
        proxy_url = (cfg.get("ai_proxy", "") or "").strip()
        cookies_browser = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        dlp.publish(video_id, running=True, pct=0, floor=0, text=tr("Preparing…"),
                    cancelling=False, intent="", structural=True)
        clear_cancel(video_id)   # drop any stale stop flag from a previous run
        # quality_key + video_url are persisted so a STOPPED download can be
        # resumed at the same quality later — including after an app restart,
        # when self._pending is long gone.
        downloads_upsert(
            video_id, title=row.get("title", ""),
            thumbnail_url=row.get("thumbnail_url", ""),
            quality_label=quality_display_label(quality),
            quality_key=quality_storage_key(quality), video_url=url,
            status="downloading", progress=0,
            filepath="", error_message="", file_size=0,
            channel_title=row.get("channel_title", ""),
            channel_thumb_url=row.get("channel_thumb_url", ""),
            channel_url=row.get("channel_url", ""),
            subscriber_count=row.get("subscriber_count"),
            subs_hidden=row.get("subs_hidden"))
        self._pending.pop(video_id, None)
        self.toast.emit(tr("Download started — {t}").format(
            t=(row.get("title") or "")[:60]), "download")
        self.refresh()
        self._launch_worker(video_id, url, target_dir, quality,
                            proxy_url, cookies_browser)

    @Slot(str)
    def resumeDownload(self, video_id):
        """Start a STOPPED download over, at the quality it was stopped at.

        The persisted row carries `video_url` and `quality_key`, so this works
        even after an app restart. yt-dlp keeps its own .part file for the
        fragment it was on, so restarting continues from roughly where it left
        off rather than re-fetching everything.
        """
        if dlp.is_running(video_id):
            return
        row = next((r for r in downloads_list()
                    if (r.get("video_id") or "") == video_id), None)
        if not row:
            self.toast.emit(tr("That download is no longer listed."), "error")
            return
        url = row.get("video_url") or (
            f"https://www.youtube.com/watch?v={video_id}" if video_id else "")
        if not url:
            self.toast.emit(tr("This item has no video URL."), "error")
            return
        quality = quality_by_key(row.get("quality_key") or "best")
        target_dir = video_download_dir("YouTube")
        try:
            os.makedirs(target_dir, exist_ok=True)
        except OSError as exc:
            self.toast.emit(str(exc), "error")
            return

        cfg = load_app_config()
        proxy_url = (cfg.get("ai_proxy", "") or "").strip()
        cookies_browser = (cfg.get("yt_cookies_browser", "") or "").strip().lower()

        clear_cancel(video_id)
        resumed_at = int(row.get("progress") or 0)
        dlp.publish(video_id, running=True, pct=resumed_at, floor=resumed_at,
                    text=tr("Resuming…"), cancelling=False, intent="",
                    structural=True)
        downloads_upsert(video_id, status="downloading", error_message="",
                         create_if_missing=False)
        self.toast.emit(tr("Resuming download…"), "download")
        self.refresh()
        self._launch_worker(video_id, url, target_dir, quality,
                            proxy_url, cookies_browser,
                            resume_pct=resumed_at)

    def _launch_worker(self, video_id, url, target_dir, quality,
                       proxy_url, cookies_browser, resume_pct=0):
        """Run one download on a daemon thread. Shared by startDownload and
        resumeDownload so both paths report progress and cancellation
        identically."""
        self._owned.add(video_id)
        def worker():
            try:
                ok, message, filepath = download_video(
                    url, target_dir, quality,
                    on_status=lambda t, v=video_id: self._dlStatus.emit(v, t),
                    on_progress=lambda p, v=video_id: self._dlProgress.emit(v, p),
                    on_detail=lambda d, t, s, e, fd, ft, v=video_id:
                        self._dlDetail.emit(v, d, t, s, e, fd, ft),
                    on_resolved=lambda px, lbl, v=video_id:
                        self._dlResolved.emit(v, px, lbl),
                    on_meta=lambda m, v=video_id: self._dlMeta.emit(v, m),
                    proxy_url=proxy_url, cookies_browser=cookies_browser,
                    should_cancel=lambda v=video_id: is_cancelled(v),
                    resume_pct=resume_pct)
            except Exception as exc:      # noqa: BLE001
                log_crash("DownloadsVM worker failed:\n" + str(exc))
                ok, message, filepath = False, str(exc), ""
            self._dlDone.emit(video_id, ok, message, filepath)

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str)
    def cancelDownload(self, video_id):
        """Stop a running download for real — the worker's yt-dlp hook sees the
        flag and unwinds the download, so nothing keeps going in the background.

        The row is KEPT (parked as "stopped" once the worker unwinds) so it can
        be resumed later; the trash icon is the destructive option.
        """
        if not dlp.is_running(video_id):
            return
        request_cancel(video_id)
        # `cancelling` makes late ticks from the still-unwinding worker get
        # dropped rather than reviving the row. `intent` tells _on_dl_done
        # whether to park the row for resume or delete it outright.
        dlp.publish(video_id, text=tr("Stopping…"), cancelling=True,
                    intent="stop")
        self.toast.emit(tr("Stopping download…"), "info")

    # ── v3.43: pause / resume (the live card's ⏸ / ▶) ─────────────────────
    def owns(self, video_id):
        return video_id in self._owned

    def canPause(self, video_id):
        entry = dlp.get(video_id) or {}
        return (video_id in self._owned and bool(entry.get("running"))
                and not entry.get("cancelling"))

    @Slot(str, result=bool)
    def pauseDownload(self, video_id):
        if not self.canPause(video_id):
            return False
        request_cancel(video_id)
        dlp.publish(video_id, text=tr("Pausing…"), cancelling=True,
                    intent="pause", speed=0.0, eta=0)
        return True

    @Slot(str, result=bool)
    def resumeAfterPause(self, video_id):
        entry = dlp.get(video_id)
        if entry is not None:
            if entry.get("cancelling") and entry.get("intent") in ("pause", "stop"):
                dlp.publish(video_id, intent="resume", text=tr("Resuming…"))
                return True
            return bool(entry.get("running"))
        self.resumeDownload(video_id)
        return dlp.is_running(video_id)

    def _ignore_tick(self, video_id):
        """True when a tick arriving from a worker should be dropped: the user
        stopped or deleted this download, so its remaining in-flight progress
        callbacks must not write to the DB or resurrect the row."""
        return (dlp.get(video_id) is None
                or dlp.is_cancelling(video_id)
                or is_cancelled(video_id))

    # ── download signal handlers (GUI thread) ────────────────────────────
    @Slot(str, str)
    def _on_dl_status(self, video_id, text):
        if self._ignore_tick(video_id):
            return
        if tr("Merging…") == text:
            # UPDATE-ONLY: a row the user deleted must not be re-created here.
            downloads_upsert(video_id, status="merging", create_if_missing=False)
            dlp.publish(video_id, text=text, structural=True)
        else:
            dlp.publish(video_id, text=text)

    @Slot(str, int)
    def _on_dl_progress(self, video_id, pct):
        if self._ignore_tick(video_id):
            return
        # Persist the percentage so a reopen shows where it got to — but the row
        # list is NOT rebuilt on every tick (that recreates every delegate and
        # resets the animating bar to zero). The shared live store + the cheap
        # progressChanged signal move the bar smoothly instead.
        #
        # create_if_missing=False is essential: without it, a download the user
        # deleted mid-flight was INSERTed back by the next tick and reappeared as
        # a title-less "Untitled" row that looked like it was downloading again.
        #
        # Throttled: a SQLite write on EVERY tick (many/sec with concurrent
        # fragments) ran on the GUI thread and stuttered the page. The live bar
        # still moves every tick; the DB only needs a reopen/resume checkpoint.
        try:
            pct_i = int(pct)
        except (TypeError, ValueError):
            pct_i = 0
        # 100 belongs to the finished file on disk (_on_dl_done), never to a
        # running row — without this clamp a late 100 tick (e.g. a
        # post-processor reporting done before the worker returns) left the
        # row showing "Downloading 100%" with a full bar that wouldn't open.
        pct_i = max(0, min(99, pct_i))
        floor = int((dlp.get(video_id) or {}).get("floor") or 0)
        if pct_i < floor:
            pct_i = floor
        now = time.monotonic()
        last = self._last_db_write.get(video_id)
        if (last is None or pct_i >= 99
                or pct_i - int(last[1]) >= 2 or now - float(last[0]) >= 2.0):
            self._last_db_write[video_id] = (now, pct_i)
            downloads_upsert(video_id, status="downloading", progress=pct_i,
                             create_if_missing=False)
        dlp.publish(video_id, pct=pct_i,
                    text=tr("Downloading… {pct}%").format(pct=pct_i))

    @Slot(str, int, int, float, int, int, int)
    def _on_dl_detail(self, video_id, done, total, speed, eta, frag_done, frag_total):
        """Byte-level progress. Kept separate from _on_dl_progress so the
        percentage still updates on a stream that reports no total size, and so
        the DB write stays on the percentage tick rather than firing on every
        speed sample."""
        if self._ignore_tick(video_id):
            return
        dlp.publish(video_id, done=done, total=total, speed=speed, eta=eta,
                    fragDone=frag_done, fragTotal=frag_total)

    @Slot(str, int, str)
    def _on_dl_resolved(self, video_id, height_px, label):
        """The download reported the resolution it ACTUALLY delivered.

        The row was labelled with the requested tier when it started, which is a
        promise the download can't always keep (a video that only ships 720p
        answers a 1080p request with 720p). Relabelling here is what makes the
        list, and the player's quality pill, describe the file on disk.

        UPDATE-ONLY: a row the user deleted mid-download must not be re-created
        by a late relabel.
        """
        if not label or self._ignore_tick(video_id):
            return
        downloads_upsert(video_id, quality_label=label, create_if_missing=False)
        self.refresh()

    @Slot(str, "QVariantMap")
    def _on_dl_meta(self, video_id, meta):
        """yt-dlp told us who made this video — complete the library row.

        Runs on the GUI thread (the worker emits a queued signal) so it never
        races the page's own reads of the same SQLite file. Without this the row
        kept only whatever the search happened to know about the channel, and a
        video downloaded from an un-enriched page opened in the player with no
        subscriber count and no avatar.
        """
        meta = dict(meta or {})
        downloads_apply_channel_meta(video_id, meta)
        # v3.51: yt-dlp often has no `channel_follower_count`, and a download
        # started from the browser extension has no search-time count either —
        # read it from the watch page instead (background thread).
        if meta.get("subscriber_count") in (None, "", 0):
            self._ensure_subs(video_id)

    def _ensure_subs(self, video_id):
        """Fill a missing subscriber count from the video's watch page, once per
        video per session. Never blocks the GUI thread; never overwrites a count
        the row already has."""
        tried = getattr(self, "_subs_tried", None)
        if tried is None:
            tried = self._subs_tried = set()
        if not video_id or video_id in tried:
            return
        tried.add(video_id)
        try:
            row = downloads_get(video_id) or {}
            if row.get("subscriber_count") not in (None, "", 0):
                return
        except Exception:                 # noqa: BLE001
            pass

        def worker():
            try:
                from app.core.download import channel_meta_for_video
                m = channel_meta_for_video(video_id) or {}
                subs = m.get("subscriber_count")
                if subs not in (None, "", 0):
                    self._dlMeta.emit(video_id, {"subscriber_count": int(subs),
                                                 "subs_hidden": False})
            except Exception:             # noqa: BLE001 — cosmetic only
                pass

        threading.Thread(target=worker, daemon=True, name="dl-subs").start()

    @Slot(str, bool, str, str)
    def _on_dl_done(self, video_id, ok, message, filepath):
        entry = dlp.get(video_id) or {}
        was_cancelling = bool(entry.get("cancelling"))
        # "stop" keeps the row so it can be resumed; "delete" (the trash icon)
        # removes it for good. Both flow through the same cancel path.
        intent = entry.get("intent") or "stop"
        stopped_pct = int(entry.get("pct") or 0)
        dlp.clear(video_id)
        clear_cancel(video_id)
        self._owned.discard(video_id)
        self._last_db_write.pop(video_id, None)
        # A user stop is not a failure. Park the row as "stopped" at the percent
        # it reached so the row offers a play button to resume, rather than
        # showing a scary "failed" state or vanishing.
        if message == DOWNLOAD_CANCELLED or was_cancelling:
            if intent == "delete":
                downloads_delete(video_id)
            else:
                downloads_upsert(video_id, status="stopped",
                                 progress=stopped_pct, error_message="",
                                 create_if_missing=False)
            self.refresh()
            if intent == "resume":
                QTimer.singleShot(0, lambda v=video_id: self.resumeDownload(v))
            elif intent == "pause":
                self.toast.emit(tr("Download paused."), "info")
            else:
                self.toast.emit(tr("Download stopped."), "info")
            return
        downloads_upsert(video_id, status="complete" if ok else "failed",
                         progress=100 if ok else None,
                         filepath=filepath if ok else "",
                         error_message="" if ok else message,
                         file_size=file_size_of(filepath) if ok else 0,
                         create_if_missing=False)
        self.refresh()
        if ok:
            self.toast.emit(tr("Download finished — {p}").format(
                p=os.path.basename(filepath or "")), "success")
        else:
            self.toast.emit(message or tr("Download failed"), "error")
        # v3.40: away notice in the corner of the screen
        announce_download(video_id, ok, message, filepath)

    # ── row actions ──────────────────────────────────────────────────────
    @Slot(str)
    def deleteEntry(self, video_id):
        # If it's still downloading, stop it for real first — otherwise the row
        # leaves the list while yt-dlp keeps pulling bytes in the background.
        # The cancel flag is also what makes late progress ticks from the
        # unwinding worker get dropped instead of re-INSERTing the row.
        if dlp.is_running(video_id):
            request_cancel(video_id)
            # intent="delete" tells _on_dl_done to remove the row rather than
            # parking it as "stopped" for resume.
            dlp.publish(video_id, cancelling=True, intent="delete")
            downloads_delete(video_id)
            self.toast.emit(tr("Stopping download…"), "info")
            self.refresh()
            return
        downloads_delete(video_id)
        dlp.clear(video_id, structural=False)
        self.toast.emit(tr("Removed from downloads."), "success")
        self.refresh()

    @Slot("QVariantList")
    def deleteEntries(self, video_ids):
        """Bulk-remove a set of rows in one shot.

        Same per-row semantics as deleteEntry (a still-running download is
        cancelled for real with intent="delete" first, so late ticks from the
        unwinding worker get dropped instead of re-INSERTing the row), but with
        a SINGLE refresh() and a single toast for the whole batch — looping
        deleteEntry() would rebuild the page and fire a toast once per row.
        """
        ids = [str(v) for v in (video_ids or []) if str(v)]
        if not ids:
            return
        for video_id in ids:
            if dlp.is_running(video_id):
                request_cancel(video_id)
                dlp.publish(video_id, cancelling=True, intent="delete")
                downloads_delete(video_id)
            else:
                downloads_delete(video_id)
                dlp.clear(video_id, structural=False)
        self.toast.emit(
            tr("Removed {n} download(s).").format(n=len(ids)), "success")
        self.refresh()

    @Slot(str, result="QVariantMap")
    def playInfo(self, video_id):
        """Everything the in-app player needs for one finished download.

        Returned as a map (rather than the player reaching into `entries`) so the
        QML side has one call to make and never has to re-derive a file URL or a
        thumbnail id. `fileUrl` is a real file:// URL — QtMultimedia's MediaPlayer
        needs that, not a bare Windows path. `qualities` lists every resolution of
        the SAME video that is on disk, which is what lets the player's gear
        switch between them (mirrors the legacy _discover_quality_variants).
        """
        row = None
        for r in self._rows:
            if r["videoId"] == video_id:
                row = r
                break
        if row is None:
            return {}
        path = row.get("filepath") or ""
        if not path or not os.path.exists(path):
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return {}
        # Pull the fuller record straight from the DB: `entries` is trimmed to
        # what the list needs, but the player also wants the channel identity.
        extra = {}
        for item in downloads_list():
            if (item.get("video_id") or "") == video_id:
                extra = item
                break
        subs = extra.get("subscriber_count")
        if subs in (None, "", 0) and not extra.get("subs_hidden"):
            self._ensure_subs(video_id)    # heals older rows; shows on next open
        return {
            "videoId": video_id,
            "title": row.get("title") or tr("Untitled"),
            "filePath": path,
            "fileUrl": QUrl.fromLocalFile(path).toString(),
            "quality": row.get("quality") or "",
            # Audio-only pick (an .mp3 on disk): the player opens as a MUSIC
            # player — cover art, a big centred transport, no video frame and no
            # fullscreen. See VideoPlayer.qml.
            "isAudio": _is_audio_download(path, row.get("quality")),
            # The video's own thumbnail, used as the music player's cover art.
            "thumbId": _thumb_id(extra.get("thumbnail_url") or ""),
            "channelTitle": row.get("channelTitle") or "",
            "channelThumbId": _thumb_id(extra.get("channel_thumb_url") or ""),
            "channelUrl": extra.get("channel_url") or "",
            "subscriberCount": int(subs) if subs not in (None, "") else 0,
            "subsHidden": bool(extra.get("subs_hidden")),
            "watchUrl": (f"https://www.youtube.com/watch?v={video_id}"
                         if video_id else ""),
            "qualities": self._quality_variants(path, video_id),
        }

    def _quality_variants(self, filepath, video_id):
        """Every file on disk for this same video id, one per downloaded quality.

        Downloads are named "<title> [<id>] <qualitykey>.<ext>", so two qualities
        of one video sit side by side rather than overwriting each other. Scanning
        for the id and pulling the trailing key out is what lets the player offer
        a switch between the resolutions actually downloaded. Current file first.
        """
        variants = []
        try:
            folder = os.path.dirname(filepath)
            vid = (video_id or "").strip()
            entries = os.listdir(folder) if folder and os.path.isdir(folder) else []
        except OSError:
            entries, folder = [], ""
        if vid and entries:
            pat = re.compile(r"\[" + re.escape(vid) + r"\]\s*([^.\[\]]*)")
            for name in entries:
                m = pat.search(name)
                if not m:
                    continue
                full = os.path.join(folder, name)
                if not os.path.isfile(full):
                    continue
                key = m.group(1).strip().lower()
                label = _QUALITY_KEY_LABELS.get(key) or (key.upper() if key
                                                        else tr("Downloaded"))
                variants.append({"label": label, "key": key,
                                 "filePath": full,
                                 "fileUrl": QUrl.fromLocalFile(full).toString()})
        if not variants:
            variants = [{"label": tr("Downloaded"), "key": "",
                         "filePath": filepath,
                         "fileUrl": QUrl.fromLocalFile(filepath).toString()}]
        cur = os.path.normcase(filepath)
        variants.sort(key=lambda v: (os.path.normcase(v["filePath"]) != cur,
                                     v["label"]))
        seen, unique = set(), []
        for v in variants:
            np = os.path.normcase(v["filePath"])
            if np not in seen:
                seen.add(np)
                unique.append(v)
        return unique

    @Slot(str)
    def openFile(self, video_id):
        path = self._path_for(video_id)
        if not path or not os.path.exists(path):
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return
        try:
            if sys.platform.startswith("win"):
                os.startfile(path)      # noqa: S606
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])
            else:
                subprocess.Popen(["xdg-open", path])
        except Exception as exc:        # noqa: BLE001
            self.toast.emit(tr("Could not open: {e}").format(e=exc), "error")

    @Slot(str)
    def reveal(self, video_id):
        path = self._path_for(video_id)
        if not path or not os.path.exists(path):
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return
        if not reveal_in_file_manager(path):
            self.toast.emit(tr("Couldn't open the folder."), "error")

    @Slot("QVariantList", result="QVariantList")
    def existingPaths(self, video_ids):
        """v3.39.9 drag-out: the on-disk files behind these rows, in the order
        given, skipping rows whose file is gone (or never finished)."""
        out = []
        for vid in video_ids or []:
            path = self._path_for(str(vid))
            if path and os.path.isfile(path):
                out.append(path)
        return out

    def _path_for(self, video_id):
        for r in self._rows:
            if r["videoId"] == video_id:
                return r["filepath"]
        return ""
