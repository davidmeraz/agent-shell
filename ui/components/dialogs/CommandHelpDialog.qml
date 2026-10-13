import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../js/ChatCommands.js" as ChatCommands
import "../shared"

GlassDialog {
    objectName: "commandHelp"
    title: "Comandos del chat"
    modal: true
    footer: DialogButtonBox {
        padding: 16
        background: null
        ActionButton { text: "Cerrar"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
    }
    contentItem: ColumnLayout {
        spacing: 12
        Repeater {
            model: ChatCommands.commands
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 3
                Text { text: modelData.label || modelData.name; color: "#ffffff"; font.family: "monospace"; font.pixelSize: 13 }
                Text {
                    Layout.fillWidth: true
                    text: modelData.description
                    color: "#bbbbbb"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: "Escribe / para ver sugerencias dentro del editor. Usa ← y → para elegir, Enter para confirmar, Tab para completar y Esc para ocultarlas. /modelos permite elegir familia, modelo y esfuerzo; por ejemplo /modelos gpt-6."
            color: "#aaaaaa"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
