import QtQuick

// Capas estáticas de vidrio; el desenfoque lo realiza el compositor de la ventana.
Rectangle {
    id: panel
    property color topColor: "#243b3b3b"
    property color bottomColor: "#181c1c1c"
    property color edgeColor: "#38ffffff"
    property bool highlighted: false
    property bool reflective: true

    radius: 12
    border.width: 1
    border.color: highlighted ? "#99ffffff" : edgeColor
    gradient: Gradient {
        GradientStop { position: 0; color: panel.topColor }
        GradientStop { position: 1; color: panel.bottomColor }
    }

    Rectangle {
        visible: panel.reflective
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, panel.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: "#09ffffff"
    }
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
            GradientStop { position: 0.35; color: "#52ffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
        }
    }
}
