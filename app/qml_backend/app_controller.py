"""app.qml_backend.app_controller - YouTube Hunter (QML).

Root object bound into the QML context as `App`. Owns cross-cutting UI state
that isn't specific to one page:

  * navigation      — which page index the StackLayout shows
  * sidebar         — expanded/collapsed rail (persisted)
  * theme           — dark/light preference, delegated to ThemeBridge
  * language        — en/fa, delegated to I18nBridge (+ FontBridge retranslate)
  * window controls — minimise / maximise / close for the frameless window
  * quota           — the sidebar's YouTube-quota ring value

It deliberately holds NO scraping/business logic — that lives in the per-page
ViewModels (app.qml_backend.vm.*), which call straight into app.core.
"""

from PySide6.QtCore import QObject, Property, QPointF, QTimer, Signal, Slot
from PySide6.QtGui import QCursor

from app.config import load_app_config, save_app_config
from app.constants import APP_VERSION, DONATE_URL
from app.core.quota import (add_quota_listener, api_quota_capacity,
                            api_quota_remaining)
from app.crash import log_crash
from app.ui import theme
from app.qml_backend import gc_pacing, svg_icon_provider


# Page indices. The QML StackLayout in Main.qml uses these directly.
PAGE_DASHBOARD    = 0
PAGE_LOGS         = 1
PAGE_HISTORY      = 2
PAGE_MONETIZE     = 3
PAGE_NICHE_FINDER = 4
PAGE_ARCHIVE      = 5
PAGE_AI_IDEAS     = 6
PAGE_CONTENT_LAB  = 7
PAGE_DOWNLOADS    = 8
PAGE_USAGE        = 9
PAGE_SETTINGS     = 10
# Appended AFTER Settings on purpose, even though the sidebar shows them above
# it: a StackLayout's index is its child order, and `App.goto(10)` for "Manage
# keys" is hardcoded in several QML files. Nav DISPLAY order comes from Sidebar's
# navItems list, which is independent of these numbers. A new page goes at the
# END of the stack so no existing index moves.
PAGE_INSIGHTS      = 11
PAGE_CUTTER        = 12
PAGE_AI_CHAT       = 13


def resolved_donate_url() -> str:
    """The Support page, or "" when the feature is switched off.

    Precedence: `donate_url` in config.json (per-install override) →
    DONATE_URL in app/constants.py (the shipped default, deliberately empty).
    http(s) only: config.json is a plain file on disk, so a tampered value must
    never be able to hand the web view a file:// path or a custom protocol.

    Why this is a module function and not just the QML property: main_qml.py
    asks the same question BEFORE the window exists. QtWebEngine costs ~260 MB
    of resident memory the moment it is initialised — measured — so the app
    only pays for it when there is actually a page to show.
    """
    url = ""
    try:
        url = str(load_app_config().get("donate_url") or "").strip()
    except Exception:                    # noqa: BLE001 — never break the rail
        url = ""
    if not url:
        url = DONATE_URL
    return url if url.lower().startswith(("http://", "https://")) else ""


class AppController(QObject):
    """Application shell state for the QML UI."""

    currentPageChanged = Signal()
    quotaChanged = Signal()
    # worker thread → GUI thread: "some quota was just spent"
    _quotaSpent = Signal()
    sidebarCollapsedChanged = Signal()
    gridColumnsChanged = Signal()
    railAnimatingChanged = Signal()
    themeChanged = Signal()
    accentChanged = Signal()
    ambientMotionChanged = Signal()
    tourSeenChanged = Signal()
    # A nav attempt was refused because a guard is armed (unsaved settings). The
    # target page index rides along so the confirm dialog can complete the jump.
    navBlocked = Signal(int)
    # Emitted after the UI language changes, so every ViewModel holding
    # translated strings can rebuild them.
    languageRetranslate = Signal()
    donateRequested = Signal()      # the Donate pill: open the Support window

    def __init__(self, theme_bridge, i18n_bridge, font_bridge, parent=None):
        super().__init__(parent)
        self._theme = theme_bridge
        self._i18n = i18n_bridge
        self._font = font_bridge
        self._current_page = PAGE_DASHBOARD
        # When armed (by SettingsPage while it has unsaved edits), goto() refuses
        # to leave the current page and emits navBlocked(idx) instead, so a
        # confirm dialog can decide whether to save, discard, or stay.
        self._nav_guard = False
        # Set by attach_context() once the QML engine exists; needed to
        # retranslate the live UI on a language switch.
        self._engine = None
        self._context = None
        self._bridges = {}

        cfg = load_app_config()
        self._sidebar_collapsed = bool(cfg.get("sidebar_collapsed", False))
        # v4: ambient motion (drifting page wash, breathing glows). On by
        # default; Settings → Appearance can turn it off for a perfectly still UI.
        self._ambient_motion = bool(cfg.get("ambient_motion", True))
        # True while the rail's collapse/expand slide is running. Grids freeze
        # their column count + card width on it (see the railTimer in
        # Sidebar.qml) so a 200ms slide doesn't rebuild every card per frame.
        self._rail_animating = False
        # How many result cards per row the grids use (3/4/5). 0 == "Auto",
        # where each grid derives the count from its own available width the way
        # it did before this preference existed. Persisted so the app reopens
        # the way the user left it.
        try:
            self._grid_columns = int(cfg.get("grid_columns", 0))
        except (TypeError, ValueError):
            self._grid_columns = 0
        if self._grid_columns not in (0, 3, 4, 5):
            self._grid_columns = 0
        self._youtube_api_keys = [k for k in (cfg.get("youtube_api_keys") or []) if k]
        if not self._youtube_api_keys and cfg.get("api_key"):
            self._youtube_api_keys = [cfg["api_key"]]
        self._quota_remaining = 0
        self._quota_capacity = 0
        # Whether the onboarding tour has been completed/skipped. Persisted, so
        # the tour opens itself exactly once — on the very first run.
        self._tour_seen = bool(cfg.get("tour_seen", False))
        self.refresh_quota()

        # Live quota card. Every billed API call (any page, any thread) pings
        # app.core.quota's listeners; the ping is marshalled here through a
        # queued signal and coalesced, so a 300-call search refreshes the card
        # a few times a second at most instead of hammering SQLite per call.
        self._quota_debounce = QTimer(self)
        self._quota_debounce.setSingleShot(True)
        self._quota_debounce.setInterval(400)
        self._quota_debounce.timeout.connect(self.refresh_quota)
        self._quotaSpent.connect(self._on_quota_spent)
        add_quota_listener(self._quotaSpent.emit)
        # Slow heartbeat: catches the Pacific-midnight reset (the card should
        # jump back to full on its own) and spend recorded by other windows.
        self._quota_heartbeat = QTimer(self)
        self._quota_heartbeat.setInterval(60_000)
        self._quota_heartbeat.timeout.connect(self.refresh_quota)
        self._quota_heartbeat.start()

        # v3.41.3: warm the download engine (yt-dlp import, ffmpeg dir, JS
        # runtime) off the GUI thread once the window has settled, so the
        # first download/cut doesn't spend its "Preparing…" on it.
        QTimer.singleShot(4000, self._prewarm_download_engine)
        # v1.0.1: the prewarm also starts the PO Token helper. On Windows 11
        # Smart App Control refuses to run it (it is not signed), and the only
        # symptom used to be a download failing for an unrelated-looking
        # reason. Say it once, plainly, a few seconds after the attempt.
        QTimer.singleShot(14000, self._report_pot_block)

    def _report_pot_block(self):
        """Tell the user when Windows refused to start bgutil-pot.exe."""
        try:
            from app.core import pot
            msg = pot.last_error()
        except Exception:                # noqa: BLE001 — cosmetic
            return
        if not msg:
            return
        try:
            from app.i18n import tr
            from app.qml_backend.desktop_notifier import announce
            announce("error", tr("Windows blocked the download helper"),
                     msg, icon="error", force=True)
        except Exception:                # noqa: BLE001 — cosmetic
            pass

    def _prewarm_download_engine(self):
        import threading

        def _warm():
            try:
                from app.core.runtime_deps import prewarm_download_engine
                prewarm_download_engine()
            except Exception:                # noqa: BLE001 — warm-up only
                pass
        threading.Thread(target=_warm, daemon=True, name="dl-prewarm").start()

    # ── onboarding tour ────────────────────────────────────────────────
    @Property(str, constant=True)
    def version(self):
        """App version (app.constants.APP_VERSION).

        Read from one place so the number in the sidebar footer, the version
        stamped on the built .exe and the version in installer.iss can never
        drift apart — a customer build that reports three different versions is
        the kind of detail that makes a product feel unfinished.
        """
        return APP_VERSION

    # ── support link (v3.52) ───────────────────────────────────────────
    # The rail's Donate pill used to be a dead button: SupportFooter emitted
    # `donateClicked()` and nothing was connected to it, so the most prominent
    # call-to-action in the app did absolutely nothing when clicked. The target
    # now lives in config.json as `donate_url`, which means switching the pill
    # on later is a one-line config change with no rebuild — and while it is
    # empty the pill stays HIDDEN instead of promising something that will
    # never happen.
    @Property(str, constant=True)
    def donateUrl(self):
        """The support page the Donate pill opens.

        Precedence: `donate_url` in config.json (per-install override) →
        DONATE_URL in app/constants.py (the shipped default). http(s) only:
        config.json is a plain file on disk, so a tampered value must never be
        able to hand the web view a file:// path or a custom protocol.
        """
        return resolved_donate_url()

    @Slot()
    def openDonate(self):
        """The Donate pill: ask the shell to open the in-app Support window."""
        if not self.donateUrl:
            return
        self.donateRequested.emit()

    @Slot()
    def openDonateExternal(self):
        """Fallback / "open in browser" — the same page in the user's browser."""
        url = self.donateUrl
        if not url:
            return
        from PySide6.QtCore import QUrl
        from PySide6.QtGui import QDesktopServices
        QDesktopServices.openUrl(QUrl(url))

    @Property(bool, notify=tourSeenChanged)
    def tourSeen(self):
        return self._tour_seen

    @Slot()
    def markTourSeen(self):
        """Called when the tour is finished or skipped."""
        if self._tour_seen:
            return
        self._tour_seen = True
        self.tourSeenChanged.emit()
        cfg = load_app_config()
        cfg["tour_seen"] = True
        save_app_config(cfg)

    @Slot()
    def resetTourSeen(self):
        """Let the tour auto-open again on next launch (Settings offers this
        next to the replay button)."""
        if not self._tour_seen:
            return
        self._tour_seen = False
        self.tourSeenChanged.emit()
        cfg = load_app_config()
        cfg["tour_seen"] = False
        save_app_config(cfg)

    # ── navigation ─────────────────────────────────────────────────────
    @Property(int, notify=currentPageChanged)
    def currentPage(self):
        return self._current_page

    @currentPage.setter
    def currentPage(self, idx):
        if idx != self._current_page:
            # v3.39.8: no cyclic-GC pass while the page fade/rise plays
            gc_pacing.hold(900)
            self._current_page = int(idx)
            self.currentPageChanged.emit()

    @Slot(int)
    def goto(self, idx):
        # When a page has unsaved changes it arms the guard; refuse to leave and
        # let the UI raise a save/discard/stay dialog. A no-op re-select (same
        # page) is always allowed.
        if self._nav_guard and int(idx) != self._current_page:
            self.navBlocked.emit(int(idx))
            return
        self.currentPage = idx

    @Slot(bool)
    def setNavGuard(self, on):
        self._nav_guard = bool(on)

    # ── grid columns preference (3 / 4 / 5, or 0 = Auto) ────────────────
    @Property(int, notify=gridColumnsChanged)
    def gridColumns(self):
        return self._grid_columns

    @Slot(int)
    def setGridColumns(self, n):
        n = int(n)
        if n not in (0, 3, 4, 5):
            n = 0
        if n == self._grid_columns:
            return
        self._grid_columns = n
        self.gridColumnsChanged.emit()
        cfg = load_app_config()
        cfg["grid_columns"] = n
        save_app_config(cfg)

    # ── sidebar ────────────────────────────────────────────────────────
    # Collapsing the nav rail to an icon-only strip hands its width back to the
    # page, which is the point: the content columns are capped by
    # Tokens.contentMaxWidth and only widen while there is room for them.
    # Persisted so the app reopens the way the user left it.
    @Property(bool, notify=sidebarCollapsedChanged)
    def sidebarCollapsed(self):
        return self._sidebar_collapsed

    @Slot()
    def toggleSidebar(self):
        self.setSidebarCollapsed(not self._sidebar_collapsed)

    @Slot(bool)
    def setSidebarCollapsed(self, collapsed):
        collapsed = bool(collapsed)
        if collapsed == self._sidebar_collapsed:
            return
        self._sidebar_collapsed = collapsed
        self.sidebarCollapsedChanged.emit()
        cfg = load_app_config()
        cfg["sidebar_collapsed"] = collapsed
        save_app_config(cfg)

    # ── ambient motion (v4) ────────────────────────────────────────────
    # Gates every looping decorative animation (page aurora drift, the CTA and
    # header-tile breathing). Interaction feedback — hover, press, focus,
    # transitions — is NOT gated: that motion carries meaning.
    @Property(bool, notify=ambientMotionChanged)
    def ambientMotion(self):
        return self._ambient_motion

    @Slot(bool)
    def setAmbientMotion(self, on):
        on = bool(on)
        if on == self._ambient_motion:
            return
        self._ambient_motion = on
        self.ambientMotionChanged.emit()
        try:
            cfg = load_app_config()
            cfg["ambient_motion"] = on
            save_app_config(cfg)
        except Exception:                    # noqa: BLE001
            log_crash("setAmbientMotion: could not persist the choice")

    # ── rail animation guard ───────────────────────────────────────────
    @Property(bool, notify=railAnimatingChanged)
    def railAnimating(self):
        return self._rail_animating

    @Slot(result=QPointF)
    def cursorPos(self):
        """Global mouse position (logical px). EditMenu uses it to open the
        right-click menu exactly under the pointer."""
        return QPointF(QCursor.pos())

    @Slot(bool)
    def setRailAnimating(self, on):
        on = bool(on)
        if on == self._rail_animating:
            return
        self._rail_animating = on
        self.railAnimatingChanged.emit()

    # ── theme ──────────────────────────────────────────────────────────
    # Applying a theme is split in two so the UI can play a "curtain" over the
    # swap: QML asks which palette it is heading TO, animates a circle of that
    # background colour out from the switch, and only then calls applyTheme —
    # so the colour change is revealed from behind the curtain instead of
    # flashing in a single frame. `toggleTheme` remains for callers that want
    # the plain, immediate swap.
    @Property(str, notify=themeChanged)
    def themePreference(self):
        """What the user picked: 'system' | 'dark' | 'light'. Drives the
        Settings page's theme segmented control."""
        return theme.THEME_PREF

    @Property(str, notify=themeChanged)
    def nextThemePreference(self):
        """The preference a toggle would move to right now."""
        return "light" if self._theme.is_dark() else "dark"

    @Slot()
    def toggleTheme(self):
        self.applyTheme(self.nextThemePreference)

    @Slot(str)
    def applyTheme(self, preference):
        self._theme._apply(preference, theme.ACCENT)
        self.themeChanged.emit()
        # Persist AFTER this frame, not during it.
        #
        # save_app_config() is a synchronous read-modify-write of config.json on
        # the GUI thread, and it used to sit between the palette swap and the
        # start of the reveal animation. Anything that makes that write slow —
        # an antivirus scanning the file, a roaming profile, a busy disk — landed
        # as a visible stutter right at the moment the wipe began, which is
        # exactly the "the theme switch sometimes lags" report. Deferring it by
        # one event-loop turn moves the I/O off the frame that matters; the
        # theme is already applied and painted by then.
        QTimer.singleShot(0, lambda p=preference: self._persist_theme(p))

    def _persist_theme(self, preference):
        """Write the theme preference. Never allowed to raise into Qt."""
        try:
            cfg = load_app_config()
            cfg["theme"] = preference
            save_app_config(cfg)
        except Exception:                    # noqa: BLE001
            log_crash("applyTheme: could not persist the theme preference")

    @Slot(str)
    def setTheme(self, preference):
        self.applyTheme(preference)

    # ── staged theme swap (v3.39.6) ──
    # The theme curtain calls beginThemeSwap() once it is opaque. The palette
    # is then republished a few milliseconds at a time, one slice per frame,
    # instead of all at once in a single long frame that froze the curtain's
    # motion mid-flight. flushThemeSwap() runs right before the reveal and
    # finishes anything still queued, so the reveal never shows a half-swap.
    @Slot(str)
    def beginThemeSwap(self, preference):
        svg_icon_provider.cancel_prewarm()      # it would only compete now
        # v3.39.8: the curtain + staged swap + reveal take ~1.4 s; keep the
        # cyclic collector out of all of it (see gc_pacing).
        gc_pacing.hold(2200)
        self._theme.begin_staged(
            preference, theme.ACCENT,
            on_done=lambda p=preference: self._theme_swap_done(p))

    @Slot()
    def flushThemeSwap(self):
        self._theme.flush()

    @Slot(result=bool)
    def themeSwapPending(self):
        """True while a staged palette swap still has keys to publish. The
        theme curtain polls this and holds its reveal until it is False
        (v3.39.8), instead of forcing the remainder into one long frame."""
        return self._theme.is_swapping()

    def _theme_swap_done(self, preference):
        self.themeChanged.emit()
        # v3.41: persist AFTER the reveal has played, not on the next turn.
        # The swap finishes right as the iris opens, so a 0 ms single-shot put
        # a synchronous config.json read-modify-write (antivirus, roaming
        # profile, slow disk) exactly on the reveal's first frames.
        QTimer.singleShot(1200, lambda p=preference: self._persist_theme(p))
        # Get the OTHER palette's icons ready for the next switch, once the
        # reveal (~1.2 s) has finished playing.
        QTimer.singleShot(1600, lambda: self.prewarmThemeSwap())

    @Slot()
    def prewarmThemeSwap(self):
        """Rasterise the icons the opposite theme will need, in idle slices.
        Called after startup, after every swap, and when the pointer reaches
        the theme switch. Cheap when everything is already warm."""
        if self._theme.is_swapping():
            return
        try:
            other = "light" if self._theme.is_dark() else "dark"
            svg_icon_provider.prewarm(self._theme.color_pairs(other))
        except Exception:                    # noqa: BLE001 — warm-up only
            log_crash("prewarmThemeSwap failed")

    # QQmlPropertyMap (the Theme bridge) can't expose @Slot methods to QML — a
    # property map only publishes its keys — so the theme-wipe helpers that QML
    # needs to CALL live here on the controller instead. They just delegate to
    # the bridge.
    @Slot(str, result=str)
    def resolvedThemeName(self, preference):
        """'system'|'dark'|'light' → the palette that actually applies ('dark'
        or 'light'), without applying it."""
        return self._theme.resolvedName(preference)

    @Slot(str, str, result="QColor")
    def themeColorOf(self, theme_name, key):
        """One colour from a palette that is not currently live — the wipe
        paints the incoming background before the swap."""
        return self._theme.colorOf(theme_name, key)


    # ── accent ─────────────────────────────────────────────────────────
    # The one signal colour. Picking one here repaints every primary button,
    # icon tile, active nav row, focus ring and corner glow — the palette's
    # whole "primary" family is generated from it in app.ui.theme, so there is
    # nothing else to keep in sync.
    @Property(str, notify=accentChanged)
    def accent(self):
        """The accent key in use ('crimson', 'ocean', …)."""
        return theme.ACCENT

    @Property("QVariantList", notify=accentChanged)
    def accents(self):
        """The picker's swatches: [{key, name, color}, …]."""
        return theme.accent_swatches()

    @Slot(str)
    def setAccent(self, key):
        # Re-apply the SAME theme preference with the new accent: one code path
        # for "swap the palette", so dark/light and the accent can never drift.
        self._theme._apply(theme.THEME_PREF, key)
        self.accentChanged.emit()
        QTimer.singleShot(0, lambda k=key: self._persist_accent(k))

    def _persist_accent(self, key):
        """Write the accent choice. Never allowed to raise into Qt."""
        try:
            cfg = load_app_config()
            cfg["accent"] = key
            save_app_config(cfg)
        except Exception:                    # noqa: BLE001
            log_crash("setAccent: could not persist the accent")


    # ── language ───────────────────────────────────────────────────────
    # Switching language live (no restart) needs one extra step beyond flipping
    # `i18n.LANG`: QML bindings that call `I18n.tr("…")` record no dependency on
    # the call's result, so a signal alone never re-runs them. Re-ASSIGNING the
    # context property does — Qt re-evaluates every binding that mentions that
    # name. So the engine's root context is handed back here (see main_qml.py)
    # and the bridges are re-set on it after the language changes.
    def attach_context(self, engine, context, bridges):
        """Give the controller what it needs to retranslate the live UI.
        `bridges` is {contextPropertyName: object}."""
        self._engine = engine
        self._context = context
        self._bridges = dict(bridges)

    def _retranslate_context(self):
        """Force every `I18n.tr(...)` / `Fonts.family(...)` binding to re-run."""
        if self._context is None:
            return
        for name, obj in self._bridges.items():
            self._context.setContextProperty(name, obj)

    @Slot()
    def toggleLanguage(self):
        """No-op: the interface is English only."""

    @Slot(str)
    def setLanguage(self, lang):
        """No-op kept for API compatibility (older QML called this). The app
        ships in English; `lang` is ignored."""

    # ── quota ring ─────────────────────────────────────────────────────
    @Property(int, notify=quotaChanged)
    def quotaRemaining(self):
        return self._quota_remaining

    @Property(int, notify=quotaChanged)
    def quotaCapacity(self):
        return self._quota_capacity

    @Property(bool, notify=quotaChanged)
    def hasApiKey(self):
        return self._quota_capacity > 0

    @Slot()
    def _on_quota_spent(self):
        # GUI thread (queued). Restarting a running single-shot would starve
        # the card during a long burst, so only arm it when idle.
        if not self._quota_debounce.isActive():
            self._quota_debounce.start()

    @Slot()
    def refresh_quota(self):
        keys = [k.strip() for k in (self._youtube_api_keys or []) if k and k.strip()]
        try:
            self._quota_capacity = api_quota_capacity(keys) if keys else 0
            self._quota_remaining = api_quota_remaining(keys) if keys else 0
        except Exception:
            self._quota_capacity = 0
            self._quota_remaining = 0
        self.quotaChanged.emit()
        # The Niche Finder's "N left today" line reads the same ledger.
        niche = getattr(self, "_niche_vm", None)
        if niche is not None:
            try:
                niche._update_quota()
            except Exception:
                pass
