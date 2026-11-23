import QtQuick

// Cristal facetado Gema UI Kit: película translúcida con filo de luz diagonal (135°) y reflejo especular.
Rectangle {
    id: panel
    property color topColor: "#16ffffff"
    property color bottomColor: "#14080c12"
    property color edgeColor: "#42ffffff"
    property bool highlighted: false
    property bool reflective: true
    readonly property color effectiveTopColor: GemaTheme.synced ? GemaTheme.tintColor(topColor, 0.16) : topColor
    readonly property color effectiveBottomColor: GemaTheme.synced ? GemaTheme.tintColor(bottomColor, 0.12) : bottomColor
    readonly property color effectiveEdgeColor: GemaTheme.synced ? GemaTheme.tintColor(edgeColor, 0.38) : edgeColor
    readonly property color highlightBorderColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.82) : "#a8ffffff"

    radius: 12
    border.width: 1
    border.color: highlighted ? highlightBorderColor : effectiveEdgeColor
    Behavior on border.color { ColorAnimation { duration: GemaTheme.animDuration } }
    Behavior on topColor { ColorAnimation { duration: GemaTheme.animDuration } }
    Behavior on bottomColor { ColorAnimation { duration: GemaTheme.animDuration } }
    gradient: Gradient {
        GradientStop { position: 0; color: panel.effectiveTopColor }
        GradientStop { position: 1; color: panel.effectiveBottomColor }
    }

    // Bisel interior de cristal (Hairline Frosted Rim) que separa visualmente controles sobre vidrio.
    Rectangle {
        visible: panel.reflective
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, panel.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: panel.highlighted
                      ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#28ffffff")
                      : (GemaTheme.synced ? GemaTheme.accentAlpha(0.12) : "#16ffffff")
    }
    // Destello especular en el canto superior del cristal tallado.
    Rectangle {
        visible: panel.reflective
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: panel.radius
        anchors.rightMargin: panel.radius
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#00ffffff" }
            GradientStop { position: 0.28; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.62) : "#68ffffff" }
            GradientStop { position: 0.65; color: "#32ffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
        }
    }
}
