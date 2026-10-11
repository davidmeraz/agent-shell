import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

GlassDialog {
    id: dialog
    required property AgentBridge bridge
    property bool enabledDraft: false
    title: "Terminal"
    modal: true
    onOpened: {
        enabledDraft = bridge.shellEnabled;
        directory.text = bridge.workspace;
    }
    contentItem: ColumnLayout {
        spacing: 12
        ActionButton {
            Layout.fillWidth: true
            text: dialog.enabledDraft ? "Terminal activada" : "Activar terminal"
            accent: dialog.enabledDraft
            enabled: dialog.bridge.ready && !dialog.bridge.busy && !dialog.bridge.loginBusy
            onClicked: dialog.enabledDraft = !dialog.enabledDraft
        }
        Text { text: "Directorio de trabajo"; color: "#ffffff"; font.pixelSize: 12 }
        GlassPanel {
            Layout.fillWidth: true
            implicitHeight: 76
            highlighted: directory.activeFocus
            TextArea {
                id: directory
                anchors.fill: parent
                anchors.margins: 8
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                selectByMouse: true
                color: "#f5f5f5"
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                font.pixelSize: 13
                background: null
            }
        }
        Text {
            Layout.fillWidth: true
            text: "Cada comando te pedirá confirmación y tendrá un máximo de " + dialog.bridge.shellTimeout
                  + " segundos. Los comandos corren con los permisos de tu usuario; su salida se envía a ChatGPT."
            color: "#bbbbbb"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
    footer: DialogButtonBox {
        padding: 16
        background: null
        ActionButton { text: "Cancelar"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        ActionButton {
            text: "Aplicar"
            enabled: dialog.bridge.ready && !dialog.bridge.busy && !dialog.bridge.loginBusy && !!directory.text.trim()
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
    onAccepted: bridge.configureShell(directory.text.trim(), enabledDraft)
}
