import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../../js/MarkdownRich.js" as MarkdownRich
import "../../js/Performance.js" as Performance
import "../shared"

GlassPanel {
    id: pane
    required property AgentBridge bridge
    signal performanceRequested(var measurement)
    signal suggestionRequested(string text)
    signal loginRequested()
    signal accountRequested()
    radius: 16
    topColor: "#00000000"
    bottomColor: "#00000000"
    edgeColor: "#00000000"
    reflective: false

    function modelLabel(slug) {
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            if (model.slug === slug) return model.displayName || slug;
        }
        return slug || "";
    }

    function assistantLabel(slug) {
        const lower = (slug || "").toLowerCase();
        if (lower.startsWith("gemini")) return "Gemini";
        if (lower.startsWith("claude")) return "Claude";
        if (lower.startsWith("gpt-oss")) return "Antigravity";
        if (!lower && bridge.provider === "agy") return "Antigravity";
        if (!lower && bridge.provider === "claude") return "Claude";
        return "ChatGPT";
    }

    // Avanza el texto revelado alineándolo a palabras completas para evitar saltos de línea a mitad de palabra.
    function nextStreamLength(fullText, currentLen, finishing) {
        const total = fullText.length;
        if (currentLen >= total) return total;
        const pending = total - currentLen;
        const ratio = finishing ? 0.36 : 0.24;
        const step = Math.max(finishing ? 4 : 3, Math.ceil(pending * ratio));
        let next = Math.min(total, currentLen + step);
        if (next < total) {
            const code = fullText.charCodeAt(next - 1);
            if (code >= 0xD800 && code <= 0xDBFF) next = Math.min(total, next + 1);
            const lookaheadLimit = Math.min(total, next + 10);
            let probe = next;
            while (probe < lookaheadLimit && /[^\s.,;:!?()[\]{}`*#|]/.test(fullText.charAt(probe)))
                probe++;
            if (probe < lookaheadLimit && probe > next)
                next = probe;
        }
        while (next < total && /[*`#|~_]/.test(fullText.charAt(next)))
            next++;
        return next;
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        spacing: 14
        visible: pane.bridge.messages.count === 0

        HeroOrb {
            anchors.horizontalCenter: parent.horizontalCenter
            bridge: pane.bridge
        }

        Text {
            width: parent.width
            visible: !pane.bridge.engineReady
            text: pane.bridge.provider === "claude"
                ? "Inicia sesión en Claude Code con tu plan Pro o Max para comenzar."
                : "Conecta tu cuenta de ChatGPT" + (pane.bridge.agyAvailable ? " o usa Gemini (agy)" : "") + " para comenzar."
            color: GemaTheme.mutedColor
            font.pixelSize: 12
            style: Text.Raised
            styleColor: GemaTheme.textShadow
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !pane.bridge.engineReady
            spacing: 10
            ActionButton {
                visible: pane.bridge.provider !== "claude"
                text: "Continuar con ChatGPT"
                accent: true
                enabled: pane.bridge.ready && !pane.bridge.loginBusy && !pane.bridge.claudeLoginBusy && !pane.bridge.accountBusy && !pane.bridge.providerBusy
                onClicked: pane.loginRequested()
            }
            ActionButton {
                objectName: "chatHeroUseAgy"
                visible: pane.bridge.provider !== "claude" && pane.bridge.agyAvailable
                text: "✦ Usar Gemini (agy)"
                enabled: pane.bridge.ready && !pane.bridge.loginBusy && !pane.bridge.claudeLoginBusy && !pane.bridge.accountBusy && !pane.bridge.providerBusy
                onClicked: pane.bridge.selectProvider("agy")
            }
            ActionButton {
                objectName: "chatHeroLoginClaude"
                visible: pane.bridge.provider === "claude" && pane.bridge.claudeAvailable
                text: pane.bridge.claudeLoginBusy ? "Iniciando sesión…" : "◆ Conectar Claude"
                accent: true
                enabled: pane.bridge.ready && !pane.bridge.loginBusy && !pane.bridge.claudeLoginBusy && !pane.bridge.accountBusy && !pane.bridge.providerBusy
                onClicked: pane.bridge.loginClaude()
            }
            ActionButton {
                objectName: "chatHeroRefreshClaude"
                visible: pane.bridge.provider === "claude" && pane.bridge.claudeAvailable
                text: "Comprobar sesión"
                enabled: pane.bridge.ready && !pane.bridge.loginBusy && !pane.bridge.claudeLoginBusy && !pane.bridge.accountBusy && !pane.bridge.providerBusy
                onClicked: pane.bridge.refreshClaudeAuth()
            }
        }
    }

    ListView {
        id: conversation
        objectName: "chatMessageList"
        property bool followLatest: true
        property double nextToolScheduleMs: 0
        visible: pane.bridge.messages.count > 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 18
        anchors.bottomMargin: 18
        width: Math.min(parent.width - 32, 820)
        clip: true
        spacing: 22
        model: pane.bridge.messages
        displaced: Transition {
            NumberAnimation {
                properties: "x,y"
                duration: GemaTheme.animations ? 240 : 0
                easing.type: Easing.OutCubic
            }
        }
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AlwaysOff
            onPressedChanged: {
                if (pressed) {
                    smoothFollowAnim.stop();
                    conversation.followLatest = false;
                } else {
                    conversation.followLatest = conversation.atYEnd;
                }
            }
        }
        NumberAnimation {
            id: smoothFollowAnim
            target: conversation
            property: "contentY"
            duration: 110
            easing.type: Easing.OutCubic
        }
        function scrollToLatest(smooth) {
            if (!followLatest || moving) return;
            const maxY = Math.max(originY, originY + contentHeight - height);
            if (!smooth || !GemaTheme.animations || Math.abs(contentY - maxY) > height * 0.75) {
                smoothFollowAnim.stop();
                positionViewAtEnd();
                return;
            }
            if (Math.abs(contentY - maxY) < 1) return;
            smoothFollowAnim.stop();
            smoothFollowAnim.from = contentY;
            smoothFollowAnim.to = maxY;
            smoothFollowAnim.start();
        }
        onMovementStarted: {
            smoothFollowAnim.stop();
            followLatest = false;
        }
        onMovementEnded: followLatest = atYEnd
        onCountChanged: {
            if (!count) followLatest = true;
            else if (model.get(count - 1).author === "TÚ"
                || (model.get(count - 1).toolJson && JSON.parse(model.get(count - 1).toolJson).source === "local")) followLatest = true;
        }
        onContentHeightChanged: {
            if (followLatest && !moving) Qt.callLater(() => {
                conversation.scrollToLatest(pane.bridge.busy);
            });
        }
        footer: Item {
            id: thinkingFooter
            readonly property bool waiting: pane.bridge.busy && !pane.bridge.shellRunning && conversation.count > 0
                && (pane.bridge.messages.get(conversation.count - 1).author === "TÚ"
                    || !!pane.bridge.messages.get(conversation.count - 1).toolJson)
            readonly property bool afterTools: waiting && conversation.count > 0
                && !!pane.bridge.messages.get(conversation.count - 1).toolJson
            readonly property string thinkingLabel: afterTools
                ? "Analizando resultados"
                : (pane.bridge.reasoningEffort ? "Razonando respuesta" : "Pensando")
            property int dotStep: 0
            width: conversation.width
            height: waiting ? 46 : 0

            Timer {
                interval: 420
                repeat: true
                running: thinkingFooter.waiting
                onTriggered: thinkingFooter.dotStep = (thinkingFooter.dotStep + 1) % 3
            }

            GlassPanel {
                id: thinkingPill
                objectName: "chatThinkingIndicator"
                visible: thinkingFooter.waiting
                x: 4
                y: 6
                implicitWidth: thinkingRow.implicitWidth + 24
                implicitHeight: 34
                radius: 11
                topColor: "#15ffffff"
                bottomColor: "#08ffffff"
                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.38) : "#32ffffff"
                reflective: true

                RowLayout {
                    id: thinkingRow
                    anchors.centerIn: parent
                    spacing: 10

                    // Tres puntos luminosos con onda progresiva al color del tema Gema.
                    Row {
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 5
                                height: 5
                                radius: 2.5
                                color: GemaTheme.synced ? GemaTheme.accent : "#eef4fa"
                                opacity: thinkingFooter.dotStep === index ? 1.0 : 0.32
                                scale: thinkingFooter.dotStep === index ? 1.22 : 0.88
                                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.InOutQuad } }
                                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.InOutQuad } }
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: thinkingFooter.thinkingLabel + "…"
                        color: GemaTheme.textColor
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: !!pane.bridge.modelName
                        text: "· " + pane.modelLabel(pane.bridge.modelName)
                        color: GemaTheme.subtleColor
                        font.pixelSize: 11
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
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
            required property var model
            readonly property string imageUrl: model.imageUrl || ""
            readonly property bool isTool: !!toolJson
            readonly property bool fromUser: author === "TÚ"
            readonly property bool systemMessage: author === "SISTEMA"
            readonly property bool streaming: pane.bridge.busy && turnId === pane.bridge.activeTurnId
            property bool wasStreaming: streaming
            readonly property bool revealingTail: wasStreaming && !streaming && revealedLength < body.length
                && !fromUser && !systemMessage && GemaTheme.animations
            readonly property bool activeStream: (streaming || revealingTail) && !fromUser && !systemMessage && GemaTheme.animations
            property int revealedLength: activeStream ? pane.nextStreamLength(body, 0, false) : body.length
            readonly property string visibleBody: (!activeStream || revealedLength >= body.length)
                ? body
                : MarkdownRich.closeOpenMarkdown(body.slice(0, revealedLength))
            readonly property var measurement: performanceJson ? JSON.parse(performanceJson) : ({})
            readonly property int userHeaderHeight: 26
            readonly property int userBubbleTop: userHeaderHeight + 7
            readonly property real cardWidth: fromUser ? Math.min(width * 0.84, 640,
                Math.max(imageUrl ? 320 : 72, Math.ceil(userTextSize.implicitWidth) + 32)) : width
            width: conversation.width
            implicitHeight: isTool
                ? toolCard.implicitHeight
                : (fromUser ? userBubbleTop + messageContent.implicitHeight + 22 : messageContent.implicitHeight + 20)
            onStreamingChanged: {
                if (streaming) {
                    wasStreaming = true;
                } else if (!GemaTheme.animations || (body.length - revealedLength) > 240
                           || measurement.status === "interrupted" || measurement.status === "failed") {
                    wasStreaming = false;
                    revealedLength = body.length;
                }
            }
            onBodyChanged: {
                if (!activeStream) {
                    revealedLength = body.length;
                } else if (revealedLength > body.length) {
                    revealedLength = body.length;
                } else if (revealedLength === 0 && body.length > 0) {
                    revealedLength = pane.nextStreamLength(body, 0, false);
                }
            }
            Timer {
                id: streamRevealTimer
                interval: 16
                repeat: true
                running: message.activeStream && message.revealedLength < message.body.length
                onTriggered: {
                    message.revealedLength = pane.nextStreamLength(message.body, message.revealedLength, !message.streaming);
                    if (!message.streaming && message.revealedLength >= message.body.length)
                        message.wasStreaming = false;
                }
            }
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
                Component.onCompleted: {
                    if (!message.isTool || !pane.bridge.busy) return;
                    const now = Date.now();
                    if (conversation.nextToolScheduleMs <= now) {
                        entranceDelay = 0;
                        conversation.nextToolScheduleMs = now + 75;
                    } else {
                        entranceDelay = Math.min(450, Math.round(conversation.nextToolScheduleMs - now));
                        conversation.nextToolScheduleMs = Math.min(now + 525, conversation.nextToolScheduleMs + 75);
                    }
                }
            }
            // Encabezado de perfil personal del usuario sobre cada mensaje enviado.
            Item {
                id: userProfileHeader
                objectName: "chatUserProfile"
                visible: message.fromUser
                anchors.right: parent.right
                anchors.rightMargin: 2
                y: 0
                width: Math.min(parent.width - 16, userProfileRow.implicitWidth)
                height: message.userHeaderHeight

                RowLayout {
                    id: userProfileRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        objectName: "chatUserProfileName"
                        text: userAvatar.displayName
                        textFormat: Text.PlainText
                        color: userProfileMouse.containsMouse
                            ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                            : GemaTheme.textColor
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                    }

                    UserAvatar {
                        id: userAvatar
                        size: 24
                        customName: pane.bridge.displayName
                        plan: pane.bridge.plan
                        connected: pane.bridge.authenticated
                    }
                }

                MouseArea {
                    id: userProfileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.accountRequested()
                }
                ToolTip.visible: userProfileMouse.containsMouse
                ToolTip.delay: 450
                ToolTip.text: userAvatar.displayName + "\nEditar nombre de usuario y cuenta"
            }
            GlassPanel {
                anchors.right: parent.right
                y: message.userBubbleTop
                width: message.cardWidth
                height: messageContent.implicitHeight + 22
                visible: message.fromUser
                radius: 15
                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.26) : "#26c4dcff"
                bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#160a101a"
                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.58) : "#4ec4dcff"
            }
            // Hilo vertical acento que da estructura y personalidad a cada respuesta de la IA.
            Rectangle {
                visible: !message.isTool && !message.fromUser && !message.systemMessage && message.body.length > 0
                x: messageContent.x + 11
                y: messageContent.y + 32
                width: 2
                height: Math.max(0, bodyText.height - 8)
                radius: 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.42) : "#48c4dcff" }
                    GradientStop { position: 0.78; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.14) : "#1cc4dcff" }
                    GradientStop { position: 1.0; color: "#00000000" }
                }
            }
            ColumnLayout {
                id: messageContent
                visible: !message.isTool
                x: message.fromUser ? message.width - message.cardWidth + 14 : 10
                y: message.fromUser ? message.userBubbleTop + 11 : 8
                width: message.fromUser ? message.cardWidth - 28 : message.width - 20
                spacing: 12
                opacity: 1.0
                transform: Translate { id: msgShift; y: 0 }
                Component.onCompleted: {
                    if (GemaTheme.animations && pane.bridge.busy && !message.isTool) {
                        messageContent.opacity = 0.0;
                        msgShift.y = 8;
                        msgEntranceAnim.start();
                    }
                }
                ParallelAnimation {
                    id: msgEntranceAnim
                    NumberAnimation {
                        target: messageContent
                        property: "opacity"
                        from: 0.0
                        to: 1.0
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: msgShift
                        property: "y"
                        from: 8
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
                Image {
                    objectName: "chatMessageImage"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(220, implicitHeight * width / Math.max(1, implicitWidth))
                    visible: !!message.imageUrl && message.fromUser
                    source: message.imageUrl
                    sourceSize: Qt.size(640, 640)
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    asynchronous: true
                    Accessible.name: "Imagen enviada"
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !message.fromUser
                    spacing: 9
                    GlassPanel {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        reflective: false
                        topColor: message.systemMessage ? "#20ffffff" : (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#28c4dcff")
                        bottomColor: message.systemMessage ? "#0cffffff" : (GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#10c4dcff")
                        edgeColor: message.systemMessage ? "#38ffffff" : (GemaTheme.synced ? GemaTheme.accentAlpha(0.58) : "#50c4dcff")
                        Text {
                            anchors.centerIn: parent
                            text: message.systemMessage ? "◈" : GemaTheme.gemSymbol
                            color: message.systemMessage ? "#e4e4e4" : (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                    Text {
                        text: message.systemMessage ? "Sistema"
                            : pane.assistantLabel(message.measurement.model || (message.streaming ? pane.bridge.modelName : ""))
                        color: GemaTheme.textColor
                        font.pixelSize: 13
                        font.bold: true
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    GlassPanel {
                        visible: !message.systemMessage && !!pane.modelLabel(message.measurement.model)
                        implicitWidth: modelBadgeText.implicitWidth + 14
                        implicitHeight: 19
                        radius: 7
                        reflective: false
                        topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#1affffff"
                        bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.06) : "#0affffff"
                        edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.36) : "#2cffffff"
                        Text {
                            id: modelBadgeText
                            anchors.centerIn: parent
                            text: pane.modelLabel(message.measurement.model)
                            textFormat: Text.PlainText
                            color: GemaTheme.synced ? GemaTheme.accentInk : GemaTheme.mutedColor
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        id: streamingBadge
                        visible: message.streaming || message.measurement.status === "interrupted"
                                 || message.measurement.status === "failed"
                        text: message.streaming ? "● Generando…"
                              : message.measurement.status === "interrupted" ? "○ Detenida" : "▲ Error"
                        color: message.streaming && GemaTheme.synced ? GemaTheme.accent : GemaTheme.mutedColor
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                        opacity: 1.0
                        SequentialAnimation on opacity {
                            id: streamingBadgePulse
                            running: message.streaming && GemaTheme.animations
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) streamingBadge.opacity = 1.0
                            NumberAnimation { from: 0.96; to: 0.45; duration: 620; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.45; to: 0.96; duration: 620; easing.type: Easing.InOutSine }
                        }
                    }
                }
                TextArea {
                    id: bodyText
                    objectName: message.fromUser ? "chatUserMessage" : message.systemMessage ? "chatSystemMessage" : "chatAssistantMessage"
                    selectionColor: GemaTheme.codePalette.selectionBg
                    selectedTextColor: GemaTheme.codePalette.selectionFg
                    Layout.fillWidth: true
                    Layout.leftMargin: !message.fromUser && !message.systemMessage ? 33 : 0
                    text: message.fromUser || message.systemMessage
                        ? message.body
                        : MarkdownRich.toHtml(message.visibleBody, GemaTheme.codePalette, GemaTheme.accentHex, GemaTheme.darkText)
                    visible: !!message.body
                    readOnly: true
                    selectByMouse: true
                    color: message.fromUser ? "#ffffff" : GemaTheme.textColor
                    font.pixelSize: message.fromUser || message.systemMessage ? 14 : 15
                    wrapMode: TextEdit.Wrap
                    textFormat: message.fromUser || message.systemMessage ? TextEdit.PlainText : TextEdit.RichText
                    onLinkActivated: link => {
                        if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link);
                    }
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: message.fromUser || message.systemMessage ? 0 : 2
                    bottomPadding: message.fromUser || message.systemMessage ? 0 : 6
                    background: null

                    Item {
                        id: streamingCursorWrap
                        objectName: "chatStreamingCursor"
                        readonly property bool showCursor: message.activeStream && bodyText.length > 0
                        readonly property rect endRect: {
                            if (!showCursor) return Qt.rect(0, 0, 0, 18);
                            let pos = bodyText.length;
                            const _h = bodyText.contentHeight;
                            const _w = bodyText.width;
                            while (pos > 1) {
                                const ch = bodyText.getText(pos - 1, pos);
                                if (ch === "\uFFFC" || ch === "\uFDD0" || ch === "\uFDD1")
                                    pos--;
                                else
                                    break;
                            }
                            return pos > 0 ? bodyText.positionToRectangle(pos) : Qt.rect(0, 0, 0, 18);
                        }
                        readonly property real lineH: endRect.height > 4 ? endRect.height : 18
                        visible: opacity > 0.01
                        opacity: showCursor ? 1.0 : 0.0
                        x: Math.min(Math.max(0, bodyText.width - width), Math.max(0, endRect.x + 2))
                        y: Math.max(0, endRect.y + (lineH - height) / 2)
                        width: 3
                        height: 16
                        Behavior on opacity {
                            enabled: GemaTheme.animations
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        Behavior on x {
                            enabled: GemaTheme.animations && streamingCursorWrap.visible
                            NumberAnimation { duration: 55; easing.type: Easing.OutCubic }
                        }
                        Behavior on y {
                            enabled: GemaTheme.animations && streamingCursorWrap.visible
                            NumberAnimation { duration: 75; easing.type: Easing.OutCubic }
                        }
                        // Estela luminosa suave detrás del cursor sobre las palabras recién generadas.
                        Rectangle {
                            anchors.right: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(36, streamingCursorWrap.x)
                            height: Math.min(20, streamingCursorWrap.lineH)
                            radius: 4
                            visible: width > 4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "#00000000" }
                                GradientStop { position: 0.72; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.14) : "#208be9fd" }
                                GradientStop { position: 1.0; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.26) : "#368be9fd" }
                            }
                        }
                        // Halo ambiental del cursor.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 11
                            height: 22
                            radius: 5.5
                            color: GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#3c8be9fd"
                            z: -1
                        }
                        // Cursor vertical luminoso pulsante.
                        Rectangle {
                            id: streamingCaretCore
                            anchors.fill: parent
                            radius: 1.5
                            color: GemaTheme.synced ? GemaTheme.accent : "#8be9fd"
                            SequentialAnimation on opacity {
                                running: streamingCursorWrap.showCursor && GemaTheme.animations
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) streamingCaretCore.opacity = 1.0
                                NumberAnimation { from: 1.0; to: 0.42; duration: 420; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.42; to: 1.0; duration: 420; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: !message.fromUser && !message.systemMessage ? 33 : 0
                    Layout.minimumHeight: 24
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
                            color: metricsButton.hovered ? GemaTheme.textColor : GemaTheme.subtleColor
                            font.pixelSize: 11
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
