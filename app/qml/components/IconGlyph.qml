import QtQuick
import QtQuick.Window
import NicheScope

// A single icon. Normally a remixicon glyph rendered as text; names that have
// a custom SVG in assets/icons/ (see app.ui.icons.SVG_ICONS) are drawn through
// image://svgicon instead, recoloured to glyphColor, so call sites never care
// which one they got: `IconGlyph { name: "search" }` either way.
Text {
    id: root
    property string name: ""
    property bool fill: false
    property int size: 18
    property color glyphColor: Theme.on_surface_var
    // false = always draw the remixicon font glyph (the sidebar menu opts out
    // so its icons stay exactly as they were)
    property bool svg: true

    readonly property bool _svg: svg && name !== "" && Icons.hasSvg(name)

    // v3.39.8 — an icon that is not on screen does not reload.
    //
    // A theme or accent change recolours every icon, and every recolour is a
    // new image://svgicon URL: a synchronous provider round-trip into Python.
    // Pages are kept alive once visited, so after a few minutes of use a
    // switch was reloading the icons of EVERY page the user had opened — the
    // reason the switch got slower the longer the app ran. Now an icon whose
    // page (or panel) is hidden keeps its last image and catches up the moment
    // it becomes visible again, which costs one cache hit per icon.
    readonly property string wantSrc: _svg
            ? "image://svgicon/" + name + "/" + (fill ? "fill" : "line")
              + "/" + String(glyphColor).replace("#", "")
            : ""
    property string shownSrc: ""
    onWantSrcChanged: if (root.visible || root.shownSrc === "" || root.wantSrc === "") root.shownSrc = root.wantSrc
    onVisibleChanged: if (root.visible && root.shownSrc !== root.wantSrc) root.shownSrc = root.wantSrc
    Component.onCompleted: root.shownSrc = root.wantSrc

    font.family: Icons.family
    font.pixelSize: size
    color: glyphColor
    text: _svg ? "" : Icons.glyph(name, fill)
    // An empty Text has no width, so give the SVG box the nominal size.
    width: _svg ? size : implicitWidth
    // Match the box height to the nominal glyph size so the glyph sits centred
    // wherever it's dropped into a Row/RowLayout with verticalCenter — a bare
    // Text is sized to font metrics (with ascent/descent padding) and rode a
    // couple of px high next to a label otherwise.
    height: size
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    // remixicon glyphs shouldn't mirror in RTL
    LayoutMirroring.enabled: false

    Image {
        visible: root._svg
        anchors.centerIn: parent
        width: root.size
        height: root.size
        readonly property real _dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        sourceSize: Qt.size(Math.ceil(root.size * _dpr), Math.ceil(root.size * _dpr))
        // '#' would start a URL fragment, so the colour travels without it.
        source: root.shownSrc
        asynchronous: false
        cache: true
        smooth: true
        mipmap: false
        fillMode: Image.PreserveAspectFit
    }
}
