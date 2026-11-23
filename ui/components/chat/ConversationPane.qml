import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../../js/Performance.js" as Performance
import "../shared"

GlassPanel {
    id: pane
    required property AgentBridge bridge
    signal performanceRequested(var measurement)
    signal suggestionRequested(string text)
    signal loginRequested()
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

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 560)
        spacing: pane.height < 260 ? 12 : 18
        visible: pane.bridge.messages.count === 0

        GlassPanel {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: heroBadgeRow.implicitWidth + 24
            implicitHeight: 28
            radius: 14
            topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.20) : "#20ffffff"
            bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#10ffffff"
            edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.48) : "#38ffffff"
            RowLayout {
                id: heroBadgeRow
                anchors.centerIn: parent
                spacing: 7
                Text {
                    text: GemaTheme.gemSymbol
                    color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                    font.pixelSize: 12
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
                Text {
                    text: pane.bridge.activeArea === "app"
                          ? "GEMA UI KIT · " + (pane.bridge.projectEngine === "rust" ? "RUST ENGINE" : "PYTHON ENGINE")
                          : pane.bridge.activeArea === "work"
                            ? "WORK · " + (pane.bridge.projectName ? pane.bridge.projectName.toUpperCase() : "ESPACIO DE DESARROLLO")
                            : "AGENT SHELL · " + GemaTheme.gemName.toUpperCase()
                    color: GemaTheme.textColor
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
        }

        Text {
            width: parent.width
            text: pane.bridge.activeArea === "app"
                  ? "Diseña tu aplicación Gema UI Kit"
                  : pane.bridge.activeArea === "work" ? "¿Qué vamos a construir?" : "¿De qué hablamos?"
            color: GemaTheme.textColor
            font.pixelSize: pane.width < 580 ? 26 : 33
            font.bold: true
            font.letterSpacing: -0.4
            style: Text.Raised
            styleColor: GemaTheme.textShadow
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: pane.bridge.authenticated
                ? (pane.bridge.activeArea === "app"
                   ? "Construye con vidrio mate transparente (Quickshell + " + (pane.bridge.projectEngine === "rust" ? "Rust" : "Python") + "). Usa 'Probar' e 'Iniciar' arriba."
                   : pane.bridge.activeArea === "work" ? "Planifica, crea y prueba en la carpeta de tu proyecto." : "Una idea, una pregunta o algo que quieras aprender.")
                : "Conecta tu cuenta de ChatGPT para comenzar."
            color: GemaTheme.mutedColor
            font.pixelSize: 13
            style: Text.Raised
            styleColor: GemaTheme.textShadow
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, 520)
            spacing: 8
            visible: pane.bridge.authenticated && pane.height >= 260
            Repeater {
                model: pane.bridge.activeArea === "app" ? [
                    { icon: "◈", label: "Añadir panel Glass", desc: "Tarjetas MattePanel, GlassPanel y controles interactivos", prompt: "Diseña en AppWindow.qml una interfaz con paneles GlassPanel/MattePanel y controles de Gema UI Kit para: " },
                    { icon: "⚡", label: "Conectar función al motor", desc: "Nueva acción por tubería JSON-Lines v2 sobre stdio", prompt: "Agrega una nueva acción en AppBridge.qml y en el motor backend por JSON-Lines stdio para: " },
                    { icon: "✦", label: "Mejorar diseño Glassmorphism", desc: "Refinar transparencias, reflejos de agua y micro-interacciones", prompt: "Refina el diseño Glassmorphism de la aplicación (transparencias, bordes luminosos, reflejos y layout) para: " }
                ] : pane.bridge.activeArea === "work" ? [
                    { icon: "❖", label: "Explorar proyecto", desc: "Analizar arquitectura, módulos y punto de arranque", prompt: "Inspecciona este proyecto y explícame su estructura y cómo se ejecuta." },
                    { icon: "⚡", label: "Crear una función", desc: "Implementar y verificar código real en el repositorio", prompt: "Quiero implementar esta función en el proyecto: " },
                    { icon: "✦", label: "Resolver un error", desc: "Diagnosticar fallos y aplicar la solución con pruebas", prompt: "Investiga y corrige este error en el proyecto: " }
                ] : [
                    { icon: "◈", label: "Explorar una idea", desc: "Diseñar conceptos, arquitecturas o planes paso a paso", prompt: "Ayúdame a desarrollar esta idea: " },
                    { icon: "❖", label: "Aprender algo", desc: "Explicaciones claras y visuales con ejemplos reales", prompt: "Explícame de forma sencilla este tema: " },
                    { icon: "✦", label: "Escribir o programar", desc: "Redactar textos, scripts o prototipos rápidamente", prompt: "Ayúdame a escribir este texto: " }
                ]
                delegate: Button {
                    id: suggestionCard
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 54
                    hoverEnabled: true
                    enabled: pane.bridge.canSend
                    scale: suggestionCard.down ? 0.985 : (suggestionCard.hovered ? 1.012 : 1.0)
                    Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                    onClicked: pane.suggestionRequested(modelData.prompt)
                    contentItem: RowLayout {
                        spacing: 12
                        GlassPanel {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 9
                            topColor: suggestionCard.hovered
                                      ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.32) : "#2effffff")
                                      : (GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#18ffffff")
                            bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.08) : "#0cffffff"
                            edgeColor: suggestionCard.hovered
                                       ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.68) : "#60ffffff")
                                       : "#2cffffff"
                            Text {
                                anchors.centerIn: parent
                                text: suggestionCard.modelData.icon
                                color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                                font.pixelSize: 14
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: suggestionCard.modelData.label
                                color: GemaTheme.textColor
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: suggestionCard.modelData.desc
                                color: GemaTheme.subtleColor
                                font.pixelSize: 11
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            text: "→"
                            color: suggestionCard.hovered ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : GemaTheme.subtleColor
                            font.pixelSize: 15
                            font.bold: true
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                        }
                    }
                    background: GlassPanel {
                        radius: 12
                        highlighted: suggestionCard.activeFocus || suggestionCard.hovered
                        topColor: suggestionCard.hovered
                                  ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#28ffffff")
                                  : "#1cffffff"
                        bottomColor: "#22060a10"
                        edgeColor: suggestionCard.hovered
                                   ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.68) : "#58ffffff")
                                   : "#3cffffff"
                    }
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
            required property var model
            readonly property string imageUrl: model.imageUrl || ""
            readonly property bool isTool: !!toolJson
            readonly property bool fromUser: author === "TÚ"
            readonly property bool systemMessage: author === "SISTEMA"
            readonly property bool streaming: pane.bridge.busy && turnId === pane.bridge.activeTurnId
            readonly property var measurement: performanceJson ? JSON.parse(performanceJson) : ({})
            readonly property real cardWidth: fromUser ? Math.min(width * 0.84, 640,
                Math.max(imageUrl ? 320 : 72, Math.ceil(userTextSize.implicitWidth) + 30)) : width
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
                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#22ffffff"
                bottomColor: "#24060a10"
                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.52) : "#42ffffff"
            }
            ColumnLayout {
                id: messageContent
                visible: !message.isTool
                x: message.fromUser ? message.width - message.cardWidth + 14 : 14
                y: message.fromUser ? 10 : 8
                width: message.cardWidth - 28
                spacing: 8
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
                    spacing: 8
                    Rectangle {
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: message.systemMessage ? "#dddddd" : (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                    }
                    Text {
                        text: message.systemMessage ? "Sistema" : "ChatGPT"
                        color: GemaTheme.textColor
                        font.pixelSize: 12
                        font.bold: true
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    GlassPanel {
                        visible: !message.systemMessage && !!pane.modelLabel(message.measurement.model)
                        implicitWidth: modelBadgeText.implicitWidth + 12
                        implicitHeight: 18
                        radius: 6
                        reflective: false
                        topColor: "#16ffffff"
                        bottomColor: "#0affffff"
                        edgeColor: "#24ffffff"
                        Text {
                            id: modelBadgeText
                            anchors.centerIn: parent
                            text: pane.modelLabel(message.measurement.model)
                            textFormat: Text.PlainText
                            color: GemaTheme.subtleColor
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: message.streaming || message.measurement.status === "interrupted"
                                 || message.measurement.status === "failed"
                        text: message.streaming ? "● Escribiendo…"
                              : message.measurement.status === "interrupted" ? "○ Detenida" : "▲ Error"
                        color: message.streaming && GemaTheme.synced ? GemaTheme.accent : GemaTheme.mutedColor
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                }
                TextArea {
                    id: bodyText
                    objectName: message.fromUser ? "chatUserMessage" : message.systemMessage ? "chatSystemMessage" : "chatAssistantMessage"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    Layout.fillWidth: true
                    text: message.body
                    visible: !!message.body
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
