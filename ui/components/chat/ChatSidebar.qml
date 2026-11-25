import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Navegación persistente; la ventana decide dónde abrir los paneles auxiliares.
MattePanel {
    id: sidebar
    required property AgentBridge bridge
    signal settingsRequested()
    signal deleteRequested(string chatId, string title)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        RowLayout {
            spacing: 12
            GlassPanel {
                implicitWidth: 38
                implicitHeight: 38
                radius: 11
                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#22ffffff"
                bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#0cffffff"
                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#50ffffff"
                GemaIcon {
                    anchors.centerIn: parent
                    name: "brand"
                    size: 20
                    color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                }
            }
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Agent Shell"
                    color: GemaTheme.textColor
                    font.pixelSize: 18
                    font.bold: true
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
                Text {
                    text: GemaTheme.synced ? "Gema · " + GemaTheme.gemName : "Tu espacio de IA"
                    color: GemaTheme.mutedColor
                    font.pixelSize: 11
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#22ffffff" }
        Text {
            Layout.fillWidth: true
            text: "CONVERSACIONES"
            color: GemaTheme.mutedColor
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.1
            style: Text.Raised
            styleColor: GemaTheme.textShadow
        }
        Text {
            Layout.fillWidth: true
            visible: sidebar.bridge.conversations.count === 0
            text: sidebar.bridge.activeArea === "app" ? "Las conversaciones de esta aplicación aparecerán aquí."
                  : sidebar.bridge.activeArea === "work" ? "Las conversaciones de este proyecto aparecerán aquí."
                  : "Tus chats se guardarán aquí."
            color: GemaTheme.mutedColor
            font.pixelSize: 12
            style: Text.Raised
            styleColor: GemaTheme.textShadow
            wrapMode: Text.Wrap
        }
        ListView {
            id: recentChats
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: sidebar.bridge.conversations
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
            delegate: ConversationRow {
                width: recentChats.width
                selected: chatId === sidebar.bridge.currentChatId
                enabled: sidebar.bridge.canBrowseHistory
                onClicked: sidebar.bridge.openChat(chatId)
                onDeleteRequested: (chatId, title) => sidebar.deleteRequested(chatId, title)
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        Button {
            id: settingsButton
            objectName: "chatSidebarSettings"
            Layout.fillWidth: true
            padding: 10
            hoverEnabled: true
            onClicked: sidebar.settingsRequested()
            contentItem: RowLayout {
                spacing: 10
                GlassPanel {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 10
                    reflective: false
                    topColor: settingsButton.hovered
                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.30) : "#2cffffff")
                        : (GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#18ffffff")
                    bottomColor: "#0affffff"
                    edgeColor: settingsButton.hovered
                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#5cffffff")
                        : "#32ffffff"
                    GemaIcon {
                        anchors.centerIn: parent
                        name: "settings"
                        size: 16
                        color: settingsButton.hovered
                            ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                            : GemaTheme.textColor
                        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: "Ajustes"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: GemaTheme.textColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Límites, terminal y preferencias"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: GemaTheme.mutedColor
                        font.pixelSize: 10
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                }
                Text {
                    text: "›"
                    color: settingsButton.hovered ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : GemaTheme.mutedColor
                    font.pixelSize: 20
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
            background: GlassPanel {
                highlighted: settingsButton.activeFocus || settingsButton.hovered
                topColor: settingsButton.hovered ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.26) : "#28ffffff") : "#1cffffff"
                bottomColor: "#24060a10"
                edgeColor: settingsButton.hovered ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.68) : "#60ffffff") : "#42ffffff"
            }
        }
        Text {
            text: "v" + (sidebar.bridge.appVersion || "…")
            color: GemaTheme.subtleColor
            font.pixelSize: 10
            style: Text.Raised
            styleColor: GemaTheme.textShadow
        }
    }
}
