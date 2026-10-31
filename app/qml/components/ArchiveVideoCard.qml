import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// ArchiveVideoCard — v17 "Lumen" card for the Search Archive grid.
//
// The result card for Niche Finder and Search Archive (`row` / `target` /
// `cardWidth` API and two signals). v17 drops the boxed outlier badge, the separate tier
// pill and the boxed stats strip: the card now reads like a premium product
// tile, with ONE hero number and typography doing the hierarchy.
//
//   ┌──────────────────────────────┐
//   │ ╭──────────────────────────╮ │  inset media, rounded on all corners
//   │ │ ◆ Gem  ⚡ Short     ⧉ ↗  │ │  frosted chips · quick actions on hover
//   │ │            ▶             │ │
//   │ │                    0:04  │ │
//   │ ╰──────────────────────────╯ │
//   │ 2.8K×               ▬▬▬▬▬    │  hero multiplier + level meter
//   │ outlier             VIRAL    │  label under each
//   │ Title on two lines…          │
//   │ (●) Channel                  │
//   │     2.5K subs · 11d          │
//   │ ──────────────────────────── │
//   │ 6.9M   │ 25.7K   │ 0.2%      │  open stats, hairline separators
//   │ views  │ per hour│ engage    │
//   │ [  Download  ]  [★]  [✦]     │
//   └──────────────────────────────┘
C.GlassPanel {
    id: card
    property var row: ({})
    property int cardWidth: 300
    property var target: Archive

    signal downloadRequested(string videoId, string title, string thumbId)
    signal thumbDownloadRequested(string thumbId, string title, bool isShort)
    signal thumbnailReady()
    property bool _thumbnailAnnounced: false

    function announceThumbnailReady() {
        if (card._thumbnailAnnounced) return
        card._thumbnailAnnounced = true
        card.thumbnailReady()
    }

    // v3.44: the Archive grid now REUSES its cards across pages (only `row`
    // changes), so "thumbnail ready" has to re-arm whenever a different video
    // moves into this card — not only once at creation.
    readonly property string _rowKey: (row && (row.archiveKey || row.videoId || row.thumbId)) || ""
    on_RowKeyChanged: {
        card._thumbnailAnnounced = false
        // a different video: its picture has to earn its place again
        card._pictureOn = false
        card._syncPicture()
        Qt.callLater(card._settleThumb)
    }

    // ── batched picture reveal (v1.0.1) ──
    // A grid that opens cold gets its thumbnails back one by one, and each
    // card used to fade its picture in the moment its own bytes landed: the
    // first row read as cards being fired in one after another. The page can
    // now HOLD the pictures (holdPicture) until every card on screen has its
    // image, then release them in the same frame so the row lands as one.
    // Once a card is showing the picture of its current row it keeps it, so a
    // re-armed hold (page turn, filter change) never blinks a picture that is
    // already up. Niche Finder never sets holdPicture: same behaviour as before.
    //
    // v1.0.1b: _pictureOn is a LATCH, so it is set imperatively by
    // _syncPicture() rather than bound. As a binding it had to read its own
    // latch, which Qt rightly reported as a binding loop.
    property bool holdPicture: false
    property bool _pictureOn: false
    function _syncPicture() {
        if (thumbImg.status !== Image.Ready) {
            if (card._pictureOn) card._pictureOn = false
            return
        }
        if (!card._pictureOn && !card.holdPicture)
            card._pictureOn = true
    }
    onHoldPictureChanged: card._syncPicture()
    function _settleThumb() {
        // a picture that came straight out of the pixmap cache (status never
        // left Ready, so onStatusChanged won't fire)
        card._syncPicture()
        // no picture at all, or one that came straight out of the pixmap cache
        // (status never left Ready, so onStatusChanged won't fire)
        if (!(row.thumbId && row.thumbId.length) || thumbImg.status === Image.Ready)
            card.announceThumbnailReady()
    }

    implicitWidth: cardWidth
    implicitHeight: col.implicitHeight
    radius: Tokens.radiusXl
    elevation: (hovered && scrollIdle) ? 1.25 : 0.4
    // v3.52 — the page drops this to false while its scroller is moving.
    // Scrolling a grid slides a new card under a pointer that is standing
    // still, and every one of them used to light up: the cover zoomed (re-
    // rendering this card's layered thumbnail + mask on every frame), the
    // panel's 9-slice shadow re-tiled while its elevation animated, and the
    // card lifted 4 px — all while it was already moving. That is what read
    // as "the scroll is stiff". A card you merely scroll past was never a
    // hover you meant; the state comes back the moment the view settles.
    // v3.55: the lift, cover zoom, elevation and quick actions now actually
    // honour scrollIdle too — only the play disc / dim / glow did before, so
    // the heaviest three kept firing mid-scroll.
    property bool scrollIdle: true
    hoverGlow: scrollIdle
    Behavior on elevation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    transform: Translate {
        y: (card.hovered && card._motion && card.scrollIdle) ? -4 : 0
        Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
    }

    // ── download state (shared by Niche Finder + Archive) ──
    readonly property var _dl: (card.target.downloads[row.videoId || ""]) || null
    readonly property bool _downloading: _dl !== null && _dl.state === "running"
    readonly property bool _stopped: _dl !== null && _dl.state === "stopped"
    readonly property bool _alreadyDone: (card.target.downloadedIds || []).indexOf(row.videoId || "") !== -1
    readonly property bool _openable: !_downloading && !_stopped
                                       && ((_dl !== null && _dl.state === "done") || _alreadyDone)
    readonly property bool _merging: _downloading && (_dl.text || "") === I18n.tr("Merging…")
    readonly property real _pct: Math.max(0, Math.min(1, ((card._dl && card._dl.pct) || 0) / 100))
    readonly property string _targetUrl: row.isChannel ? (row.channelUrl || "") : (row.videoUrl || "")

    // Public so the handler name is plain (onSavedChanged) — drives the pop.
    readonly property bool saved: (card.target.savedIds || []).indexOf(row.videoId || "") >= 0
    onSavedChanged: if (card.hovered && card._motion) savePop.restart()

    // ── outlier heat ──
    // Log-scaled: 1× → 0, 10× → 0.25, 100× → 0.5, 1Kx → 0.75, 10Kx+ → 1.
    readonly property real _mult: Number(row.multiplierValue || 0)
    readonly property bool _hasMult: (row.multiplier || "—") !== "—" && _mult > 0
    readonly property real heat: _hasMult ? Math.max(0.04, Math.min(1, Math.log(Math.max(1, _mult)) / Math.LN10 / 4)) : 0
    // 1..5 lit bars on the signal meter
    readonly property int _bars: !_hasMult ? 0 : (_mult < 2 ? 1 : _mult < 10 ? 2 : _mult < 100 ? 3 : _mult < 1000 ? 4 : 5)
    readonly property color _heatColor: _bars >= 5 ? U.mix(Theme.primary, Theme.warn, 0.62)
                                        : _bars >= 4 ? U.mix(Theme.primary, Theme.warn, 0.30)
                                        : _bars >= 3 ? Theme.primary
                                        : U.mix(Theme.primary, Theme.on_surface_var, 0.45)
    readonly property string _tier: _bars >= 5 ? I18n.tr("Viral")
                                  : _bars >= 4 ? I18n.tr("Breakout")
                                  : _bars >= 3 ? I18n.tr("Strong")
                                  : _bars >= 2 ? I18n.tr("Rising")
                                  : I18n.tr("Typical")
    // "2.8Kx" → "2.8K" + "×", so the sign can sit smaller and lighter
    readonly property string _multNum: String(row.multiplier || "").replace(/[x×]\s*$/i, "")

    readonly property real _engNum: parseFloat(String(row.engagement || "").replace("%", ""))
    readonly property bool _isChan: row.isChannel === true
    // A channel card's download/open actions always belong to its hero upload,
    // so the filename must be the video's title, not the channel's.
    readonly property string _dlTitle: _isChan ? (row.bestTitle || row.title || "")
                                               : (row.title || "")
    // Channel cards answer the questions a creator actually asks of a channel
    // they just discovered: how much does it publish, how strong is a normal
    // upload, how many of its videos cleared MY filters, and how much attention
    // those hits pulled. Its best video's outlier is the hero above.
    readonly property var _stats: _isChan
        ? [ { l: I18n.tr("uploads"),     v: row.uploadsText || "—", m: -1 },
            { l: I18n.tr("avg / upload"), v: row.avgViewsText || "—", m: -1 },
            { l: I18n.tr("hits here"),   v: row.hitsText || "0",   m: -1 },
            { l: I18n.tr("hit views"),   v: row.views || "0",      m: -1 } ]
        : (row.chOutlier || "") !== ""
        // v1.0.2: "× its channel's average video" — the cleanest outlier read.
        // Only Niche Finder rows carry it; Archive cards keep three columns.
        ? [ { l: I18n.tr("views"),    v: row.views || "0",      m: -1 },
            { l: I18n.tr("vs ch. avg"), v: String(row.chOutlier).replace(/x\s*$/i, "×"), m: -1 },
            { l: I18n.tr("per hour"), v: row.perHour || "0",    m: -1 },
            { l: I18n.tr("engage"),   v: row.engagement || "—",
              m: isNaN(card._engNum) ? -1 : Math.min(1, card._engNum / 8) } ]
        : [ { l: I18n.tr("views"),    v: row.views || "0",      m: -1 },
            { l: I18n.tr("per hour"), v: row.perHour || "0",    m: -1 },
            { l: I18n.tr("engage"),   v: row.engagement || "—",
              m: isNaN(card._engNum) ? -1 : Math.min(1, card._engNum / 8) } ]

    readonly property string _subLine: {
        const subs = I18n.tr("{s} subs").replace("{s}", row.subsText || "—")
        if (row.isChannel === true || !(row.ageShort) || row.ageShort === "—")
            return subs
        return subs + "  ·  " + row.ageShort
    }

    // Channel identity line: size · how old the channel is · where it is
    // registered. Country is YouTube's declared channel country, not the
    // audience's — it is a hint, so it sits quietly in the meta line.
    readonly property string _chanMeta: {
        const bits = []
        bits.push(I18n.tr("{s} subs").replace("{s}", row.subsText || "—"))
        if ((row.channelAgeShort || "") !== "") bits.push(row.channelAgeShort)
        if ((row.channelCountry || "") !== "") bits.push(row.channelCountry)
        return bits.join("  ·  ")
    }

    readonly property real _inset: 6
    readonly property real _r: card.radius - _inset

    // frosted chip used on the media: dark glass, white label, only the icon
    // carries colour — quieter than a tinted outline, reads on any frame
    component MediaChip: Rectangle {
        id: mc
        property string icon: ""
        property string label: ""
        property color tint: "#ffffff"
        height: 22
        width: mcRow.implicitWidth + 16
        radius: Tokens.radiusPill
        color: Qt.rgba(0.02, 0.03, 0.05, 0.52)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
        Row {
            id: mcRow
            anchors.centerIn: parent
            spacing: 4
            C.IconGlyph {
                visible: mc.icon !== ""
                name: mc.icon; fill: true; size: 11
                glyphColor: mc.tint
                anchors.verticalCenter: parent.verticalCenter
            }
            C.AppText {
                text: mc.label
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontMicro
                color: "#ffffff"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    ColumnLayout {
        id: col
        width: card.width
        spacing: 0

        // ══════════════════════ media ══════════════════════
        Item {
            id: media
            Layout.fillWidth: true
            Layout.leftMargin: card._inset
            Layout.rightMargin: card._inset
            Layout.topMargin: card._inset
            Layout.preferredHeight: Math.round((card.width - card._inset * 2) * 9 / 16)

            Rectangle {
                anchors.fill: parent
                radius: card._r
                color: Theme.surface_high
            }
            C.ThumbSkeleton {
                anchors.fill: parent
                active: (row.thumbId || "") !== "" && !card._pictureOn
                        && thumbImg.status !== Image.Error
                // a skeleton that keeps sweeping while its card slides past is
                // pure motion for the eye and pure work for the renderer
                animate: card.scrollIdle
                topLeftRadius: card._r
                topRightRadius: card._r
                bottomLeftRadius: card._r
                bottomRightRadius: card._r
                glyph: row.isChannel === true ? "user" : "movie"
            }

            // picture + scrims, clipped to the media box
            // v1.0.3 perf: no layer, no mask, no MultiEffect. Each card used
            // to render this block into an offscreen texture, render a
            // rounded mask into a SECOND texture and composite the two
            // through a shader: 24 cards = 48 FBOs + 24 effect passes on
            // every page, and the hover zoom re-rendered the whole chain
            // every frame. Now the picture is drawn straight to the scene
            // with a plain rectangular clip, and the rounded corners are
            // "cut" by the cap ring below (card-coloured, which works because
            // the card surface is opaque in both palettes).
            Item {
                id: mediaSrc
                anchors.fill: parent
                clip: true
                opacity: card._pictureOn ? 1 : 0
                visible: opacity > 0.001
                // v3.53: the picture lands in 180 ms instead of 320.
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Image {
                    id: thumbImg
                    anchors.fill: parent
                    // v3.39.4: the request waits for a real width and the
                    // size is bucketed to 64px. Before, sourceSize followed
                    // the live width, so a card laid out at 0 → final width
                    // (or nudged by a resize) asked the provider for the SAME
                    // thumbnail 2-3 times and decoded each one.
                    readonly property int _bucketW: media.width > 1
                        ? Math.ceil(media.width / 64) * 64 : 0
                    source: (_bucketW > 0 && row.thumbId && row.thumbId.length)
                            ? "image://thumbs/" + row.thumbId : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: _bucketW
                    sourceSize.height: Math.round(_bucketW * 9 / 16)
                    scale: (card.hovered && card._motion && card.scrollIdle) ? 1.06 : 1.0
                    // v3.53: 720 ms was a slow "breathing" zoom that kept this
                    // card's layered thumbnail + mask re-rendering for most of a
                    // second on every hover — the single heaviest thing a grid of
                    // these did. 300 ms still glides, and it is over before the
                    // pointer has moved on.
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    onStatusChanged: {
                        card._syncPicture()
                        if (status === Image.Ready || status === Image.Error)
                            card.announceThumbnailReady()
                    }
                    // no thumbnail at all → settled straight away (an empty
                    // source while waiting for a width is NOT "ready")
                    Component.onCompleted: {
                        card._syncPicture()
                        if (!(row.thumbId && row.thumbId.length)) card.announceThumbnailReady()
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height * 0.32
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * 0.36
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.40) }
                    }
                }
                // hover dim, so the play disc and quick actions pop
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 1)
                    // a MouseArea keeps reporting containsMouse while the card
                    // slides under a still pointer, so it needs the same guard
                    opacity: (mediaArea.containsMouse && card.scrollIdle) ? 0.22 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                }
            }
            // corner caps: a card-coloured ring whose INNER edge is the
            // media's rounded rect. Its 4 px of overhang stays inside the
            // card's 6 px inset, clear of the panel border and its 1 px
            // specular top line. One antialiased rectangle, batched with
            // the rest of the card — the cheapest rounded clip there is.
            Rectangle {
                readonly property real _k: 4
                anchors.fill: parent
                anchors.margins: -_k
                radius: card._r + _k
                color: "transparent"
                border.width: _k
                border.color: card.color
                antialiasing: true
                visible: mediaSrc.visible
            }
            // inner hairline: the tile reads as a lit glass object, not a pasted image
            Rectangle {
                anchors.fill: parent
                radius: card._r
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.07 : 0.14)
            }

            MouseArea {
                id: mediaArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // On a channel card the cover IS its best video, so the image
                // opens that video; the channel itself is one click away on
                // the identity row and the "Open channel" action.
                onClicked: card.target.openUrl(row.videoUrl || card._targetUrl)
            }

            // play disc
            Rectangle {
                visible: (row.videoUrl || "") !== ""
                anchors.centerIn: parent
                width: 52; height: 52; radius: 26
                color: Qt.rgba(1, 1, 1, 0.16)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.38)
                opacity: (mediaArea.containsMouse && card.scrollIdle) ? 1.0 : 0.0
                scale: (mediaArea.containsMouse && card.scrollIdle) ? 1.0 : 0.7
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                C.IconGlyph {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 2
                    name: "play_arrow"; fill: true; size: 28
                    glyphColor: "#ffffff"
                }
            }

            // top-left badges
            Row {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Tokens.space2 + 2
                spacing: Tokens.space1 + 1
                // Viral Radar: the chart position it was found at ("#3 US")
                MediaChip {
                    visible: (row.viralTag || "") !== ""
                    icon: "trending_up"
                    label: row.viralTag || ""
                    tint: U.mix(Theme.error, Qt.rgba(1, 1, 1, 1), 0.10)
                }
                // Gold Score (v1.1): "Gold 86" / "Hot 61" — the steal-worthy ones
                MediaChip {
                    visible: (row.goldTier || "") !== ""
                    icon: row.goldTier === "gold" ? "star" : "bolt"
                    label: (row.goldTier === "gold" ? I18n.tr("Gold") : I18n.tr("Hot")) + " " + (row.goldScore || 0)
                    tint: row.goldTier === "gold" ? "#f2bd3a" : U.mix(Theme.warn, Qt.rgba(1, 1, 1, 1), 0.15)
                }
                MediaChip {
                    visible: row.isGem === true
                    icon: "diamond"
                    label: I18n.tr("Gem")
                    tint: U.mix(Theme.secondary_container, Qt.rgba(1, 1, 1, 1), 0.15)
                }
                MediaChip {
                    visible: row.isShort === true
                    icon: "fmt_short"
                    label: I18n.tr("Short")
                }
                // v3.43: YouTube no longer returns it (deleted / private):
                // the numbers below are the last ones it had
                MediaChip {
                    visible: row.unavailable === true
                    icon: "visibility_off"
                    label: I18n.tr("Unavailable")
                    tint: Theme.warn
                }
                MediaChip {
                    visible: card.saved
                    icon: "bookmark"
                    label: I18n.tr("Favorited")
                    tint: U.mix(Theme.primary, Qt.rgba(1, 1, 1, 1), 0.35)
                }
            }

            // top-right quick actions (hover)
            Row {
                id: quick
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.space2 + 2
                spacing: Tokens.space1 + 2
                readonly property bool shown: card.hovered && card.scrollIdle
                opacity: shown ? 1 : 0
                visible: opacity > 0.01
                transform: Translate {
                    y: quick.shown ? 0 : -8
                    Behavior on y { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                }
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

                C.IconButton {
                    visible: row.isChannel !== true && (row.thumbId || "") !== ""
                    overlay: true
                    implicitWidth: 32; implicitHeight: 32
                    glyphSize: 16
                    iconName: "image"
                    accent: "#ffffff"
                    tip: I18n.tr("Save thumbnail")
                    onClicked: card.thumbDownloadRequested(row.thumbId || "", row.title || "", row.isShort || false)
                }
                C.IconButton {
                    overlay: true
                    implicitWidth: 32; implicitHeight: 32
                    glyphSize: 16
                    iconName: "link"
                    accent: "#ffffff"
                    enabled: card._targetUrl !== ""
                    tip: I18n.tr("Copy the link")
                    onClicked: card.target.copyLink(card._targetUrl)
                }
                C.IconButton {
                    overlay: true
                    implicitWidth: 32; implicitHeight: 32
                    glyphSize: 16
                    iconName: "open_in_new"
                    accent: "#ffffff"
                    enabled: card._targetUrl !== ""
                    tip: I18n.tr("Open on YouTube")
                    onClicked: card.target.openUrl(card._targetUrl)
                }
            }

            // The channel card's cover is a specific upload; name it, or the
            // thumbnail reads as generic channel art.
            MediaChip {
                visible: card._isChan
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.space2 + 2
                anchors.bottomMargin: Tokens.space2 + 2
                icon: "play_arrow"
                label: I18n.tr("Best video")
            }

            // duration
            Rectangle {
                visible: !!row.duration && row.duration !== "—"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Tokens.space2 + 2
                anchors.bottomMargin: Tokens.space2 + 2
                radius: Tokens.radiusPill
                color: Qt.rgba(0.02, 0.03, 0.05, 0.58)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)
                width: durLbl.implicitWidth + 16
                height: 22
                C.AppText {
                    id: durLbl
                    anchors.centerIn: parent
                    text: row.duration || ""
                    mono: true
                    weight: Tokens.weightDemiBold
                    font.pixelSize: Tokens.fontMicro
                    color: "#ffffff"
                    LayoutMirroring.enabled: false
                }
            }

            // ── download rail ──
            // v16: the outlier "heat rail" is gone. A thin line along the
            // bottom of a thumbnail reads as a YouTube watch-progress bar, so
            // people took it for the video's playtime. The rail now ONLY
            // appears while a download runs (where a progress line is exactly
            // the right metaphor); the outlier lives in the badge below.
            Item {
                id: heatRail
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: card._r
                anchors.rightMargin: card._r
                anchors.bottomMargin: 5
                height: 3
                visible: card._downloading || card._stopped
                Rectangle {
                    anchors.fill: parent
                    radius: 1.5
                    color: Qt.rgba(1, 1, 1, 0.18)
                }
                // download progress takes over the rail while a transfer runs
                Rectangle {
                    visible: card._downloading || card._stopped
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * card._pct
                    radius: 1.5
                    color: card._stopped ? Theme.warn : Theme.primary
                    Behavior on width { NumberAnimation { duration: Tokens.durMed } }
                }
            }
        }

        // ══════════════════════ body ══════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.space4
            Layout.rightMargin: Tokens.space4
            Layout.topMargin: Tokens.space3 + 2
            Layout.bottomMargin: Tokens.space4
            spacing: Tokens.space3 + 2

            // ── headline: the multiplier IS the card ──
            // v17: no box, no second pill. One display-size number (the sign
            // set smaller and lighter), its label underneath, and on the far
            // side a five-step level meter with the worded tier — Typical ·
            // Rising · Strong · Breakout · Viral. Horizontal steps read as a
            // level, not as Wi-Fi strength like the old vertical bars did.
            Item {
                id: headline
                Layout.fillWidth: true
                // A channel with no measurable multiplier has no hero number;
                // hiding it keeps the card honest instead of showing a "—".
                visible: !card._isChan || card._hasMult
                clip: true
                implicitHeight: heroCol.implicitHeight
                HoverHandler { id: meterHover }
                C.AppTooltip {
                    visible: meterHover.hovered
                    delay: 300
                    text: card._isChan
                          ? I18n.tr("The best of this channel's matched videos — views ÷ subscribers")
                          : I18n.tr("Views ÷ subscribers — how far this video outran its channel")
                }

                Column {
                    id: heroCol
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Row {
                        spacing: 1
                        LayoutMirroring.enabled: false
                        C.AppText {
                            id: heroNum
                            text: card._hasMult ? card._multNum : "—"
                            weight: Tokens.weightExtraBold
                            font.pixelSize: Tokens.fontDisplay
                            font.letterSpacing: -0.6
                            color: card._hasMult && card._bars >= 3 ? card._heatColor : Theme.text_strong
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                        }
                        C.AppText {
                            visible: card._hasMult
                            anchors.baseline: heroNum.baseline
                            text: "×"
                            weight: Tokens.weightMedium
                            font.pixelSize: Tokens.fontSubtitle
                            color: U.withAlpha(card._bars >= 3 ? card._heatColor : Theme.text_strong, 0.55)
                        }
                    }
                    C.AppText {
                        text: card._isChan ? I18n.tr("best video outlier")
                                           : I18n.tr("outlier")
                        weight: Tokens.weightMedium
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.outline
                    }
                }

                // level meter + tier word
                Column {
                    visible: card._hasMult
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7
                    Row {
                        id: steps
                        anchors.right: parent.right
                        spacing: 3
                        Repeater {
                            model: 5
                            delegate: Rectangle {
                                readonly property bool lit: index < card._bars
                                width: 11; height: 4; radius: 2
                                color: lit ? card._heatColor : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.10 : 0.09)
                                // the lit steps fill in, one after another, on hover
                                opacity: lit ? ((card.hovered && card._motion) ? 1.0 : 0.88) : 1.0
                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed + index * 40 } }
                            }
                        }
                    }
                    C.AppText {
                        anchors.right: parent.right
                        text: card._tier
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontMicro
                        font.letterSpacing: I18n.rtl ? 0 : 1.1
                        font.capitalization: I18n.rtl ? Font.MixedCase : Font.AllUppercase
                        color: card._bars >= 3 ? card._heatColor : Theme.on_surface_var
                    }
                }

                // a slow sheen across the hero number for the two top tiers
                Rectangle {
                    id: sheen
                    visible: card._bars >= 4 && card._motion
                    width: 28; height: headline.height * 1.8
                    rotation: 18
                    y: -headline.height * 0.4
                    x: -40
                    opacity: 0.0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.07 : 0.22) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                    SequentialAnimation {
                        id: sheenRun
                        PropertyAction { target: sheen; property: "opacity"; value: 1 }
                        NumberAnimation { target: sheen; property: "x"; from: -40; to: heroCol.width + 30; duration: 700; easing.type: Easing.InOutCubic }
                        PropertyAction { target: sheen; property: "opacity"; value: 0 }
                    }
                    Connections {
                        target: card
                        function onHoveredChanged() { if (card.hovered && card.scrollIdle && card._bars >= 4 && card._motion) sheenRun.restart() }
                    }
                }
            }

            // ── title ── (the channel identity block below is the title on
            // a channel card; repeating the channel name here said nothing)
            C.AppText {
                id: titleText
                visible: !card._isChan
                text: row.title || ""
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontLabel
                color: titleHover.containsMouse ? Theme.primary : Theme.text_strong
                lineHeight: 1.28
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                Layout.fillWidth: true
                Layout.preferredHeight: Math.ceil(font.pixelSize * 1.28 * 2)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                MouseArea {
                    id: titleHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.target.openUrl(card._targetUrl)
                    C.AppTooltip {
                        visible: titleHover.containsMouse && titleText.truncated
                        delay: 500
                        text: row.title || ""
                    }
                }
            }

            // ── channel ── (one hit target over avatar + name)
            // On a channel card this block IS the card's title, so the avatar
            // and name step up a size and the meta line carries the facts that
            // decide whether the channel is worth studying: subscribers,
            // channel age, declared country.
            Item {
                id: chanBlock
                Layout.fillWidth: true
                implicitHeight: chanRow.implicitHeight
                // v1.0.2 perf: `hovered` is the pointer, `hot` is "and the
                // grid is at rest". Every moving part below reads `hot`, so a
                // flick-scroll past 24 cards does not build animations for
                // each one it crosses (same rule as the card's own hoverGlow,
                // v3.52). The still colour/arrow feedback stays on `hovered`.
                readonly property bool hovered: chanArea.containsMouse
                readonly property bool hot: hovered && card.scrollIdle && card._motion
                readonly property real avatarW: card._isChan ? 42 : 30

                // v1.0.2 "Channel lock-on" hover. A frosted accent capsule
                // grows out of the avatar to the end of the row, a comet arc
                // orbits the avatar, the name gets an underline that draws
                // itself, and an "open" arrow slides in after it.
                Rectangle {
                    id: chanCapsule
                    x: -6
                    anchors.verticalCenter: parent.verticalCenter
                    height: chanBlock.avatarW + 12
                    radius: height / 2
                    width: chanBlock.hot ? chanBlock.width + 12 : height
                    opacity: chanBlock.hot ? 1 : 0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.11) }
                        GradientStop { position: 0.55; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.06 : 0.045) }
                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                    }
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, 0.18)
                    antialiasing: true
                    Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: chanBlock.hot ? 160 : 260; easing.type: Easing.OutCubic } }
                }

                RowLayout {
                    id: chanRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.space2 + 2

                    Item {
                        width: card._isChan ? 42 : 30
                        height: width
                        Layout.preferredWidth: width
                        Layout.preferredHeight: width
                        scale: chanBlock.hot ? 1.07 : 1
                        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: U.withAlpha(Theme.primary, 0.14)
                        }
                        // v1.0.3 perf: the provider hands back an already
                        // round, transparent-cornered avatar ("circle/" ids,
                        // see image_provider.py), so it is drawn directly —
                        // no mask layer + MultiEffect per card any more.
                        // Requested at 2x for crisp edges on HiDPI screens.
                        Image {
                            id: avatar
                            anchors.fill: parent
                            source: (row.channelThumbId && row.channelThumbId.length) ? "image://thumbs/circle/" + row.channelThumbId : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true
                            sourceSize.width: (card._isChan ? 42 : 30) * 2
                            sourceSize.height: (card._isChan ? 42 : 30) * 2
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                        }
                        C.AppText {
                            anchors.centerIn: parent
                            visible: avatar.status !== Image.Ready
                            text: (row.channelTitle || "?").charAt(0).toUpperCase()
                            weight: Tokens.weightBold
                            font.pixelSize: card._isChan ? Tokens.fontLabel : Tokens.fontBody
                            color: Theme.primary
                        }
                        // faint full orbit under the comet
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: U.withAlpha(Theme.primary, 0.28)
                            opacity: chanBlock.hot ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                            antialiasing: true
                        }
                        // comet arc: painted once, only rotated while hovered
                        // v1.0.3 perf: built on demand. 24 Canvases (each its
                        // own image texture + a JS paint) were created with
                        // every grid; most are never hovered. Armed the first
                        // time the pointer enters the CARD, so it already
                        // exists — and fades — by the time it reaches the row.
                        Loader {
                            id: cometLoader
                            anchors.fill: parent
                            anchors.margins: -4
                            property bool armed: false
                            active: armed
                            Connections {
                                target: card
                                function onHoveredChanged() {
                                    if (card.hovered && card.scrollIdle) cometLoader.armed = true
                                }
                            }
                            sourceComponent: Canvas {
                                id: comet
                                anchors.fill: parent
                                antialiasing: true
                                smooth: true
                                opacity: chanBlock.hot ? 1 : 0
                                scale: chanBlock.hot ? 1 : 0.82
                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                                Behavior on scale { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                                property color tint: Theme.primary
                                onTintChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var cx = width / 2, cy = height / 2, r = width / 2 - 1.25
                                    if (r <= 0) return
                                    var R = Math.round(tint.r * 255), G = Math.round(tint.g * 255), B = Math.round(tint.b * 255)
                                    var steps = 40, span = Math.PI * 1.45
                                    ctx.lineWidth = 2
                                    ctx.lineCap = "round"
                                    for (var k = 0; k < steps; k++) {
                                        var a0 = -k * span / steps, a1 = -(k + 1) * span / steps
                                        ctx.strokeStyle = "rgba(" + R + "," + G + "," + B + "," + Math.pow(1 - k / steps, 1.4).toFixed(3) + ")"
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, r, a1, a0 + 0.02, false)
                                        ctx.stroke()
                                    }
                                    // the comet's head
                                    ctx.fillStyle = "rgba(" + R + "," + G + "," + B + ",0.35)"
                                    ctx.beginPath(); ctx.arc(cx + r, cy, 3.6, 0, Math.PI * 2); ctx.fill()
                                    ctx.fillStyle = "rgba(255,255,255,0.95)"
                                    ctx.beginPath(); ctx.arc(cx + r, cy, 1.4, 0, Math.PI * 2); ctx.fill()
                                }
                                RotationAnimator on rotation {
                                    running: chanBlock.hot && comet.visible
                                    from: -90; to: 270
                                    duration: 1500
                                    loops: Animation.Infinite
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: card._isChan ? 1 : 0
                        Layout.fillWidth: true
                        C.AppText {
                            id: chanName
                            text: row.channelTitle || "—"
                            weight: Tokens.weightDemiBold
                            font.pixelSize: card._isChan ? Tokens.fontLabel : Tokens.fontBody
                            color: chanBlock.hot ? Theme.primary : Theme.text_strong
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            // room for the arrow, so it never sits on the text
                            rightPadding: card._isChan ? 0 : 18
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                            readonly property real _textW: Math.min(contentWidth, width - rightPadding)
                            // underline that draws itself from the avatar side
                            Rectangle {
                                x: I18n.rtl ? chanName.width - chanName.rightPadding - width : 0
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: -1
                                height: 1.5
                                radius: 1
                                width: chanBlock.hot ? chanName._textW : 0
                                Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.primary }
                                    GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.15) }
                                }
                            }
                            // "open channel" arrow, slides in after the name
                            C.IconGlyph {
                                visible: !card._isChan
                                name: "arrow_right_up"
                                size: 13
                                glyphColor: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                                x: chanName._textW + 4 + (chanBlock.hot ? 0 : -6)
                                opacity: chanBlock.hot ? 1 : 0
                                Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                            }
                        }
                        C.AppText {
                            text: card._isChan ? card._chanMeta : card._subLine
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // A quiet affordance that the identity row leaves the app
                    // for the channel page — the media opens the video instead.
                    C.IconGlyph {
                        visible: card._isChan
                        name: I18n.rtl ? "chevron_left" : "chevron_right"
                        size: 16
                        glyphColor: chanBlock.hovered ? Theme.primary : Theme.outline
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                MouseArea {
                    id: chanArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.target.openUrl(row.channelUrl || card._targetUrl)
                }
            }

            // ── best video ── the cover above is a specific upload, not
            // channel art. Naming it turns the thumbnail into evidence and
            // gives the bookmark / download actions an explicit target.
            Rectangle {
                id: bestBlock
                visible: card._isChan
                Layout.fillWidth: true
                implicitHeight: bestRow.implicitHeight + Tokens.space2 * 2
                radius: Tokens.radiusSm
                color: bestArea.containsMouse
                       ? U.withAlpha(Theme.primary, Theme.isDark ? 0.11 : 0.07)
                       : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.035 : 0.03)
                border.width: 1
                border.color: bestArea.containsMouse
                              ? U.withAlpha(Theme.primary, 0.34) : Theme.border
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }

                RowLayout {
                    id: bestRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.space3
                    anchors.rightMargin: Tokens.space3
                    spacing: Tokens.space2 + 2

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        color: U.withAlpha(Theme.primary, bestArea.containsMouse ? 0.24 : 0.15)
                        Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        C.IconGlyph {
                            anchors.centerIn: parent
                            name: "play_arrow"; fill: true; size: 17
                            glyphColor: Theme.primary
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        C.AppText {
                            text: I18n.tr("BEST VIDEO")
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontMicro
                            font.letterSpacing: I18n.rtl ? 0 : Tokens.trackingLabel
                            color: Theme.outline
                        }
                        C.AppText {
                            text: row.bestTitle || "—"
                            weight: Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontBody
                            color: bestArea.containsMouse ? Theme.primary : Theme.text_strong
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.alignment: Qt.AlignVCenter
                        C.AppText {
                            text: row.bestViews || "0"
                            mono: true
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            color: Theme.text_strong
                            LayoutMirroring.enabled: false
                        }
                        C.AppText {
                            text: I18n.tr("views") + ((row.bestAgeShort || "") !== ""
                                                      ? "  ·  " + row.bestAgeShort : "")
                            font.pixelSize: Tokens.fontMicro
                            color: Theme.outline
                            LayoutMirroring.enabled: false
                        }
                    }
                }
                MouseArea {
                    id: bestArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: (row.videoUrl || "") !== ""
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.target.openUrl(row.videoUrl || "")
                    C.AppTooltip {
                        visible: bestArea.containsMouse
                        delay: 600
                        text: row.bestTitle || ""
                    }
                }
            }

            // ── stats: open columns, hairline separators ──
            // v17: no box. A hairline above, three columns divided by short
            // vertical rules, value over label. The engagement meter is gone —
            // a 0.2% bar is mostly empty track and read as "broken".
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.space3
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: U.withAlpha(Theme.outline_variant, Theme.isDark ? 0.55 : 0.75)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        // Fixed slots, not the row-derived array: with
                        // `model: card._stats` every page flip / filter /
                        // star toggle destroyed and rebuilt 3–4 delegate
                        // trees per card inside the rowsChanged emit (~130 ms
                        // for the 24-card grid). The count only ever varies
                        // between 3 and 4, so four permanent delegates whose
                        // text rebinds is the same picture with no churn.
                        model: 4
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 0
                            readonly property var stat: card._stats[index] || null
                            visible: stat !== null
                            Rectangle {
                                visible: index > 0
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 28
                                Layout.alignment: Qt.AlignVCenter
                                color: U.withAlpha(Theme.outline_variant, Theme.isDark ? 0.55 : 0.75)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: index > 0 ? Tokens.space3 : 0
                                spacing: 1
                                C.AppText {
                                    text: stat ? stat.v : ""
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontLabel
                                    font.letterSpacing: -0.2
                                    color: Theme.text_strong
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    LayoutMirroring.enabled: false
                                    horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
                                }
                                C.AppText {
                                    text: stat ? stat.l : ""
                                    weight: Tokens.weightMedium
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.outline
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
            }

            // ── actions ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.space2

                C.PrimaryButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    variant: card._openable ? "ghost" : "primary"
                    enabled: !card._downloading && (row.videoId || "") !== ""
                    iconName: card._downloading ? "downloading"
                            : card._stopped ? "pause"
                            : card._openable ? "play_circle"
                            : "download"
                    text: card._downloading
                          ? (card._dl.text || I18n.tr("Downloading…"))
                          : card._stopped
                            ? I18n.tr("Stopped at {pct}%").replace("{pct}", card._dl.pct || 0)
                            : card._openable ? I18n.tr("Open file") : I18n.tr("Download")
                    progress: card._downloading ? (card._dl.pct / 100)
                            : card._stopped ? ((card._dl.pct || 0) / 100) : -1
                    indeterminate: card._merging
                    onClicked: {
                        if (card._openable)
                            card.target.openDownloaded(row.videoId || "")
                        else
                            card.downloadRequested(row.videoId || "", card._dlTitle, row.thumbId || "")
                    }
                }
                C.IconButton {
                    visible: card._downloading
                    implicitWidth: 42; implicitHeight: 40
                    iconName: "stop_circle"
                    accent: Theme.error
                    tip: I18n.tr("Stop this download")
                    onClicked: card.target.cancelDownload(row.videoId || "")
                }
                C.IconButton {
                    visible: card._stopped
                    implicitWidth: 42; implicitHeight: 40
                    iconName: "play_arrow"
                    accent: Theme.primary
                    active: true
                    tip: I18n.tr("Resume at the same quality")
                    onClicked: card.target.resumeDownload(row.videoId || "")
                }
                // A channel card's primary action is the same Download as a
                // video card, scoped to its hero upload. The channel itself
                // stays one click away here (and on the identity row above).
                C.IconButton {
                    visible: card._isChan && !card._downloading && !card._stopped
                    implicitWidth: 42; implicitHeight: 40
                    iconName: "open_in_new"
                    enabled: (row.channelUrl || "") !== ""
                    tip: I18n.tr("Open channel")
                    onClicked: card.target.openUrl(row.channelUrl || "")
                }
                // bookmark, wrapped so the pop can scale it without fighting
                // IconButton's own press scale
                Item {
                    id: saveWrap
                    implicitWidth: 42; implicitHeight: 40
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    C.IconButton {
                        anchors.fill: parent
                        iconName: card.saved ? "bookmark" : "bookmark_add"
                        iconFill: card.saved
                        accent: Theme.primary
                        active: card.saved
                        enabled: (row.videoId || "") !== ""
                        tip: card.saved
                             ? I18n.tr("Remove from favourites")
                             : (card._isChan ? I18n.tr("Save its best video to favourites")
                                             : I18n.tr("Save to favourites"))
                        onClicked: card.target.toggleSaved(row.videoId || "")
                    }
                    SequentialAnimation {
                        id: savePop
                        NumberAnimation { target: saveWrap; property: "scale"; to: 1.22; duration: 110; easing.type: Easing.OutCubic }
                        NumberAnimation { target: saveWrap; property: "scale"; to: 1.0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }
                // v3.42: lit while this video is ticked on the AI Ideas page,
                // so the click visibly lands (it used to change nothing).
                Item {
                    id: ideaWrap
                    readonly property bool picked: (row.videoId || "") !== ""
                                                   && (Ideas.selectedKeys || []).indexOf(row.videoId) >= 0
                    implicitWidth: 42; implicitHeight: 40
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 40
                    C.IconButton {
                        anchors.fill: parent
                        iconName: "auto_awesome"
                        iconFill: ideaWrap.picked
                        accent: Theme.primary
                        active: ideaWrap.picked
                        enabled: (row.videoId || "") !== ""
                        tip: ideaWrap.picked ? I18n.tr("Picked on AI Ideas")
                                             : I18n.tr("Send to AI Ideas as a reference")
                        onClicked: {
                            card.target.sendToIdeas(row.videoId || "")
                            ideaPop.restart()
                        }
                    }
                    SequentialAnimation {
                        id: ideaPop
                        NumberAnimation { target: ideaWrap; property: "scale"; to: 1.22; duration: 110; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ideaWrap; property: "scale"; to: 1.0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }
            }
        }
    }
}
