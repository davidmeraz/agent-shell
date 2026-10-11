import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// Navegación persistente; la ventana decide dónde abrir los paneles auxiliares.
GlassPanel {
    id: sidebar
    required property AgentBridge bridge
    signal historyRequested()
    signal performanceRequested()
    signal accountRequested()
    topColor: "#242e4051"
    bottomColor: "#20131e2d"
    edgeColor: "#20ffffff"
    radius: 16

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        RowLayout {
            spacing: 10
            GlassPanel {
                implicitWidth: 36
                implicitHeight: 36
                edgeColor: "#5072e5c0"
                Text { anchors.centerIn: parent; text: "AS"; color: "#b3f5df"; font.pixelSize: 12; font.bold: true }
            }
            ColumnLayout {
                spacing: 3
                Text { text: "Agent Shell"; color: "#edf4fa"; font.pixelSize: 18; font.bold: true }
                Text { text: "Tu espacio de IA"; color: "#a5b6c6"; font.pixelSize: 11 }
            }
        }
        ActionButton {
            Layout.fillWidth: true
            text: "+  Nuevo chat"
            accent: true
            enabled: sidebar.bridge.canBrowseHistory
            onClicked: sidebar.bridge.newChat()
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "CONVERSACIONES"
                color: "#a5b6c6"
                font.pixelSize: 10
                font.letterSpacing: 1
            }
            ActionButton {
                text: "Ver todas"
                font.pixelSize: 11
                horizontalPadding: 8
                verticalPadding: 6
                enabled: sidebar.bridge.historyReady
                onClicked: sidebar.historyRequested()
            }
        }
        Text {
            Layout.fillWidth: true
            visible: sidebar.bridge.conversations.count === 0
            text: "Tus chats se guardarán aquí."
            color: "#a5b6c6"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        ListView {
            id: recentChats
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: sidebar.bridge.conversations
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                id: chat
                required property string chatId
                required property string title
                required property string updatedAt
                readonly property bool selected: chatId === sidebar.bridge.currentChatId
                width: recentChats.width
                padding: 10
                enabled: sidebar.bridge.canBrowseHistory
                onClicked: sidebar.bridge.openChat(chatId)
                contentItem: Column {
                    spacing: 5
                    Text {
                        width: parent.width
                        text: chat.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: chat.selected ? "#b3f5df" : "#e0e9f1"
                        font.pixelSize: 12
                    }
                    Text {
                        text: new Date(chat.updatedAt).toLocaleDateString()
                        color: "#a5b6c6"
                        font.pixelSize: 10
                    }
                }
                background: GlassPanel {
                    radius: 9
                    visible: chat.selected || chat.hovered || chat.activeFocus
                    highlighted: chat.activeFocus
                    topColor: chat.selected ? "#30408273" : "#24445669"
                    bottomColor: "#18203040"
                    edgeColor: chat.selected ? "#5072e5c0" : "#24ffffff"
                }
            }
        }
        ActionButton {
            Layout.fillWidth: true
            text: "Rendimiento"
            enabled: sidebar.bridge.historyReady
            onClicked: sidebar.performanceRequested()
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        Button {
            id: account
            Layout.fillWidth: true
            padding: 10
            hoverEnabled: true
            onClicked: sidebar.accountRequested()
            contentItem: RowLayout {
                spacing: 10
                Rectangle {
                    implicitWidth: 8; implicitHeight: 8; radius: 4
                    color: sidebar.bridge.authenticated ? "#72e5c0" : "#f5c478"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: sidebar.bridge.authenticated ? sidebar.bridge.email || "Cuenta conectada" : "Conectar ChatGPT"
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: "#edf4fa"
                        font.pixelSize: 12
                    }
                    Text {
                        text: sidebar.bridge.authenticated ? "Cuenta y uso del plan" : "Inicia sesión para conversar"
                        color: "#a5b6c6"
                        font.pixelSize: 10
                    }
                }
                Text { text: "›"; color: "#a5b6c6"; font.pixelSize: 20 }
            }
            background: GlassPanel {
                highlighted: account.activeFocus
                topColor: account.hovered ? "#30445669" : "#182e4051"
                bottomColor: "#14131e2d"
                edgeColor: "#24ffffff"
            }
        }
        Text {
            text: "v" + (sidebar.bridge.appVersion || "…")
            color: "#a5b6c6"
            font.pixelSize: 10
        }
    }
}
