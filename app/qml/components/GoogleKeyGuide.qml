import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import NicheScope
import "." as C
import "../Utils.js" as U

// v18 Settings section: "Google keys, step by step".
//
// The v17 guide was two collapsed lines inside the YouTube card, and it was
// out of date (the Cloud console now REQUIRES an API restriction before it
// will create a key, and Gemini keys are their own thing since the May 2026
// auth-key change). This is a full section with two tracks:
//
//   [ YouTube Data API v3 · required ]  [ Gemini API · optional ]
//   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  3 / 6 done
//   ① Sign in to Google Cloud        [Open page ↗] [⧉]
//   │  console.cloud.google.com
//   ② Create a project …
//   │  Project picker › New project › Create
//   …
//   ▸ When something goes wrong   (real error codes → the fix)
//
// Steps are a real sequence, so they are numbered and joined by a rail. Each
// node is a checkbox: tick it off as you go, the rail fills behind you and the
// next step pulses. The last step of each track wires straight back into the
// app ("Go to the key field" / "Use Gemini"), so the guide ends where the key
// goes. Ticks are per-session only; nothing here is persisted.
//
// Facts checked against Google's docs (Oct 2026):
//  • console: Credentials → Create credentials → API key, and the console
//    asks for at least one API restriction before it creates the key;
//  • YouTube Data API: 10,000 units/day per PROJECT, reset at midnight PT,
//    search.list = 100 units, no billing account needed;
//  • Gemini: AI Studio → API keys → Create API key; new keys are auth keys
//    restricted to the Gemini API, unrestricted standard keys are rejected.
C.GlassPanel {
    id: root

    property string track: "youtube"      // "youtube" | "gemini"
    property bool dimmed: false
    property int maskYt: 0
    property int maskAi: 0
    property bool troubleOpen: false

    signal keyFieldRequested()            // jump to the YouTube key field
    signal geminiRequested()              // pick Gemini + jump to AI Provider

    function show(t) { root.track = t }
    function flash() { flashAnim.restart() }

    readonly property bool isYt: root.track === "youtube"
    readonly property var steps: root.isYt ? root.ytSteps : root.aiSteps
    readonly property int mask: root.isYt ? root.maskYt : root.maskAi
    function isDone(i) { return ((root.mask >> i) & 1) === 1 }
    function toggle(i) {
        if (root.isYt) root.maskYt = root.maskYt ^ (1 << i)
        else root.maskAi = root.maskAi ^ (1 << i)
    }
    readonly property int doneCount: {
        let n = 0
        for (let i = 0; i < root.steps.length; i++)
            if (((root.mask >> i) & 1) === 1) n++
        return n
    }
    // first step that is not ticked yet: the one that pulses
    readonly property int nextStep: {
        for (let i = 0; i < root.steps.length; i++)
            if (((root.mask >> i) & 1) === 0) return i
        return -1
    }

    readonly property var ytSteps: [
        { t: I18n.tr("Sign in to Google Cloud"),
          d: I18n.tr("Open the Cloud Console with any Google account. On the first visit pick your country and accept the terms. No credit card or billing account is needed for this API."),
          path: ["console.cloud.google.com"],
          url: "https://console.cloud.google.com/", act: "" },
        { t: I18n.tr("Create a project"),
          d: I18n.tr("Open the project picker in the top bar, choose New project, give it a name such as YouTubeHunter and press Create. Then make sure the new project is the one selected in the top bar."),
          path: ["Project picker", "New project", "Create"],
          url: "https://console.cloud.google.com/projectcreate", act: "" },
        { t: I18n.tr("Enable YouTube Data API v3"),
          d: I18n.tr("In the API Library open YouTube Data API v3 and press Enable. Skip this and the key still gets created, but every request fails with error 403."),
          path: ["APIs & Services", "Library", "YouTube Data API v3", "Enable"],
          url: "https://console.cloud.google.com/apis/library/youtube.googleapis.com", act: "" },
        { t: I18n.tr("Create the API key"),
          d: I18n.tr("Go to Credentials, press Create credentials and choose API key. The console asks for at least one API restriction: select YouTube Data API v3. Leave the service-account option unticked and Application restrictions on None, then press Create."),
          path: ["Credentials", "Create credentials", "API key", "YouTube Data API v3"],
          url: "https://console.cloud.google.com/apis/credentials", act: "" },
        { t: I18n.tr("Copy the key"),
          d: I18n.tr("The API key created dialog shows a string that starts with AIza and is 39 characters long. Copy all of it. You can show it again any time from Credentials → Show key."),
          path: ["API key created", "Copy"],
          url: "https://console.cloud.google.com/apis/credentials", act: "" },
        { t: I18n.tr("Paste it into YouTube Hunter"),
          d: I18n.tr("Paste it into Primary key above, press Validate, then Save. A brand-new key or a just-enabled API can take up to 5 minutes to start working. Want more quota? Repeat steps 2 to 5 in a new project and add that key as a backup."),
          path: [],
          url: "", act: "key" }
    ]
    readonly property var aiSteps: [
        { t: I18n.tr("Open Google AI Studio"),
          d: I18n.tr("Sign in with your Google account and accept the terms. A brand-new account gets a default project, and often a first key, created automatically."),
          path: ["aistudio.google.com/apikey"],
          url: "https://aistudio.google.com/apikey", act: "" },
        { t: I18n.tr("Create an API key"),
          d: I18n.tr("On the API keys page press Create API key and pick a project, or let AI Studio create one. Keys made here are auth keys, already restricted to the Gemini API, which is exactly what it now requires."),
          path: ["Dashboard", "API keys", "Create API key"],
          url: "https://aistudio.google.com/apikey", act: "" },
        { t: I18n.tr("Copy the key"),
          d: I18n.tr("Copy the whole key. Keep it separate from your YouTube key: a key restricted to YouTube cannot call Gemini, and Gemini rejects unrestricted keys."),
          path: ["API keys", "Copy"],
          url: "", act: "" },
        { t: I18n.tr("Paste it into AI Provider"),
          d: I18n.tr("Choose Gemini, paste the key, press Validate, then Save. Fetch models lists every model this key can use. The free tier is rate-limited; turning on billing for the project lifts the limits."),
          path: [],
          url: "", act: "gemini" }
    ]

    readonly property var ytTrouble: [
        { c: "403 · accessNotConfigured", f: I18n.tr("YouTube Data API v3 is not enabled in this key's project. Do step 3, wait a couple of minutes, validate again.") },
        { c: "403 · quotaExceeded",       f: I18n.tr("Today's 10,000 units are spent. Wait for the midnight Pacific reset, or add a backup key from a different project.") },
        { c: "400 · API key not valid",   f: I18n.tr("Part of the key is missing or has a space in it. Copy it again from Credentials → Show key.") },
        { c: "403 · Requests blocked",    f: I18n.tr("An application restriction (websites, IP addresses, apps) is set on the key. For a desktop app set Application restrictions to None.") }
    ]
    readonly property var aiTrouble: [
        { c: "400 · User location is not supported", f: I18n.tr("The Gemini API only answers requests from supported regions. The proxy under AI Provider → Connection & routing applies to AI calls only.") },
        { c: "403 · Key blocked / unrestricted",     f: I18n.tr("Old unrestricted or long-unused standard keys are blocked. Create a fresh key in AI Studio.") },
        { c: "429 · RESOURCE_EXHAUSTED",             f: I18n.tr("Free-tier rate limit reached. Wait a minute, pick a lighter model, or enable billing on the project.") },
        { c: I18n.tr("No permission to create a key"),  f: I18n.tr("The project belongs to an organisation you can't manage. Create a new project that isn't tied to an organisation.") }
    ]

    Layout.fillWidth: true
    radius: Tokens.radiusXl
    implicitHeight: col.implicitHeight + Tokens.space6 * 2
    opacity: root.dimmed ? 0.38 : 1.0
    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }

    Rectangle {
        id: flashRing
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        opacity: 0
        z: 50
        SequentialAnimation {
            id: flashAnim
            PauseAnimation { duration: 180 }
            NumberAnimation { target: flashRing; property: "opacity"; to: 0.9; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: flashRing; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutSine }
        }
    }

    // ── track card ──
    component TrackCard: AbstractButton {
        id: tc
        property string glyph: ""
        property string name: ""
        property string caption: ""
        property var facts: []
        property bool active: false
        property color tint: Theme.primary
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: tcCol.implicitHeight + 18 * 2
        hoverEnabled: true
        padding: 0
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        scale: tc.pressed ? 0.985 : 1.0
        Behavior on scale { NumberAnimation { duration: Tokens.durFast; easing.type: Easing.OutCubic } }

        background: Item {
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: Tokens.radiusXl + 4
                color: "transparent"
                border.width: 4
                border.color: U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.12)
                opacity: tc.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
            }
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusXl
                clip: true
                color: tc.hovered && !tc.active ? U.hoverTint(Theme.surface_low, Theme.isDark, 0.05) : Theme.surface_low
                border.width: 1
                border.color: tc.active ? Theme.primary : tc.hovered ? Theme.border_med : Theme.border
                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                Behavior on border.color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    opacity: tc.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: U.withAlpha(Theme.primary, Theme.isDark ? 0.14 : 0.08) }
                        GradientStop { position: 1.0; color: U.withAlpha(Theme.primary, 0.0) }
                    }
                }
            }
        }
        contentItem: Item {
            RowLayout {
                id: tcCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: Tokens.space4
                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    Layout.alignment: Qt.AlignTop
                    radius: 14
                    color: tc.active ? Theme.primary : U.withAlpha(tc.tint, Theme.isDark ? 0.16 : 0.12)
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                    C.IconGlyph {
                        anchors.centerIn: parent
                        name: tc.glyph
                        fill: true
                        size: 22
                        glyphColor: tc.active ? Theme.on_primary : U.mix(tc.tint, Theme.text_strong, Theme.isDark ? 0.25 : 0.0)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    C.AppText {
                        text: tc.name
                        weight: Tokens.weightBold
                        font.pixelSize: Tokens.fontSubtitle - 1
                        color: Theme.text_strong
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    C.AppText {
                        text: tc.caption
                        font.pixelSize: Tokens.fontCaption + 1
                        color: Theme.on_surface_var
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 6
                        Repeater {
                            model: tc.facts
                            Rectangle {
                                radius: Tokens.radiusPill
                                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.06 : 0.05)
                                border.width: 1
                                border.color: Theme.border
                                implicitWidth: factTxt.implicitWidth + 18
                                implicitHeight: 24
                                width: implicitWidth
                                height: implicitHeight
                                C.AppText {
                                    id: factTxt
                                    anchors.centerIn: parent
                                    text: modelData
                                    weight: Tokens.weightDemiBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.on_surface
                                }
                            }
                        }
                    }
                }
                // radio
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    Layout.alignment: Qt.AlignTop
                    radius: 11
                    color: tc.active ? Theme.primary : "transparent"
                    border.width: tc.active ? 0 : 1.5
                    border.color: tc.hovered ? Theme.outline : U.mix(Theme.border, Theme.outline, 0.5)
                    C.IconGlyph {
                        anchors.centerIn: parent
                        visible: tc.active
                        name: "check"; size: 13
                        glyphColor: Theme.on_primary
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.space6
        spacing: Tokens.space5

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space4
            C.IconTile {
                iconName: "key"
                size: 44
                lit: ghHover.hovered
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignVCenter
                HoverHandler { id: ghHover }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                C.AppText {
                    text: I18n.tr("Google key guide")
                    weight: Tokens.weightBold
                    font.pixelSize: Tokens.fontSubtitle + 2
                    color: Theme.text_strong
                }
                C.AppText {
                    text: I18n.tr("The exact clicks for both Google keys YouTube Hunter uses. Free, about five minutes each.")
                    font.pixelSize: Tokens.fontBody
                    color: Theme.on_surface_var
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        // ── tracks ──
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 760 ? 1 : 2
            columnSpacing: Tokens.space4
            rowSpacing: Tokens.space4
            TrackCard {
                glyph: "youtube"
                tint: "#FF3B30"
                name: "YouTube Data API v3"
                caption: I18n.tr("Search, video and channel stats. Required for every scrape.")
                facts: [I18n.tr("Free"), I18n.tr("10,000 units / day"), I18n.tr("6 steps")]
                active: root.isYt
                onClicked: root.track = "youtube"
            }
            TrackCard {
                glyph: "provider_gemini"
                tint: "#4C8DF6"
                name: "Gemini API"
                caption: I18n.tr("AI Ideas, CSV reports and video watching. Optional, recommended.")
                facts: [I18n.tr("Free tier"), I18n.tr("Rate-limited"), I18n.tr("4 steps")]
                active: !root.isYt
                onClicked: root.track = "gemini"
            }
        }

        // ── progress ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.space3
            Rectangle {
                id: progTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: U.withAlpha(Theme.on_surface, Theme.isDark ? 0.08 : 0.07)
                Rectangle {
                    // anchored, not x-positioned, so it fills from the reading edge in RTL too
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: root.steps.length > 0 ? parent.width * root.doneCount / root.steps.length : 0
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.primary }
                        GradientStop { position: 1.0; color: U.mix(Theme.primary, Theme.primary_deep, 0.7) }
                    }
                    Behavior on width { NumberAnimation { duration: Tokens.durSlow; easing.type: Easing.OutCubic } }
                }
            }
            C.AppText {
                text: root.doneCount === root.steps.length
                      ? I18n.tr("All done")
                      : I18n.tr("{d} of {n} done").replace("{d}", root.doneCount).replace("{n}", root.steps.length)
                weight: Tokens.weightDemiBold
                font.pixelSize: Tokens.fontCaption
                color: root.doneCount === root.steps.length ? Theme.secondary_container : Theme.on_surface_var
            }
            C.IconButton {
                visible: root.doneCount > 0
                iconName: "restart_alt"
                implicitWidth: 30; implicitHeight: 30
                glyphSize: 15
                tip: I18n.tr("Reset ticks")
                onClicked: { if (root.isYt) root.maskYt = 0; else root.maskAi = 0 }
            }
        }

        // ── stepper ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: root.steps
                RowLayout {
                    id: stepRow
                    readonly property bool done: root.isDone(index)
                    readonly property bool current: index === root.nextStep
                    readonly property bool last: index === root.steps.length - 1
                    Layout.fillWidth: true
                    spacing: Tokens.space4

                    // node + rail
                    Item {
                        Layout.preferredWidth: 36
                        Layout.fillHeight: true
                        // rail down to the next node
                        Rectangle {
                            visible: !stepRow.last
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 40
                            width: 2
                            height: Math.max(0, parent.height - 40)
                            radius: 1
                            color: stepRow.done ? Theme.primary : U.withAlpha(Theme.on_surface, Theme.isDark ? 0.10 : 0.10)
                            Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durSlow } }
                        }
                        AbstractButton {
                            id: node
                            width: 36; height: 36
                            anchors.horizontalCenter: parent.horizontalCenter
                            hoverEnabled: true
                            padding: 0
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            onClicked: root.toggle(index)
                            scale: node.pressed ? 0.9 : 1.0
                            Behavior on scale { NumberAnimation { duration: Tokens.durFast } }
                            C.AppTooltip {
                                visible: node.hovered
                                text: stepRow.done ? I18n.tr("Mark as not done") : I18n.tr("Mark as done")
                            }
                            background: Item {
                                // pulse ring on the step you are on
                                Rectangle {
                                    id: pulse
                                    anchors.centerIn: parent
                                    width: 36; height: 36; radius: 18
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.primary
                                    visible: stepRow.current
                                    opacity: 0
                                    SequentialAnimation on scale {
                                        running: pulse.visible && Tokens.appActive && (App.ambientMotion !== undefined ? App.ambientMotion : true)
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 1.45; duration: 1400; easing.type: Easing.OutCubic }
                                        PauseAnimation { duration: 300 }
                                    }
                                    SequentialAnimation on opacity {
                                        running: pulse.visible && Tokens.appActive && (App.ambientMotion !== undefined ? App.ambientMotion : true)
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.55; to: 0.0; duration: 1400; easing.type: Easing.OutCubic }
                                        PauseAnimation { duration: 300 }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 18
                                    color: stepRow.done ? Theme.primary
                                         : stepRow.current ? U.withAlpha(Theme.primary, Theme.isDark ? 0.16 : 0.10)
                                         : Theme.surface_low
                                    border.width: stepRow.done ? 0 : 1.5
                                    border.color: stepRow.current ? Theme.primary
                                                : node.hovered ? Theme.outline : Theme.border_med
                                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                                }
                            }
                            contentItem: Item {
                                C.AppText {
                                    anchors.centerIn: parent
                                    visible: !stepRow.done
                                    text: index + 1
                                    mono: true
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontBody
                                    color: stepRow.current ? Theme.primary : Theme.on_surface_var
                                }
                                C.IconGlyph {
                                    anchors.centerIn: parent
                                    visible: stepRow.done
                                    name: "check"
                                    fill: true
                                    size: 17
                                    glyphColor: Theme.on_primary
                                }
                            }
                        }
                    }

                    // body
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: stepRow.last ? 0 : Tokens.space5
                        spacing: Tokens.space2

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.minimumHeight: 36
                            spacing: Tokens.space3
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.t
                                weight: Tokens.weightBold
                                font.pixelSize: Tokens.fontLabel + 1
                                color: stepRow.done ? Theme.on_surface_var : Theme.text_strong
                                wrapMode: Text.WordWrap
                                Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durMed } }
                            }
                            C.IconButton {
                                visible: modelData.url !== ""
                                iconName: "content_copy"
                                implicitWidth: 34; implicitHeight: 34
                                glyphSize: 15
                                tip: I18n.tr("Copy link")
                                onClicked: Settings.copyToClipboard(modelData.url)
                            }
                            C.ActionButton {
                                visible: modelData.url !== ""
                                compact: true
                                variant: stepRow.current ? "primary" : "ghost"
                                iconName: "open_in_new"
                                text: I18n.tr("Open page")
                                onClicked: Qt.openUrlExternally(modelData.url)
                            }
                            C.ActionButton {
                                visible: modelData.act !== ""
                                compact: true
                                variant: "primary"
                                iconName: modelData.act === "gemini" ? "provider_gemini" : "key"
                                text: modelData.act === "gemini" ? I18n.tr("Use Gemini") : I18n.tr("Go to the key field")
                                onClicked: {
                                    if (!stepRow.done) root.toggle(index)
                                    if (modelData.act === "gemini") root.geminiRequested()
                                    else root.keyFieldRequested()
                                }
                            }
                        }

                        C.AppText {
                            Layout.fillWidth: true
                            text: modelData.d
                            font.pixelSize: Tokens.fontBody
                            lineHeight: 1.45
                            color: Theme.on_surface_var
                            wrapMode: Text.WordWrap
                            opacity: stepRow.done ? 0.7 : 1.0
                            Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                        }

                        // where to click, as breadcrumb chips
                        Flow {
                            visible: modelData.path.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 6
                            Repeater {
                                model: modelData.path
                                Row {
                                    spacing: 6
                                    C.IconGlyph {
                                        visible: index > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: I18n.rtl ? "chevron_left" : "chevron_right"
                                        size: 14
                                        glyphColor: Theme.outline
                                    }
                                    Rectangle {
                                        radius: 8
                                        color: U.withAlpha(Theme.primary, Theme.isDark ? 0.10 : 0.07)
                                        border.width: 1
                                        border.color: U.withAlpha(Theme.primary, 0.22)
                                        implicitWidth: crumb.implicitWidth + 16
                                        implicitHeight: 26
                                        width: implicitWidth
                                        height: implicitHeight
                                        C.AppText {
                                            id: crumb
                                            anchors.centerIn: parent
                                            text: modelData
                                            mono: true
                                            weight: Tokens.weightMedium
                                            font.pixelSize: Tokens.fontCaption
                                            color: Theme.text_strong
                                            LayoutMirroring.enabled: false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── troubleshooting ──
        Item {
            id: trouble
            Layout.fillWidth: true
            implicitHeight: troubleHead.height + (root.troubleOpen ? troubleGrid.implicitHeight + Tokens.space4 : 0)
            Layout.preferredHeight: implicitHeight
            clip: true
            Behavior on implicitHeight { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }

            AbstractButton {
                id: troubleHead
                width: parent.width
                height: 50
                hoverEnabled: true
                padding: 0
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                onClicked: root.troubleOpen = !root.troubleOpen
                background: Rectangle {
                    radius: Tokens.radiusLg
                    color: troubleHead.hovered ? U.hoverTint(Theme.surface_low, Theme.isDark) : Theme.surface_low
                    border.width: 1
                    border.color: Theme.border
                    Behavior on color { enabled: !Tokens.themeSwapping; ColorAnimation { duration: Tokens.durFast } }
                }
                contentItem: Item {
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.space4
                        anchors.rightMargin: Tokens.space4
                        spacing: Tokens.space3
                        C.IconGlyph { name: "warning"; size: 17; glyphColor: Theme.warn }
                        C.AppText {
                            text: I18n.tr("When something goes wrong")
                            weight: Tokens.weightDemiBold
                            color: Theme.text_strong
                        }
                        C.AppText {
                            text: I18n.tr("The error you see, and the fix")
                            font.pixelSize: Tokens.fontCaption
                            color: Theme.outline
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        C.IconGlyph {
                            name: "expand_more"
                            size: 18
                            glyphColor: Theme.on_surface_var
                            rotation: root.troubleOpen ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Tokens.durMed; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }

            GridLayout {
                id: troubleGrid
                anchors.left: parent.left
                anchors.right: parent.right
                y: troubleHead.height + Tokens.space4
                columns: root.width < 760 ? 1 : 2
                columnSpacing: Tokens.space3
                rowSpacing: Tokens.space3
                opacity: root.troubleOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Tokens.durMed } }
                Repeater {
                    model: root.isYt ? root.ytTrouble : root.aiTrouble
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        radius: Tokens.radiusLg
                        color: Theme.surface_low
                        border.width: 1
                        border.color: Theme.border
                        implicitHeight: tCol.implicitHeight + Tokens.space4 * 2
                        ColumnLayout {
                            id: tCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.space4
                            spacing: Tokens.space2
                            Rectangle {
                                radius: 7
                                color: U.withAlpha(Theme.error, 0.12)
                                border.width: 1
                                border.color: U.withAlpha(Theme.error, 0.28)
                                implicitWidth: Math.min(tCol.width, codeTxt.implicitWidth + 16)
                                implicitHeight: 24
                                C.AppText {
                                    id: codeTxt
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, tCol.width - 16)
                                    text: modelData.c
                                    mono: true
                                    weight: Tokens.weightBold
                                    font.pixelSize: Tokens.fontCaption
                                    color: Theme.error
                                    elide: Text.ElideRight
                                }
                            }
                            C.AppText {
                                Layout.fillWidth: true
                                text: modelData.f
                                font.pixelSize: Tokens.fontCaption + 1
                                lineHeight: 1.35
                                color: Theme.on_surface
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}
