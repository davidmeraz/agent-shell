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
    topColor: "#14292929"
    bottomColor: "#24171717"
    edgeColor: "#20ffffff"

    function modelLabel(slug) {
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            if (model.slug === slug) return model.displayName || slug;
        }
        return slug || "";
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 540)
        spacing: pane.height < 260 ? 12 : 20
        visible: pane.bridge.messages.count === 0
        Text {
            width: parent.width
            text: "¿En qué trabajamos?"
            color: "#f5f5f5"
            font.pixelSize: pane.width < 580 ? 25 : 32
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: pane.bridge.authenticated ? "Una idea, una pregunta o tu próximo proyecto." : "Conecta tu cuenta de ChatGPT para comenzar."
            color: "#bbbbbb"
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
        objectName: "chatMessageList"
        property bool followLatest: true
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
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOff
            onPressedChanged: {
                if (pressed) conversation.followLatest = false;
                else conversation.followLatest = conversation.atYEnd;
            }
        }
        onMovementStarted: followLatest = false
        onMovementEnded: followLatest = atYEnd
        onCountChanged: {
            if (!count) followLatest = true;
            else if (model.get(count - 1).author === "TÚ"
                || (model.get(count - 1).toolJson && JSON.parse(model.get(count - 1).toolJson).source === "local")) followLatest = true;
        }
        onContentHeightChanged: {
            if (followLatest && !moving) Qt.callLater(() => {
                if (conversation.followLatest && !conversation.moving) conversation.positionViewAtEnd();
            });
        }
        footer: Item {
            readonly property bool waiting: pane.bridge.busy && !pane.bridge.shellRunning && conversation.count > 0
                && (pane.bridge.messages.get(conversation.count - 1).author === "TÚ"
                    || !!pane.bridge.messages.get(conversation.count - 1).toolJson)
            width: conversation.width
            height: waiting ? 44 : 0
            Row {
                objectName: "chatThinkingIndicator"
                visible: parent.waiting
                x: 14; y: 12
                spacing: 8
                BusyIndicator { width: 16; height: 16; running: parent.visible }
                Text {
                    text: "Preparando respuesta…"
                    color: "#aaaaaa"
                    font.pixelSize: 11
                }
            }
        }
        delegate: Item {
            id: message
            required property string author
            required property string body
            required property string turnId
            required property string performanceJson
            required property string toolJson
            readonly property bool isTool: !!toolJson
            readonly property bool fromUser: author === "TÚ"
            readonly property bool systemMessage: author === "SISTEMA"
            readonly property bool streaming: pane.bridge.busy && turnId === pane.bridge.activeTurnId
            readonly property var measurement: performanceJson ? JSON.parse(performanceJson) : ({})
            readonly property real cardWidth: fromUser ? Math.min(width * 0.84, 640,
                Math.max(72, Math.ceil(userTextSize.implicitWidth) + 30)) : width
            width: conversation.width
            implicitHeight: isTool ? toolCard.implicitHeight : messageContent.implicitHeight + (fromUser ? 20 : 16)
            // Mide la línea más ancha, respetando saltos explícitos y el mismo tipo de letra.
            Text {
                id: userTextSize
                visible: false
                font: bodyText.font
                text: message.fromUser ? message.body : ""
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
            }
            ToolCallCard {
                id: toolCard
                width: parent.width
                visible: message.isTool
                call: message.isTool ? JSON.parse(message.toolJson) : ({})
            }
            GlassPanel {
                anchors.right: parent.right
                width: message.cardWidth
                height: parent.height
                visible: message.fromUser
                radius: 14
                topColor: "#20555555"
                bottomColor: "#14292929"
                edgeColor: "#20ffffff"
            }
            ColumnLayout {
                id: messageContent
                visible: !message.isTool
                x: message.fromUser ? message.width - message.cardWidth + 14 : 14
                y: message.fromUser ? 10 : 8
                width: message.cardWidth - 28
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    visible: !message.fromUser
                    spacing: 8
                    Text {
                        text: message.systemMessage ? "Sistema" : "ChatGPT"
                        color: "#bbbbbb"
                        font.pixelSize: 11
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !message.systemMessage
                        text: pane.modelLabel(message.measurement.model)
                        textFormat: Text.PlainText
                        color: "#888888"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: message.streaming || message.measurement.status === "interrupted"
                                 || message.measurement.status === "failed"
                        text: message.streaming ? "Escribiendo…"
                              : message.measurement.status === "interrupted" ? "Detenida" : "Error"
                        color: "#aaaaaa"
                        font.pixelSize: 10
                    }
                }
                TextArea {
                    id: bodyText
                    objectName: message.fromUser ? "chatUserMessage" : message.systemMessage ? "chatSystemMessage" : "chatAssistantMessage"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    Layout.fillWidth: true
                    text: message.body
                    readOnly: true
                    selectByMouse: true
                    color: "#f5f5f5"
                    font.pixelSize: message.fromUser || message.systemMessage ? 14 : 15
                    wrapMode: TextEdit.Wrap
                    textFormat: message.fromUser || message.systemMessage ? TextEdit.PlainText : TextEdit.MarkdownText
                    onLinkActivated: link => {
                        if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link);
                    }
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    background: null
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !message.fromUser && !message.systemMessage && message.body.length > 0
                    spacing: 6
                    Button {
                        id: metricsButton
                        objectName: "chatResponseMetrics"
                        visible: !!message.measurement.turn_id
                        text: Performance.compactSummary(message.measurement)
                        hoverEnabled: true
                        padding: 4
                        Accessible.name: "Ver rendimiento de esta respuesta: " + text
                        contentItem: Text {
                            text: metricsButton.text
                            color: metricsButton.hovered ? "#cccccc" : "#999999"
                            font.pixelSize: 10
                        }
                        background: Rectangle {
                            radius: 6
                            color: metricsButton.hovered ? "#12ffffff" : "transparent"
                            border.width: metricsButton.visualFocus ? 1 : 0
                            border.color: "#60ffffff"
                        }
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: Performance.summary(message.measurement)
                            + (message.measurement.context_tokens !== null && message.measurement.context_tokens !== undefined
                                ? "\nContexto: tokens de entrada de la última llamada." : "")
                            + (message.measurement.tokens_per_second !== null && message.measurement.tokens_per_second !== undefined
                                ? "\nMedia: incluye red y razonamiento; excluye tiempo de terminal." : "")
                            + "\nVer detalles de rendimiento"
                        onClicked: pane.performanceRequested(message.measurement)
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    MessageCopyButton {
                        objectName: "chatCopyResponse"
                        textToCopy: message.body
                    }
                }
            }
        }
    }
    ActionButton {
        objectName: "chatJumpToLatest"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20
        visible: conversation.count > 0 && !conversation.followLatest && !conversation.atYEnd
        text: "↓"
        implicitWidth: 32
        implicitHeight: 32
        horizontalPadding: 6
        verticalPadding: 6
        Accessible.name: "Ir al último mensaje"
        ToolTip.visible: hovered
        ToolTip.text: "Ir al último mensaje"
        onClicked: { conversation.followLatest = true; conversation.positionViewAtEnd(); }
    }
}
