import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Tres áreas, un espacio visible: Chat, Work y App (Gema UI Kit).
GlassPanel {
    id: switcher
    objectName: "workspaceSwitcher"
    required property AgentBridge bridge
    implicitWidth: 252
    implicitHeight: 36
    radius: 12
    reflective: false
    topColor: "#143b3b3b"
    bottomColor: "#101c1c1c"
    edgeColor: "#20ffffff"
    component AreaTab: Button {
        id: tab
        required property AgentBridge bridge
        readonly property bool selected: bridge.activeArea === text.toLowerCase()
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 0
        hoverEnabled: true
        enabled: bridge.canSelectArea
        onClicked: {
            if (!selected) bridge.selectArea(text.toLowerCase());
        }
        contentItem: Text {
            text: tab.text
            color: tab.selected ? "#f5f5f5" : "#999999"
            font.pixelSize: 12
            font.weight: tab.selected ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
            color: tab.selected ? "#20ffffff" : tab.hovered ? "#0cffffff" : "transparent"
            border.width: tab.selected || tab.activeFocus ? 1 : 0
            border.color: tab.activeFocus ? "#70ffffff" : "#20ffffff"
        }
        Accessible.name: text
        Accessible.description: text === "Chat" ? "Conversaciones generales"
            : text === "App" ? "Creador de aplicaciones Gema UI Kit (Glassmorphism)"
            : "Proyectos con carpeta e historial propios"
    }
    RowLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 3
        AreaTab {
            objectName: "chatAreaButton"
            text: "Chat"
            bridge: switcher.bridge
        }
        AreaTab {
            objectName: "workAreaButton"
            text: "Work"
            bridge: switcher.bridge
        }
        AreaTab {
            objectName: "appAreaButton"
            text: "App"
            bridge: switcher.bridge
        }
    }
}
