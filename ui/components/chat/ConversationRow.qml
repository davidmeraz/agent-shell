import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

ItemDelegate {
    id: row
    required property string chatId
    required property string title
    required property string updatedAt
    property bool selected: false
    signal deleteRequested(string chatId, string title)
    padding: 10
    font.pixelSize: 12
    contentItem: RowLayout {
        spacing: 8
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 5
            Text {
                Layout.fillWidth: true
                text: row.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.selected ? "#ffffff" : "#e8e8e8"
                font.pixelSize: row.font.pixelSize
            }
            Text {
                Layout.fillWidth: true
                text: new Date(row.updatedAt).toLocaleDateString()
                elide: Text.ElideRight
                color: "#aaaaaa"
                font.pixelSize: 10
            }
        }
        ActionButton {
            id: deleteButton
            implicitWidth: 30
            implicitHeight: 30
            horizontalPadding: 7
            verticalPadding: 7
            Accessible.name: "Borrar conversación: " + row.title
            ToolTip.visible: hovered
            ToolTip.delay: 400
            ToolTip.text: "Borrar conversación"
            onClicked: row.deleteRequested(row.chatId, row.title)
            contentItem: Item {
                // Papelera dibujada con formas nativas, sin depender de una fuente de iconos.
                Rectangle {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 2
                    width: 10; height: 11; radius: 2
                    color: "transparent"
                    border.width: 1
                    border.color: deleteButton.hovered ? "#ffffff" : "#aaaaaa"
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 5
                    width: 14; height: 1
                    color: deleteButton.hovered ? "#ffffff" : "#aaaaaa"
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 8
                    width: 6; height: 3; radius: 1
                    color: "transparent"
                    border.width: 1
                    border.color: deleteButton.hovered ? "#ffffff" : "#aaaaaa"
                }
            }
        }
    }
    background: GlassPanel {
        radius: 9
        visible: row.selected || row.hovered || row.activeFocus
        highlighted: row.activeFocus
        topColor: row.selected ? "#30707070" : "#24555555"
        bottomColor: "#182c2c2c"
        edgeColor: row.selected ? "#50ffffff" : "#24ffffff"
    }
}
