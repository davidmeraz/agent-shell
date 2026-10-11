import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../ChatCommands.js" as ChatCommands

// Editor con sugerencias de comandos y acciones de envío.
GlassPanel {
    id: composer
    objectName: "chatComposer"
    required property AgentBridge bridge
    property bool compact: false
    property bool commandsDismissed: false
    readonly property var commandMatches: ChatCommands.suggestions(prompt.text)
    readonly property var modelQuery: ChatCommands.modelQuery(prompt.text)
    readonly property bool modelMode: modelQuery !== null
    readonly property var completions: {
        if (!modelMode) return commandMatches.map(command => ({
            label: command.label || command.name, value: command.name, description: command.description
        }));
        const rows = [];
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            if (!modelQuery || (model.slug + " " + model.displayName).toLowerCase().includes(modelQuery))
                rows.push({ label: model.displayName, value: model.slug, description: model.slug });
        }
        return rows;
    }
    readonly property bool showCommands: prompt.activeFocus && !commandsDismissed && (completions.length > 0 || modelMode)
    readonly property bool canSubmit: prompt.text.trim().startsWith("/") || bridge.canSend
    readonly property string activeModelLabel: {
        if (!bridge.authenticated || !bridge.modelName) return "";
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            if (model.slug === bridge.modelName) return model.displayName || model.slug;
        }
        return "";
    }
    implicitHeight: editorLayout.implicitHeight + 24
    radius: 16
    topColor: "#28393939"
    bottomColor: "#201c1c1c"
    highlighted: prompt.activeFocus

    function prepare(text) {
        prompt.text = text;
        prompt.forceActiveFocus();
        prompt.cursorPosition = prompt.length;
    }
    function send() {
        if (!prompt.text.trim()) return;
        if (showCommands && completions.length) { executeSelected(); return; }
        if (bridge.submit(prompt.text)) prompt.clear();
    }
    function executeSelected() {
        const option = completions[completionList.currentIndex];
        if (!option) return;
        if (!modelMode && option.value === "/modelos") {
            if (ChatCommands.blockedReason("/modelos", bridge)) bridge.submit("/modelos");
            else openModels();
            return;
        }
        if (bridge.submit(modelMode ? "/modelos " + option.value : option.value)) prompt.clear();
    }
    function openModels() {
        prepare("/modelos ");
    }

    ColumnLayout {
        id: editorLayout
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: composer.compact ? 64 : 88
            clip: true
            TextArea {
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                id: prompt
                objectName: "chatPrompt"
                placeholderText: composer.bridge.authenticated ? "Escribe un mensaje o /comando…" : "Escribe /ayuda o conecta ChatGPT…"
                placeholderTextColor: "#aaaaaa"
                color: "#f5f5f5"
                font.pixelSize: 14
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                onTextChanged: { composer.commandsDismissed = false; completionList.currentIndex = 0; }
                padding: 4
                background: null
                Keys.onPressed: event => {
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
                            prompt.text = composer.modelMode ? "/modelos " + option.value : option.value;
                            prompt.cursorPosition = prompt.length;
                            composer.commandsDismissed = true;
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
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        RowLayout {
            objectName: "chatComposerActions"
            Layout.fillWidth: true
            Layout.minimumHeight: 40
            Layout.maximumHeight: 40
            Layout.preferredHeight: 40
            spacing: 8
            // Este espacio permanece reservado cuando las sugerencias se ocultan.
            Item {
                objectName: "chatCommandSlot"
                Layout.fillWidth: true
                implicitHeight: 40
                Text {
                    objectName: "chatActiveModel"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !composer.showCommands && composer.activeModelLabel !== ""
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
                    ToolTip.text: composer.bridge.modelName + " · Cambia con /modelos"
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
                        ScrollIndicator.horizontal: ScrollIndicator {}
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
                                text: (composer.modelMode && modelData.value === composer.bridge.modelName ? "• " : "") + modelData.label
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
                        text: composer.bridge.availableModels.count ? "Sin coincidencias" : "Conecta ChatGPT para ver tus modelos"
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
            ActionButton {
                text: "Detener"
                visible: composer.bridge.busy
                onClicked: composer.bridge.cancel()
            }
            ActionButton {
                text: "Enviar  ↑"
                accent: true
                enabled: composer.canSubmit && prompt.text.trim().length > 0 && prompt.text.length <= 16000
                onClicked: composer.send()
            }
        }
    }
}
