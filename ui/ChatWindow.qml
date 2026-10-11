import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "components"

// Cliente de conversación: cuenta, texto progresivo y controles de turno.
FloatingWindow {
    id: window
    required property AgentBridge bridge
    title: "Agent Shell · Codex"
    implicitWidth: 820
    implicitHeight: 780
    minimumSize: Qt.size(560, 560)
    color: "#0d1420"
    visible: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "AGENT SHELL"; color: "#72e5c0"; font.pixelSize: 12; font.letterSpacing: 3 }
                Text { text: "Conversa con Codex"; color: "#edf4fa"; font.pixelSize: 27; font.bold: true }
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: "Historial"
                enabled: window.bridge.historyReady
                onClicked: historyPanel.open()
            }
            ActionButton {
                text: "Nuevo chat"
                enabled: window.bridge.canBrowseHistory
                onClicked: window.bridge.newChat()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: accountRow.implicitHeight + 24
            color: "#172330"
            radius: 10
            border.color: window.bridge.authenticated ? "#2f6156" : "#314155"
            RowLayout {
                id: accountRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: window.bridge.authenticated ? "#72e5c0" : "#f5c478"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: window.bridge.authenticated
                              ? window.bridge.email || "Cuenta de ChatGPT conectada"
                              : "Conecta tu cuenta de ChatGPT"
                        color: "#edf4fa"
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.bridge.authenticated
                              ? "Sesión de Codex CLI" + (window.bridge.plan ? " · " + window.bridge.plan : "")
                              : "Puedes reutilizar la sesión que ya tienes en Codex CLI."
                        color: "#96a9bb"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
                ActionButton {
                    text: window.bridge.authenticated ? "Actualizar" : "Iniciar sesión"
                    accent: !window.bridge.authenticated
                    enabled: window.bridge.ready && !window.bridge.busy && !window.bridge.loginBusy
                    onClicked: window.bridge.authenticated ? window.bridge.refreshAccount() : window.bridge.login()
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: window.bridge.currentTitle !== ""
            text: window.bridge.currentTitle
            color: "#96a9bb"
            font.pixelSize: 12
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        RowLayout {
            visible: window.bridge.loginBusy
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Continúa en el navegador para conectar tu cuenta."
                color: "#96a9bb"
                wrapMode: Text.Wrap
            }
            ActionButton {
                text: "Abrir navegador"
                enabled: window.bridge.authUrl !== ""
                onClicked: Qt.openUrlExternally(window.bridge.authUrl)
            }
            ActionButton { text: "Cancelar"; onClicked: window.bridge.cancelLogin() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#111d2a"
            radius: 12
            border.color: "#243347"
            Text {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: window.bridge.messages.count === 0
                text: "¿Qué tienes en mente?\n\nPregunta, comparte una idea o pide ayuda con código."
                color: "#96a9bb"
                font.pixelSize: 16
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
            ListView {
                id: conversation
                anchors.fill: parent
                anchors.margins: 18
                clip: true
                spacing: 20
                model: window.bridge.messages
                ScrollBar.vertical: ScrollBar {}
                onContentHeightChanged: {
                    if (!moving) Qt.callLater(() => conversation.positionViewAtEnd());
                }
                delegate: Column {
                    required property string author
                    required property string body
                    width: conversation.width - 16
                    spacing: 6
                    Text {
                        text: parent.author
                        color: parent.author === "SISTEMA" ? "#f5c478" : "#72e5c0"
                        font.pixelSize: 11
                        font.bold: true
                    }
                    TextArea {
                        text: parent.body
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        color: "#d8e5ee"
                        font.pixelSize: 14
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        padding: 0
                        background: null
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: window.bridge.status
            color: window.bridge.busy || window.bridge.loginBusy ? "#f5c478" : "#96a9bb"
            font.pixelSize: 12
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 95
            TextArea {
                id: prompt
                placeholderText: window.bridge.authenticated ? "Escribe un mensaje…" : "Inicia sesión para conversar…"
                placeholderTextColor: "#788da2"
                color: "#edf4fa"
                font.pixelSize: 14
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                enabled: window.bridge.canSend
                background: Rectangle { color: "#192535"; radius: 8; border.color: "#314155" }
                // Enter envía; Shift+Enter conserva el salto de línea.
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && !(event.modifiers & Qt.ShiftModifier)) {
                        window.sendPrompt();
                        event.accepted = true;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "v" + (window.bridge.appVersion || "…")
                      + (window.bridge.modelName ? " · " + window.bridge.modelName : " · Codex")
                color: "#788da2"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            ActionButton { text: "Detener"; enabled: window.bridge.busy; onClicked: window.bridge.cancel() }
            ActionButton {
                text: "Enviar"
                accent: true
                enabled: window.bridge.canSend && prompt.text.trim().length > 0 && prompt.text.length <= 16000
                onClicked: window.sendPrompt()
            }
        }
    }

    Drawer {
        id: historyPanel
        width: Math.min(360, window.width - 40)
        height: window.height
        edge: Qt.LeftEdge
        background: Rectangle { color: "#111d2a"; border.color: "#314155" }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14
            Text { text: "Historial de chats"; color: "#edf4fa"; font.pixelSize: 21; font.bold: true }
            Text {
                Layout.fillWidth: true
                visible: window.bridge.conversations.count === 0
                text: "Tus conversaciones aparecerán aquí al enviar el primer mensaje."
                color: "#96a9bb"
                wrapMode: Text.Wrap
            }
            ListView {
                id: savedChats
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: window.bridge.conversations
                ScrollBar.vertical: ScrollBar {}
                delegate: ItemDelegate {
                    id: savedChat
                    required property string chatId
                    required property string title
                    required property string updatedAt
                    width: savedChats.width
                    enabled: window.bridge.canBrowseHistory
                    onClicked: {
                        window.bridge.openChat(chatId);
                        historyPanel.close();
                    }
                    contentItem: Column {
                        spacing: 6
                        Text {
                            width: parent.width
                            text: savedChat.title
                            color: "#d8e5ee"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Text {
                            text: new Date(savedChat.updatedAt).toLocaleString()
                            color: "#96a9bb"
                            font.pixelSize: 10
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: savedChat.chatId === window.bridge.currentChatId ? "#263e44" : "#192535"
                    }
                }
            }
            Text { text: "Directorio del historial"; color: "#72e5c0"; font.pixelSize: 12 }
            TextArea {
                Layout.fillWidth: true
                text: window.bridge.historyDirectory
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: "#96a9bb"
                font.pixelSize: 11
                background: null
                padding: 0
            }
            RowLayout {
                Layout.fillWidth: true
                ActionButton {
                    text: "Abrir carpeta"
                    enabled: window.bridge.historyDirectory !== ""
                    onClicked: Qt.openUrlExternally("file://" + window.bridge.historyDirectory)
                }
                ActionButton {
                    text: "Actualizar"
                    enabled: window.bridge.canBrowseHistory
                    onClicked: window.bridge.refreshHistory()
                }
            }
        }
    }

    function sendPrompt() {
        if (!bridge.canSend || !prompt.text.trim() || prompt.text.length > 16000) return;
        bridge.submit(prompt.text);
        prompt.clear();
    }
}
