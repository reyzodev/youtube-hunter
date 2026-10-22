"""main_qml - YouTube Hunter (QML front-end).

The app entry point. It builds NO QWidgets: a QGuiApplication drives a
QQmlApplicationEngine that loads app/qml/Main.qml (a frameless Window). The
Python side exposes:

  * App      (AppController)  — navigation, theme, language, quota
  * Theme    (ThemeBridge)    — live semantic colour palette
  * I18n     (I18nBridge)     — tr() + RTL flag
  * Fonts    (FontBridge)     — language/weight-aware font families
  * Icons    (IconBridge)     — remixicon glyph lookup
  * Dashboard(DashboardVM)    — the first migrated page's ViewModel

Run:  python main_qml.py
"""


def _install_crash_guard(notify=None):
    """Keep a Python exception raised inside a Qt-invoked callback from taking
    the whole process down.

    In PySide6 an exception that escapes a slot, a property getter or an event
    handler can abort the interpreter outright — to the user that looks like the
    window simply vanishing mid-action, with nothing printed and nothing logged.
    main.py has carried this guard since the QWidgets build; the QML entry point
    never did, so every such escape here was an unexplained disappearance.

    Two differences from main.py's version:
      * No QMessageBox — this process is a QGuiApplication and has no QtWidgets.
        `notify(summary)` is passed in instead and routes through the QML
        message dialog, which is already wired to Dashboard.popup.
      * Worker-thread exceptions go through the same callback, which is safe
        because it emits a Qt signal (queued onto the GUI thread) rather than
        touching the UI directly.
    """
    _enable_faulthandler()

    def _report(summary):
        if notify is None:
            return
        try:
            notify(str(summary))
        except Exception:
            pass

    def handle_exception(exc_type, exc_value, exc_tb):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_tb)
            return
        msg = "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
        log_crash("Unhandled exception (main thread):\n" + msg)
        if sys.stderr is not None:      # None in windowed (no-console) builds
            try:
                sys.stderr.write(msg)
            except Exception:
                pass
        _report(exc_value)

    sys.excepthook = handle_exception

    def handle_thread_exception(args):
        if issubclass(args.exc_type, SystemExit):
            return
        msg = "".join(traceback.format_exception(
            args.exc_type, args.exc_value, args.exc_traceback))
        thread_name = getattr(args.thread, "name", "?")
        log_crash(f"Unhandled exception (worker thread {thread_name}):\n{msg}")
        _report(args.exc_value)

    threading.excepthook = handle_thread_exception

import os
import sys
import threading
import traceback

from PySide6.QtCore import QTimer, QUrl, Qt, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterSingletonType

from app import i18n
from app.config import load_app_config
from app.core.db.archive import init_archive_db
from app.core.db.chat import init_chat_db
from app.core.db.clips import init_clips_db
from app.core.db.content_lab import init_content_lab_db
from app.core.db.downloads import init_downloads_db
from app.core.db.ideas import init_ideas_db
from app.core.db.insights import init_insights_db
from app.core.quota import init_niche_db
from app.crash import CRASH_LOG_PATH, _enable_faulthandler, log_crash
from app.i18n import tr
from app.paths import asset_path
from app.qt_logging import _qt_message_filter, note_shutting_down
from app.ui.fonts import load_fonts
from app.ui.theme import apply_theme
from app.ui.brand import window_icon as brand_window_icon

from app.qml_backend.app_controller import AppController
from app.qml_backend.cursor_guard import CursorGuard
from app.qml_backend.desktop_notifier import DesktopNotifier, announce
from app.qml_backend.file_drag import FileDragBridge
from app.qml_backend.font_bridge import FontBridge
from app.qml_backend.text_layout_bridge import TextLayoutBridge
from app.qml_backend.i18n_bridge import I18nBridge
from app.qml_backend.icon_bridge import IconBridge
from app.qml_backend.svg_icon_provider import SvgIconProvider
from app.qml_backend.image_provider import ThumbImageProvider
from app.qml_backend.theme_bridge import ThemeBridge
from app.qml_backend.vm.archive_vm import ArchiveVM
from app.qml_backend.vm.chat_vm import ChatVM
from app.qml_backend.vm.content_lab_vm import ContentLabVM
from app.qml_backend.vm.cutter_vm import CutterVM
from app.qml_backend.vm.dashboard_vm import DashboardVM
from app.qml_backend.vm.deno_vm import DenoVM
from app.qml_backend.vm.downloads_vm import DownloadsVM
from app.qml_backend.vm.geo_vm import GeoVM
from app.qml_backend.vm.history_vm import HistoryVM
from app.qml_backend.vm.ideas_vm import IdeasVM
from app.qml_backend.vm.insights_vm import InsightsVM
from app.qml_backend.vm.monetize_vm import MonetizeVM
from app.qml_backend.vm.niche_vm import NicheVM
from app.qml_backend.vm.notifications_vm import NotificationsVM
from app.qml_backend.vm.update_vm import UpdateVM
from app.qml_backend.vm.quality_probe import QualityProbeVM
from app.qml_backend.vm.settings_vm import SettingsVM
from app.qml_backend.vm.studio_vm import StudioVM
from app.qml_backend.vm.usage_vm import UsageVM
from app.qml_backend.web_bridge import WebBridge, bridge_running
from app.qml_backend.vm.extension_setup_vm import ExtensionSetupVM


def main():
    # v1.1.2: keep the UI responsive while a worker thread does heavy Python
    # (yt-dlp's link read, the cutter's stream pick). The GUI thread needs the
    # GIL for every QML -> Python property read; with CPython's default 5 ms
    # switch interval a busy worker made each read wait up to 5 ms, so one
    # frame with a few hundred reads stalled for SECONDS ("the cutter freezes
    # for 1-4 s when a cut starts"). 1 ms hands the GIL back 5x sooner at a
    # negligible cost to the worker.
    try:
        sys.setswitchinterval(0.001)
    except Exception:  # noqa: BLE001
        pass

    # v3.42 "Hunter on YouTube": the browser extension wakes the app through
    # the youtubehunter:// link (registered by the installer) when nothing is
    # answering on the bridge port. Such a launch starts MINIMISED — the user
    # is on YouTube and only wants the download — and, if a copy is already
    # running after all, exits at once instead of opening a second window.
    _args = [a.lower() for a in sys.argv[1:]]
    launch_hidden = ("--background" in _args
                     or any(a.startswith("youtubehunter:") for a in _args))
    if launch_hidden and bridge_running():
        return
    # QtMultimedia software-decode fallback (same rationale as main.py): must
    # be set before anything touches Qt/QtMultimedia.
    os.environ.setdefault("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "")
    # Support window: Chromium's own net-stack logging (e.g. "ssl_client_socket
    # handshake failed ... net_error -100" when a tracker/CDN on the donation
    # page is filtered) goes straight to stderr and is harmless. Keep only
    # FATAL. Appended, so flags already set in the environment are kept.
    _cf = os.environ.get("QTWEBENGINE_CHROMIUM_FLAGS", "")
    if "--log-level" not in _cf:
        os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] = (_cf + " --log-level=3").strip()

    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(
        Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    # Own taskbar identity on Windows, so a source run shows the YouTube Hunter
    # icon instead of python.exe's.
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                "YouTubeHunter.App")
        except Exception:
            pass
    app = QGuiApplication(sys.argv)
    # Branding: YouTube Hunter name. The window / taskbar icon is set once the
    # theme is applied (below), because it is painted in the accent colour.
    app.setApplicationName("YouTube Hunter")
    app.setApplicationDisplayName("YouTube Hunter")
    app.setWindowIcon(QIcon(asset_path("assets", "app.ico")))
    # From here on, "Cannot read property ... of null" binding warnings are
    # the QML engine talking about its own teardown — the window is already
    # gone and every context property is half-destroyed — so the log filter
    # stops printing them instead of dumping ~200 scary-looking lines that
    # mean nothing. Identical messages during a live session still show.
    app.aboutToQuit.connect(note_shutting_down)

    # ── the in-app donation page (Support window) ──────────────────────
    # DonateOverlay hosts a live WebEngineView, and QtWebEngine has to be
    # initialised before the QML engine loads that file. It is also expensive:
    # measured on a cold start, initialising Chromium costs ~260 MB of resident
    # memory before a single page is loaded (118 MB → 377 MB). So it only
    # happens when there is a page to show — `donate_url` in config.json or
    # DONATE_URL in app/constants.py. With no address the Support window does
    # not exist at all: no Chromium, no view, no cost, and the Donate pill hides
    # itself. If the module is missing (a trimmed build) the pill falls back to
    # the system browser instead.
    try:
        from app.qml_backend.app_controller import resolved_donate_url
        if resolved_donate_url():
            from PySide6.QtWebEngineQuick import QtWebEngineQuick
            QtWebEngineQuick.initialize()
    except Exception as _exc:                    # noqa: BLE001 — optional
        log_crash("QtWebEngine unavailable, Donate falls back to the "
                  "browser: " + str(_exc))

    cfg = load_app_config()
    # The interface is English only; a "language" value left in an older config
    # is ignored.
    i18n.LANG = "en"
    app.setLayoutDirection(Qt.LeftToRight)
    # Installed before apply_theme, like main.py: the theme rebuild is the first
    # thing that makes Qt walk the font database, and the filter is what keeps
    # those 20-30 harmless DirectWrite lines from burying real warnings.
    qInstallMessageHandler(_qt_message_filter)
    apply_theme(cfg.get("theme", "system"), cfg.get("accent", "crimson"))
    load_fonts()

    # The QML pages write to the same SQLite files the legacy app does (search
    # archive / favorites, AI Ideas, downloads, quota), so the schemas have to
    # exist before any ViewModel touches them — main.py does this in
    # MainWindow.__init__, which never runs here.
    init_niche_db()
    init_archive_db()
    init_ideas_db()
    # The AI Ideas page persists its generated blueprints into the content_lab
    # tables (they live in the same ideas.db file), so that schema has to exist
    # before IdeasVM touches it.
    init_content_lab_db()
    init_downloads_db()
    init_clips_db()
    # Niche Scan caches one report per analysed result set in the same
    # file; InsightsVM reads it in its constructor, so the schema has to exist.
    init_insights_db()
    # AI Chat: threads, messages and sources live in the same ideas.db.
    init_chat_db()

    # ---- bridges + ViewModels ----
    theme_bridge = ThemeBridge()
    # Logo in the taskbar / alt-tab follows the theme accent, like the in-app
    # mark does. Re-painted on every palette swap (theme or accent change).
    # The mark only uses the accent pair, so a dark/light swap leaves it
    # untouched: skip the 7-size repaint + setWindowIcon (which Windows fans
    # out to every top-level window) unless the accent really changed. It used
    # to run inside the theme swap frame and added to the switch hitch.
    _icon_key = [None]

    def _refresh_window_icon():
        from app.ui import theme as _th
        key = (_th.CLR.get("logo_grad_in"), _th.CLR.get("logo_grad_out"))
        if key == _icon_key[0]:
            return
        try:
            app.setWindowIcon(brand_window_icon())
            _icon_key[0] = key
        except Exception:
            pass
    _refresh_window_icon()
    theme_bridge.changed.connect(_refresh_window_icon)
    i18n_bridge = I18nBridge()
    font_bridge = FontBridge()
    text_layout = TextLayoutBridge()   # selectable AppText line-height sync
    icon_bridge = IconBridge()
    app_ctrl = AppController(theme_bridge, i18n_bridge, font_bridge)
    # Left-to-right always (English-only interface). Kept as a hook so native
    # dialogs stay in step if a direction change is ever reintroduced.
    app_ctrl.languageRetranslate.connect(
        lambda: app.setLayoutDirection(
            Qt.RightToLeft if i18n.LANG == "fa" else Qt.LeftToRight))
    # v3.40: desktop "away notices" — a toast in the corner of the screen when
    # a job finishes while the user is in another app. Created before the VMs
    # so their finish handlers can announce through it from the first run.
    desktop_notify = DesktopNotifier(app_ctrl)
    dashboard_vm = DashboardVM()
    settings_vm = SettingsVM(app_ctrl)
    history_vm = HistoryVM()
    usage_vm = UsageVM()
    niche_vm = NicheVM()
    app_ctrl._niche_vm = niche_vm     # live "N left today" on quota spend
    downloads_vm = DownloadsVM()
    desktop_notify.attach_downloads(downloads_vm)   # v3.43: ⏸ / ▶ on live cards
    monetize_vm = MonetizeVM()
    notifications_vm = NotificationsVM()
    # v1.1: in-app updates from GitHub Releases (title-bar button + dialog)
    updater_vm = UpdateVM(notifications=notifications_vm)
    archive_vm = ArchiveVM()
    ideas_vm = IdeasVM()
    content_lab_vm = ContentLabVM()
    # Video Cutter: cut a segment out of a link or a local file. One instance
    # for the whole app, like every other page VM.
    cutter_vm = CutterVM()
    # Script Studio: reads the blueprints Content Lab / AI Ideas already stored
    # and drives the teleprompter. Constructed here rather than lazily because
    # the BlueprintPane overlay on two other pages talks to the same instance.
    studio_vm = StudioVM()
    # Niche Scan: reads a whole result SET rather than one row. Fed rows
    # by Niche Finder / Search Archive through Main.qml, so it makes no API call
    # of its own and costs no quota.
    insights_vm = InsightsVM()
    # v3.42: the ✦ "Send to AI Ideas" tile on Niche Finder / Search Archive
    # cards ticks the video as a reference on the AI Ideas page. It used to
    # write the legacy `ideas` table, which nothing reads any more, so the
    # click did nothing visible.
    niche_vm.ideas_sink = ideas_vm.addReferences
    archive_vm.ideas_sink = ideas_vm.addReferences
    insights_vm.ideas_sink = ideas_vm.addReferences
    # AI Chat ("Scope"). Gets the Niche VM so its picker can offer the live
    # result pool without a second search.
    chat_vm = ChatVM(niche_vm)
    # A provider added / edited / removed in Settings shows up in the chat's
    # model list the moment it is saved, without leaving and re-opening the page.
    settings_vm.aiSaved.connect(chat_vm.reloadConfig)
    # v1.1.3: Niche Scan builds its brief from the same AI config; without
    # this it kept the key it saw at startup ("No AI provider configured").
    settings_vm.aiSaved.connect(insights_vm.reloadConfig)
    # One probe object for the whole app: exactly one quality picker is open at
    # a time, and all three pages that own a picker would otherwise carry three
    # copies of the same worker-thread plumbing.
    quality_probe = QualityProbeVM()
    # Manages the deno JS runtime yt-dlp needs for YouTube downloads — one
    # app-wide object so the install dialog and every download-point gate share
    # the same availability/progress state.
    deno_vm = DenoVM()
    # "Your IP is in Iran" guard: a launch check plus the scrape gate. The
    # Scraper asks it before every run (see DashboardVM.startScraping).
    geo_vm = GeoVM()
    dashboard_vm._geo = geo_vm
    geo_vm.gateBlocked.connect(
        lambda purpose: dashboard_vm.geoBlocked() if purpose == "scrape" else None)

    # Now that a VM exists to route the message through, arm the guard: an
    # exception escaping a slot reaches the same themed dialog every other error
    # uses, instead of killing the process silently.
    _install_crash_guard(
        notify=lambda summary: dashboard_vm.popup.emit(
            tr("Unexpected Error"),
            tr("An unexpected error occurred, but the app has been kept "
               "open.\n\nDetails:\n") + summary
            + "\n\n" + tr("Full details: {path}").format(path=CRASH_LOG_PATH),
            "error"))

    # Mirror every page's transient toast into the persistent notification
    # tray, so the title-bar bell is a running log of what the app has done.
    for _vm, _default_title in ((settings_vm, "Settings"),
                                (history_vm, "History"),
                                (niche_vm, "Niche Finder"),
                                (downloads_vm, "Downloads"),
                                (monetize_vm, "Monetize Checker"),
                                 (archive_vm, "Search Archive"),
                                 (ideas_vm, "AI Ideas"),
                                 (content_lab_vm, "Content Lab"),
                                 (cutter_vm, "Video Cutter"),
                                 (studio_vm, "Script Studio"),
                                (insights_vm, "Niche Scan"),
                                (chat_vm, "AI Chat"),
                                (geo_vm, "Connection"),
                                (deno_vm, "Downloads")):
        _toast = getattr(_vm, "toast", None)
        if _toast is not None:
            _toast.connect(
                lambda msg, kind, t=_default_title: notifications_vm.push(msg, kind, t))
    # The dashboard reports through popup/donePopup (title, message, kind)
    # rather than a plain toast — funnel both into the tray too.
    dashboard_vm.popup.connect(
        lambda title, msg, kind: notifications_vm.push(msg, kind, title))
    dashboard_vm.donePopup.connect(
        lambda title, msg, path: notifications_vm.push(
            (msg + ("\n" + path if path else "")), "success", title))

    # v3.40: the scraper reports its finish through the same two signals, so
    # the away notice hooks in here rather than inside the worker thread.
    # popup() is also used for instant form errors ("Missing Field"), so only
    # the ones that arrive while a scrape is actually running are announced.
    dashboard_vm.donePopup.connect(
        lambda title, msg, path: announce(
            "success", tr("Scrape complete"), msg, page=0, path=path,
            icon="nav_scrape", source=tr("Scraper")))
    dashboard_vm.popup.connect(
        lambda title, msg, kind: announce(
            "error" if kind == "error" else "warn", title,
            msg.split("\n\n")[0], page=0, icon="nav_scrape",
            source=tr("Scraper"))
        if dashboard_vm._is_running and kind in ("error", "warning") else None)

    # v3.39.9: drag a downloaded video / cut clip OUT of the app (desktop,
    # Explorer, an editor's timeline, a chat...). Toasts land in the tray too.
    file_drag = FileDragBridge()
    file_drag.toast.connect(
        lambda msg, kind: notifications_vm.push(msg, kind, "Downloads"))

    engine = QQmlApplicationEngine()
    engine.addImageProvider("thumbs", ThumbImageProvider())
    engine.addImageProvider("svgicon", SvgIconProvider())
    ctx = engine.rootContext()
    ctx.setContextProperty("App", app_ctrl)
    ctx.setContextProperty("Theme", theme_bridge)
    ctx.setContextProperty("I18n", i18n_bridge)
    ctx.setContextProperty("Fonts", font_bridge)
    ctx.setContextProperty("TextLayout", text_layout)
    ctx.setContextProperty("Icons", icon_bridge)
    ctx.setContextProperty("Dashboard", dashboard_vm)
    ctx.setContextProperty("Settings", settings_vm)
    ctx.setContextProperty("History", history_vm)
    ctx.setContextProperty("Usage", usage_vm)
    ctx.setContextProperty("Niche", niche_vm)
    ctx.setContextProperty("Downloads", downloads_vm)
    ctx.setContextProperty("Monetize", monetize_vm)
    ctx.setContextProperty("Archive", archive_vm)
    ctx.setContextProperty("Ideas", ideas_vm)
    ctx.setContextProperty("ContentLab", content_lab_vm)
    ctx.setContextProperty("Cutter", cutter_vm)
    ctx.setContextProperty("Studio", studio_vm)
    ctx.setContextProperty("Insights", insights_vm)
    ctx.setContextProperty("Chat", chat_vm)
    ctx.setContextProperty("QualityProbe", quality_probe)
    ctx.setContextProperty("Deno", deno_vm)
    ctx.setContextProperty("Geo", geo_vm)
    ctx.setContextProperty("Notifications", notifications_vm)
    ctx.setContextProperty("Updater", updater_vm)
    ctx.setContextProperty("FileDrag", file_drag)
    ctx.setContextProperty("DesktopNotify", desktop_notify)
    # v3.43: "Add the YouTube button" — guided browser-extension install
    ext_setup = ExtensionSetupVM()
    ctx.setContextProperty("ExtensionSetup", ext_setup)

    # Live language switching: re-assigning these context properties is what
    # makes every `I18n.tr(...)` / `Fonts.family(...)` binding re-evaluate — a
    # signal alone can't, because a QML binding records no dependency on a
    # function call's result. The controller does the re-assign on setLanguage().
    app_ctrl.attach_context(engine, ctx, {
        "I18n": i18n_bridge,
        "Fonts": font_bridge,
    })
    # ViewModels that translate strings once, at construction, rebuild them here.
    for _vm in (settings_vm, history_vm, usage_vm, niche_vm, downloads_vm,
                monetize_vm, archive_vm, ideas_vm, content_lab_vm,
                studio_vm, insights_vm, chat_vm, dashboard_vm,
                notifications_vm, deno_vm, geo_vm):
        _retranslate = getattr(_vm, "retranslate", None)
        if callable(_retranslate):
            app_ctrl.languageRetranslate.connect(_retranslate)

    qml_dir = asset_path("app", "qml")
    engine.addImportPath(qml_dir)
    # Register the Tokens singleton under the NicheScope module. The on-disk
    # qmldir is enough when the dir is an import path, but registering here too
    # makes `import NicheScope` resolve regardless of how the app is launched
    # (source vs PyInstaller bundle).
    qmlRegisterSingletonType(
        QUrl.fromLocalFile(os.path.join(qml_dir, "Tokens.qml")),
        "NicheScope", 1, 0, "Tokens")
    if launch_hidden:
        # Never flash the window up first: Main.qml declares `visible: true`.
        engine.setInitialProperties({"visible": False})
    engine.load(QUrl.fromLocalFile(os.path.join(qml_dir, "Main.qml")))

    if not engine.rootObjects():
        print("QML failed to load Main.qml", file=sys.stderr)
        sys.exit(1)

    # Frameless windows drop WS_MINIMIZEBOX, which is what the Windows taskbar
    # keys off for its click-to-minimize/restore toggle — add it back now that
    # the window (and its HWND) exists. No-op off Windows.
    from app.qml_backend.win_taskbar import enable_taskbar_minimize
    enable_taskbar_minimize(engine.rootObjects()[0])

    # v3.40.1: native frame behaviour (DWM maximize/restore animation, one
    # resize per state change, Aero-snap). Replaces the per-frame geometry
    # tween that made maximize / restore lag. See app/qml_backend/win_frame.py.
    from app.qml_backend.win_frame import install_native_frame
    native_frame = install_native_frame(engine.rootObjects()[0])
    # v3.40.1: frame-time probe, only with YH_PERF=1 (see perf_probe.py).
    from app.qml_backend import perf_probe
    _perf = perf_probe.install(engine.rootObjects()[0], app_ctrl)

    # Rounded outer frame, guaranteed. The QML shell draws the curve, but on a
    # machine where Qt is not granted an alpha surface the window composites
    # opaque and those corners come out square — the "on some systems the frame
    # is sharp" report. This re-asserts the transparent window colour, asks DWM
    # to round the window too, and falls back to a window region clip when the
    # surface has no alpha channel. Radius matches Tokens.windowRadius.
    from app.qml_backend.win_shape import apply_rounded_window
    window_shaper = apply_rounded_window(engine.rootObjects()[0], radius=14)

    # The away-notice cards restore and raise this window when clicked.
    desktop_notify.attach_window(engine.rootObjects()[0])

    # v3.42: local bridge for the browser extension (download from YouTube
    # without opening the app). See app/qml_backend/web_bridge.py.
    web_bridge = WebBridge(downloads_vm, desktop_notify, cutter_vm=cutter_vm)
    web_bridge.extensionSeen.connect(ext_setup.markConnected)
    web_bridge.start()
    # First update check a few seconds after the window is up, then every
    # UPDATE_CHECK_HOURS. Silent unless a newer release exists.
    updater_vm.start()
    app.aboutToQuit.connect(web_bridge.stop)
    if launch_hidden:
        engine.rootObjects()[0].showMinimized()

    # Safety net for the "my mouse cursor disappeared" class of bug: a leaked
    # blank override cursor (Qt hides the pointer while typing) or a window left
    # on an unset cursor renders as no pointer at all, even though hovering and
    # clicking still work. The guard re-asserts a visible cursor on every
    # pointer move — see app/qml_backend/cursor_guard.py. It is parented to the
    # application, so it lives as long as the app does.
    cursor_guard = CursorGuard(app)
    # The "Aura" pointer set — see app/qml_backend/premium_cursor.py.
    from app.qml_backend.premium_cursor import PremiumCursor
    premium_cursor = PremiumCursor(app)

    # keep refs alive
    # Every object handed to QML as a context property belongs here: QML holds
    # only a borrowed pointer, so anything dropped from this tuple can be
    # garbage-collected out from under a live binding, which surfaces as
    # "TypeError: Cannot read property 'x' of null" against a VM that plainly
    # exists. deno_vm was missing, which is exactly what the Deno.* bindings in
    # Main.qml and SettingsPage.qml were hitting.
    app._qml_refs = (theme_bridge, i18n_bridge, font_bridge, icon_bridge,
                     app_ctrl, dashboard_vm, settings_vm, history_vm, usage_vm,
                     niche_vm, downloads_vm, monetize_vm, notifications_vm,
                     archive_vm, ideas_vm, content_lab_vm, cutter_vm, studio_vm,
                     insights_vm, chat_vm, quality_probe, deno_vm, geo_vm,
                     cursor_guard, premium_cursor, window_shaper,
                     desktop_notify, native_frame, _perf, text_layout,
                     web_bridge, updater_vm)
    # Where is this machine coming from? Looked up once, a moment after the
    # window is on screen, so it never delays startup. A restricted country
    # (Iran first of all) opens the GeoGateDialog — see app/core/geo.py.
    QTimer.singleShot(1800, geo_vm.checkStartup)
    # v3.39.8: keep Python's cyclic GC off the animated frames (freeze the
    # start-up heap, pause during theme/page transitions, collect in full when
    # the window loses focus). See app/qml_backend/gc_pacing.py.
    from app.qml_backend import gc_pacing
    gc_pacing.install(app)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
