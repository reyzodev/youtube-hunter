"""app.qml_backend.theme_bridge - YouTube Hunter (QML).

Exposes the existing semantic colour palette (app.ui.theme.CLR) to QML.

Implemented as a QQmlPropertyMap: every palette key becomes a real,
QML-readable property (`Theme.primary`, `Theme.surface`, …) and re-inserting a
key on a theme swap emits `valueChanged`, so QML bindings refresh automatically
— no widget-tree rebuild, which is what the old QWidgets app had to do.

(Dynamically injecting Property descriptors on a plain QObject subclass does
NOT work: PySide builds the QMetaObject at class-definition time, so late
setattr'd properties are invisible to QML. QQmlPropertyMap is the supported way
to publish a dynamic, bindable property set.)

The palette holds two value shapes:
  * '#rrggbb' hex
  * 'rgba(r,g,b,a)' strings the old stylesheet used  (QColor can't parse these)
Colour keys are normalised through qcolor_from_clr() and stored as real QColor;
the handful of scalar keys (is_dark, glow_rgb, ring_inner, shadow_alpha) are
stored as strings.
"""

import time
from collections import deque

from PySide6.QtCore import QObject, QTimer, Signal, Slot
from PySide6.QtGui import QColor
from PySide6.QtQml import QQmlPropertyMap

from app.ui import theme
from app.ui.colors import qcolor_from_clr

_SCALAR_KEYS = {"is_dark", "glow_rgb", "ring_inner", "shadow_alpha"}
# Plain numbers QML multiplies with (v4 glow intensity per theme).
_NUMBER_KEYS = {"glow_level"}

# v3.39.6 staged swap: how long ONE slice of the palette republish may hold the
# GUI thread, and the gap left between slices so a frame can be rendered.
# The curtain is opaque for ~500 ms; a full swap finishes in well under that.
_SWAP_SLICE_S = 0.005
_SWAP_GAP_MS = 4

def _later(ms, fn):
    """Single-shot `fn` after `ms` ms.

    ALWAYS hand QTimer a plain closure, never a bound method of this bridge:
    PySide treats `bridge._drain` as "slot `_drain` on that QObject" and looks
    it up in the meta-object — and a QQmlPropertyMap's meta-object is dynamic,
    so the lookup fails with "Slot 'QQmlPropertyMap::' not found" (v3.39.6
    first build). Short single-shots already run on a precise timer in Qt 6.
    """
    QTimer.singleShot(ms, lambda: fn())


class ThemeBridge(QQmlPropertyMap):
    """Live colour palette for QML. `Theme.primary`, `Theme.surface`, … all
    resolve here and update together whenever set_theme() swaps the palette."""

    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._pending = deque()      # (key, value) still to publish (staged swap)
        self._on_done = None
        self._active = False         # a staged swap is in flight
        self._load()

    @staticmethod
    def _entries(palette=None):
        """(key, value) pairs exactly as QML sees them, for `palette` (the
        live CLR by default)."""
        palette = theme.CLR if palette is None else palette
        out = []
        for key, value in palette.items():
            if key in _NUMBER_KEYS:
                try:
                    out.append((key, float(value)))
                except (TypeError, ValueError):
                    out.append((key, 1.0))
            elif key in _SCALAR_KEYS:
                out.append((key, str(value)))
            else:
                out.append((key, qcolor_from_clr(value)))
        # convenience flag mirrored as a plain property
        out.append(("isDark", palette.get("is_dark") == "1"))
        return out

    def _load(self):
        for key, value in self._entries():
            self.insert(key, value)

    # ---- helpers callable from QML ---------------------------------------
    @Slot(str, result="QColor")
    def color(self, key):
        """Any palette key as a QColor (also reachable as a bare property)."""
        v = theme.CLR.get(key)
        if v is None:
            return QColor("#000000")
        return qcolor_from_clr(v)

    @Slot(str, result=str)
    def raw(self, key):
        return str(theme.CLR.get(key, ""))

    @Slot("QColor", float, result="QColor")
    @Slot(str, float, result="QColor")
    def alpha(self, base, a):
        """A colour re-emitted at an explicit alpha 0..1 — the QML equivalent
        of app.ui.colors._rgba(), for hover/press tints. Accepts a QColor
        (e.g. Theme.primary) or a palette-key/hex string."""
        if isinstance(base, QColor):
            c = QColor(base)
        elif isinstance(base, str) and base.startswith(("#", "rgb")):
            c = qcolor_from_clr(base)
        else:
            c = qcolor_from_clr(theme.CLR.get(base, "#000000"))
        c.setAlphaF(max(0.0, min(1.0, float(a))))
        return c

    @Slot(str, str, result="QColor")
    def colorOf(self, theme_name, key):
        """One colour from a palette that is NOT currently applied.

        The theme-change wipe needs to paint the INCOMING theme's background
        over the outgoing one before the swap happens, so it has to read a
        palette without making it live. `theme_name` is 'dark' or 'light'; an
        unknown name or key falls back to the active palette."""
        palette = theme.THEMES.get(theme_name)
        if palette is None:
            return self.color(key)
        value = palette.get(key)
        if value is None:
            return self.color(key)
        return qcolor_from_clr(value)

    @Slot(str, result=str)
    def resolvedName(self, preference):
        """Which palette 'system' | 'dark' | 'light' actually resolves to,
        without applying it. Lets QML ask "what am I wiping TO?"."""
        if preference in ("dark", "light"):
            return preference
        return theme.detect_system_theme()

    # ---- state ------------------------------------------------------------
    def is_dark(self):
        """Python-side accessor (the QML-facing flag is the 'isDark' map key)."""
        return theme.CLR.get("is_dark") == "1"

    def _apply(self, preference, accent=None):
        """Swap the palette (and optionally the accent) and republish every key,
        so QML bindings refresh. `accent` is an app.ui.theme.ACCENTS key; None
        keeps whatever accent is already live."""
        self.flush()          # never let a staged swap land on top of this one
        theme.apply_theme(preference, accent)
        self._load()          # re-insert every key → valueChanged fires per key
        self.changed.emit()

    # ---- staged swap (v3.39.6) -------------------------------------------
    # Republishing the whole palette in one go re-evaluates every colour
    # binding in every loaded page (thousands) and re-requests every recoloured
    # SVG icon, all inside ONE frame. That frame landed in the middle of the
    # theme curtain's motion, so the mark / orbit visibly hitched — the "small
    # lag" on every theme switch. The staged path publishes only the keys that
    # actually change, a few milliseconds' worth per slice, with a frame in
    # between, while the curtain is opaque. QML calls flush() before the reveal
    # so whatever is left (normally nothing) is guaranteed done by then.
    def is_swapping(self):
        return self._active

    def begin_staged(self, preference, accent=None, on_done=None):
        self.flush()
        theme.apply_theme(preference, accent)
        keys = set(self.keys())
        pending = deque()
        for key, value in self._entries():
            if key in keys:
                try:
                    if self.value(key) == value:
                        continue
                except Exception:            # noqa: BLE001 — just republish it
                    pass
            pending.append((key, value))
        self._pending = pending
        self._on_done = on_done
        self._active = True
        _later(0, self._drain)

    def _drain(self):
        if not self._active:
            return
        try:
            self._drain_slice()
        except Exception:                    # noqa: BLE001 — finish in one go
            self.flush()

    def _drain_slice(self):
        deadline = time.perf_counter() + _SWAP_SLICE_S
        while self._pending:
            key, value = self._pending.popleft()
            self.insert(key, value)
            if time.perf_counter() >= deadline:
                break
        if self._pending:
            _later(_SWAP_GAP_MS, self._drain)
        else:
            self._finish()

    def flush(self):
        """Publish whatever a staged swap still has queued, right now."""
        if not self._active:
            return
        while self._pending:
            key, value = self._pending.popleft()
            self.insert(key, value)
        self._finish()

    def _finish(self):
        if not self._active:
            return
        self._active = False
        cb, self._on_done = self._on_done, None
        self.changed.emit()
        if cb is not None:
            try:
                cb()
            except Exception:                # noqa: BLE001
                pass

    def color_pairs(self, target_name):
        """[(live QColor, same key in `target_name` QColor), …] for every colour
        key, with the live accent applied to the target. Feeds the SVG icon
        pre-warm so the next swap finds its icons already rasterised."""
        base = theme.THEMES.get(target_name)
        if base is None:
            return []
        target = theme._apply_accent(dict(base), theme.ACCENT)
        tgt = dict(self._entries(target))
        pairs = []
        for key, cur in self._entries():
            if key in _SCALAR_KEYS or key in _NUMBER_KEYS or key == "isDark":
                continue
            new = tgt.get(key)
            if isinstance(cur, QColor) and isinstance(new, QColor) and cur != new:
                pairs.append((cur, new))
        return pairs
