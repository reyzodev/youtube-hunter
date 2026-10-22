import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Shapes
import NicheScope
import "../Utils.js" as U

// Frameless-window title strip: drag-to-move, brand mark, and themed
// minimise / maximise / close buttons. `win` is the top-level Window.
Rectangle {
    id: root
    property var win
    height: Tokens.titleBarHeight
    color: Theme.header_bg

    // The title bar stays left-to-right in every language. It is a window
    // chrome strip, not page content: mirroring it in Persian threw the brand,
    // the app controls and the OS min/max/close buttons on top of each other in
    // the top-left corner. Fixed LTR keeps brand on the left and every control
    // on the right, exactly as in English, which is what "displays correctly"
    // means for a title bar. Page CONTENT still mirrors (see Main.qml).
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // The theme switch asks for the reveal curtain rather than applying the
    // palette itself; the window owns the animation, so the request bubbles up.
    signal themeWipeRequested(real cx, real cy, string preference)
    // Same for the language pill: the window covers the app with a veil while
    // every label, the font and the layout direction change together.
    // The help button in this bar restarts the onboarding tour.
    signal tourRequested()
    // v1.1: the update button asks the shell to open the update dialog.
    signal updateRequested()
    // v3.36: the "not connected" pill reopens the connection gate. Main.qml
    // owns the gate and tells the bar when it is already on screen.
    signal connectionRequested()
    property bool gateOpen: false

    // drag to move — sits below the button groups, so it only starts a move
    // when the empty strip is dragged; the groups on top handle their own clicks.
    MouseArea {
        anchors.fill: parent
        property point pressPos
        onPressed: (m) => pressPos = Qt.point(m.x, m.y)
        onPositionChanged: (m) => {
            if (root.win && (m.buttons & Qt.LeftButton))
                root.win.startSystemMove()
        }
        onDoubleClicked: root.win.toggleMaximize()
    }

    // ── window min/max/close ──
    // Pinned to the window's right edge in BOTH languages — the OS controls
    // never move. The brand and app-control groups arrange themselves around
    // this fixed anchor (see below).
    component WinBtn: AbstractButton {
        property string glyph: ""
        property bool danger: false
        width: 46; height: Tokens.titleBarHeight
        hoverEnabled: true
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        // The hover backdrop is an inset rounded pill rather than a full-
        // bleed square: it sits a couple of px inside the button so the
        // corners read as rounded on hover, matching every other control.
        background: Item {
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: Tokens.radiusSm
                color: parent.parent.hovered
                       ? (parent.parent.danger ? Theme.error : Theme.hover_bg)
                       : U.withAlpha((parent.parent.danger ? Theme.error : Theme.hover_bg), 0)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
        }
        contentItem: IconGlyph {
            name: parent.glyph
            size: 16
            glyphColor: parent.hovered && parent.danger ? "#ffffff" : Theme.on_surface_var
        }
    }

    Row {
        id: winButtons
        objectName: "hdrWin"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        LayoutMirroring.enabled: false
        spacing: 0
        WinBtn { glyph: "remove"; onClicked: root.win.showMinimized() }
        WinBtn {
            glyph: root.win && root.win.isMaximized ? "fullscreen_exit" : "crop_square"
            onClicked: root.win.toggleMaximize()
        }
        WinBtn { glyph: "close"; danger: true; onClicked: root.win.close() }
    }

    // brand: menu-toggle · logo · name · "Core Control".
    // Positioned by an explicit x (never by swapping left/right anchors — that
    // left both anchors bound at once and stretched the Row to full width).
    // LTR — hard against the window's left edge.
    // RTL — sits just left of the window buttons, children reversed so reading
    // right-to-left gives menu → logo → name.
    Row {
        id: brandRow
        objectName: "hdrBrand"
        layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
        LayoutMirroring.enabled: false
        anchors.verticalCenter: parent.verticalCenter
        x: I18n.rtl ? (winButtons.x - width - Tokens.space3) : Tokens.space3
        spacing: Tokens.space2

        // ── nav-rail toggle ──
        // The rail has its own toggle, but that one disappears from view the
        // moment someone is reading a page, so the shell keeps a permanent
        // hamburger here: it is the control people look for, and it is the only
        // one visible no matter which page is open.
        AbstractButton {
            id: menuBtn
            width: 30; height: 30
            anchors.verticalCenter: parent.verticalCenter
            hoverEnabled: true
            scale: pressed ? 0.92 : 1.0
            Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
            onClicked: App.toggleSidebar()

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            background: Rectangle {
                radius: Tokens.radiusSm
                color: menuBtn.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
            }
            contentItem: IconGlyph {
                name: App.sidebarCollapsed ? "menu_unfold" : "menu_fold"
                size: 19
                glyphColor: menuBtn.hovered ? Theme.primary : Theme.on_surface_var
            }

            AppTooltip {
                visible: menuBtn.hovered
                text: App.sidebarCollapsed ? I18n.tr("Expand menu")
                                           : I18n.tr("Collapse menu")
            }
        }

        // YouTube Hunter mark: vector, follows the theme accent live.
        BrandMark {
            width: 22; height: 24
            anchors.verticalCenter: parent.verticalCenter
        }
        AppText {
            text: I18n.tr("YouTube Hunter")
            weight: Tokens.weightBold
            color: Theme.text_strong
            anchors.verticalCenter: parent.verticalCenter
        }
        AppText {
            text: "·  " + I18n.tr("YouTube Research Studio")
            color: Theme.on_surface_var
            font.pixelSize: Tokens.fontCaption
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // app controls: help · notifications · language · theme
    // LTR — sit just left of the window buttons on the right.
    // RTL — move to the window's LEFT edge (the reference sketch puts Help ·
    // Bell · Language · Theme on the left in Persian).
    Row {
        id: controls
        objectName: "hdrCtl"
        anchors.verticalCenter: parent.verticalCenter
        // Placed by explicit x: just left of the window buttons in LTR, hard
        // against the left edge in RTL. (Binding both left+right anchors made
        // the Row span the whole bar and pile the icons at x≈0.)
        x: I18n.rtl ? Tokens.space2 : (winButtons.x - width)
        LayoutMirroring.enabled: false
        spacing: 0

        // ── app controls: notifications · language · theme ──
        // These sit left of the caption trio, separated by a hairline. They
        // are the three things you glance at constantly, so they live in the
        // open rather than behind a gear (which is how the legacy build ended
        // up doing it before this row was added).
        Row {
            id: appControls
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.space2
            rightPadding: Tokens.space3
            LayoutMirroring.enabled: false

            // ── "not connected" pill (v3.36) ──
            // Shown after the user skipped the connection gate while the app
            // still cannot reach YouTube, so a new user always knows WHY a
            // search or download is failing. One click reopens the fix.
            AbstractButton {
                id: netPill
                visible: Geo.blocked && !Geo.checking && !root.gateOpen
                height: 26
                width: netRow.implicitWidth + 20
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.connectionRequested()
                HoverHandler { id: netHover; cursorShape: Qt.PointingHandCursor }
                background: Rectangle {
                    radius: 13
                    color: U.withAlpha(Theme.error, netHover.hovered ? 0.22 : 0.13)
                    border.width: 1
                    border.color: U.withAlpha(Theme.error, 0.45)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                contentItem: Item {
                    Row {
                        id: netRow
                        anchors.centerIn: parent
                        spacing: 7
                        // Persian reads right-to-left: dot first on the right.
                        layoutDirection: I18n.rtl ? Qt.RightToLeft : Qt.LeftToRight
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                running: netPill.visible && Tokens.appActive
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.3; to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                        AppText {
                            text: Geo.offline ? I18n.tr("No internet")
                                  : Geo.reason === "unreachable" ? I18n.tr("YouTube isn't answering")
                                  : I18n.tr("YouTube is blocked")
                            weight: Tokens.weightBold
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
                AppTooltip {
                    visible: netHover.hovered
                    delay: 250
                    text: I18n.tr("The app can't reach YouTube right now. Click to see how to fix it.")
                }
            }

            // help / replay-tour button
            AbstractButton {
                id: helpBtn
                width: 30; height: 30
                anchors.verticalCenter: parent.verticalCenter
                scale: pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                onClicked: root.tourRequested()

                HoverHandler { id: helpHover; cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    radius: Tokens.radiusSm
                    color: helpHover.hovered ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                contentItem: IconGlyph {
                    name: "help"
                    size: 17
                    glyphColor: helpHover.hovered ? Theme.primary : Theme.on_surface_var
                }

                AppTooltip {
                    visible: helpHover.hovered
                    text: I18n.tr("Show the guided tour")
                }
            }

            // ── update button (v1.1) ──
            // Appears beside Help only when GitHub has a newer release. It
            // breathes while an update waits, draws the download as a ring
            // while it runs, and turns into "restart" once it is ready.
            AbstractButton {
                id: updBtn
                visible: Updater.hasUpdate
                width: 30; height: 30
                anchors.verticalCenter: parent.verticalCenter
                scale: pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                onClicked: root.updateRequested()
                HoverHandler { id: updHover; cursorShape: Qt.PointingHandCursor }

                readonly property bool busy: Updater.state === "downloading"
                readonly property bool ready: Updater.state === "ready" || Updater.state === "installing"
                readonly property color tint: ready ? Theme.secondary_container : Theme.primary

                background: Item {
                    // breathing halo
                    Rectangle {
                        anchors.centerIn: parent
                        width: 30; height: 30; radius: 15
                        color: U.withAlpha(updBtn.tint, 0.16)
                        SequentialAnimation on scale {
                            running: updBtn.visible && !updBtn.busy && Tokens.appActive
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.82; to: 1.12; duration: 1100; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1.12; to: 0.82; duration: 1100; easing.type: Easing.InOutSine }
                        }
                        opacity: updHover.hovered ? 1 : 0.85
                    }
                    // progress arc while downloading
                    Shape {
                        anchors.fill: parent
                        visible: updBtn.busy
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: U.withAlpha(Theme.primary, 0.22); strokeWidth: 2.4
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 15; centerY: 15; radiusX: 13; radiusY: 13; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeColor: Theme.primary; strokeWidth: 2.4
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: 15; centerY: 15; radiusX: 13; radiusY: 13; startAngle: -90
                                           sweepAngle: 360 * Math.max(0.02, Updater.progress) }
                        }
                    }
                }
                contentItem: IconGlyph {
                    name: updBtn.ready ? "restart_alt" : updBtn.busy ? "downloading" : "download"
                    size: 16
                    fill: true
                    glyphColor: updBtn.tint
                }
                // "new" dot
                Rectangle {
                    visible: Updater.state === "available"
                    width: 8; height: 8; radius: 4
                    color: Theme.primary
                    border.width: 1.5; border.color: Theme.header_bg
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.topMargin: 2; anchors.rightMargin: 2
                }
                AppTooltip {
                    visible: updHover.hovered
                    text: updBtn.ready ? I18n.tr("Update ready: restart to install")
                          : updBtn.busy ? I18n.tr("Downloading update… {p}%").replace("{p}", Math.round(Updater.progress * 100))
                          : I18n.tr("Update available: v{v}").replace("{v}", Updater.latestVersion)
                }
            }

            // notifications bell + unread badge
            AbstractButton {
                id: bellBtn
                width: 34; height: 30
                anchors.verticalCenter: parent.verticalCenter
                scale: pressed ? 0.92 : 1.0
                Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }
                // a press on the bell while the tray is open already closed it (press
                // outside); don't let the same click open it straight back up
                onClicked: notifTray.opened ? notifTray.close()
                         : (Date.now() - notifTray.closedAt > 250 ? notifTray.open() : undefined)

                // HoverHandler avoids the tooltip-open hover blink (see langBtn).
                HoverHandler { id: bellHover; cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    radius: Tokens.radiusSm
                    color: bellHover.hovered || notifTray.opened ? Theme.hover_bg : U.withAlpha(Theme.hover_bg, 0)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                contentItem: IconGlyph {
                    name: "notifications"
                    fill: notifTray.opened
                    size: 16
                    glyphColor: bellHover.hovered || notifTray.opened ? Theme.primary : Theme.on_surface_var
                }

                // unread count badge (hidden while the tray itself is showing them)
                Rectangle {
                    visible: Notifications.unreadCount > 0 && !notifTray.opened
                    z: 2
                    radius: height / 2
                    height: 15
                    width: Math.max(15, badgeLbl.implicitWidth + 6)
                    color: Theme.primary
                    border.width: 1.5
                    border.color: Theme.header_bg
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 2
                    anchors.rightMargin: 2
                    AppText {
                        id: badgeLbl
                        anchors.centerIn: parent
                        text: Notifications.unreadCount > 9 ? "9+" : Notifications.unreadCount
                        mono: true
                        weight: Tokens.weightExtraBold
                        font.pixelSize: 11
                        color: Theme.on_primary
                    }
                }

                AppTooltip {
                    visible: bellHover.hovered && !notifTray.opened
                    delay: 350
                    text: I18n.tr("Notifications")
                }

            }

            // theme sun/moon switch. The switch doesn't swap the palette
            // itself — it asks the window to play the reveal curtain and the
            // window applies the theme mid-animation (see Main.qml).
            ThemeSwitch {
                anchors.verticalCenter: parent.verticalCenter
                onWipeRequested: (cx, cy, preference) =>
                    root.themeWipeRequested(cx, cy, preference)
            }
        }

        // hairline on the left side in RTL, between the app controls and the
        // brand group that sits further right.
        Rectangle {
            visible: I18n.rtl
            width: 1; height: 18
            color: Theme.border
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // v3.41.2: the tray is no longer a CHILD of the bell. The bell scales on
    // press (0.92 → 1), and a Popup maps its position through its parent's
    // transform, so the tray opened at the shrunken bell's coordinates and then
    // jumped when the bell sprang back. It now hangs off the bar itself and is
    // placed from the bell's UNSCALED geometry (plain arithmetic, no mapToItem).
    NotificationsTray {
        id: notifTray
        readonly property real _bellX: controls.x + appControls.x + bellBtn.x
        readonly property real _bellY: controls.y + appControls.y + bellBtn.y
        y: _bellY + bellBtn.height + 8
        // LTR: right edge under the bell, growing leftward.
        // RTL: the controls sit at the window's LEFT edge, so the left edge
        // aligns instead, growing into the window.
        x: I18n.rtl ? _bellX : (_bellX + bellBtn.width - width)
    }
}
