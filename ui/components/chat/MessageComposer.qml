import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AgentShell.Native
import "../.."
import "../../js/ChatCommands.js" as ChatCommands
import "../../js/Performance.js" as Performance
import "../shared"

// Editor con sugerencias de comandos y acciones de envío.
GlassPanel {
    id: composer
    objectName: "chatComposer"
    required property AgentBridge bridge
    property bool compact: false
    property string statusText: bridge.status
    property bool commandsDismissed: false
    property var drafts: ({})
    property var imageDrafts: ({})
    property string attachedImage: ""
    property string pendingPasteId: ""
    property bool areaTransition: false
    signal performanceRequested(var measurement)
    readonly property var contextMeasurement: bridge.latestPerformance
    readonly property string contextModel: unified ? (architect.model || "") : bridge.modelName
    readonly property bool hasContext: !bridge.shellRunning && !!bridge.currentChatId
        && contextMeasurement.chat_id === bridge.currentChatId
        && (!contextModel || contextMeasurement.model === contextModel)
        && typeof contextMeasurement.context_tokens === "number"
        && isFinite(contextMeasurement.context_tokens) && contextMeasurement.context_tokens >= 0
    readonly property var commandMatches: ChatCommands.suggestions(prompt.text)
    readonly property bool unified: !!bridge.unifiedMode
    readonly property var architect: bridge.unifiedArchitect || ({})
    readonly property string architectName: String(architect.name || architect.model || "Sin modelo disponible")
    readonly property string architectEngine: architect.provider === "chatgpt" ? "ChatGPT"
        : architect.provider === "agy" ? "Gemini/Antigravity"
        : architect.provider === "claude" ? "Claude" : String(architect.provider || "")
    readonly property string architectDetail: (architectEngine ? " · " + architectEngine : "")
        + (architect.effort ? " · " + architect.effort : "")
    readonly property string unifiedModelNotice: "Modo unificado: el arquitecto (" + architectName
        + ") es de solo lectura; el selector de modelos está desactivado."
    readonly property var modelQuery: unified ? null : ChatCommands.modelQuery(prompt.text)
    readonly property bool modelMode: modelQuery !== null
    readonly property bool narrow: width < 520
    readonly property var completions: {
        if (!modelMode) return commandMatches.filter(command => !unified || command.name !== "/modelos").map(command => ({
            label: command.label || command.name, value: command.name, description: command.description
        }));
        const models = [];
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            models.push({ slug: model.slug, displayName: model.displayName, family: model.family,
                efforts: JSON.parse(model.reasoningEfforts), defaultEffort: model.defaultReasoningEffort });
        }
        return ChatCommands.modelChoices(prompt.text, models, bridge.modelName, bridge.reasoningEffort);
    }
    readonly property bool showCommands: prompt.activeFocus && !commandsDismissed && (completions.length > 0 || modelMode)
    readonly property bool canSubmit: !pendingPasteId && (prompt.text.trim().startsWith("/") || bridge.canSend)
    readonly property string activeModelLabel: {
        if (unified || bridge.shellRunning || !bridge.engineReady || !bridge.modelName) return "";
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            if (model.slug === bridge.modelName) return (model.displayName || model.slug)
                + (bridge.reasoningEffort ? " · " + ChatCommands.effortLabel(bridge.reasoningEffort) : "");
        }
        return "";
    }
    implicitHeight: editorLayout.implicitHeight + 24
    radius: 18
    topColor: promptHover.hovered || prompt.activeFocus ? "#24ffffff" : "#1cffffff"
    bottomColor: "#28060a10"
    edgeColor: prompt.activeFocus ? "#70ffffff" : promptHover.hovered ? "#52ffffff" : "#42ffffff"
    highlighted: prompt.activeFocus

    function prepare(text) {
        prompt.text = text;
        prompt.forceActiveFocus();
        prompt.cursorPosition = prompt.length;
    }
    function blockUnifiedModels() {
        bridge.status = unifiedModelNotice;
        prompt.forceActiveFocus();
    }
    function send() {
        if (unified && ChatCommands.modelQuery(prompt.text) !== null) { blockUnifiedModels(); return; }
        if (pendingPasteId || (!prompt.text.trim() && !attachedImage)) return;
        if (showCommands && completions.length) { executeSelected(); return; }
        const command = ChatCommands.parse(prompt.text);
        if (bridge.submit(prompt.text, command ? "" : attachedImage)) {
            prompt.clear();
            if (!command) attachedImage = "";
        }
    }
    function cancelPaste() {
        pendingPasteId = "";
        pasteTimeout.stop();
    }
    function pasteImage() {
        if (pendingPasteId) return;
        pendingPasteId = bridge.pasteClipboard();
        if (pendingPasteId) pasteTimeout.start();
        else bridge.status = "Espera a que el motor esté disponible para pegar una imagen.";
    }
    function executeSelected() {
        const option = completions[completionList.currentIndex];
        if (!option) return;
        if (unified && option.value === "/modelos") { blockUnifiedModels(); return; }
        if (modelMode && ChatCommands.blockedReason("/modelos", bridge)) {
            bridge.submit(prompt.text);
            return;
        }
        if (!modelMode && option.value === "/modelos") {
            if (ChatCommands.blockedReason("/modelos", bridge)) bridge.submit("/modelos");
            else openModels();
            return;
        }
        if (!modelMode && option.value === "/shell") {
            prepare("/shell ");
            commandsDismissed = true;
            return;
        }
        if (modelMode && !option.final) {
            prepare(option.command);
            commandsDismissed = false;
            completionList.currentIndex = 0;
            return;
        }
        if (bridge.submit(modelMode ? option.command : option.value)) prompt.clear();
    }
    function openModels(command) {
        if (unified) { blockUnifiedModels(); return; }
        prepare(command ? command.trim() + " " : "/modelos ");
        commandsDismissed = false;
    }

    Connections {
        target: composer.bridge
        function onAreaChanged(previousKey, currentKey) {
            composer.drafts[previousKey] = prompt.text;
            composer.imageDrafts[previousKey] = composer.attachedImage;
            composer.cancelPaste();
            composer.areaTransition = true;
            prompt.text = composer.drafts[currentKey] || "";
            composer.attachedImage = composer.imageDrafts[currentKey] || "";
            prompt.cursorPosition = prompt.length;
            composer.commandsDismissed = false;
        }
        function onClipboardResult(result) {
            if (!composer.pendingPasteId || result.request_id !== composer.pendingPasteId) return;
            composer.cancelPaste();
            if (result.image) {
                composer.attachedImage = result.image;
                composer.bridge.status = "Imagen adjunta. Puedes añadir un mensaje y enviarla.";
            } else if (result.message) composer.bridge.status = result.message;
            else prompt.paste();
        }
        function onEventReceived(event) {
            if (event.type === "project.deleted") {
                for (const prefix of ["work:", "app:"]) {
                    const key = prefix + event.data.project_id;
                    delete composer.drafts[key];
                    delete composer.imageDrafts[key];
                }
            }
            if (event.type === "chat.reset" || event.type === "chat.loaded") {
                composer.cancelPaste();
                if (!composer.areaTransition) composer.attachedImage = "";
                composer.areaTransition = false;
            }
        }
        function onReadyChanged() {
            if (!composer.bridge.ready) composer.cancelPaste();
        }
    }
    Timer {
        id: pasteTimeout
        interval: 6500
        onTriggered: {
            composer.pendingPasteId = "";
            composer.bridge.status = "No se pudo obtener la imagen del portapapeles. Intenta pegarla otra vez.";
        }
    }

    ColumnLayout {
        id: editorLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        RowLayout {
            objectName: "chatAttachmentPreview"
            Layout.fillWidth: true
            visible: !!composer.attachedImage || !!composer.pendingPasteId
            spacing: 10
            GlassPanel {
                implicitWidth: 48
                implicitHeight: 48
                radius: 8
                Image {
                    objectName: "chatAttachmentThumbnail"
                    anchors.fill: parent
                    anchors.margins: 4
                    source: composer.attachedImage
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    asynchronous: true
                }
                BusyIndicator { anchors.centerIn: parent; width: 24; height: 24; running: !!composer.pendingPasteId; visible: running }
            }
            Text {
                Layout.fillWidth: true
                text: composer.pendingPasteId ? "Pegando imagen…" : "Imagen adjunta"
                color: "#d0d0d0"
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Button {
                objectName: "chatRemoveAttachment"
                text: "×"
                implicitWidth: 28
                implicitHeight: 28
                padding: 0
                hoverEnabled: true
                onClicked: { composer.cancelPaste(); composer.attachedImage = ""; prompt.forceActiveFocus(); }
                Accessible.name: "Quitar imagen adjunta"
                ToolTip.visible: hovered
                ToolTip.text: "Quitar imagen"
                contentItem: Text { text: parent.text; color: "#cccccc"; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: parent.hovered ? "#12ffffff" : "transparent"; border.color: "#30ffffff"; border.width: parent.visualFocus ? 1 : 0 }
            }
        }
        ScrollView {
            HoverHandler { id: promptHover }
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            Layout.fillWidth: true
            Layout.preferredHeight: composer.compact || composer.narrow ? 64 : 88
            Layout.minimumHeight: 48
            clip: true
            TextArea {
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                id: prompt
                objectName: "chatPrompt"
                placeholderText: composer.bridge.activeArea === "app"
                    ? "Describe qué quieres añadir a tu aplicación Gema UI Kit o /shell comando…"
                    : composer.bridge.activeArea === "work"
                      ? "Describe lo que quieres construir o /shell comando…"
                      : composer.bridge.engineReady ? "Escribe un mensaje o /comando…" : "Escribe /shell comando o conecta ChatGPT…"
                placeholderTextColor: "#aaaaaa"
                color: "#f5f5f5"
                font.pixelSize: 14
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                onTextChanged: { composer.commandsDismissed = false; completionList.currentIndex = 0; }
                padding: 4
                background: null
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_V && event.modifiers === Qt.ControlModifier && !NativeApp.clipboardText) {
                        composer.pasteImage();
                        event.accepted = true;
                        return;
                    }
                    if (composer.showCommands && event.modifiers === Qt.NoModifier) {
                        if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
                            if (composer.completions.length) {
                                const step = event.key === Qt.Key_Right ? 1 : -1;
                                completionList.currentIndex = (completionList.currentIndex + step + composer.completions.length) % composer.completions.length;
                                completionList.positionViewAtIndex(completionList.currentIndex, ListView.Contain);
                            }
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Escape) {
                            composer.commandsDismissed = true;
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Tab && composer.completions.length) {
                            const option = composer.completions[completionList.currentIndex];
                            if (composer.unified && option.value === "/modelos") { composer.blockUnifiedModels(); event.accepted = true; return; }
                            prompt.text = composer.modelMode ? option.command : option.value + (option.value === "/shell" ? " " : "");
                            prompt.cursorPosition = prompt.length;
                            composer.commandsDismissed = !(option.final === false || option.value === "/modelos");
                            completionList.currentIndex = 0;
                            event.accepted = true;
                            return;
                        }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            composer.send();
                            event.accepted = true;
                            return;
                        }
                    }
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && !(event.modifiers & Qt.ShiftModifier)) {
                        composer.send();
                        event.accepted = true;
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: prompt.activeFocus ? "#30ffffff" : "#18ffffff" }
        RowLayout {
            objectName: "chatComposerActions"
            Layout.fillWidth: true
            Layout.minimumHeight: 40
            Layout.maximumHeight: 40
            Layout.preferredHeight: 40
            spacing: 8
            ActionButton {
                objectName: "chatPasteImageButton"
                implicitWidth: 36
                implicitHeight: 36
                horizontalPadding: 0
                verticalPadding: 0
                font.pixelSize: 16
                text: "＋"
                enabled: composer.bridge.ready && !composer.bridge.busy && !composer.pendingPasteId
                Accessible.name: "Pegar imagen del portapapeles"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: "Pegar imagen del portapapeles"
                onClicked: composer.pasteImage()
            }
            // Este espacio permanece reservado cuando las sugerencias se ocultan.
            Item {
                objectName: "chatCommandSlot"
                Layout.fillWidth: true
                implicitHeight: 40
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !composer.showCommands
                    spacing: 6
                    Rectangle {
                        objectName: "chatUnifiedArchitect"
                        Layout.preferredWidth: Math.min(architectRow.implicitWidth + 16, parent.width * 0.6)
                        Layout.preferredHeight: 22
                        visible: composer.unified
                        radius: 11
                        color: "#14ffffff"
                        border.width: 1
                        border.color: architectHover.hovered ? "#50ffffff" : "#28ffffff"
                        activeFocusOnTab: true
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Arquitecto unificado, solo lectura: " + composer.architectName
                            + composer.architectDetail
                        Accessible.description: "No se puede cambiar el modelo en modo unificado."
                        HoverHandler { id: architectHover }
                        ToolTip.visible: architectHover.hovered
                        ToolTip.delay: 400
                        ToolTip.text: "El sistema elige automáticamente el mejor modelo con cuota disponible; no se puede cambiar en modo unificado."
                        RowLayout {
                            id: architectRow
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 5
                            Text { text: "◆"; color: "#cccccc"; font.pixelSize: 9 }
                            Text {
                                objectName: "chatUnifiedArchitectName"
                                Layout.fillWidth: true
                                text: composer.architectName + composer.architectDetail
                                textFormat: Text.PlainText
                                color: "#e6e6e6"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text { text: "auto"; color: "#aaaaaa"; font.pixelSize: 9; opacity: 0.7 }
                        }
                    }
                    Text {
                        objectName: "chatActiveModel"
                        Layout.preferredWidth: Math.min(implicitWidth, parent.width * 0.4)
                        visible: composer.activeModelLabel !== "" && !composer.narrow
                        text: composer.activeModelLabel
                        textFormat: Text.PlainText
                        color: "#aaaaaa"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Modelo activo: " + text
                        HoverHandler { id: modelHover }
                        ToolTip.visible: visible && modelHover.hovered
                        ToolTip.delay: 400
                        ToolTip.text: composer.bridge.provider === "agy"
                            ? composer.bridge.modelName + " · Antigravity (agy) · Cambia con /modelos"
                            : composer.bridge.provider === "claude"
                              ? composer.bridge.modelName + " · Claude Code · Esfuerzo: "
                                + ChatCommands.effortLabel(composer.bridge.reasoningEffort || "auto") + " · Cambia con /modelos"
                              : composer.bridge.modelName + " · Esfuerzo: "
                                + ChatCommands.effortLabel(composer.bridge.reasoningEffort || "auto") + " · Cambia con /modelos"
                    }
                    Text {
                        visible: (composer.activeModelLabel !== "" || composer.unified) && composer.statusText !== "" && !composer.narrow
                        text: "·"
                        color: "#888888"
                        font.pixelSize: 11
                    }
                    Text {
                        objectName: "chatComposerStatus"
                        Layout.fillWidth: true
                        text: composer.statusText
                        textFormat: Text.PlainText
                        color: composer.bridge.busy || composer.bridge.loginBusy ? "#d6d6d6" : "#aaaaaa"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        HoverHandler { id: statusHover }
                        ToolTip.visible: visible && statusHover.hovered
                        ToolTip.delay: 400
                        ToolTip.text: text
                    }
                }
                RowLayout {
                    id: inlineSuggestions
                    objectName: "chatInlineSuggestions"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    visible: composer.showCommands
                    spacing: 8
                    ListView {
                        id: completionList
                        objectName: "chatCommandList"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: composer.completions.length > 0
                        orientation: ListView.Horizontal
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        spacing: 6
                        model: composer.completions
                        currentIndex: 0
                        onCountChanged: { if (currentIndex < 0 || currentIndex >= count) currentIndex = 0; }
                        ScrollIndicator.horizontal: ScrollIndicator { visible: false }
                        delegate: Button {
                            id: optionButton
                            required property var modelData
                            required property int index
                            readonly property string blocked: ChatCommands.blockedReason(composer.modelMode ? "/modelos" : modelData.value, composer.bridge)
                            width: Math.min(200, label.implicitWidth + 20)
                            height: 28
                            enabled: !blocked
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            onClicked: { completionList.currentIndex = index; composer.executeSelected(); }
                            contentItem: Text {
                                id: label
                                text: (composer.modelMode && modelData.selected ? "• " : "") + modelData.label
                                font.pixelSize: 11
                                color: optionButton.enabled ? "#dddddd" : "#777777"
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 7
                                color: completionList.currentIndex === optionButton.index || optionButton.hovered ? "#20ffffff" : "transparent"
                                border.width: 1
                                border.color: completionList.currentIndex === optionButton.index ? "#60ffffff" : "#20ffffff"
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: blocked || modelData.description
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !composer.completions.length
                        text: composer.bridge.availableModels.count ? "Sin coincidencias"
                            : (composer.bridge.provider === "agy"
                               ? "Cargando modelos de Antigravity (agy)…"
                               : composer.bridge.provider === "claude"
                                 ? "Conecta Claude Code para ver los modelos"
                                 : "Conecta ChatGPT para ver tus modelos")
                        color: "#aaaaaa"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: composer.completions.length > 0 && inlineSuggestions.width >= 360
                        text: "←→ · Enter"
                        color: "#888888"
                        font.pixelSize: 10
                    }
                }
            }
            Button {
                id: contextButton
                objectName: "chatComposerContext"
                visible: composer.hasContext
                text: composer.narrow ? Performance.tokens(composer.contextMeasurement.context_tokens)
                                      : "Contexto: " + Performance.tokens(composer.contextMeasurement.context_tokens) + " tokens"
                hoverEnabled: true
                padding: 4
                Accessible.name: "Ver contexto de la última llamada: " + composer.contextMeasurement.context_tokens + " tokens"
                ToolTip.visible: visible && hovered
                ToolTip.delay: 400
                ToolTip.text: composer.contextMeasurement.context_tokens + " tokens de entrada en la última llamada medida."
                    + (composer.bridge.compactThresholdTokens > 0
                       ? "\nUmbral de compactación: " + Performance.tokens(composer.bridge.compactThresholdTokens)
                         + " · Compactaciones: " + composer.bridge.chatCompactionCount + "/" + composer.bridge.maxCompactions
                       : "")
                    + "\nVer detalles de rendimiento (configura límites con /limites)."
                onClicked: composer.performanceRequested(composer.contextMeasurement)
                contentItem: Text {
                    readonly property bool nearThreshold: composer.bridge.compactThresholdTokens > 0
                        && composer.contextMeasurement.context_tokens >= composer.bridge.compactThresholdTokens * 0.8
                    text: contextButton.text
                    color: contextButton.hovered || nearThreshold ? "#e6e6e6" : "#999999"
                    font.pixelSize: 11
                }
                background: Rectangle {
                    radius: 6
                    color: contextButton.hovered ? "#12ffffff" : "transparent"
                    border.width: contextButton.visualFocus ? 1 : 0
                    border.color: "#60ffffff"
                }
            }
            Text {
                objectName: "chatCharCounter"
                visible: prompt.text.length > 14000
                text: prompt.text.length + (composer.narrow ? "" : " / 16000")
                color: prompt.text.length > 16000 ? "#ff8a80" : "#aaaaaa"
                font.pixelSize: 10
                Accessible.name: prompt.text.length + " de 16000 caracteres"
            }
            ActionButton {
                id: sendButton
                objectName: "chatSendButton"
                implicitWidth: composer.narrow ? 42 : 108
                implicitHeight: 38
                horizontalPadding: composer.narrow ? 0 : 14
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: 13
                text: composer.bridge.busy ? (composer.narrow ? "◼" : "Detener  ◼") : (composer.narrow ? "↑" : "Enviar  ↑")
                accent: true
                enabled: composer.bridge.busy || (composer.canSubmit
                    && (!!prompt.text.trim() || !!composer.attachedImage) && prompt.text.length <= 16000)
                Accessible.name: composer.bridge.busy ? "Detener ejecución" : "Enviar mensaje"
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: composer.bridge.busy ? "Detener ejecución" : "Enviar (Enter) · Salto de línea: Shift+Enter"
                onClicked: {
                    if (composer.bridge.busy) composer.bridge.cancel();
                    else composer.send();
                }
            }
        }
    }
}
