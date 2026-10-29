import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Shapes
import QtWebEngine
import NicheScope
import "." as C
import "../Utils.js" as U

// ═══════════════════════════════════════════════════════════════════════
//  Support — the in-app donation window
// ═══════════════════════════════════════════════════════════════════════
//
// The Donate pill in the rail used to hand the link to the system browser,
// which drops the user out of the app mid-session. It now opens this: a
// single, quiet card over a blurred app, with the real donation page live
// inside it (QtWebEngine), so the whole flow — pick an amount, fill the form,
// pay — happens without leaving YouTube Hunter.
//
// The page itself is not ours: `App.donateUrl` is whatever
// `DONATE_URL` says in app/constants.py (or `donate_url` in config.json).
// Nothing is stored here, and no payment detail ever touches the app — the
// web view is a window onto the provider's own secure page.
//
// Design notes (2026 pass):
//   * one card, one job. No sidebar of options, no "are you sure" step.
//   * premium pass (v2): the card is a lit object: drop shadow, an accent
//     halo that blooms from behind the top edge on open and keeps breathing,
//     an accent-warm rim fading to a hairline, a specular top line. Header:
//     beating-heart tile, a live security chip (lock + Secure + the CURRENT
//     host, so a bank hop is visible), browser controls grouped in one pill,
//     a thin load beam for gateway steps. Footer: keycap hints + version.
//     The chrome still carries no loud colour, so the page stays the hero.
//   * the frame around the page is square-cornered on purpose: a rounded
//     Rectangle does not round its children's clip, so a radius there only
//     rounds the hairline border and then has the page cut it into four gaps.
//   * loading and failure are first-class: "Heartline" while it loads
//     (components/DonateLoader.qml), and a clear retry / open-in-browser pair
//     if it cannot load at all. Offline is its own state: it waits for the
//     connection and reopens the page by itself.
//   * this card always stays ON TOP of the "Signal lost" gate. If the internet
//     drops while it is open, the gate opens BEHIND it (z below), so the donor
//     is not thrown out of the page; close the card and the gate is there.
//   * the page gets as much room as the window will give (up to 1120x920), so
//     the whole form — amount, name, phone, the pay button — is on screen at
//     once on a maximised window. A form that needs scrolling before you have
//     even decided to pay reads as friction.
//   * a payment gateway often opens its own window (window.open). That request
//     is taken over by this view instead of being dropped, so the donor never
//     hits a button that appears to do nothing.
Popup {
    id: root

    parent: Overlay.overlay
    modal: true
    // MUST stay true. `dim` is what makes Qt build the Overlay.modal item at
    // all: with `dim: false` the DialogScrim below is never created, so there
    // was no blur and no dim behind this card (the old "DialogScrim does the
    // dimming" note had it backwards — DialogScrim IS the dim layer).
    dim: true
    padding: 0
    // NoAutoClose: only Esc (below) and the close button close this card —
    // a stray click on the backdrop must not end a half-filled donation.
    // CloseOnEscape is deliberately NOT used: on this Qt build the popup
    // item claims the key through shortcut-override and then never acts on
    // it, which is exactly why Esc did nothing. See the Shortcut below.
    closePolicy: Popup.NoAutoClose
    focus: true
    // Above the connection gate (GeoGateDialog, z 0) and every other dialog:
    // a connection drop mid-donation opens the gate BEHIND this card.
    z: 50

    // v1.0.4: wider (1120 -> 1360). The extra room goes to a brand rail on the
    // left, not to empty margin around the page; the page keeps ~1000 px.
    width: Math.min(1360, parent ? parent.width - 64 : 960)
    height: Math.min(940, parent ? parent.height - 56 : 700)
    anchors.centerIn: parent

    // Wide enough for the rail (left: brand, perks, security; right: page).
    // Below this the card falls back to the single-column layout.
    readonly property bool wide: width >= 1100
    readonly property int _railW: 300
    readonly property int _frameR: Tokens.radiusLg

    // A stronger backdrop than the app's other dialogs (they use a light
    // 3.5 px so you keep your bearings). Donating is a full-attention flow:
    // the app behind should step right back, recognisable as shapes but not
    // readable, so the page is the only thing the eye lands on.
    Overlay.modal: C.DialogScrim {
        blurPx: 18
        dimOpacity: Theme.isDark ? 0.58 : 0.38
        // The card is the only thing moving here; a live full-window capture
        // plus an 18 px blur every frame is the heaviest cost in the app while
        // this is open, and behind 18 px of blur nobody can tell it is a still.
        frozen: true
    }

    // the URL is loaded lazily: the first open pays for it, and closing the
    // card keeps the page (and any half-filled form) alive for the next open.
    property bool _loaded: false
    property bool _failed: false
    property int _progress: 0
    // the last failure was the network (no internet, DNS, timeout), not the page
    property bool _netError: false
    readonly property bool offline: _failed && (_netError || Geo.offline)
    // True between "asked to open" and "the view has a size". A page that lays
    // itself out from its own viewport must not be handed a 0x0 one, and the
    // popup has no geometry until it has been opened. See _beginLoad() below.
    property bool _pending: false

    // What the header chip shows. Derived from App.donateUrl rather than
    // hard-coded, so changing the address in app/constants.py (or config.json)
    // also changes the label — no second place to forget.
    readonly property string host: {
        var u = String(App.donateUrl || "")
        u = u.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "")
        u = u.replace(/^www\./i, "")
        return u.split("/")[0]
    }

    function present() {
        if (!App.donateUrl) return
        if (!root._loaded || root._failed) root._pending = true
        root.open()
    }

    // Starts the first load once the card is on screen and the view has a real
    // size. A binding on `web.width` cannot do this job: `web` lives in the
    // popup's contentItem, which does not exist yet when the properties above
    // are evaluated — a binding that touches it at construction time captures
    // null and never re-runs. So the wait is a function, called from onOpened.
    property int _tries: 0
    function _beginLoad() {
        if (!root._pending) return
        if ((web.width < 40 || web.height < 40) && root._tries < 40) {
            root._tries += 1
            Qt.callLater(root._beginLoad)
            return
        }
        root._tries = 0
        root.reload()
    }
    onOpened: Qt.callLater(root._beginLoad)

    function reload() {
        root.pageLang = ""
        root._pending = false
        root._failed = false
        root._netError = false
        root._progress = 0
        web.url = ""
        web.url = App.donateUrl
        root._loaded = true
    }

    // The ONLY things handed to the operating system are mail and phone links —
    // the two a donation page legitimately uses for "contact us". Everything
    // else that is not a web page is dropped: a page must not be able to make
    // the app launch an arbitrary scheme handler (file:, smb:, a custom
    // protocol that some installed program registered).
    function _handOff(url) {
        var s = String(url || "").toLowerCase()
        if (s.startsWith("mailto:") || s.startsWith("tel:"))
            Qt.openUrlExternally(url)
    }

    // ── post-load wake-up ──────────────────────────────────────────────
    // Insurance for software compositing (RDP, VMs, a VM-style GPU driver):
    // there the view can keep the page's FIRST paint — header, logo, language
    // pill — and never upload the rest, so the card shows a frame with nothing
    // inside even though the load says 100 %. Anything that forces a full
    // repaint fixes it, and the cheapest invisible one is a 0.1 % zoom
    // round-trip: about one pixel at this width, and it cannot lose a
    // half-filled form. Two repaint triggers (down, then back 450 ms later);
    // on a normal GPU this is invisible.
    // ── page language switch (v1.0.4) ──────────────────────────────────
    // The donation page draws its own small language toggle (ENG / FA) as a
    // floating circle pinned against the edge of its "recent donations" box,
    // where it reads as part of that box. It is taken over here: the page's
    // own button is found by its label, hidden, and a "language" control in
    // this card's header clicks it for you. If the page has no such button
    // (or it changes shape), nothing is hidden and nothing shows in the header,
    // so the worst case is exactly the old behaviour.
    property string pageLang: ""
    property int _langTries: 0
    readonly property string _langJs: "(function(){" +
        "var RX=/^(ENG?|EN|FA|FAR|PER|English|Persian|\u0641\u0627|\u0641\u0627\u0631\u0633\u06cc)$/i;" +
        "var S=window.__yhLang;" +
        "if(!S){S=window.__yhLang={el:null,t:0};" +
        " var st=document.createElement('style');" +
        " st.textContent='[data-yh-lang]{display:none !important}';" +
        " (document.head||document.documentElement).appendChild(st);" +
        " new MutationObserver(function(){if(S.el&&document.contains(S.el))return;" +
        "  clearTimeout(S.t);S.t=setTimeout(S.find,250);})" +
        " .observe(document.documentElement,{childList:true,subtree:true});" +
        " S.find=function(){" +
        "  if(S.el&&document.contains(S.el))return S.el;S.el=null;" +
        "  var c=document.querySelectorAll('button,a,[role=button],div,span');" +
        "  for(var i=0;i<c.length;i++){var e=c[i];" +
        "   if(e.children.length>2)continue;" +
        "   var t=(e.textContent||'').trim();if(!RX.test(t))continue;" +
        "   var r=e.getBoundingClientRect();if(r.width<=0||r.width>140||r.height>90)continue;" +
        "   var b=e.querySelector('button,a,[role=button]')||e.closest('button,a,[role=button]')||e;" +
        "   e.setAttribute('data-yh-lang','1');S.el=e;S.btn=b;return e;}" +
        "  return null;};" +
        " S.label=function(){return S.el?(S.el.textContent||'').trim().slice(0,8):'';};" +
        " S.toggle=function(){if(S.find())(S.btn||S.el).click();};" +
        "}" +
        "S.find();return S.label();})()"

    function _hookLang() {
        web.runJavaScript(root._langJs, function(res) {
            root.pageLang = String(res || "")
            // a client-rendered page may draw the toggle a moment after load
            if (root.pageLang === "" && root._langTries < 8) {
                root._langTries += 1
                langRetry.restart()
            }
        })
    }
    function toggleLang() {
        web.runJavaScript("window.__yhLang&&window.__yhLang.toggle();", function() {
            langRelabel.restart()
        })
    }
    Timer { id: langRetry; interval: 700; onTriggered: root._hookLang() }
    // the page re-renders after a switch; read the new label once it settled
    Timer { id: langRelabel; interval: 600; onTriggered: root._hookLang() }

    function _wake() {
        web.zoomFactor = 1.001
        wakeTimer.restart()
    }
    Timer {
        id: wakeTimer
        interval: 450
        onTriggered: web.zoomFactor = 1.0
    }

    // ── offline recovery ───────────────────────────────────────────────
    // While the offline panel is up, knock on the donation host every few
    // seconds with a tiny HEAD request. The first answer of any kind means the
    // network is back: reload. (Reloading the view itself on a timer would
    // flash the loader and the panel in turn.) Geo's own monitor reporting the
    // connection back does the same.
    Timer {
        id: probeTimer
        interval: 4000
        repeat: true
        running: root.opened && root.offline
        onTriggered: root._probe()
    }
    function _probe() {
        var url = String(App.donateUrl || "")
        if (!url) return
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            if (x.status > 0 && root.opened && root.offline) root.reload()
        }
        x.open("HEAD", url)
        x.send()
    }
    Connections {
        target: Geo
        function onConnectionRestored() {
            if (root._failed && root.opened) root.reload()
        }
    }

    onClosed: {
        // drop focus back to the shell so keyboard shortcuts keep working
        if (root.parent) root.parent.forceActiveFocus()
    }

    // ── arrival ────────────────────────────────────────────────────────
    // The card rises a few pixels and settles with the faintest overshoot,
    // and only then does the accent halo bloom out from behind its top edge:
    // two beats, so the open feels placed rather than switched on. Leaving is
    // quicker and quieter than arriving.
    property real _rise: 0
    property real _halo: 0
    property real _breath: 0

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.05 }
        NumberAnimation { target: root; property: "_rise"; from: 22; to: 0; duration: 460; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 140 }
            NumberAnimation { target: root; property: "_halo"; from: 0; to: 1; duration: 820; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1; to: 0.975; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "_rise"; to: 10; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "_halo"; to: 0; duration: 140 }
    }
    // the halo keeps breathing, slowly, for as long as the card is open
    SequentialAnimation {
        running: root.opened
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "_breath"; to: 1; duration: 3200; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "_breath"; to: 0; duration: 3200; easing.type: Easing.InOutSine }
    }

    // ── keyboard ───────────────────────────────────────────────────────
    // Browser muscle memory works inside the card.
    //
    // Esc is a window-level Shortcut, NOT `closePolicy: CloseOnEscape`. With
    // CloseOnEscape the popup item answers the key's shortcut-override and then
    // never acts on the press, so the shortcut is blocked AND nothing closes —
    // the card stayed open on Esc, in every focus state (reproduced with a bare
    // Popup, so it is the popup item's behaviour, not this card's). NoAutoClose
    // above leaves Esc unclaimed, this Shortcut gets it, and it is dispatched
    // before the focused item — so it also works once the page has the keyboard.
    Shortcut {
        sequence: "Esc"
        enabled: root.opened
        onActivated: root.close()
    }
    Shortcut {
        sequences: ["Ctrl+R", "F5"]
        enabled: root.opened
        onActivated: root.reload()
    }
    Shortcut {
        sequence: "Alt+Left"
        enabled: root.opened && web.canGoBack
        onActivated: web.goBack()
    }

    // small keycap used in the footer hints
    component Kbd: Rectangle {
        property alias label: kbdText.text
        implicitHeight: 20
        implicitWidth: Math.max(20, kbdText.implicitWidth + 12)
        radius: 5
        color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.05 : 0.04)
        border.width: 1
        border.color: Theme.border_med
        // keycap bottom lip
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 3; anchors.rightMargin: 3
            height: 1
            color: Theme.border_med
        }
        C.AppText {
            id: kbdText
            anchors.centerIn: parent
            mono: true
            font.pixelSize: Tokens.fontMicro
            color: Theme.on_surface_var
        }
    }

    // v1.0.4: one line in the rail's "what it funds" list
    component Perk: RowLayout {
        id: perk
        property string icon: ""
        property alias label: perkText.text
        spacing: Tokens.space3
        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: Tokens.radiusMd
            antialiasing: true
            color: U.withAlpha(Theme.primary, Theme.isDark ? 0.13 : 0.08)
            border.width: 1
            border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.26 : 0.16)
            C.IconGlyph {
                anchors.centerIn: parent
                name: perk.icon
                fill: true
                size: 16
                glyphColor: Theme.primary
            }
        }
        C.AppText {
            id: perkText
            Layout.fillWidth: true
            font.pixelSize: Tokens.fontBody
            weight: Tokens.weightDemiBold
            color: Theme.on_surface
            wrapMode: Text.WordWrap
        }
    }

    // ── the card ───────────────────────────────────────────────────────
    // A lit object, not a flat box: a soft drop shadow, an accent halo rising
    // from behind the top edge, a rim that is accent-warm at the top and fades
    // to a hairline, a whisper of accent washed down from the top, and a 1 px
    // specular line along the top edge.
    background: Item {
        transform: Translate { y: root._rise }

        C.GlowBlob {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height * 0.42
            size: Math.min(720, parent.width * 0.62)
            glow: Theme.primary
            strength: (Theme.isDark ? 0.22 : 0.10) * root._halo * (0.82 + 0.18 * root._breath)
        }

        BorderImage {
            source: "shadow_soft.png"
            border { left: 64; right: 64; top: 64; bottom: 64 }
            horizontalTileMode: BorderImage.Stretch
            verticalTileMode: BorderImage.Stretch
            smooth: true
            anchors.fill: parent
            anchors.margins: -60
            anchors.topMargin: -60 + 18
            anchors.bottomMargin: -60 - 18
            opacity: Theme.isDark ? 0.75 : 0.16
        }

        Rectangle {
            id: rim
            anchors.fill: parent
            radius: Tokens.radiusXl
            antialiasing: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: U.mix(Theme.border_med, Theme.primary, Theme.isDark ? 0.55 : 0.40) }
                GradientStop { position: 0.22; color: Theme.border_med }
                GradientStop { position: 1.0; color: Theme.border }
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Tokens.radiusXl - 1
            antialiasing: true
            color: Theme.surface

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                antialiasing: true
                // v1.0.4: ends above the page frame — the frame's rounded
                // corner caps are plain Theme.surface and must match
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.085 : 0.045) }
                    GradientStop { position: Math.min(0.2, 60 / Math.max(1, root.height)); color: U.withAlpha(Theme.primary, 0.0) }
                }
            }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.7
            height: 1
            // v1.0.4: the lit edge carries the accent out to both sides and
            // burns white in the middle, like light caught on a glass lip
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0) }
                GradientStop { position: 0.3; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.55 : 0.40) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.40 : 0.85) }
                GradientStop { position: 0.7; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.55 : 0.40) }
                GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0) }
            }
        }
    }

    contentItem: RowLayout {
        spacing: 0
        transform: Translate { y: root._rise }

        // ── rail (v1.0.4) ─────────────────────────────────────────────
        // Brand, what a donation funds, and the security promise, so the page
        // on the right can be just the page. Static apart from the heart.
        Item {
            id: rail
            visible: root.wide
            Layout.preferredWidth: root._railW
            Layout.fillHeight: true
            clip: true      // squares off the wash's right edge at the divider

            HoverHandler { id: railHover }

            // wash: accent at the top fading into a faint tint. Rounded like
            // the card on the left, and wider than the rail so the clip above
            // cuts its right corners away.
            Rectangle {
                x: 1; y: 1
                width: parent.width + 40
                height: parent.height - 2
                radius: Tokens.radiusXl - 1
                antialiasing: true
                gradient: Gradient {
                    GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.11 : 0.06) }
                    GradientStop { position: 0.42; color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.018 : 0.014) }
                    GradientStop { position: 1.0; color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.018 : 0.014) }
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: Tokens.space5
                anchors.bottomMargin: Tokens.space5
                width: 1
                color: Theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 28
                anchors.rightMargin: 28
                anchors.topMargin: 30
                anchors.bottomMargin: Tokens.space5
                spacing: 0

                // brand tile: the accent as a glossy app-icon square with the
                // beating heart in white (same language as Hunter's chat mark)
                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 18
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.mix(Theme.logo_grad_in, "#FFFFFF", 0.14) }
                        GradientStop { position: 0.55; color: Theme.logo_grad_in }
                        GradientStop { position: 1.0; color: U.mix(Theme.logo_grad_out, "#000000", 0.18) }
                    }
                    border.width: 1
                    border.color: Theme.isDark ? Qt.rgba(0, 0, 0, 0.4) : U.withAlpha(Theme.logo_grad_out, 0.22)
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        antialiasing: true
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.30) }
                            GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, 0.04) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        antialiasing: true
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                    }
                    C.HeartBeat {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1
                        size: 26
                        hot: "#FFFFFF"
                        deep: U.mix("#FFFFFF", Theme.primary, 0.22)
                        racing: railHover.hovered
                        running: root.opened && root.wide
                    }
                }

                C.AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space5
                    text: I18n.tr("Support YouTube Hunter")
                    font.pixelSize: Tokens.fontTitle
                    font.letterSpacing: -0.5
                    weight: Tokens.weightExtraBold
                    color: Theme.text_strong
                    wrapMode: Text.WordWrap
                }
                C.AppText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space2
                    text: I18n.tr("Your support keeps the updates coming.")
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface_var
                    wrapMode: Text.WordWrap
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space6
                    spacing: Tokens.space3
                    Perk { Layout.fillWidth: true; icon: "bolt"; label: I18n.tr("Faster fixes and updates") }
                    Perk { Layout.fillWidth: true; icon: "auto_awesome"; label: I18n.tr("New AI features") }
                    Perk { Layout.fillWidth: true; icon: "favorite"; label: I18n.tr("Keeps it independent") }
                }

                Item { Layout.fillHeight: true }

                // the security promise, as a card of its own
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: secCol.implicitHeight + Tokens.space4 * 2
                    radius: Tokens.radiusLg
                    antialiasing: true
                    color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.07 : 0.06)
                    border.width: 1
                    border.color: U.withAlpha(Theme.secondary_container, Theme.isDark ? 0.24 : 0.22)

                    ColumnLayout {
                        id: secCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.space4
                        anchors.rightMargin: Tokens.space4
                        spacing: Tokens.space2

                        RowLayout {
                            spacing: Tokens.space2
                            Rectangle {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: 11
                                color: U.withAlpha(Theme.secondary_container, 0.18)
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    name: "lock"
                                    fill: true
                                    size: 12
                                    glyphColor: Theme.secondary_container
                                }
                            }
                            C.AppText {
                                text: I18n.tr("Secure checkout")
                                font.pixelSize: Tokens.fontBody
                                weight: Tokens.weightBold
                                color: Theme.text_strong
                            }
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: I18n.tr("Payments run on the provider's own secure page. Nothing is stored in this app.")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface_var
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.space4
                    spacing: Tokens.space2
                    C.AppText {
                        Layout.fillWidth: true
                        text: I18n.tr("Thank you for being here.")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        implicitHeight: 20
                        implicitWidth: railVer.implicitWidth + 14
                        radius: Tokens.radiusPill
                        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.08)
                        C.AppText {
                            id: railVer
                            anchors.centerIn: parent
                            text: "v" + App.version
                            mono: true
                            font.pixelSize: Tokens.fontMicro
                            color: U.mix(Theme.on_surface_var, Theme.primary, 0.45)
                        }
                    }
                }
            }
        }

        // ── right column: header, page, footer ────────────────────────
        ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        // ── header ────────────────────────────────────────────────────
        Item {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: root.wide ? 68 : 78

            // where the view actually is right now (the gateway may move on to
            // a bank page) — so the security chip always tells the truth
            readonly property string pageUrl: String(web.url || "") !== "" ? String(web.url) : String(App.donateUrl || "")
            readonly property string pageHost: {
                var u = pageUrl.replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "").replace(/^www\./i, "")
                var h = u.split("/")[0].split("?")[0]
                return h || root.host
            }
            readonly property bool secure: pageUrl.toLowerCase().startsWith("https://")
            readonly property color secureColor: secure ? Theme.secondary_container : Theme.warn

            HoverHandler { id: headHover }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space4
                spacing: Tokens.space3

                // the heart tile — a glass chip with the app's beating heart in
                // it; hovering the header makes it race. (Wide card: the rail
                // carries the brand, so the header is just the browser bar.)
                Rectangle {
                    visible: !root.wide
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignVCenter
                    radius: 14
                    antialiasing: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.28 : 0.16) }
                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.07 : 0.04) }
                    }
                    border.width: 1
                    border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.40 : 0.28)

                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 22
                        height: 1
                        color: Qt.rgba(1, 1, 1, Theme.isDark ? 0.22 : 0.6)
                    }
                    C.HeartBeat {
                        anchors.centerIn: parent
                        size: 20
                        racing: headHover.hovered
                        running: root.opened && !root.wide
                    }
                }

                ColumnLayout {
                    visible: !root.wide
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 2
                    spacing: 3

                    C.AppText {
                        text: I18n.tr("Support YouTube Hunter")
                        font.pixelSize: Tokens.fontSubtitle
                        font.letterSpacing: -0.2
                        weight: Tokens.weightBold
                        color: Theme.text_strong
                    }
                    C.AppText {
                        text: I18n.tr("Your support keeps the updates coming.")
                        font.pixelSize: Tokens.fontCaption
                        color: Theme.on_surface_var
                    }
                }

                Item { Layout.fillWidth: true; visible: !root.wide }

                // security chip: lock + Secure + the live host. Click opens the
                // same page in the browser.
                Rectangle {
                    id: addr
                    Layout.alignment: Qt.AlignVCenter
                    // wide card: a full address bar (Safari-style, host centred)
                    Layout.fillWidth: root.wide
                    implicitHeight: root.wide ? 38 : 32
                    implicitWidth: Math.min(320, addrRow.implicitWidth + 22)
                    radius: Tokens.radiusPill
                    color: U.withAlpha(Theme.on_surface, addrHover.hovered ? 0.07 : 0.035)
                    border.width: 1
                    border.color: addrHover.hovered ? Theme.border_med : Theme.border
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }

                    HoverHandler { id: addrHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: App.openDonateExternal() }
                    C.AppTooltip {
                        visible: addrHover.hovered
                        delay: 400
                        text: I18n.tr("Open this page in your browser")
                    }

                    RowLayout {
                        id: addrRow
                        anchors.centerIn: parent
                        spacing: 7

                        Rectangle {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            radius: 9
                            color: U.withAlpha(header.secureColor, 0.16)
                            C.IconGlyph {
                                anchors.centerIn: parent
                                name: "lock"
                                fill: true
                                size: 11
                                glyphColor: header.secureColor
                            }
                        }
                        C.AppText {
                            text: header.secure ? I18n.tr("Secure") : I18n.tr("Not secure")
                            font.pixelSize: Tokens.fontCaption
                            weight: Tokens.weightDemiBold
                            color: header.secureColor
                        }
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 12
                            color: Theme.border_med
                        }
                        C.AppText {
                            Layout.maximumWidth: root.wide ? 420 : 190
                            text: header.pageHost
                            mono: true
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.on_surface
                            elide: Text.ElideMiddle
                        }
                    }
                }

                // browser controls, grouped in one pill
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 36
                    implicitWidth: navRow.implicitWidth + 4
                    radius: Tokens.radiusPill
                    color: U.withAlpha(Theme.on_surface, 0.035)
                    border.width: 1
                    border.color: Theme.border

                    RowLayout {
                        id: navRow
                        anchors.centerIn: parent
                        spacing: 0

                        // the page's language switch, moved up here (v1.0.4)
                        AbstractButton {
                            id: langBtn
                            visible: root.pageLang !== "" && !root._failed
                            Layout.preferredHeight: 32
                            Layout.preferredWidth: langRow.implicitWidth + 20
                            hoverEnabled: true
                            onClicked: root.toggleLang()
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            C.AppTooltip {
                                visible: langBtn.hovered
                                delay: 400
                                text: I18n.tr("Switch the page language")
                            }
                            background: Rectangle {
                                radius: Tokens.radiusPill
                                color: langBtn.pressed ? Theme.hover_bg_strong
                                       : langBtn.hovered ? Theme.hover_bg : "transparent"
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                            }
                            contentItem: Item {
                                Row {
                                    id: langRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    C.IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "translate"
                                        size: 15
                                        glyphColor: langBtn.hovered ? Theme.on_surface : Theme.on_surface_var
                                    }
                                    C.AppText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.pageLang.toUpperCase()
                                        mono: true
                                        font.pixelSize: Tokens.fontMicro
                                        weight: Tokens.weightBold
                                        color: langBtn.hovered ? Theme.text_strong : Theme.on_surface
                                    }
                                }
                            }
                        }
                        Rectangle {
                            visible: langBtn.visible
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 16
                            Layout.leftMargin: 2
                            Layout.rightMargin: 2
                            color: Theme.border_med
                        }

                        // the gateway may navigate a few pages deep (amount ->
                        // bank -> back); a way back beats starting over
                        C.IconButton {
                            visible: web.canGoBack
                            chromeless: true
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            iconName: "arrow_back"
                            glyphSize: 16
                            tip: I18n.tr("Back  (Alt+←)")
                            onClicked: web.goBack()
                        }
                        C.IconButton {
                            id: reloadBtn
                            chromeless: true
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            iconName: "refresh"
                            glyphSize: 16
                            tip: I18n.tr("Reload  (Ctrl+R)")
                            onClicked: root.reload()
                            // the glyph turns while the page is loading
                            RotationAnimator {
                                target: reloadBtn.contentItem
                                from: 0; to: 360
                                duration: 900
                                loops: Animation.Infinite
                                running: web.loading && root.opened
                                onRunningChanged: if (!running && reloadBtn.contentItem) reloadBtn.contentItem.rotation = 0
                            }
                        }
                        C.IconButton {
                            chromeless: true
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            iconName: "open_in_new"
                            glyphSize: 16
                            tip: I18n.tr("Open in your browser")
                            onClicked: {
                                App.openDonateExternal()
                                root.close()
                            }
                        }
                    }
                }

                C.IconButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    iconName: "close"
                    glyphSize: 17
                    tip: I18n.tr("Close  (Esc)")
                    onClicked: root.close()
                }
            }

            // hairline + live load line. After the first load the veil is gone,
            // so a gateway step (amount -> bank) shows its progress here, as a
            // thin accent beam with a bright head, the way a browser would.
            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Tokens.space4
                anchors.rightMargin: Tokens.space4
                height: 2

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.border
                    opacity: 0.8
                }
                Rectangle {
                    id: loadLine
                    readonly property bool beaming: web.loading && !veil.wanted && !root._failed
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    width: parent.width * Math.max(0.04, web.loadProgress / 100)
                    opacity: beaming ? 1 : 0
                    Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: loadLine.beaming ? 120 : 420; easing.type: Easing.OutCubic } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, 0.0) }
                        GradientStop { position: 0.7; color: Theme.primary }
                        GradientStop { position: 1.0; color: U.mix(Theme.primary, "#FFFFFF", 0.55) }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 6; radius: 3
                        color: U.withAlpha(U.mix(Theme.primary, "#FFFFFF", 0.4), 0.55)
                    }
                }
            }
        }
        // ── the page ──────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Tokens.space3

            Rectangle {
                id: frame
                anchors.fill: parent
                // Square on purpose. A rounded Rectangle does NOT round its
                // children's clip — `clip: true` is rectangular — so a radius
                // here would only round the hairline border and then have the
                // page's own square corners cut it into four gaps. The card
                // around it is rounded; this is the viewport.
                // v1.0.4: the viewport now LOOKS rounded. A clip cannot round
                // (see above), so four corner caps in the card's colour are laid
                // over the page's square corners, and the hairline is drawn on
                // top as a rounded outline. Static, so they cost nothing.
                radius: 0
                color: Theme.surface_low
                border.width: 0
                clip: true

                WebEngineView {
                    id: web
                    anchors.fill: parent
                    anchors.margins: 1
                    backgroundColor: Theme.isDark ? "#0E0E11" : "#FFFFFF"
                    zoomFactor: 1.0
                    // never paint Chromium's own "This site can't be reached"
                    // page inside the card; the app's panel below says it better
                    settings.errorPageEnabled: false

                    // The donation page is a third-party Next.js site; its own
                    // console chatter ("resource was preloaded using link
                    // preload but not used…") is not ours to fix and only
                    // floods the app log. Handling the signal stops QtWebEngine
                    // forwarding it to the log; nothing is printed on purpose.
                    onJavaScriptConsoleMessage: (level, message, lineNumber, sourceID) => { }

                    onLoadingChanged: (req) => {
                        if (req.status === WebEngineView.LoadStartedStatus) {
                            root._failed = false
                            root._netError = false
                            root._progress = 0
                        } else if (req.status === WebEngineView.LoadSucceededStatus) {
                            root._langTries = 0
                            root._hookLang()
                            root._failed = false
                            root._wake()
                        } else if (req.status === WebEngineView.LoadFailedStatus) {
                            // Chromium net errors: -1xx = connection (incl.
                            // -106 INTERNET_DISCONNECTED, -105 NAME_NOT_RESOLVED),
                            // -21 NETWORK_CHANGED, -7 TIMED_OUT
                            var c = req.errorCode
                            // -3 ABORTED: a load replaced by the next one
                            // (reload() does exactly that) — not a failure
                            if (c === -3) return
                            root._netError = (c <= -100 && c > -200) || c === -21 || c === -7
                            root._failed = true
                        }
                    }
                    // progress 100 is the trigger, not LoadSucceeded: a donation
                    // page usually keeps one long-lived request open (analytics,
                    // a live "recent donations" feed), so LoadSucceeded can be
                    // minutes away even though the page is fully painted.
                    onLoadProgressChanged: {
                        root._progress = web.loadProgress
                        if (web.loadProgress >= 100) {
                            root._wake()
                            root._langTries = 0
                            root._hookLang()
                        }
                    }

                    // Anything that is not a web page (a `tel:`, a `mailto:`, an
                    // app deep link) must not be loaded INTO the card: WebEngine
                    // would fail the load and the donor would see the "didn't
                    // load" panel for a link that was never meant to open here.
                    // Hand it to the OS instead.
                    onNavigationRequested: (request) => {
                        var u = String(request.url || "").toLowerCase()
                        var ok = u.startsWith("http://") || u.startsWith("https://")
                                || u.startsWith("about:") || u.startsWith("blob:")
                                || u.startsWith("data:")
                        if (ok) request.accept()
                        else {
                            request.reject()
                            root._handOff(request.url)
                        }
                    }

                    // A payment gateway frequently hands off with window.open.
                    // Without this handler that click is silently swallowed and
                    // the flow looks broken; taking the request over keeps the
                    // whole payment inside the card (and the Back button above
                    // gets you out of it).
                    onNewWindowRequested: (request) => {
                        var u = String(request.requestedUrl || "").toLowerCase()
                        if (u && !u.startsWith("http://") && !u.startsWith("https://")
                                && !u.startsWith("about:")) {
                            root._handOff(request.requestedUrl)
                            return
                        }
                        request.openIn(web)
                    }

                    // Chromium's renderer can die (GPU reset, out of memory).
                    // Without this the card would sit on a blank white page
                    // forever with no hint that anything went wrong.
                    onRenderProcessTerminated: (status, exitCode) => {
                        root._failed = true
                    }
                }

                // loading veil — "Heartline" (components/DonateLoader.qml):
                // the brand mark beating lub-dub inside a ring that fills with
                // the page's real progress. It fades out (and the mark blooms
                // forward) rather than blinking off the instant the page
                // lands: the switch from "opening…" to a fully-painted page is
                // the one moment this card can look abrupt.
                Item {
                    id: veil
                    anchors.fill: parent
                    readonly property bool wanted: !root._failed && root._progress < 100
                    opacity: wanted ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity {
                        enabled: !Tokens.themeSwapping
                        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
                    }

                    C.DonateLoader {
                        anchors.fill: parent
                        progress: root._progress
                        host: root.host
                        running: veil.visible && root.visible
                        leaving: !veil.wanted
                    }
                }

                // failure — an OPAQUE panel. Chromium's own error page is off
                // (settings.errorPageEnabled above), and this sits on a solid
                // base, so a dropped connection never shows a browser error
                // bleeding through the card. Offline gets its own state that
                // watches for the connection and reopens the page by itself.
                Rectangle {
                    id: failPanel
                    anchors.fill: parent
                    color: Theme.isDark ? "#0E0E11" : "#FFFFFF"
                    opacity: root._failed ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity {
                        enabled: !Tokens.themeSwapping
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    // swallow clicks so nothing reaches the dead page below
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

                    C.GlowBlob {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -60
                        size: Math.min(parent.width, parent.height) * 0.45
                        glow: root.offline ? Theme.warn : Theme.primary
                        strength: Theme.isDark ? 0.10 : 0.06
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Tokens.space3
                        width: Math.min(380, parent.width - 80)

                        // offline: a signal glyph whose arcs keep "searching"
                        Item {
                            id: signal
                            visible: root.offline
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 60
                            property real scan: 0
                            readonly property real cx: width / 2
                            readonly property real cy: height - 8

                            NumberAnimation {
                                target: signal; property: "scan"; from: 0; to: 3
                                duration: 1800; loops: Animation.Infinite
                                running: signal.visible && failPanel.visible
                            }

                            Repeater {
                                model: 3
                                delegate: Shape {
                                    required property int index
                                    anchors.fill: parent
                                    preferredRendererType: Shape.CurveRenderer
                                    // arc lights up as the scan passes it
                                    readonly property real lit: Math.max(0, 1 - Math.abs(signal.scan - index - 0.5))
                                    opacity: 0.22 + 0.6 * lit
                                    ShapePath {
                                        fillColor: "transparent"
                                        strokeColor: Theme.warn
                                        strokeWidth: 4
                                        capStyle: ShapePath.RoundCap
                                        PathAngleArc {
                                            centerX: signal.cx; centerY: signal.cy
                                            radiusX: 14 + index * 14; radiusY: 14 + index * 14
                                            startAngle: -135; sweepAngle: 90
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                x: signal.cx - 4; y: signal.cy - 4
                                color: Theme.warn
                            }
                            // the slash
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Theme.isDark ? "#0E0E11" : "#FFFFFF"
                                    strokeWidth: 9
                                    capStyle: ShapePath.RoundCap
                                    startX: 14; startY: 6
                                    PathLine { x: 58; y: 52 }
                                }
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Theme.text_strong
                                    strokeWidth: 3.5
                                    capStyle: ShapePath.RoundCap
                                    startX: 14; startY: 6
                                    PathLine { x: 58; y: 52 }
                                }
                            }
                        }

                        C.IconGlyph {
                            visible: !root.offline
                            Layout.alignment: Qt.AlignHCenter
                            name: "error"
                            size: 30
                            glyphColor: Theme.warn
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.space1
                            text: root.offline ? I18n.tr("You're offline")
                                               : I18n.tr("The donation page didn't load.")
                            font.pixelSize: Tokens.fontSubtitle
                            weight: Tokens.weightDemiBold
                            color: Theme.text_strong
                            horizontalAlignment: Text.AlignHCenter
                        }
                        C.AppText {
                            Layout.fillWidth: true
                            text: root.offline
                                  ? I18n.tr("The donation page will open by itself as soon as you're back online.")
                                  : I18n.tr("Check your connection, or open the same page in your browser.")
                            font.pixelSize: Tokens.fontBody
                            color: Theme.on_surface_var
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // offline: "waiting" chip with a live dot
                        Rectangle {
                            visible: root.offline
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Tokens.space1
                            implicitHeight: 28
                            implicitWidth: waitRow.implicitWidth + Tokens.space4 * 2
                            radius: Tokens.radiusPill
                            color: U.withAlpha(Theme.warn, 0.10)
                            border.width: 1
                            border.color: U.withAlpha(Theme.warn, 0.30)
                            RowLayout {
                                id: waitRow
                                anchors.centerIn: parent
                                spacing: Tokens.space2
                                Rectangle {
                                    id: waitDot
                                    width: 7; height: 7; radius: 3.5
                                    color: Theme.warn
                                    SequentialAnimation on opacity {
                                        running: root.offline && failPanel.visible
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                                    }
                                }
                                C.AppText {
                                    text: I18n.tr("Waiting for connection")
                                    font.pixelSize: Tokens.fontCaption
                                    weight: Tokens.weightMedium
                                    color: Theme.on_surface
                                }
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Tokens.space2
                            spacing: Tokens.space2

                            C.PrimaryButton {
                                text: I18n.tr("Try again")
                                iconName: "refresh"
                                onClicked: root.reload()
                            }
                            C.PrimaryButton {
                                visible: !root.offline
                                variant: "ghost"
                                text: I18n.tr("Open in browser")
                                iconName: "open_in_new"
                                onClicked: {
                                    App.openDonateExternal()
                                    root.close()
                                }
                            }
                        }
                    }
                }

                // rounded corners: caps (card colour) + outline
                Repeater {
                    model: 4
                    delegate: Shape {
                        required property int index
                        width: root._frameR; height: root._frameR
                        x: (index === 1 || index === 2) ? frame.width - width : 0
                        y: index >= 2 ? frame.height - height : 0
                        rotation: index * 90
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: "transparent"
                            strokeWidth: -1
                            fillColor: Theme.surface
                            startX: 0; startY: 0
                            PathLine { x: root._frameR; y: 0 }
                            PathArc {
                                x: 0; y: root._frameR
                                radiusX: root._frameR; radiusY: root._frameR
                                direction: PathArc.Counterclockwise
                            }
                            PathLine { x: 0; y: 0 }
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: root._frameR
                    antialiasing: true
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.border
                }
            }
        }

        // ── footer ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.wide ? 44 : 48

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.space5
                anchors.rightMargin: Tokens.space5
                spacing: Tokens.space2

                C.IconGlyph {
                    visible: !root.wide
                    name: "lock"
                    fill: true
                    size: 13
                    glyphColor: Theme.secondary_container
                }
                // wide card: the security line lives in the rail
                Item { Layout.fillWidth: true; visible: root.wide }
                C.AppText {
                    visible: !root.wide
                    Layout.fillWidth: true
                    text: I18n.tr("Payments run on the provider's own secure page. Nothing is stored in this app.")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    elide: Text.ElideRight
                }

                // keyboard hints: quiet keycaps, the way a pro tool says it
                Kbd { label: "Esc" }
                C.AppText {
                    text: I18n.tr("close")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    Layout.rightMargin: Tokens.space2
                }
                Kbd { label: "Ctrl R" }
                C.AppText {
                    text: I18n.tr("reload")
                    font.pixelSize: Tokens.fontCaption
                    color: Theme.on_surface_var
                    Layout.rightMargin: root.wide ? 0 : Tokens.space3
                }
                Rectangle {
                    visible: !root.wide
                    implicitHeight: 20
                    implicitWidth: verText.implicitWidth + 14
                    radius: Tokens.radiusPill
                    color: U.withAlpha(Theme.primary, Theme.isDark ? 0.12 : 0.08)
                    C.AppText {
                        id: verText
                        anchors.centerIn: parent
                        text: "v" + App.version
                        mono: true
                        font.pixelSize: Tokens.fontMicro
                        color: U.mix(Theme.on_surface_var, Theme.primary, 0.45)
                    }
                }
            }
        }
        }
    }
}
