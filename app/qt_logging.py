"""app.qt_logging - Youtube Scrapper."""

import sys

from PySide6.QtCore import QtMsgType

# Qt categories that are pure noise on Windows and drown out anything real.
#
# "qt.text.font.db: OpenType support missing for <font>, script 11" is printed
# once per candidate fallback font per script, the first time Qt has to shape
# a run it can't handle with the requested family — scripts 11/12 are Arabic
# and Hebrew, which every Latin font in the fallback chain legitimately lacks.
# It is harmless (Qt then picks a font that does work), but it prints 20-30
# lines at startup and buries actual warnings. Filtered here rather than
# silenced globally, so everything else Qt has to say still reaches the
# console.
#
# "qt.qpa.mime: Retrying to obtain clipboard." is the Windows clipboard being
# briefly locked by whichever process last wrote to it — an IME candidate
# window, a clipboard manager, or the app itself pasting. Qt retries and
# succeeds; the line is printed once per attempt, so a few pastes in a row fill
# the console with it. It is not an error and there is nothing to fix on our
# side, so it is muted for the same reason as the font warnings below.
_QT_MUTED_CATEGORIES = ("qt.text.font.db", "qt.qpa.mime")

# Same idea, but matched by message text instead of category — Qt logs these
# uncategorized. "DirectWrite: CreateFontFaceFromHDC() failed ... for
# QFontDef(Family="8514oem" ...)" / "Fixedsys" / "Terminal" / "System" etc.
# happens while Qt's Windows font engine walks every font Windows *reports*
# as installed to build a fallback chain for a requested weight/size. Those
# particular names are ancient GDI stock bitmap fonts (non-scalable raster
# fonts, not real TrueType/OpenType files), which DirectWrite simply cannot
# turn into a font face — Qt logs a warning and skips that candidate, same
# as always. It has nothing to do with the app's own bundled fonts (loaded
# via QFontDatabase.addApplicationFont, a completely different path) and
# nothing is missing on screen; it just repeats on every startup/theme
# rebuild and buries real warnings, so it's muted the same way as above.
_QT_MUTED_SUBSTRINGS = ("CreateFontFaceFromHDC() failed",)

# Set once the app starts quitting (see note_shutting_down). While the QML
# engine tears itself down, every binding that reads a context property
# (Niche.*, Studio.*, Dashboard.* …) re-evaluates against objects that are
# already half-destroyed and logs "TypeError: Cannot read property 'x' of
# null" — dozens of lines, all after the window is already gone. It looks
# alarming in a terminal but means nothing: performance is unaffected, no
# data is lost, and the same teardown happens on every clean exit. Muted
# ONLY after shutdown starts, so the identical message during a live session
# (a genuinely missing context property) still reaches the console.
_SHUTTING_DOWN = False
# v3.53: the same class of teardown noise comes in three wordings, all of them
# "a binding re-evaluated after its context property was released":
#   TypeError: Cannot read property 'x' of null      (the original one)
#   TypeError: Cannot call method 'tr' of null       (I18n.tr in a label)
#   TypeError: Value is null and could not be converted to an object
#                                                  (Theme.some_colour)
# The last two printed ~1000-7000 lines on exit once a page with 24 cards was
# alive, burying anything real. All three are muted ONLY after aboutToQuit, so
# a genuinely missing context property during a live session still shows.
_QT_TEARDOWN_SUBSTRINGS = ("Cannot read propert",
                           "Cannot call method",
                           "Value is null and could not be converted")


def note_shutting_down():
    """Arm the teardown filter. Connect to QGuiApplication.aboutToQuit."""
    global _SHUTTING_DOWN
    _SHUTTING_DOWN = True


def silence_ffmpeg_logs():
    """Raise libav's log threshold to FATAL for the in-process media backend.

    Qt's FFmpeg backend prints the whole format dump of every opened file
    and harmless decoder / Media-Foundation notices straight to stderr,
    bypassing qInstallMessageHandler — a handful of card hovers was enough to
    bury the console in lines the user can do nothing about. Playback failures
    still reach the UI through MediaPlayer.error, so only the raw stderr
    chatter is dropped.

    Windows only: the DLL has to be the exact copy the multimedia plugin
    loads, and both live in the PySide6 package there. LoadLibrary returns the
    already-loaded module, so this level applies to the plugin as well.
    """
    if sys.platform != "win32":
        return
    try:
        import ctypes
        import glob
        import os

        import PySide6

        root = os.path.dirname(getattr(PySide6, "__file__", "") or "")
        dlls = glob.glob(os.path.join(root, "avutil-*.dll"))
        if dlls:
            ctypes.WinDLL(dlls[0]).av_log_set_level(8)   # AV_LOG_FATAL
    except Exception:      # noqa: BLE001 — logging is best-effort
        pass


def _qt_message_filter(mode, context, message):
    text = message or ""
    category = getattr(context, "category", "") or ""
    if (category in _QT_MUTED_CATEGORIES
            or text.startswith(_QT_MUTED_CATEGORIES)
            or any(s in text for s in _QT_MUTED_SUBSTRINGS)):
        return
    if _SHUTTING_DOWN and any(s in text for s in _QT_TEARDOWN_SUBSTRINGS):
        return
    stream = sys.stderr
    if stream is None:
        return
    try:
        label = {QtMsgType.QtDebugMsg: "qt.debug",
                 QtMsgType.QtInfoMsg: "qt.info",
                 QtMsgType.QtWarningMsg: "qt.warning",
                 QtMsgType.QtCriticalMsg: "qt.critical",
                 QtMsgType.QtFatalMsg: "qt.fatal"}.get(mode, "qt")
        stream.write(f"[{label}] {text}\n")
        stream.flush()
    except Exception:
        pass
