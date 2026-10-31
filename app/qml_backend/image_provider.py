"""app.qml_backend.image_provider - YouTube Hunter (QML).

Async image provider bound into the QML engine as `image://thumbs/<b64url>`.
It's the QML-native replacement for the legacy ThumbLoader-on-QLabel: QML asks
for an image by id, we decode the id back to the real thumbnail URL and serve
the bytes from the shared, three-layer cache in app.core.thumbs
(in-memory -> on-disk -> network), so a thumbnail already seen this session (or
on a previous run) is never re-downloaded and i.ytimg.com is never hammered.

Fetching runs on a QThreadPool worker (QQuickAsyncImageProvider), so the GUI
thread never blocks on the network. QImage — unlike QPixmap — is safe to build
off the GUI thread, which is exactly why the provider builds a QImage here and
lets the render thread turn it into a texture.

In QML:  Image { source: url ? "image://thumbs/" + Qt.btoa(url) : "" }

v1.0.3: `image://thumbs/circle/<b64url>` serves the same picture cropped to
an antialiased circle on a transparent square. Round avatars used to be a
layered Image + mask + MultiEffect per card (two offscreen textures and a
shader pass each); a pre-cut image is drawn like any other picture. The
prefix can never collide with a real id: every id is base64 of an http(s)
URL, which always starts with "aHR0".
"""

import base64

from PySide6.QtCore import (QBuffer, QByteArray, QIODevice, QRectF,
                            QRunnable, QThreadPool, Qt)
from PySide6.QtGui import QImage, QImageReader, QPainter, QPainterPath
from PySide6.QtQuick import (
    QQuickAsyncImageProvider, QQuickImageResponse, QQuickTextureFactory)

from app.core.thumbs import get_grid_image_bytes


def _decode(raw, size):
    """Decode straight to (about) the box QML asked for.

    QImageReader.setScaledSize lets the JPEG decoder skip work (libjpeg can
    decode at 1/2, 1/4, 1/8 natively) instead of decoding full size and then
    running a SmoothTransformation pass — noticeably cheaper per card, and it
    keeps the GIL held for less time so the other workers keep downloading.
    Cover semantics (KeepAspectRatioByExpanding) are preserved."""
    buf = QBuffer()
    buf.setData(QByteArray(raw))
    buf.open(QIODevice.ReadOnly)
    reader = QImageReader(buf)
    reader.setAutoTransform(True)
    src = reader.size()
    if (size.width() > 0 and size.height() > 0 and src.isValid()
            and (src.width() > size.width() or src.height() > size.height())):
        reader.setScaledSize(src.scaled(size, Qt.KeepAspectRatioByExpanding))
    img = reader.read()
    if img.isNull():
        # some odd payloads only decode via loadFromData
        img = QImage()
        if not img.loadFromData(raw):
            return QImage()
        if (size.width() > 0 and size.height() > 0
                and (img.width() > size.width() or img.height() > size.height())):
            img = img.scaled(size, Qt.KeepAspectRatioByExpanding,
                             Qt.SmoothTransformation)
    return img


_CIRCLE_PREFIX = "circle/"


def _circle(img, size):
    """Centre-crop `img` to a square and cut it to an antialiased circle on
    transparency. QImage + QPainter are safe off the GUI thread."""
    if img.isNull():
        return img
    side = min(img.width(), img.height())
    if size.width() > 0 and size.height() > 0:
        side = min(side, max(size.width(), size.height())) or side
    side = max(1, side)
    out = QImage(side, side, QImage.Format.Format_ARGB32_Premultiplied)
    out.fill(Qt.GlobalColor.transparent)
    p = QPainter(out)
    try:
        p.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, True)
        path = QPainterPath()
        path.addEllipse(QRectF(0, 0, side, side))
        p.setClipPath(path)
        # cover: scale the short edge to `side`, centre the long one
        k = side / float(min(img.width(), img.height()))
        w, h = img.width() * k, img.height() * k
        p.drawImage(QRectF((side - w) / 2.0, (side - h) / 2.0, w, h), img)
    finally:
        p.end()
    return out


class _ThumbResponse(QQuickImageResponse, QRunnable):
    """One in-flight image request. Runs on the pool, then signals QML."""

    def __init__(self, b64_url, requested_size):
        QQuickImageResponse.__init__(self)
        QRunnable.__init__(self)
        self._b64_url = b64_url
        self._size = requested_size
        self._image = QImage()
        self.setAutoDelete(False)

    def run(self):
        b64 = self._b64_url or ""
        circle = b64.startswith(_CIRCLE_PREFIX)
        if circle:
            b64 = b64[len(_CIRCLE_PREFIX):]
        try:
            # QML's Qt.btoa() produces standard (not URL-safe) base64.
            url = base64.b64decode(b64.encode("ascii")).decode("utf-8")
        except Exception:
            url = ""
        if url:
            try:
                # grid-sized variant (hqdefault) first — 3-6x fewer bytes
                # than the hq720/maxres url innertube hands back.
                raw = get_grid_image_bytes(url, self._size.width())
            except Exception:
                raw = None
            if raw:
                self._image = _decode(raw, self._size)
                if circle:
                    try:
                        self._image = _circle(self._image, self._size)
                    except Exception:   # noqa: BLE001 — square beats nothing
                        pass
        self.finished.emit()

    def textureFactory(self):
        return QQuickTextureFactory.textureFactoryForImage(self._image)


class ThumbImageProvider(QQuickAsyncImageProvider):
    """`image://thumbs/<base64-url>` -> cached thumbnail bytes, async."""

    def __init__(self):
        super().__init__()
        self._pool = QThreadPool()
        # Cap concurrency so the grid filling in doesn't fire hundreds of
        # simultaneous requests at i.ytimg.com (which returned "excessive
        # load" over HTTP/2 when every card fetched at once).
        self._pool.setMaxThreadCount(6)
        self._pending = []

    def requestImageResponse(self, id, requested_size):
        resp = _ThumbResponse(id, requested_size)
        self._pending.append(resp)
        resp.finished.connect(lambda r=resp: self._pending.remove(r)
                              if r in self._pending else None)
        self._pool.start(resp)
        return resp
