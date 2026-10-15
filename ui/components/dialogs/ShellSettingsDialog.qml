import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

GlassDialog {
    id: dialog
    required property AgentBridge bridge
    title: "Terminal"
    modal: true
    onOpened: {
        directory.text = bridge.workspace;
    }
    contentItem: ColumnLayout {
        spacing: 12
        Text {
            Layout.fillWidth: true
            text: "Siempre disponible · ejecución automática"
            color: "#cccccc"
            font.pixelSize: 12
        }
        Text { text: dialog.bridge.activeArea === "work" ? "Carpeta del proyecto" : "Directorio de Chat"; color: "#ffffff"; font.pixelSize: 12 }
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
            text: "La IA usa la terminal cuando la tarea lo requiere. Los comandos se ejecutan sin confirmación "
                  + "con los permisos de tu usuario; su salida acotada se envía a ChatGPT. Máximo "
                  + dialog.bridge.agentShellTimeout + " segundos por comando de IA y "
                  + dialog.bridge.shellTimeout + " segundos con /shell."
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
    onAccepted: bridge.configureShell(directory.text.trim())
}
