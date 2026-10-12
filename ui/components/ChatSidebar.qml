import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// Navegación persistente; la ventana decide dónde abrir los paneles auxiliares.
MattePanel {
    id: sidebar
    required property AgentBridge bridge
    signal historyRequested()
    signal performanceRequested()
    signal accountRequested()
    signal shellRequested()
    signal projectRequested()
    signal deleteRequested(string chatId, string title)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        RowLayout {
            spacing: 10
            GlassPanel {
                implicitWidth: 36
                implicitHeight: 36
                edgeColor: "#50ffffff"
                Text { anchors.centerIn: parent; text: "AS"; color: "#ffffff"; font.pixelSize: 12; font.bold: true }
            }
            ColumnLayout {
                spacing: 3
                Text { text: "Agent Shell"; color: "#f5f5f5"; font.pixelSize: 18; font.bold: true }
                Text { text: "Tu espacio de IA"; color: "#aaaaaa"; font.pixelSize: 11 }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: sidebar.bridge.activeArea === "work"
            Text {
                Layout.fillWidth: true
                text: sidebar.bridge.projectName || "Tus proyectos"
                color: "#dddddd"
                font.pixelSize: 12
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            ActionButton {
                text: "Proyectos"
                font.pixelSize: 11
                horizontalPadding: 8
                verticalPadding: 6
                enabled: sidebar.bridge.canSelectArea
                onClicked: sidebar.bridge.selectArea("work", "")
            }
        }
        ActionButton {
            Layout.fillWidth: true
            text: sidebar.bridge.activeArea === "work" ? (sidebar.bridge.projectId ? "+  Nueva conversación" : "+  Nuevo proyecto") : "+  Nuevo chat"
            accent: true
            enabled: sidebar.bridge.canBrowseHistory
            onClicked: {
                if (sidebar.bridge.activeArea === "work" && !sidebar.bridge.projectId) sidebar.projectRequested();
                else sidebar.bridge.newChat();
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "CONVERSACIONES"
                color: "#aaaaaa"
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
            text: sidebar.bridge.activeArea === "work" ? "Las conversaciones de este proyecto aparecerán aquí." : "Tus chats se guardarán aquí."
            color: "#aaaaaa"
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
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
            delegate: ConversationRow {
                width: recentChats.width
                selected: chatId === sidebar.bridge.currentChatId
                enabled: sidebar.bridge.canBrowseHistory
                onClicked: sidebar.bridge.openChat(chatId)
                onDeleteRequested: (chatId, title) => sidebar.deleteRequested(chatId, title)
            }
        }
        ActionButton {
            Layout.fillWidth: true
            text: "Rendimiento"
            enabled: sidebar.bridge.historyReady
            onClicked: sidebar.performanceRequested()
        }
        ActionButton {
            Layout.fillWidth: true
            text: "Terminal"
            enabled: sidebar.bridge.canSelectArea && sidebar.bridge.workspaceSelected
            onClicked: sidebar.shellRequested()
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
                    color: sidebar.bridge.authenticated ? "#ffffff" : "#777777"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: sidebar.bridge.authenticated ? sidebar.bridge.email || "Cuenta conectada" : "Conectar ChatGPT"
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: "#f5f5f5"
                        font.pixelSize: 12
                    }
                    Text {
                        text: sidebar.bridge.authenticated ? "Cuenta y uso del plan" : "Inicia sesión para conversar"
                        color: "#aaaaaa"
                        font.pixelSize: 10
                    }
                }
                Text { text: "›"; color: "#aaaaaa"; font.pixelSize: 20 }
            }
            background: GlassPanel {
                highlighted: account.activeFocus
                topColor: account.hovered ? "#30555555" : "#183b3b3b"
                bottomColor: "#141c1c1c"
                edgeColor: "#24ffffff"
            }
        }
        Text {
            text: "v" + (sidebar.bridge.appVersion || "…")
            color: "#aaaaaa"
            font.pixelSize: 10
        }
    }
}
