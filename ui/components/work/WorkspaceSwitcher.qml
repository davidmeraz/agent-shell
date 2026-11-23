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
    implicitWidth: 276
    implicitHeight: 38
    radius: 13
    reflective: true
    topColor: "#16ffffff"
    bottomColor: "#0cffffff"
    edgeColor: "#32ffffff"
    component AreaTab: Button {
        id: tab
        required property AgentBridge bridge
        readonly property string areaId: text.toLowerCase()
        readonly property bool selected: bridge.activeArea === areaId
        readonly property string iconSymbol: areaId === "chat" ? "◈" : areaId === "work" ? "❖" : GemaTheme.gemSymbol
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 0
        hoverEnabled: true
        enabled: bridge.canSelectArea
        scale: tab.down ? 0.96 : (tab.hovered && !tab.selected ? 1.03 : 1.0)
        Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
        onClicked: {
            if (!selected) bridge.selectArea(areaId);
        }
        contentItem: RowLayout {
            spacing: 5
            Item { Layout.fillWidth: true }
            Text {
                text: tab.iconSymbol
                color: tab.selected ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : (tab.hovered ? "#e0e6f0" : "#9aa4b4")
                font.pixelSize: 11
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            }
            Text {
                text: tab.text
                color: tab.selected ? GemaTheme.textColor : (tab.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                font.pixelSize: 12
                font.weight: tab.selected ? Font.Bold : Font.Medium
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            }
            Item { Layout.fillWidth: true }
        }
        background: Rectangle {
            radius: 10
            color: tab.selected ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#24ffffff")
                   : tab.hovered ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#12ffffff") : "transparent"
            border.width: tab.selected || tab.activeFocus || tab.hovered ? 1 : 0
            border.color: tab.activeFocus ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.75) : "#70ffffff")
                          : tab.selected ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.52) : "#40ffffff")
                          : (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#18ffffff")
            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            Behavior on border.color { ColorAnimation { duration: GemaTheme.animDuration } }
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
