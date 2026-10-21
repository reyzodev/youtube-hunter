"""app.qml_backend.vm.geo_vm - YouTube Hunter (QML).

The "can this connection reach YouTube?" guard.

v3.41.5: a LIVE monitor, not just a launch check
------------------------------------------------
It used to look once, at launch. Now it keeps watching for the whole session:

  * a background re-check every 60 s while things are fine, and every 10 s
    while blocked (so a VPN that comes up is noticed within seconds);
  * an immediate re-check when the OS reports a network change
    (QNetworkInformation: Wi-Fi drop, VPN up/down, cable out);
  * a re-check when the window comes back to the foreground after a while.

Every check looks at three things, over the route each part of the app really
uses (see app.core.geo):

  offline      nothing answered at all — the internet is down.
  restricted   the public IP is in a country where YouTube is filtered (Iran…).
  unreachable  the internet works but YouTube itself does NOT answer from this
               IP (filtered network, or an IP YouTube has blocked). This catches
               countries and VPN exits that aren't on any list.

Signals for the UI:
  startupWarning      the launch check found a problem
  connectionLost(r)   mid-session: was fine, now blocked (r = reason)
  connectionRestored  mid-session: was blocked, now fine
  gateBlocked(p)      a gated action (scrape / download) is waiting on the user

Background checks are SILENT (`checking` stays false), so the UI doesn't
flicker every minute; only user-started checks show a spinner.
"""

import threading
import time

from PySide6.QtCore import QObject, Property, Signal, Slot, QTimer

from app.config import load_app_config
from app.core import geo
from app.crash import log_crash
from app.i18n import tr

# A clean result younger than this is trusted for a gate without a new lookup.
_FRESH_S = 45
# Live monitor cadence.
_MONITOR_OK_MS = 60_000
_MONITOR_BLOCKED_MS = 10_000
# Re-check on window activation when the last result is older than this.
_ACTIVATE_STALE_S = 20
# Debounce for OS network-change events (they come in bursts).
_NETCHANGE_DEBOUNCE_MS = 1500


def _lang():
    try:
        from app import i18n
        return "fa" if getattr(i18n, "LANG", "en") == "fa" else "en"
    except Exception:
        return "en"


class GeoVM(QObject):
    changed = Signal()
    startupWarning = Signal()          # launch check found a problem
    connectionLost = Signal(str)       # (reason) mid-session: fine → blocked
    connectionRestored = Signal()      # mid-session: blocked → fine
    gateBlocked = Signal(str)          # (purpose) a gated action is waiting on the user
    gateCleared = Signal(str)          # (purpose) a re-check came back clean → action ran
    toast = Signal(str, str)           # (message, kind) → notification tray

    _done = Signal(int, object)        # worker → GUI (run id, result dict)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._result = None
        self._checking = False
        self._silent = False           # current run is a background one
        self._run = 0
        self._why = ""                 # "startup" | "gate" | "recheck" | "monitor"
        self._pending = None           # the parked action (callable)
        self._pending_cancel = None
        self._purpose = ""             # what the parked action is ("scrape" | "download")
        self._startup_retried = False
        self._started = False          # the launch check has completed once
        self._last_reason = ""         # reason after the previous check
        self._gate_waiting = False     # a gate joined an already-running check
        self._done.connect(self._on_done)

        self._monitor = QTimer(self)
        self._monitor.setSingleShot(True)
        self._monitor.timeout.connect(lambda: self._background("monitor"))
        self._netDebounce = QTimer(self)
        self._netDebounce.setSingleShot(True)
        self._netDebounce.setInterval(_NETCHANGE_DEBOUNCE_MS)
        self._netDebounce.timeout.connect(lambda: self._background("monitor"))
        self._netinfo = None
        self._hook_network_events()

    # ── live monitor wiring ────────────────────────────────────────────
    def _monitor_on(self):
        try:
            return bool(load_app_config().get("geo_monitor", True))
        except Exception:      # noqa: BLE001
            return True

    def _hook_network_events(self):
        """OS network changes → immediate re-check. Optional: without a
        backend the 60 s / 10 s timer still catches everything."""
        try:
            from PySide6.QtNetwork import QNetworkInformation
            feat = QNetworkInformation.Feature.Reachability
            ok = False
            try:
                ok = QNetworkInformation.loadBackendByFeatures(feat)
            except Exception:  # noqa: BLE001 — older PySide6
                try:
                    ok = QNetworkInformation.load(feat)
                except Exception:  # noqa: BLE001
                    ok = QNetworkInformation.loadDefaultBackend()
            inst = QNetworkInformation.instance() if ok else None
            if inst is not None:
                self._netinfo = inst
                inst.reachabilityChanged.connect(self._on_net_event)
                try:
                    inst.isBehindCaptivePortalChanged.connect(self._on_net_event)
                except Exception:  # noqa: BLE001
                    pass
                try:
                    inst.transportMediumChanged.connect(self._on_net_event)
                except Exception:  # noqa: BLE001
                    pass
        except Exception:      # noqa: BLE001
            self._netinfo = None
        try:
            from PySide6.QtGui import QGuiApplication
            app = QGuiApplication.instance()
            if app is not None:
                app.applicationStateChanged.connect(self._on_app_state)
        except Exception:      # noqa: BLE001
            pass

    def _on_net_event(self, *_a):
        if self._started:
            self._netDebounce.start()

    def _on_app_state(self, state):
        try:
            from PySide6.QtCore import Qt
            active = state == Qt.ApplicationState.ApplicationActive
        except Exception:      # noqa: BLE001
            active = False
        if not active or not self._started:
            return
        at = float((self._result or {}).get("at", 0))
        if time.time() - at > _ACTIVATE_STALE_S:
            self._background("monitor")

    def _schedule(self):
        if not self._monitor_on():
            self._monitor.stop()
            return
        self._monitor.start(_MONITOR_BLOCKED_MS if self.blocked else _MONITOR_OK_MS)

    def _background(self, why):
        # Never interrupt a user-started or gate check: a new run id would drop
        # its result (and strand a parked action).
        if self._checking:
            self._schedule()
            return
        if not self._monitor_on() and why == "monitor":
            return
        self._start(why, silent=True)

    # ── worker ─────────────────────────────────────────────────────────
    def _start(self, why, silent=False):
        self._monitor.stop()
        self._run += 1
        rid = self._run
        self._why = why
        self._checking = True
        self._silent = silent
        self.changed.emit()

        def work():
            try:
                res = geo.check_routes()
            except Exception:          # noqa: BLE001 — unknown, never blocking
                import traceback
                log_crash("geo check:\n" + traceback.format_exc())
                res = {"api": {}, "web": {}, "same_route": True, "at": time.time()}
            self._done.emit(rid, res)

        threading.Thread(target=work, daemon=True, name="geo-check").start()

    @Slot(int, object)
    def _on_done(self, rid, res):
        if rid != self._run:
            return
        why = self._why
        self._checking = False
        self._silent = False
        if res:
            self._result = res
        self.changed.emit()

        now_reason = self.reason
        prev_reason = self._last_reason
        self._last_reason = now_reason

        if why == "startup":
            if now_reason == "offline" and not self._startup_retried:
                # Nothing answered. One more try a few seconds later before
                # telling the user their internet is down.
                self._startup_retried = True
                QTimer.singleShot(3000, lambda: self._start("startup"))
                return
            first = not self._started
            self._started = True
            if now_reason and first and self._pending is None:
                self.startupWarning.emit()
        elif self._started:
            # Mid-session transitions (any check after the launch one).
            if now_reason and not prev_reason:
                self.connectionLost.emit(now_reason)
                self.toast.emit(self._lost_text(now_reason), "error")
            elif prev_reason and not now_reason:
                self.connectionRestored.emit()
                self.toast.emit(
                    tr("Connection is back — YouTube is reachable again."), "success")

        self._schedule()

        gate_waiting, self._gate_waiting = self._gate_waiting, False
        if self._pending is None:
            if why == "recheck" and res and not now_reason and self.hasResult:
                self.toast.emit(
                    tr("Connection looks good — you're coming from {c}.").format(
                        c=self.countryName), "success")
            return

        # A gated action is waiting.
        if not self._gate_blocked(self._purpose):
            purpose = self._purpose
            action = self._pending
            self._clear_pending()
            if why in ("recheck", "monitor"):
                self.gateCleared.emit(purpose)
            self._run_action(action)
        elif why == "gate" or gate_waiting:
            self.gateBlocked.emit(self._purpose)

    def _lost_text(self, reason):
        if reason == "offline":
            return tr("Internet connection lost.")
        if reason == "unreachable":
            return tr("YouTube stopped answering from this IP.")
        return tr("Your IP is now in {c}, where YouTube is filtered.").format(
            c=self.countryName)

    def _gate_blocked(self, purpose):
        if purpose == "download":
            return self.downloadBlocked
        return self.apiBlocked

    def _run_action(self, action):
        try:
            action()
        except Exception:              # noqa: BLE001
            import traceback
            log_crash("geo gate action:\n" + traceback.format_exc())

    def _clear_pending(self):
        self._pending = None
        self._pending_cancel = None
        self._purpose = ""
        self.changed.emit()

    # ── Python API (DashboardVM) ───────────────────────────────────────
    def gate(self, purpose, proceed, on_cancel=None):
        """Run `proceed` now if the route is clean, otherwise park it until the
        user re-checks, overrides or cancels."""
        self._pending = proceed
        self._pending_cancel = on_cancel
        self._purpose = purpose
        res = self._result
        fresh = bool(res) and (time.time() - float(res.get("at", 0))) < _FRESH_S
        if fresh and not self._gate_blocked(purpose):
            action = self._pending
            self._clear_pending()
            self._run_action(action)
            return
        self.changed.emit()
        if self._checking:
            # A check is already running: its result decides (starting a new
            # run would throw that one away, e.g. the launch check).
            self._gate_waiting = True
            self._silent = False
            self.changed.emit()
            return
        self._start("gate")

    # ── QML API ────────────────────────────────────────────────────────
    @Slot()
    def checkStartup(self):
        try:
            if not load_app_config().get("geo_check_on_launch", True):
                # No launch dialog, but the live monitor still runs.
                self._started = True
                self._background("monitor")
                return
        except Exception:
            pass
        self._start("startup")

    @Slot()
    def recheck(self):
        if self._checking and self._why == "recheck":
            return
        self._start("recheck")

    @Slot()
    def nudge(self):
        """Something just failed on the network (a download, a request):
        re-check now in the background instead of waiting for the timer."""
        if self._started:
            self._netDebounce.start()

    @Slot(result=bool)
    def allowDownload(self):
        """QML download gates call this. True = go ahead. False = the
        connection can't reach YouTube right now; the gate dialog is asked for
        (gateBlocked("download")) and a fresh check runs."""
        if not self.downloadBlocked:
            return True
        self.gateBlocked.emit("download")
        if not self._checking:
            self._start("recheck")
        return False

    @Slot()
    def override(self):
        """"Scrape anyway" — the user knows better than the geo database."""
        action = self._pending
        self._clear_pending()
        if action is not None:
            self._run_action(action)

    @Slot()
    def cancelGate(self):
        cancel = self._pending_cancel
        had = self._pending is not None
        self._clear_pending()
        if had and cancel is not None:
            self._run_action(cancel)

    # ── properties ─────────────────────────────────────────────────────
    def _route(self, name):
        return (self._result or {}).get(name) or {}

    @Property(bool, notify=changed)
    def checking(self):
        """True only for checks the user is waiting on (background monitor
        runs are silent)."""
        return self._checking and not self._silent

    @Property(bool, notify=changed)
    def monitoring(self):
        return self._monitor_on()

    @Property(bool, notify=changed)
    def hasResult(self):
        return bool(self._route("api").get("ok") or self._route("web").get("ok"))

    def _online(self, name):
        r = self._route(name)
        return bool(r.get("online", r.get("ok")))

    def _yt_down(self, name):
        """The route has internet but YouTube did NOT answer on it. False when
        the probe never ran (older result)."""
        r = self._route(name)
        if "yt_ok" not in r:
            return False
        return self._online(name) and not r.get("yt_ok")

    @Property(bool, notify=changed)
    def apiRestricted(self):
        return bool(self._route("api").get("restricted"))

    @Property(bool, notify=changed)
    def webRestricted(self):
        return bool(self._route("web").get("restricted"))

    @Property(bool, notify=changed)
    def restricted(self):
        return self.apiRestricted or self.webRestricted

    @Property(bool, notify=changed)
    def offline(self):
        """A check has finished and NOTHING answered on either route — not one
        geo service and not YouTube: the machine has no working internet."""
        if self._result is None or self._checking:
            return False
        return not (self._online("api") or self._online("web"))

    @Property(bool, notify=changed)
    def unreachable(self):
        """Internet works, the country isn't on the list, but YouTube itself
        doesn't answer (filtered network / IP blocked by YouTube)."""
        if self._result is None or self.offline or self.restricted:
            return False
        return self._yt_down("web") or self._yt_down("api")

    @Property(bool, notify=changed)
    def youtubeRefused(self):
        r = self._route("web").get("yt") or {}
        return bool(r.get("refused"))

    @Property(bool, notify=changed)
    def apiBlocked(self):
        """The scraper's route (YouTube Data API) can't work right now."""
        if self._result is None:
            return False
        return self.apiRestricted or self.offline or self._yt_down("api")

    @Property(bool, notify=changed)
    def downloadBlocked(self):
        """Downloads' route can't reach YouTube right now. Judged on the REAL
        probe, not the country list, so a geo-database mistake can't lock it."""
        if self._result is None:
            return False
        if self.offline:
            return True
        r = self._route("web")
        if "yt_ok" in r:
            return not r.get("yt_ok")
        return self.webRestricted

    @Property(bool, notify=changed)
    def blocked(self):
        """Any reason the app cannot work right now."""
        return self.restricted or self.offline or self.unreachable

    @Property(str, notify=changed)
    def reason(self):
        """"offline" | "restricted" | "unreachable" | "" — which story to tell."""
        if self.offline:
            return "offline"
        if self.restricted:
            return "restricted"
        if self.unreachable:
            return "unreachable"
        return ""

    @Property(int, notify=changed)
    def youtubeMs(self):
        return int((self._route("web").get("yt") or {}).get("ms") or 0)

    @Property(bool, notify=changed)
    def splitRoute(self):
        """The proxy in Settings gets downloads out, but the scraper still
        leaves from the restricted IP — the case the TUN tip is for."""
        return (not (self._result or {}).get("same_route", True)
                and self.apiRestricted and self._route("web").get("ok", False)
                and not self.webRestricted)

    @Property(bool, notify=changed)
    def gatePending(self):
        return self._pending is not None

    @Property(str, notify=changed)
    def gatePurpose(self):
        return self._purpose

    def _shown(self):
        # The route worth talking about: the restricted one, API first.
        api, web = self._route("api"), self._route("web")
        if api.get("restricted") or not web.get("ok"):
            return api
        if web.get("restricted"):
            return web
        return api if api.get("ok") else web

    @Property(str, notify=changed)
    def ip(self):
        return self._shown().get("ip", "") or ""

    @Property(str, notify=changed)
    def countryCode(self):
        return (self._shown().get("code", "") or "").upper()

    @Property(str, notify=changed)
    def countryName(self):
        r = self._shown()
        return geo.country_label(r.get("code", ""), r.get("name", ""), _lang())

    @Property(str, notify=changed)
    def webCountryCode(self):
        return (self._route("web").get("code", "") or "").upper()

    @Property(str, notify=changed)
    def webCountryName(self):
        r = self._route("web")
        return geo.country_label(r.get("code", ""), r.get("name", ""), _lang())

    @Slot()
    def retranslate(self):
        self.changed.emit()
