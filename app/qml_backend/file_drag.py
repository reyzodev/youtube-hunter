"""app.qml_backend.file_drag - YouTube Hunter (QML).

Drag a finished video OUT of the app: onto the desktop, into an Explorer
folder, a Premiere / CapCut timeline, a Telegram chat, a browser upload box...
anywhere that accepts files dropped from Explorer.

QML starts it from a DragHandler (see components/FileDragSource.qml) and hands
over the file paths plus an optional grabbed thumbnail. Here a real OS drag is
started with the files as `text/uri-list` (Qt turns that into CF_HDROP on
Windows, which is what Explorer and every desktop app read).

Only CopyAction is offered, on purpose: Explorer's default for a same-drive
drop is MOVE, and a move would silently pull the file out of the Downloads /
Clips library. Copy keeps the original where the app expects it.
"""

import os

from PySide6.QtCore import (QMimeData, QObject, QPoint, QRectF, QUrl, Qt,
                            Property, Signal, Slot)
from PySide6.QtGui import (QColor, QDrag, QFont, QFontMetrics, QGuiApplication,
                           QImage, QPainter, QPainterPath, QPen, QPixmap)

from app.i18n import tr


def _local_path(p):
    """A QML value -> a plain local path ('' when unusable). Accepts plain
    paths and file:// URLs (a QUrl or its string form)."""
    if p is None:
        return ""
    if isinstance(p, QUrl):
        return p.toLocalFile() if p.isLocalFile() else ""
    s = str(p).strip()
    if s.lower().startswith("file:"):
        return QUrl(s).toLocalFile()
    return s


class FileDragBridge(QObject):
    """Context property `FileDrag`."""

    activeChanged = Signal()
    toast = Signal(str, str)           # (message, kind)

    _W = 176                           # drag card width (logical px)
    _THUMB_H = 99                      # 16:9 of the width
    _RED = QColor("#FF0000")

    def __init__(self, parent=None):
        super().__init__(parent)
        self._active = False

    # True for the whole OS drag. Pages with their own DropArea (the cutter's
    # "drop a video to cut it") read it so they ignore a drag that started in
    # this very app.
    @Property(bool, notify=activeChanged)
    def active(self):
        return self._active

    def _set_active(self, v):
        if v != self._active:
            self._active = v
            self.activeChanged.emit()

    @Slot("QVariant", "QVariant", result=bool)
    def start(self, paths, image=None):
        if self._active:
            return False
        # The button was let go before the drag could start (a very quick
        # flick): starting now would "drop" straight back onto our own window.
        if not (QGuiApplication.mouseButtons() & Qt.LeftButton):
            return False

        if paths is None:
            paths = []
        elif isinstance(paths, (str, QUrl)):
            paths = [paths]
        files, seen = [], set()
        for p in paths:
            lp = _local_path(p)
            if not lp:
                continue
            key = os.path.normcase(os.path.abspath(lp))
            if key in seen:
                continue
            seen.add(key)
            if os.path.isfile(lp):
                files.append(os.path.abspath(lp))
        if not files:
            self.toast.emit(tr("The file couldn't be found — it may have been "
                               "moved or deleted."), "error")
            return False

        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(f) for f in files])

        drag = QDrag(self)
        drag.setMimeData(mime)
        try:
            pix = self._drag_pixmap(image, files)
            if pix is not None and not pix.isNull():
                drag.setPixmap(pix)
                dpr = pix.devicePixelRatio() or 1.0
                drag.setHotSpot(QPoint(int(pix.width() / dpr / 2),
                                       int(self._THUMB_H / 2)))
        except Exception:               # noqa: BLE001 — a plain drag still works
            pass

        self._set_active(True)
        try:
            # Blocks in the OS drag loop until the drop / cancel.
            drag.exec(Qt.CopyAction, Qt.CopyAction)
        finally:
            self._set_active(False)
        return True

    # ── the card that follows the cursor ───────────────────────────────────
    def _drag_pixmap(self, image, files):
        screen = QGuiApplication.primaryScreen()
        dpr = screen.devicePixelRatio() if screen else 1.0
        W, TH = self._W, self._THUMB_H
        CAP = 26                        # caption pill height
        H = TH + 6 + CAP

        pix = QPixmap(int(W * dpr), int(H * dpr))
        pix.setDevicePixelRatio(dpr)
        pix.fill(Qt.transparent)
        p = QPainter(pix)
        p.setRenderHint(QPainter.Antialiasing, True)
        p.setRenderHint(QPainter.SmoothPixmapTransform, True)

        # thumbnail (or a plain film tile when there is none)
        thumb = QRectF(0.5, 0.5, W - 1, TH - 1)
        clip = QPainterPath()
        clip.addRoundedRect(thumb, 10, 10)
        p.save()
        p.setClipPath(clip)
        img = image if isinstance(image, QImage) else None
        if isinstance(image, QPixmap):
            img = image.toImage()
        if img is not None and not img.isNull():
            scaled = img.scaled(int(W * dpr), int(TH * dpr),
                                Qt.KeepAspectRatioByExpanding,
                                Qt.SmoothTransformation)
            sx = (scaled.width() - W * dpr) / 2
            sy = (scaled.height() - TH * dpr) / 2
            p.drawImage(thumb, scaled,
                        QRectF(sx, sy, W * dpr, TH * dpr))
        else:
            p.fillRect(thumb, QColor("#1c1c1f"))
            p.setPen(QPen(QColor(255, 255, 255, 150), 2))
            cx, cy = W / 2, TH / 2
            tri = QPainterPath()
            tri.moveTo(cx - 9, cy - 12)
            tri.lineTo(cx + 13, cy)
            tri.lineTo(cx - 9, cy + 12)
            tri.closeSubpath()
            p.fillPath(tri, QColor(255, 255, 255, 190))
        p.restore()
        p.setPen(QPen(QColor(255, 255, 255, 60), 1))
        p.setBrush(Qt.NoBrush)
        p.drawPath(clip)

        # count badge when several files ride along
        if len(files) > 1:
            txt = str(len(files))
            f = QFont(QGuiApplication.font())
            f.setPixelSize(13)
            f.setBold(True)
            p.setFont(f)
            bw = max(26, QFontMetrics(f).horizontalAdvance(txt) + 14)
            badge = QRectF(W - bw - 6, 6, bw, 24)
            p.setPen(Qt.NoPen)
            p.setBrush(self._RED)
            p.drawRoundedRect(badge, 12, 12)
            p.setPen(QColor("#ffffff"))
            p.drawText(badge, Qt.AlignCenter, txt)

        # caption: the file name (or "N videos")
        f = QFont(QGuiApplication.font())
        f.setPixelSize(12)
        f.setBold(True)
        p.setFont(f)
        fm = QFontMetrics(f)
        label = (os.path.basename(files[0]) if len(files) == 1
                 else tr("{n} videos").format(n=len(files)))
        label = fm.elidedText(label, Qt.ElideMiddle, W - 24)
        cw = min(W, fm.horizontalAdvance(label) + 22)
        cap = QRectF((W - cw) / 2, TH + 6, cw, CAP)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(20, 20, 22, 230))
        p.drawRoundedRect(cap, CAP / 2, CAP / 2)
        p.setPen(QColor("#ffffff"))
        p.drawText(cap, Qt.AlignCenter, label)
        p.end()
        return pix
