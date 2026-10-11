import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// El modelo y las acciones de envío pertenecen al mismo espacio de escritura.
GlassPanel {
    id: composer
    required property AgentBridge bridge
    property bool compact: false
    signal submitted(string text)
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
        if (!bridge.canSend || !prompt.text.trim() || prompt.text.length > 16000) return;
        submitted(prompt.text);
        prompt.clear();
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
                placeholderText: composer.bridge.authenticated ? "Escribe un mensaje…" : "Conecta ChatGPT para escribir…"
                placeholderTextColor: "#aaaaaa"
                color: "#f5f5f5"
                font.pixelSize: 14
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                enabled: composer.bridge.canSend
                padding: 4
                background: null
                Keys.onPressed: event => {
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
            Layout.fillWidth: true
            spacing: 8
            GlassComboBox {
                opensAbove: true
                Layout.fillWidth: true
                Layout.maximumWidth: 280
                visible: composer.bridge.availableModels.count > 0
                model: composer.bridge.availableModels
                textRole: "displayName"
                valueRole: "slug"
                enabled: composer.bridge.canSend
                font.pixelSize: 12
                currentIndex: {
                    for (let i = 0; i < composer.bridge.availableModels.count; ++i)
                        if (composer.bridge.availableModels.get(i).slug === composer.bridge.modelName) return i;
                    return -1;
                }
                onActivated: composer.bridge.selectModel(currentValue)
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: "Detener"
                visible: composer.bridge.busy
                onClicked: composer.bridge.cancel()
            }
            ActionButton {
                text: "Enviar  ↑"
                accent: true
                enabled: composer.bridge.canSend && prompt.text.trim().length > 0 && prompt.text.length <= 16000
                onClicked: composer.send()
            }
        }
    }
}
