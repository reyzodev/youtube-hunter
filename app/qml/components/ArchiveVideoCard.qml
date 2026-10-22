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
        Qt.callLater(card._settleThumb)
    }
    function _settleThumb() {
        // no picture at all, or one that came straight out of the pixmap cache
        // (status never left Ready, so onStatusChanged won't fire)
        if (!(row.thumbId && row.thumbId.length) || thumbImg.status === Image.Ready)
            card.announceThumbnailReady()
    }

    implicitWidth: cardWidth
    implicitHeight: col.implicitHeight
    radius: Tokens.radiusXl
    elevation: hovered ? 1.25 : 0.4
    // v3.52 — the page drops this to false while its scroller is moving.
    // Scrolling a grid slides a new card under a pointer that is standing
    // still, and every one of them used to light up: the cover zoomed over
    // 720 ms (re-rendering this card's layered thumbnail + mask on every
    // frame), the panel's 9-slice shadow re-tiled while its elevation
    // animated, and the card lifted 4 px — all while it was already moving.
    // That is what read as "the scroll is stiff". A card you merely scroll
    // past was never a hover you meant; the state comes back the moment the
    // view settles.
    property bool scrollIdle: true
    hoverGlow: scrollIdle
    Behavior on elevation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

    readonly property bool _motion: App.ambientMotion !== undefined ? App.ambientMotion : true
    transform: Translate {
        y: (card.hovered && card._motion) ? -4 : 0
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
    readonly property var _stats: row.isChannel
        ? [ { l: I18n.tr("views"),    v: row.views || "0",      m: -1 },
            { l: I18n.tr("videos"),   v: row.videoCount || "0", m: -1 },
            { l: I18n.tr("latest"),   v: row.ageShort || "—",   m: -1 } ]
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
                active: (row.thumbId || "") !== "" && thumbImg.status !== Image.Ready
                topLeftRadius: card._r
                topRightRadius: card._r
                bottomLeftRadius: card._r
                bottomRightRadius: card._r
                glyph: row.isChannel === true ? "user" : "movie"
            }

            // picture + scrims in one layer, rounded by a single mask
            Item {
                id: mediaSrc
                anchors.fill: parent
                visible: false
                clip: true
                layer.enabled: true
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
                    scale: (card.hovered && card._motion) ? 1.06 : 1.0
                    Behavior on scale { NumberAnimation { duration: Tokens.durGlow * 2; easing.type: Easing.OutCubic } }
                    onStatusChanged: {
                        if (status === Image.Ready || status === Image.Error)
                            card.announceThumbnailReady()
                    }
                    // no thumbnail at all → settled straight away (an empty
                    // source while waiting for a width is NOT "ready")
                    Component.onCompleted: if (!(row.thumbId && row.thumbId.length)) card.announceThumbnailReady()
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
            Item {
                id: mediaMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    color: "white"
                    radius: card._r
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: mediaSrc
                maskEnabled: true
                maskSource: mediaMask
                opacity: thumbImg.status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
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
                onClicked: card.target.openUrl(card._targetUrl)
            }

            // play disc
            Rectangle {
                visible: row.isChannel !== true
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
                readonly property bool shown: card.hovered
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
                visible: row.isChannel !== true
                clip: true
                implicitHeight: heroCol.implicitHeight
                HoverHandler { id: meterHover }
                C.AppTooltip {
                    visible: meterHover.hovered
                    delay: 300
                    text: I18n.tr("Views ÷ subscribers — how far this video outran its channel")
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
                        text: I18n.tr("outlier")
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
                        function onHoveredChanged() { if (card.hovered && card._bars >= 4 && card._motion) sheenRun.restart() }
                    }
                }
            }

            // ── title ──
            C.AppText {
                id: titleText
                text: row.title || ""
                // v1.2 — a Persian/Arabic title keeps its OWN reading direction
                // even though the interface is English. AppText defaults to
                // Text.AlignLeft, which pins the block to the left edge, so a
                // right-to-left sentence hung off the wrong side of its own
                // card and its closing punctuation ended up in front of it.
                // LayoutMirroring is switched off here so the enum stays
                // absolute (AlignRight is the visual right) no matter what the
                // UI language does later. Qt 6 has no Text.direction, so the
                // bidi base stays "natural" (first strong character) — which is
                // already right for these titles; only the block was misplaced.
                readonly property bool rtl: U.isRtlText(text)
                LayoutMirroring.enabled: false
                horizontalAlignment: rtl ? Text.AlignRight : Text.AlignLeft
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
            Item {
                Layout.fillWidth: true
                implicitHeight: chanRow.implicitHeight

                RowLayout {
                    id: chanRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.space2 + 2

                    Item {
                        width: 30; height: 30
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: U.withAlpha(Theme.primary, 0.14)
                        }
                        Image {
                            id: avatar
                            anchors.fill: parent
                            visible: false
                            source: (row.channelThumbId && row.channelThumbId.length) ? "image://thumbs/" + row.channelThumbId : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 30
                            sourceSize.height: 30
                        }
                        Item {
                            id: avatarMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
                        }
                        C.AppText {
                            anchors.centerIn: parent
                            visible: avatar.status !== Image.Ready
                            text: (row.channelTitle || "?").charAt(0).toUpperCase()
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontBody
                            color: Theme.primary
                        }
                        MultiEffect {
                            anchors.fill: parent
                            visible: (row.channelThumbId || "") !== ""
                            source: avatar
                            maskEnabled: true
                            maskSource: avatarMask
                            opacity: avatar.status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.primary
                            opacity: chanArea.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durFast } }
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        C.AppText {
                            text: row.channelTitle || "—"
                            weight: Tokens.weightDemiBold
                            font.pixelSize: Tokens.fontBody
                            color: chanArea.containsMouse ? Theme.primary : Theme.text_strong
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                        }
                        C.AppText {
                            text: card._subLine
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
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
                        model: card._stats
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 0
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
                                    text: modelData.v
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
                                    text: modelData.l
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
                    visible: row.isChannel !== true
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
                            card.downloadRequested(row.videoId || "", row.title || "", row.thumbId || "")
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
                C.PrimaryButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    visible: row.isChannel === true
                    variant: "ghost"
                    iconName: "open_in_new"
                    text: I18n.tr("Open channel")
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
                        tip: card.saved ? I18n.tr("Remove from favourites") : I18n.tr("Save to favourites")
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
