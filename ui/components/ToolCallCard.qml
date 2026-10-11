import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GlassPanel {
    id: card
    required property var call
    implicitHeight: content.implicitHeight + 24
    topColor: "#50343434"
    bottomColor: "#40181818"
    edgeColor: "#38ffffff"
    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8
        Text {
            Layout.fillWidth: true
            text: "TERMINAL · " + ({ pending: "Esperando confirmación", running: "Ejecutando…", completed: "Completado",
                error: "Error", timeout: "Tiempo agotado", denied: "Rechazado", interrupted: "Interrumpido" })[card.call.status]
            color: "#ffffff"
            font.pixelSize: 11
            font.bold: true
            wrapMode: Text.Wrap
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(command.implicitHeight, 90)
            clip: true
            TextArea {
                id: command
                text: card.call.command || "Comando no ejecutado"
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                font.family: "monospace"
                font.pixelSize: 12
                color: "#f5f5f5"
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                padding: 0
                background: null
            }
        }
        Text {
            Layout.fillWidth: true
            text: card.call.workdir || ""
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: "#aaaaaa"
            font.pixelSize: 10
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(output.implicitHeight, 180)
            visible: !!card.call.output
            clip: true
            TextArea {
                id: output
                text: card.call.output || ""
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                font.family: "monospace"
                font.pixelSize: 12
                color: "#dddddd"
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                padding: 0
                background: null
            }
        }
        Text {
            Layout.fillWidth: true
            visible: card.call.exit_code !== null && card.call.exit_code !== undefined || !!card.call.truncated
            text: (card.call.exit_code !== null && card.call.exit_code !== undefined ? "Salida: " + card.call.exit_code : "")
                  + (card.call.truncated ? " · Salida recortada" : "")
            color: "#aaaaaa"
            font.pixelSize: 10
        }
    }
}
