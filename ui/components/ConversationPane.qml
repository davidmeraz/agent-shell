import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../Performance.js" as Performance

GlassPanel {
    id: pane
    required property AgentBridge bridge
    signal performanceRequested(var measurement)
    signal suggestionRequested(string text)
    signal loginRequested()
    radius: 16
    topColor: "#141c2d40"
    bottomColor: "#24101928"
    edgeColor: "#20ffffff"

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 540)
        spacing: pane.height < 260 ? 12 : 20
        visible: pane.bridge.messages.count === 0
        Text {
            width: parent.width
            text: "¿En qué trabajamos?"
            color: "#edf4fa"
            font.pixelSize: pane.width < 580 ? 25 : 32
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: pane.bridge.authenticated ? "Una idea, una pregunta o tu próximo proyecto." : "Conecta tu cuenta de ChatGPT para comenzar."
            color: "#b0bfcd"
            font.pixelSize: 13
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            visible: pane.bridge.authenticated && pane.height >= 260
            Repeater {
                model: [
                    { label: "Explorar una idea", prompt: "Ayúdame a desarrollar esta idea: " },
                    { label: "Revisar código", prompt: "Ayúdame a revisar este código: " },
                    { label: "Planear un proyecto", prompt: "Ayúdame a planear este proyecto: " }
                ]
                delegate: ActionButton {
                    required property var modelData
                    text: modelData.label
                    font.pixelSize: 12
                    enabled: pane.bridge.canSend
                    onClicked: pane.suggestionRequested(modelData.prompt)
                }
            }
        }
        ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !pane.bridge.authenticated
            text: "Continuar con ChatGPT"
            accent: true
            enabled: pane.bridge.ready && !pane.bridge.loginBusy && !pane.bridge.accountBusy
            onClicked: pane.loginRequested()
        }
    }

    ListView {
        id: conversation
        visible: pane.bridge.messages.count > 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        width: Math.min(parent.width - 32, 820)
        clip: true
        spacing: 12
        model: pane.bridge.messages
        ScrollBar.vertical: ScrollBar {}
        onContentHeightChanged: {
            if (!moving) Qt.callLater(() => conversation.positionViewAtEnd());
        }
        delegate: Item {
            id: message
            required property string author
            required property string body
            required property string performanceJson
            readonly property bool fromUser: author === "TÚ"
            readonly property bool systemMessage: author === "SISTEMA"
            readonly property var measurement: performanceJson ? JSON.parse(performanceJson) : ({})
            readonly property real cardWidth: fromUser ? Math.min(width * 0.88, 640) : width
            width: conversation.width
            implicitHeight: messageContent.implicitHeight + 28
            GlassPanel {
                anchors.right: parent.right
                width: message.cardWidth
                height: parent.height
                visible: message.fromUser
                radius: 14
                topColor: "#24408273"
                bottomColor: "#1425373c"
                edgeColor: "#3072e5c0"
            }
            ColumnLayout {
                id: messageContent
                x: message.fromUser ? message.width - message.cardWidth + 14 : 14
                y: 14
                width: message.cardWidth - 28
                spacing: 10
                RowLayout {
                    spacing: 8
                    Rectangle {
                        implicitWidth: 22; implicitHeight: 22; radius: 7
                        color: message.systemMessage ? "#24f5c478" : "#2472e5c0"
                        Text {
                            anchors.centerIn: parent
                            text: message.fromUser ? "T" : message.systemMessage ? "!" : "AI"
                            color: message.systemMessage ? "#f5c478" : "#b3f5df"
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                    Text {
                        text: message.fromUser ? "Tú" : message.systemMessage ? "Sistema" : "ChatGPT"
                        color: message.systemMessage ? "#f5c478" : "#b0bfcd"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
                TextArea {
                    Layout.fillWidth: true
                    text: message.body
                    readOnly: true
                    selectByMouse: true
                    color: "#edf4fa"
                    font.pixelSize: 15
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    padding: 0
                    background: null
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !!message.measurement.turn_id
                    Text {
                        Layout.fillWidth: true
                        text: Performance.summary(message.measurement)
                        color: "#a5b6c6"
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                    }
                    ActionButton {
                        text: "Detalles"
                        font.pixelSize: 11
                        horizontalPadding: 10
                        verticalPadding: 6
                        onClicked: pane.performanceRequested(message.measurement)
                    }
                }
            }
        }
    }
}
