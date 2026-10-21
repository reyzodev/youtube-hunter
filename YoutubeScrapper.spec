# -*- mode: python ; coding: utf-8 -*-
"""
YoutubeScrapper.spec — PyInstaller build recipe for YouTube Hunter.

Goal: a build that opens on any Windows PC WITHOUT errors, with no pip,
no Python install, and no internet needed on the target machine.

Build with:
    python -m PyInstaller --clean --noconfirm YoutubeScrapper.spec

Output: dist/YouTubeHunter/  (an "onedir" folder — copy the WHOLE folder, or
use the Inno Setup installer in installer.iss to wrap it into setup.exe).

Entry point is main_qml.py (the QML interface the app actually runs).
The legacy QWidgets main.py is NOT bundled.

Why onedir and not onefile:
  * onefile unpacks ~200MB to a temp dir on every launch → slow start and
    the #1 cause of antivirus false-positives / "won't open" reports.
  * onedir launches instantly and is far less likely to be quarantined.
"""

import glob
import os
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

# ── bundled data files ───────────────────────────────────────────────────
datas = []

# App's own resources (read via app.paths.asset_path / BASE_DIR). This includes
# assets/bin/ffprobe.exe — yt-dlp needs ffprobe (the "Audio only" mp3
# conversion dies without it), and imageio-ffmpeg ships only ffmpeg. At runtime
# app.core.runtime_deps stages this ffprobe next to imageio's ffmpeg in a
# directory it hands yt-dlp as ffmpeg_location, which is how yt-dlp finds both.
datas += [("fonts", "fonts")]
datas += [("assets", "assets")]

# The whole QML interface (Main.qml, pages/, components/, Tokens.qml,
# Utils.js, qmldir). main_qml.py loads it via asset_path("app", "qml") at
# runtime — without this bundled, the built exe opens to "QML failed to
# load Main.qml" and exits. This was the missing piece.
datas += [("app/qml", "app/qml")]

# imageio-ffmpeg ships a real ffmpeg .exe inside its package; collecting its
# data files bundles that binary so video download/mux works fully offline.
datas += collect_data_files("imageio_ffmpeg")

# google-api-python-client uses "static discovery": it reads the YouTube API
# description from JSON files shipped inside googleapiclient/discovery_cache/
# documents/. Without these bundled, build("youtube","v3",...) fails on the
# target machine. collect_data_files grabs every .json in the package.
#
# ...but that package carries ~600 discovery documents (~100 MB) for APIs this
# app will never call, and `discovery_cache.get_static_doc()` opens exactly
# "<service>.<version>.json" — one file. Shipping the one file and dropping the
# other 599 takes ~100 MB off the customer's download for no behaviour change.
_gapi_data = collect_data_files("googleapiclient")
datas += [d for d in _gapi_data
          if "discovery_cache" not in d[0].replace("\\", "/")
          or os.path.basename(d[0]).startswith("youtube.v3.")]

# yt-dlp solves YouTube's JS download challenge with a solver script shipped
# (minified) inside yt_dlp_ejs. Bundling it means the challenge is solved
# offline once the user has a deno runtime — nothing else to fetch at runtime.
datas += collect_data_files("yt_dlp_ejs")

# ── hidden imports (things PyInstaller's static analysis can miss) ─────────
hiddenimports = []
# yt-dlp lazy-imports hundreds of extractor modules by string name; without
# collecting them the download feature breaks with ModuleNotFoundError.
hiddenimports += collect_submodules("yt_dlp")
hiddenimports += collect_submodules("yt_dlp_ejs")
hiddenimports += collect_submodules("googleapiclient")
hiddenimports += collect_submodules("google")
hiddenimports += collect_submodules("app.qml_backend")
hiddenimports += [
    "app.qml_backend.win_taskbar",
    "app.qml_backend.desktop_notifier",
    "winsound",            # v3.40 away-notice chime (stdlib, Windows only)
    # The Persian string table is imported by app.i18n at module level, so static
    # analysis normally finds it — but it is the one file whose absence turns
    # every label in the app English-only in a shipped build, and listing it
    # explicitly costs nothing.
    "app.locales.fa",
    "youtube_transcript_api",
    "openpyxl",
    "shiboken6",
    "sqlite3",
]
# AI Chat reads PDFs through pypdf when it is installed (optional dependency).
try:
    hiddenimports += collect_submodules("pypdf")
except Exception:
    pass

a = Analysis(
    ["main_qml.py"],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # Trim heavy stuff we never use to keep the build small and clean.
    excludes=[
        "tkinter", "matplotlib", "numpy", "pandas", "scipy",
        "PySide6.QtWebEngineCore", "PySide6.QtWebEngineWidgets",
        "PySide6.Qt3DCore", "PySide6.QtDataVisualization",
        "PySide6.QtCharts", "PySide6.QtQuick3D", "PySide6.QtBluetooth",
    ],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# ── trim: Chromium ──────────────────────────────────────────────────────
# PySide6's Qt hook drags Qt6WebEngineCore.dll into the bundle — 195 MB, by far
# the single biggest file in the build — because the QtWebEngine QML modules
# declare it as a dependency. This app never touches WebEngine: no QML file
# imports QtWebEngine, and the Python side lists PySide6.QtWebEngine* in
# `excludes` above. But `excludes` only drops PYTHON modules; a DLL that the Qt
# hook decided to collect has to be filtered out of the tables after Analysis.
#
# Removing it takes the onedir build from ~790 MB to ~590 MB.
_WEBENGINE_TAGS = ("webengine", "qtwebview")
def _is_webengine(name):
    low = str(name).replace("\\", "/").lower()
    return any(tag in low for tag in _WEBENGINE_TAGS)

# ── trim: the other 599 Google API descriptions ────────────────────────
# _pyinstaller_hooks_contrib's hook-googleapiclient.model.py does
# `collect_data_files('googleapiclient.discovery_cache')`, which copies the whole
# discovery_cache/documents folder (~600 JSON files, ~100 MB) into the bundle.
# That happens DURING Analysis, so filtering the `datas` list up top is not
# enough — it has to be filtered again here, once the hook has had its turn.
#
# The app only ever builds the YouTube v3 service, and
# `discovery_cache.get_static_doc()` opens exactly "<service>.<version>.json",
# so one file is all that is needed. Keeping only that one takes another ~100 MB
# off the customer's download.
_DISCOVERY_DIR = "googleapiclient/discovery_cache/documents"
def _is_dead_discovery_doc(entry):
    src = str(entry[0]).replace("\\", "/").lower()
    dst = str(entry[1]).replace("\\", "/").lower()
    if _DISCOVERY_DIR not in dst and _DISCOVERY_DIR not in src:
        return False
    return not src.endswith("/youtube.v3.json")

_kept_binaries = [b for b in a.binaries if not _is_webengine(b[0])]
_kept_datas = [d for d in a.datas
               if not _is_webengine(d[0]) and not _is_dead_discovery_doc(d)]
_dropped_webengine = len(a.binaries) - len(_kept_binaries), len(a.datas) - len(_kept_datas)
_dropped_docs = sum(1 for d in a.datas if _is_dead_discovery_doc(d))
print("trimmed WebEngine: dropped {} binaries and {} data files".format(*_dropped_webengine))
print("trimmed discovery docs: {} data files dropped".format(_dropped_docs))
a.binaries = _kept_binaries
a.datas = _kept_datas

# ── Qt Multimedia backend plugins (v3.40.2) ─────────────────────────────
# Video playback lives entirely in QML (pages/CutterPage.qml →
# components/VideoPlayer.qml), so nothing imports PySide6.QtMultimedia from
# Python. PyInstaller's Qt hook only collects a module's plugins when the
# module is imported from Python, so the backend plugin was never bundled:
# Qt logged "No QtMultimedia backends found" and every video preview stayed
# black — in the packaged build only, never when running from source.
# Collect the backends and the FFmpeg DLLs they link against by hand.
_PYSIDE_DIR = os.path.dirname(os.path.abspath(__import__("PySide6").__file__))
_mm_plugins = glob.glob(os.path.join(_PYSIDE_DIR, "plugins", "multimedia", "*.dll"))
for _plugin in _mm_plugins:
    a.binaries.append(("PySide6/plugins/multimedia/" + os.path.basename(_plugin),
                       _plugin, "BINARY"))
_ffmpeg_dlls = []
for _lib in ("avcodec", "avformat", "avutil", "swresample", "swscale"):
    for _dll in glob.glob(os.path.join(_PYSIDE_DIR, _lib + "-*.dll")):
        a.binaries.append(("PySide6/" + os.path.basename(_dll), _dll, "BINARY"))
        _ffmpeg_dlls.append(_dll)
print("added multimedia backends: {} plugin(s), {} ffmpeg dll(s)".format(
    len(_mm_plugins), len(_ffmpeg_dlls)))

# ── trim: Qt modules this app can never load ────────────────────────────
# PySide6's Qt hook collects every Qt module it can see, not the ones the app
# actually imports. The complete list of QML modules app/qml imports is
# QtQuick, QtQuick.Controls.Basic, QtQuick.Dialogs, QtQuick.Effects,
# QtQuick.Layouts, QtQuick.Shapes, QtQuick.Window, QtMultimedia and
# NicheScope (the app's own QML module) — and the Python side uses only QtCore, QtGui, QtWidgets, QtQml,
# QtQuick, QtNetwork, QtSvg, QtMultimedia (plus QtOpenGL, which PySide6's own
# QtQuick module imports, so that one must stay even though nothing here names
# it).
#
# Everything below was checked against the real load-time dependency graph of
# the DLLs that ARE kept — `.workbuddy-ai/qt-trim-analysis.py` walks the PE
# import tables of the whole bundle and proves no kept module depends on a
# dropped one. That matters: dropping a DLL that Qt6Quick statically links
# would stop the process from starting at all, not fail politely.
#
# Worth ~45 MB of DLLs + ~13 MB of QML modules + ~8 MB of Qt's own .qm
# translation files, none of which the app ever opens.
_DEAD_QT_DLL_PREFIXES = (
    "qt63d",                     # Qt 3D — Animation/Core/Extras/Input/Logic/Quick/Render
    "qt6charts", "qt6datavisualization", "qt6graphs",
    "qt6pdf",
    "qt6location", "qt6positioning",
    "qt6remoteobjects", "qt6scxml", "qt6sensors", "qt6statemachine",
    "qt6texttospeech", "qt6virtualkeyboard",
    "qt6webchannel", "qt6websockets", "qt6webview",
    "qt6test", "qt6concurrent",
    "qt6quick3d", "qt6quickparticles", "qt6quicktest", "qt6quicktimeline",
    "qt6quickshapesdesignhelpers", "qt6spatialaudio",
    "qt6multimediawidgets", "qt6openglwidgets", "qt6qmlxmllistmodel",
    # Qt Quick Controls styles other than the one the app imports
    # (`import QtQuick.Controls.Basic` in every page).
    "qt6quickcontrols2imagine", "qt6quickcontrols2material",
    "qt6quickcontrols2universal", "qt6quickcontrols2fusion",
    "qt6quickcontrols2fluentwinui3", "qt6quickcontrols2windowsstyleimpl",
    "qt6labs",                   # Qt.labs.* — no QML file imports one
)

_DEAD_QML_PATHS = (
    "pyside6/qml/qt3d", "pyside6/qml/qtcharts",
    "pyside6/qml/qtdatavisualization", "pyside6/qml/qtgraphs",
    "pyside6/qml/qtlocation", "pyside6/qml/qtpositioning",
    "pyside6/qml/qtremoteobjects", "pyside6/qml/qtscxml",
    "pyside6/qml/qtsensors", "pyside6/qml/qttest",
    "pyside6/qml/qttexttospeech", "pyside6/qml/qtwebchannel",
    "pyside6/qml/qtwebsockets", "pyside6/qml/qtquick3d",
    "pyside6/qml/qt5compat", "pyside6/qml/qt/labs",
    "pyside6/qml/qtquick/pdf", "pyside6/qml/qtquick/particles",
    "pyside6/qml/qtquick/timeline", "pyside6/qml/qtquick/virtualkeyboard",
    "pyside6/qml/qtquick/scene2d", "pyside6/qml/qtquick/scene3d",
    "pyside6/qml/qtquick/vectorimage", "pyside6/qml/qtquick/localstorage",
    "pyside6/qml/qtquick/nativestyle", "pyside6/qml/qtquick/tooling",
    "pyside6/qml/qtquick/controls/fusion", "pyside6/qml/qtquick/controls/imagine",
    "pyside6/qml/qtquick/controls/material",
    "pyside6/qml/qtquick/controls/universal",
    "pyside6/qml/qtquick/controls/windows",
    "pyside6/qml/qtquick/controls/designer",
    # QML debugger / profiler plugins: unused at runtime, and they open a
    # listening socket the app has no business opening on a customer machine.
    "pyside6/plugins/qmltooling",
)


def _norm(entry):
    return str(entry).replace("\\", "/").lower()


def _is_dead_qt(entry):
    src, dst = _norm(entry[0]), _norm(entry[1])
    for key in (src, dst):
        base = key.rsplit("/", 1)[-1]
        if base.endswith(".dll") and base.startswith(_DEAD_QT_DLL_PREFIXES):
            return True
        for dead in _DEAD_QML_PATHS:
            if key.startswith(dead + "/") or ("/" + dead + "/") in key:
                return True
    return False


def _is_dead_translation(entry):
    """Qt's own .qm files. The app carries its own Persian strings in
    app/locales/fa.py and never installs a QTranslator, so only the two
    languages it could plausibly need are kept — the other 140 are 8 MB of
    files that are never opened."""
    low = _norm(entry[1])
    if not low.endswith(".qm") or "/translations/" not in low:
        return False
    base = low.rsplit("/", 1)[-1]
    return not (base.endswith("_fa.qm") or base.endswith("_en.qm"))


_before = sum(len(t) for t in (a.binaries, a.datas))
a.binaries = [b for b in a.binaries if not _is_dead_qt(b)]
a.datas = [d for d in a.datas
           if not _is_dead_qt(d) and not _is_dead_translation(d)]
print("trimmed dead Qt modules: {} entries dropped ({} -> {})".format(
    _before - sum(len(t) for t in (a.binaries, a.datas)),
    _before, sum(len(t) for t in (a.binaries, a.datas))))

# Windows version resource: Explorer -> Properties -> Details, and one of the
# signals SmartScreen/antivirus weigh. See version_info.txt.
_version_file = "version_info.txt" if os.path.exists("version_info.txt") else None

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="YouTubeHunter",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,                 # UPX compression trips antivirus — keep it off
    console=False,             # windowed app, no console window
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    version=_version_file,
    icon="assets/app.ico" if os.path.exists("assets/app.ico") else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="YouTubeHunter",
)
