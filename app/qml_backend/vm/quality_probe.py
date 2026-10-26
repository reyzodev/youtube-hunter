"""app.qml_backend.vm.quality_probe - YouTube Hunter (QML).

The download-quality picker's data source.

The picker used to list DOWNLOAD_QUALITY_PRESETS verbatim — the same fixed
"Best / 1080p / 720p / 480p / Audio" ladder for every video, whether or not the
video had those resolutions. Picking 1080p on a 720p-only upload silently
yielded 720p, because each preset's `format` is a `[height<=N]` cap that just
falls through. The list was a menu of hopes.

This asks YouTube what the ONE video in question actually ships (yt-dlp
metadata, download=False) and reports back the real resolutions plus an
estimated file size for each. Wired as a single app-wide object rather than a
method on every ViewModel because exactly one picker is open at a time, and all
three pages that own a picker (Niche Finder, Search Archive, Downloads) would
otherwise carry three copies of the same worker-thread plumbing.

A probe that fails is NOT fatal: `options` falls back to the full preset ladder,
whose height caps still resolve server-side, so the download stays possible and
only the size/availability detail is lost.
"""

import threading

from PySide6.QtCore import QObject, Property, Signal, Slot

from app.config import load_app_config
from app.core.audio_tracks import audio_tracks_from_formats
from app.core.download import (AUDIO_CODECS, DOWNLOAD_QUALITY_PRESETS,
                               VIDEO_CONTAINERS, audio_lang_for,
                               download_prefs, fetch_probe_info,
                               qualities_from_info, save_download_prefs,
                               set_audio_lang, _PROBE_AGREED,
                               _PROBE_BEST_PX, _PROBE_LIMITED, _THIN_PX)
from app.crash import log_crash
from app.i18n import tr

# Index into DOWNLOAD_QUALITY_PRESETS by key, so a probed subset can still tell
# the ViewModels which preset it means — startDownload(video_id, quality_index)
# indexes the full ladder, and the picker only ever shows part of it.
_PRESET_INDEX = {p["key"]: i for i, p in enumerate(DOWNLOAD_QUALITY_PRESETS)}


def _size_text(n):
    """Bytes as a short human string, or "" when the size is unknown."""
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


def _row(preset, size=None, exact=False):
    """One picker row. `size` None means "not probed" — the row is still
    offered, it just carries no size. `exact` marks a real reported filesize;
    anything else is an estimate and must be shown as one."""
    return {
        "key": preset["key"],
        "label": tr(preset["label"]),
        # Once probed, say what will ACTUALLY be fetched ("1920×1080 · 60fps ·
        # H.264", "VP9 → H.264", "OPUS 133 kbps → MP3 192 kbps") instead of
        # the generic preset blurb — it is also what explains a size.
        "sub": preset.get("detail") or tr(preset["sub"]),
        "icon": preset["icon"],
        "presetIndex": _PRESET_INDEX.get(preset["key"], 0),
        "sizeText": _size_text(size),
        "sizeExact": bool(exact and size),
        # Raw bytes (0 = unknown) — the v14 picker sizes its ladder bars from
        # this; the text above stays the thing the user reads.
        "sizeBytes": int(size or 0),
        "isAudio": bool(preset.get("audio_only")),
    }


def default_quality_rows():
    """The full preset ladder, sizeless. What a ViewModel's `qualityOptions`
    returns and what the picker shows if a probe fails."""
    return [_row(p) for p in DOWNLOAD_QUALITY_PRESETS]


class QualityProbeVM(QObject):
    """Live per-video quality list for the shared QualityPicker."""

    changed = Signal()
    formatChanged = Signal()
    audioChanged = Signal()            # v1.2: dub list / picked dub

    _tracksReady = Signal(str, "QVariant")  # (video_id, tracks)

    # worker → GUI bridge (auto-queued across threads)
    _done = Signal(str, "QVariant", str, bool, bool, int)
    # (video_id, rows_or_None, error, ip_limited, clients_agreed, best_px)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._video_id = ""
        self._busy = False
        self._rows = default_quality_rows()
        self._probed = False        # rows came from a real probe
        self._error = ""
        # Why the probed ceiling is low (see fetch_probe_info). `_limited`
        # means the short list is probably this IP/VPN rather than the upload,
        # so the picker offers "change your IP, then check again".
        self._limited = False
        self._agreed = False
        self._best_px = 0
        self._fmt = download_prefs()
        # (video_id, info) of the last successful extraction. Kept so that
        # switching MP4/MKV/MP3… recomputes the sizes locally — the size of
        # the finished file depends on the output format (an MP4 pick of a
        # VP9 tier is converted, an MP3 pick is re-encoded), and the old
        # picker kept showing the first format's numbers after a switch.
        self._info = (None, None)
        # v1.2: the video's audio languages (dubbed videos) + the pick
        self._tracks = []
        self._audio = ""
        self._done.connect(self._on_done)
        self._tracksReady.connect(self._on_tracks)

    # ── read-only state for QML ──────────────────────────────────────────
    @Property(str, notify=changed)
    def videoId(self):
        return self._video_id

    @Property(bool, notify=changed)
    def busy(self):
        return self._busy

    @Property(bool, notify=changed)
    def probed(self):
        """True once real per-video formats are in `options`. The picker uses
        this to decide whether it may claim the sizes are this video's."""
        return self._probed

    @Property(bool, notify=changed)
    def failed(self):
        return self._error != "" and not self._probed

    @Property(bool, notify=changed)
    def limited(self):
        """True when the probe's short list is probably this IP/VPN being
        restricted (several clients did NOT agree on the low ceiling). The
        picker shows a "change your IP, then check again" banner for this."""
        return self._limited

    @Property(bool, notify=changed)
    def thinHint(self):
        """True whenever the probe came back with only low resolutions.

        Clients agreeing on the ceiling makes the upload itself plausible, but
        a restricted IP can cap every client identically — so the picker still
        offers the IP check, worded more softly in that case."""
        return bool(self._probed and self._best_px > 0
                    and self._best_px <= _THIN_PX)

    @Property(int, notify=changed)
    def bestHeight(self):
        """Highest resolution the probe actually got, 0 when unknown."""
        return self._best_px

    @Property(str, notify=changed)
    def limitTitle(self):
        if not self.thinHint:
            return ""
        if self._limited:
            return tr("Only low qualities are being offered")
        return tr("Only up to {px}p is available").format(px=self._best_px)

    @Property(str, notify=changed)
    def limitNote(self):
        """The actionable explanation under the banner. Deliberately says
        "usually"/"may", because a genuine 360p upload produces a similar
        short list and only another probe after an IP change can tell them
        apart."""
        if not self.thinHint:
            return ""
        if not self._limited:
            return tr("This video may really top out here. If you expected a "
                      "higher quality, your IP, VPN or network can also be the "
                      "reason — change it, then check again. The current "
                      "quality downloads fine.")
        px = f"{self._best_px}p" if self._best_px else tr("low resolutions")
        return tr("YouTube answered with {px} as the best quality. This is "
                  "usually your IP, VPN or network being restricted — not the "
                  "video. Change your IP (another VPN server or network), then "
                  "check again. You can still download the current quality.").format(px=px)

    @Property("QVariantList", notify=changed)
    def options(self):
        """The rows to offer. Real resolutions once probed; the full preset
        ladder before that and after a failure."""
        return self._rows

    @Property(str, notify=changed)
    def note(self):
        """One line under the list explaining what the user is looking at —
        the difference between "these are this video's formats" and "this is
        the generic ladder" matters, and silence would imply the former."""
        if self._busy:
            return tr("Checking which qualities this video actually has…")
        if self._probed:
            if self._agreed and self._best_px:
                return tr("This video itself offers only up to {px}p. Sizes are "
                          "of the finished file; ≈ marks a conversion whose size "
                          "can only be estimated.").format(px=self._best_px)
            if self._limited:
                return tr("The list below is what YouTube answered with. Sizes "
                          "are of the finished file; ≈ marks a conversion whose "
                          "size can only be estimated.")
            return tr("Only the qualities this video actually has are listed. "
                      "Sizes are of the finished file; ≈ marks a conversion "
                      "whose size can only be estimated.")
        if self._error:
            # NOT "the best available match will be downloaded" any more. A picked
            # quality is now delivered exactly or the download fails, so promising a
            # substitute here would be the dialog contradicting the downloader.
            return tr("Couldn't read this video's formats — showing the "
                      "standard options. If the quality you pick isn't "
                      "available, the download will stop and say so.")
        return ""

    # ── output format (container / audio codec) ─────────────────────────
    # Shared by every page's picker and persisted in the app config, so the
    # last choice is pre-selected next time. The ViewModels read the saved
    # choice when a download starts (download.with_container).
    @Property("QVariantList", notify=formatChanged)
    def videoFormats(self):
        return [{"key": c["key"], "label": c["label"], "sub": tr(c["sub"])}
                for c in VIDEO_CONTAINERS]

    @Property("QVariantList", notify=formatChanged)
    def audioFormats(self):
        return [{"key": c["key"], "label": c["label"], "sub": tr(c["sub"])}
                for c in AUDIO_CODECS]

    @Property(str, notify=formatChanged)
    def videoFormat(self):
        return self._fmt["video"]

    @Property(str, notify=formatChanged)
    def audioFormat(self):
        return self._fmt["audio"]

    @Slot(str)
    def setVideoFormat(self, key):
        key = (key or "").lower()
        if key and key != self._fmt["video"]:
            save_download_prefs(video=key)
            self._fmt = download_prefs()
            self.formatChanged.emit()
            self._recompute()

    @Slot(str)
    def setAudioFormat(self, key):
        key = (key or "").lower()
        if key and key != self._fmt["audio"]:
            save_download_prefs(audio=key)
            self._fmt = download_prefs()
            self.formatChanged.emit()
            self._recompute()

    # ── audio track (dubbed videos, v1.2) ────────────────────────────────
    @Property("QVariantList", notify=audioChanged)
    def audioTracks(self):
        """[{key, lang, code, name, native, nameFa, kind, kbps, rtl}], the
        original first. Empty for a single-language video."""
        return self._tracks

    @Property(str, notify=audioChanged)
    def audioTrack(self):
        """Picked track key: "" = original, else a language code."""
        return self._audio

    @Slot(str)
    def setAudioTrack(self, key):
        key = str(key or "")
        if key and not any(t.get("key") == key for t in self._tracks):
            return
        if key == self._audio:
            return
        self._audio = key
        set_audio_lang(self._video_id, key)
        self.audioChanged.emit()
        self._recompute()          # sizes follow the picked track

    @Slot(str, "QVariant")
    def _on_tracks(self, video_id, tracks):
        if video_id != self._video_id:
            return
        self._tracks = list(tracks or [])
        keys = {t.get("key") for t in self._tracks}
        if self._audio not in keys:
            self._audio = ""
            set_audio_lang(self._video_id, "")
        self.audioChanged.emit()

    def _rows_for(self, info):
        ok, opts, err = qualities_from_info(
            info, self._fmt["video"], self._fmt["audio"],
            audio_lang=audio_lang_for(self._video_id))
        if not ok:
            log_crash("QualityProbeVM: no rows: " + str(err))
            return None, err or "probe failed"
        return [_row(p, p.get("size"), p.get("size_exact")) for p in opts], ""

    def _recompute(self):
        """Re-size the rows for a new output format, from the cached
        extraction (no network). Off the GUI thread: yt-dlp's selection is
        quick but not free, and the dialog must not stutter on a click."""
        vid, info = self._info
        if not info or vid != self._video_id:
            return
        limited = bool(info.get(_PROBE_LIMITED))
        agreed = bool(info.get(_PROBE_AGREED))
        best_px = int(info.get(_PROBE_BEST_PX) or 0)
        self._busy = True
        self.changed.emit()

        def worker(_vid=vid, _info=info):
            try:
                rows, err = self._rows_for(_info)
                self._done.emit(_vid, rows, err, limited, agreed, best_px)
            except Exception as exc:      # noqa: BLE001
                log_crash("QualityProbeVM._recompute failed: " + str(exc))
                self._done.emit(_vid, None, str(exc), limited, agreed, best_px)

        threading.Thread(target=worker, daemon=True).start()

    # ── actions ──────────────────────────────────────────────────────────
    @Slot(str)
    def start(self, video_id):
        """Probe one video, by id. Called by the picker as it opens.

        Re-probing the video already loaded is a no-op: reopening the picker on
        the same card should not spend another extraction, and the format list
        does not change minute to minute.
        """
        self._probe(video_id, force=False)

    @Slot()
    def refresh(self):
        """Ask YouTube again for the current video, ignoring every cache.

        The picker's "check again" after the user changes IP/VPN. A thin answer
        is not cached in the first place, but the cached rich answer (or a
        previously agree-on-360p verdict) would otherwise short-circuit the
        probe and make the button a no-op."""
        self._probe(self._video_id, force=True)

    def _probe(self, video_id, force=False):
        video_id = (video_id or "").strip()
        if not video_id:
            self.reset()
            return
        if not force and video_id == self._video_id and (self._busy or self._probed):
            return

        self._video_id = video_id
        self._busy = True
        self._probed = False
        self._error = ""
        self._limited = False
        self._agreed = False
        self._best_px = 0
        self._tracks = []
        self._audio = audio_lang_for(video_id)
        self.audioChanged.emit()
        # Keep the generic ladder on screen while probing rather than blanking
        # the list — the dialog would otherwise collapse and re-expand.
        self._rows = default_quality_rows()
        self.changed.emit()

        cfg = load_app_config()
        proxy = (cfg.get("ai_proxy", "") or "").strip()
        cookies = (cfg.get("yt_cookies_browser", "") or "").strip().lower()
        url = f"https://www.youtube.com/watch?v={video_id}"

        def worker(_vid=video_id, _url=url, _proxy=proxy, _cookies=cookies,
                   _force=force):
            try:
                info, err = fetch_probe_info(
                    _url, proxy_url=_proxy, cookies_browser=_cookies,
                    use_cache=not _force)
                if not info:
                    self._done.emit(_vid, None, err or "probe failed",
                                    False, False, 0)
                    return
                limited = bool(info.get(_PROBE_LIMITED))
                agreed = bool(info.get(_PROBE_AGREED))
                best_px = int(info.get(_PROBE_BEST_PX) or 0)
                # only cache it if the user is still on this video — a slow
                # probe for A must not overwrite B's extraction
                if _vid == self._video_id:
                    self._info = (_vid, info)
                try:
                    tracks = audio_tracks_from_formats(info.get("formats"))
                except Exception as exc:  # noqa: BLE001 — optional extra
                    log_crash("QualityProbeVM tracks: " + str(exc))
                    tracks = []
                self._tracksReady.emit(_vid, tracks)
                rows, err = self._rows_for(info)
                self._done.emit(_vid, rows, err, limited, agreed, best_px)
            except Exception as exc:      # noqa: BLE001 — reported, not raised
                log_crash("QualityProbeVM.start failed: " + str(exc))
                self._done.emit(_vid, None, str(exc), False, False, 0)

        threading.Thread(target=worker, daemon=True).start()

    @Slot()
    def reset(self):
        """Forget the current probe. Called when the picker closes so the next
        open starts clean instead of flashing the previous video's list."""
        self._video_id = ""
        self._busy = False
        self._probed = False
        self._error = ""
        self._limited = False
        self._agreed = False
        self._best_px = 0
        self._info = (None, None)
        self._rows = default_quality_rows()
        self._tracks = []
        self._audio = ""
        self.changed.emit()
        self.audioChanged.emit()

    @Slot(str, "QVariant", str, bool, bool, int)
    def _on_done(self, video_id, rows, error, limited, agreed, best_px):
        # A stale result — the user moved on to another card while this ran.
        if video_id != self._video_id:
            return
        self._busy = False
        self._limited = bool(limited) and bool(rows)
        self._agreed = bool(agreed) and bool(rows)
        self._best_px = int(best_px or 0)
        if rows:
            self._rows = rows
            self._probed = True
            self._error = ""
        else:
            self._rows = default_quality_rows()
            self._probed = False
            self._error = error or "probe failed"
            self._limited = False
            self._agreed = False
        self.changed.emit()
