import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

GlassDialog {
    id: dialog
    required property AgentBridge bridge
    readonly property var call: bridge.pendingTool.call || ({})
    title: "Ejecutar comando"
    modal: true
    contentItem: ColumnLayout {
        spacing: 12
        Text {
            Layout.fillWidth: true
            text: "ChatGPT propone ejecutar este comando:"
            color: "#bbbbbb"
            font.pixelSize: 13
            wrapMode: Text.Wrap
        }
        GlassPanel {
            Layout.fillWidth: true
            implicitHeight: 130
            ScrollView {
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                TextArea {
                    text: dialog.call.command || ""
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: "#ffffff"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    background: null
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: "Directorio: " + (dialog.call.workdir || "")
            textFormat: Text.PlainText
            color: "#dddddd"
            font.pixelSize: 12
            wrapMode: Text.WrapAnywhere
        }
        Text {
            Layout.fillWidth: true
            text: "Máximo " + dialog.bridge.shellTimeout + " segundos · La salida se compartirá con ChatGPT."
            color: "#aaaaaa"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
    footer: DialogButtonBox {
        padding: 16
        background: null
        ActionButton { text: "Rechazar"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        ActionButton {
            text: "Ejecutar"
            accent: true
            enabled: dialog.bridge.busy && !!dialog.bridge.pendingTool.request_id
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
    onAccepted: bridge.decideTool(true)
    onRejected: bridge.decideTool(false)
}
