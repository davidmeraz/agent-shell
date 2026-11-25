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
    property real typingEnergy: 0.0
    readonly property int basePromptHeight: composer.compact || composer.narrow ? 48 : 64
    readonly property int targetPromptHeight: {
        const contentH = Math.ceil(prompt.contentHeight) + 12;
        if (contentH <= basePromptHeight) return basePromptHeight;
        return Math.min(144, contentH);
    }
    signal performanceRequested(var measurement)
    signal imagePreviewRequested(string imageUrl)
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
    readonly property string architectDetail: architect.effort ? " · " + architect.effort : ""
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
    implicitHeight: editorLayout.implicitHeight + 22
    radius: 22
    topColor: prompt.activeFocus
        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.18) : "#22ffffff")
        : (promptHover.hovered ? "#20ffffff" : "#18ffffff")
    bottomColor: "#24060a10"
    edgeColor: prompt.activeFocus
        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.72) : "#76ffffff")
        : (promptHover.hovered ? "#4cffffff" : "#34ffffff")
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
    // Brillo especular superior que reacciona suavemente al foco y a cada pulsación de tecla.
    Rectangle {
        id: typingGlowBar
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * (prompt.activeFocus ? (0.42 + 0.36 * composer.typingEnergy) : 0.22)
        height: 1.5
        radius: 1
        opacity: prompt.activeFocus ? (0.36 + 0.58 * composer.typingEnergy) : (promptHover.hovered ? 0.24 : 0.0)
        Behavior on opacity { NumberAnimation { duration: GemaTheme.animations ? 180 : 0; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: GemaTheme.animations ? 220 : 0; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#00ffffff" }
            GradientStop { position: 0.3; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.75) : "#88ffffff" }
            GradientStop { position: 0.5; color: GemaTheme.synced ? GemaTheme.accent : "#ffffff" }
            GradientStop { position: 0.7; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.75) : "#88ffffff" }
            GradientStop { position: 1.0; color: "#00ffffff" }
        }
    }

    SequentialAnimation {
        id: typingPulseAnim
        NumberAnimation {
            target: composer
            property: "typingEnergy"
            to: 1.0
            duration: GemaTheme.animations ? 90 : 0
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: composer
            property: "typingEnergy"
            to: 0.0
            duration: GemaTheme.animations ? 480 : 0
            easing.type: Easing.OutCubic
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
                id: attachmentThumbBox
                implicitWidth: 48
                implicitHeight: 48
                radius: 8
                highlighted: thumbMouse.containsMouse && !!composer.attachedImage
                scale: thumbMouse.pressed ? 0.95 : (thumbMouse.containsMouse && !!composer.attachedImage ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 120 : 0; easing.type: Easing.OutCubic } }
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
                MouseArea {
                    id: thumbMouse
                    anchors.fill: parent
                    enabled: !!composer.attachedImage && !composer.pendingPasteId
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: composer.imagePreviewRequested(composer.attachedImage)
                }
                ToolTip.visible: thumbMouse.containsMouse && !!composer.attachedImage
                ToolTip.delay: 350
                ToolTip.text: "Ver imagen en grande"
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
            Layout.preferredHeight: composer.targetPromptHeight
            Layout.minimumHeight: 40
            clip: true
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: GemaTheme.animations ? 160 : 0; easing.type: Easing.OutCubic }
            }
            TextArea {
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                id: prompt
                objectName: "chatPrompt"
                placeholderText: ""
                color: "#f5f5f5"
                font.pixelSize: 14
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                onTextChanged: {
                    composer.commandsDismissed = false;
                    completionList.currentIndex = 0;
                    if (GemaTheme.animations && prompt.activeFocus && prompt.text.length > 0)
                        typingPulseAnim.restart();
                }
                padding: 4
                background: null
                // Placeholder animado con desvanecimiento y desplazamiento suave al escribir
                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: prompt.leftPadding + 1
                    anchors.topMargin: prompt.topPadding
                    text: composer.bridge.activeArea === "app"
                        ? "Describe qué quieres añadir a tu aplicación o escribe /comando…"
                        : composer.bridge.activeArea === "work"
                          ? "Describe lo que quieres construir o escribe /comando…"
                          : composer.bridge.engineReady ? "Escribe un mensaje o /comando…" : "Escribe /shell comando o conecta ChatGPT…"
                    color: prompt.activeFocus ? "#9aa6b8" : "#808b9a"
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    opacity: prompt.text.length === 0 ? 1.0 : 0.0
                    transform: Translate {
                        x: prompt.text.length === 0 ? 0 : 8
                        Behavior on x { NumberAnimation { duration: GemaTheme.animations ? 160 : 0; easing.type: Easing.OutCubic } }
                    }
                    Behavior on opacity { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                }
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
        RowLayout {
            objectName: "chatComposerActions"
            Layout.fillWidth: true
            Layout.minimumHeight: 36
            Layout.maximumHeight: 36
            Layout.preferredHeight: 36
            spacing: 8
            Button {
                id: pasteButton
                objectName: "chatPasteImageButton"
                implicitWidth: 34
                implicitHeight: 34
                padding: 0
                hoverEnabled: true
                enabled: composer.bridge.ready && !composer.bridge.busy && !composer.pendingPasteId
                scale: down ? 0.92 : (hovered ? 1.06 : 1.0)
                Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 120 : 0; easing.type: Easing.OutCubic } }
                Accessible.name: "Pegar imagen del portapapeles"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: "Pegar imagen del portapapeles"
                onClicked: composer.pasteImage()
                contentItem: Item {
                    GemaIcon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 16
                        color: !pasteButton.enabled ? "#666666"
                             : pasteButton.hovered ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : GemaTheme.mutedColor
                        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                    }
                }
                background: GlassPanel {
                    radius: 17
                    reflective: pasteButton.hovered
                    highlighted: pasteButton.activeFocus || pasteButton.hovered
                    topColor: pasteButton.hovered
                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#26ffffff")
                        : "#14ffffff"
                    bottomColor: "#0affffff"
                    edgeColor: pasteButton.hovered
                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.60) : "#54ffffff")
                        : "#2cffffff"
                    opacity: pasteButton.enabled ? 1.0 : 0.45
                }
            }
            // Este espacio permanece reservado cuando las sugerencias se ocultan.
            Item {
                objectName: "chatCommandSlot"
                Layout.fillWidth: true
                implicitHeight: 36
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !composer.showCommands
                    spacing: 8
                    Rectangle {
                        objectName: "chatUnifiedArchitect"
                        Layout.preferredWidth: Math.min(architectRow.implicitWidth + 18, parent.width * 0.62)
                        Layout.preferredHeight: 24
                        visible: composer.unified
                        radius: 12
                        color: GemaTheme.synced ? GemaTheme.accentAlpha(0.14) : "#16ffffff"
                        border.width: 1
                        border.color: architectHover.hovered
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.60) : "#50ffffff")
                            : (GemaTheme.synced ? GemaTheme.accentAlpha(0.32) : "#28ffffff")
                        activeFocusOnTab: true
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Arquitecto unificado, solo lectura: " + composer.architectName
                            + composer.architectDetail
                        Accessible.description: "No se puede cambiar el modelo en modo unificado."
                        HoverHandler { id: architectHover }
                        ToolTip.visible: architectHover.hovered
                        ToolTip.delay: 400
                        ToolTip.text: composer.architectName + (composer.architectEngine ? " · " + composer.architectEngine : "")
                            + (composer.architect.effort ? " · " + composer.architect.effort : "")
                            + "\nEl sistema elige automáticamente el mejor modelo con cuota disponible."
                        RowLayout {
                            id: architectRow
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 10
                            spacing: 6
                            GemaIcon {
                                name: "brand"
                                size: 12
                                color: GemaTheme.synced ? GemaTheme.accent : "#e6e6e6"
                            }
                            Text {
                                objectName: "chatUnifiedArchitectName"
                                Layout.fillWidth: true
                                text: composer.architectName + composer.architectDetail
                                textFormat: Text.PlainText
                                color: GemaTheme.textColor
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                    }
                    Text {
                        objectName: "chatActiveModel"
                        Layout.preferredWidth: Math.min(implicitWidth, parent.width * 0.45)
                        visible: composer.activeModelLabel !== "" && !composer.narrow
                        text: composer.activeModelLabel
                        textFormat: Text.PlainText
                        color: GemaTheme.mutedColor
                        font.pixelSize: 11
                        font.weight: Font.Medium
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
                        objectName: "chatComposerStatus"
                        Layout.fillWidth: true
                        text: composer.statusText
                        textFormat: Text.PlainText
                        color: composer.bridge.busy || composer.bridge.loginBusy ? GemaTheme.textColor : GemaTheme.subtleColor
                        opacity: composer.bridge.busy || composer.bridge.loginBusy ? 0.92 : 0.48
                        font.pixelSize: 10
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
                    spacing: 6
                    property real slideOffset: 0
                    transform: Translate { y: inlineSuggestions.slideOffset }
                    onVisibleChanged: {
                        if (visible && GemaTheme.animations) {
                            inlineSuggestions.opacity = 0;
                            inlineSuggestions.slideOffset = 2;
                            commandPaletteEnter.restart();
                        } else {
                            inlineSuggestions.opacity = 1;
                            inlineSuggestions.slideOffset = 0;
                        }
                    }
                    ParallelAnimation {
                        id: commandPaletteEnter
                        NumberAnimation {
                            target: inlineSuggestions
                            property: "opacity"
                            from: 0; to: 1
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: inlineSuggestions
                            property: "slideOffset"
                            from: 2; to: 0
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
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
                            readonly property bool activeChoice: completionList.currentIndex === optionButton.index
                            width: Math.min(210, labelRow.implicitWidth + 20)
                            height: 26
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            padding: 0
                            enabled: !blocked
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            scale: down ? 0.94 : (hovered ? 1.03 : 1.0)
                            Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 120 : 0; easing.type: Easing.OutCubic } }
                            onClicked: { completionList.currentIndex = index; composer.executeSelected(); }
                            contentItem: RowLayout {
                                id: labelRow
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle {
                                    visible: optionButton.activeChoice || (composer.modelMode && !!optionButton.modelData.selected)
                                    implicitWidth: 5
                                    implicitHeight: 5
                                    radius: 2.5
                                    color: optionButton.enabled
                                        ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                                        : "#666666"
                                }
                                Text {
                                    id: label
                                    text: optionButton.modelData.label
                                    font.pixelSize: 11
                                    font.weight: optionButton.activeChoice ? Font.DemiBold : Font.Medium
                                    color: !optionButton.enabled ? "#6e7784"
                                         : optionButton.activeChoice ? "#ffffff"
                                         : (optionButton.hovered ? "#eef2f8" : GemaTheme.mutedColor)
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                                }
                            }
                            background: GlassPanel {
                                radius: 14
                                reflective: optionButton.activeChoice
                                highlighted: optionButton.activeChoice || optionButton.hovered
                                topColor: optionButton.activeChoice
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.30) : "#2effffff")
                                    : (optionButton.hovered ? "#1effffff" : "#10ffffff")
                                bottomColor: optionButton.activeChoice
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.12) : "#14ffffff")
                                    : "#08ffffff"
                                edgeColor: optionButton.activeChoice
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.75) : "#6cffffff")
                                    : (optionButton.hovered ? "#42ffffff" : "#22ffffff")
                            }
                            ToolTip.visible: hovered
                            ToolTip.delay: 260
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
                        color: GemaTheme.subtleColor
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Row {
                        visible: composer.completions.length > 0 && inlineSuggestions.width >= 350
                        spacing: 4
                        Repeater {
                            model: ["Tab", "↵"]
                            delegate: Rectangle {
                                required property string modelData
                                implicitWidth: keyText.implicitWidth + 10
                                implicitHeight: 20
                                radius: 6
                                color: "#12ffffff"
                                border.width: 1
                                border.color: "#26ffffff"
                                Text {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
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
            Button {
                id: sendButton
                objectName: "chatSendButton"
                implicitWidth: 34
                implicitHeight: 34
                padding: 0
                hoverEnabled: true
                Layout.alignment: Qt.AlignVCenter
                readonly property bool readyToSend: composer.bridge.busy || (composer.canSubmit
                    && (!!prompt.text.trim() || !!composer.attachedImage) && prompt.text.length <= 16000)
                property real readyPopScale: 1.0
                onReadyToSendChanged: {
                    if (readyToSend && GemaTheme.animations)
                        sendReadyPop.restart();
                }
                SequentialAnimation {
                    id: sendReadyPop
                    NumberAnimation { target: sendButton; property: "readyPopScale"; to: 1.12; duration: 110; easing.type: Easing.OutCubic }
                    NumberAnimation { target: sendButton; property: "readyPopScale"; to: 1.0; duration: 150; easing.type: Easing.OutBack }
                }
                enabled: readyToSend
                scale: (down ? 0.92 : (hovered && enabled ? 1.07 : 1.0)) * readyPopScale
                Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 120 : 0; easing.type: Easing.OutCubic } }
                Accessible.name: composer.bridge.busy ? "Detener ejecución" : "Enviar mensaje"
                ToolTip.visible: hovered
                ToolTip.delay: 420
                ToolTip.text: composer.bridge.busy ? "Detener ejecución" : "Enviar (Enter) · Salto de línea: Shift+Enter"
                onClicked: {
                    if (composer.bridge.busy) composer.bridge.cancel();
                    else composer.send();
                }
                contentItem: Item {
                    GemaIcon {
                        anchors.centerIn: parent
                        name: composer.bridge.busy ? "stop" : "send"
                        size: composer.bridge.busy ? 15 : 16
                        color: !sendButton.enabled ? "#68707c"
                             : "#ffffff"
                    }
                }
                background: GlassPanel {
                    radius: 17
                    reflective: sendButton.enabled
                    highlighted: sendButton.activeFocus || (sendButton.hovered && sendButton.enabled)
                    topColor: sendButton.enabled
                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(sendButton.hovered ? 0.56 : 0.42) : (sendButton.hovered ? "#44ffffff" : "#34ffffff"))
                        : "#12ffffff"
                    bottomColor: sendButton.enabled
                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#1cffffff")
                        : "#08ffffff"
                    edgeColor: sendButton.enabled
                        ? (GemaTheme.synced ? GemaTheme.accent : "#88ffffff")
                        : "#24ffffff"
                    opacity: sendButton.enabled ? 1.0 : 0.55
                }
            }
        }
    }
}
