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
    signal renameRequested(string chatId, string title)
    signal deleteRequested(string chatId, string title)
    padding: 9
    font.pixelSize: 12
    contentItem: RowLayout {
        spacing: 6
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: row.title
                textFormat: Text.PlainText
                maximumLineCount: 1
                elide: Text.ElideRight
                color: row.selected ? "#ffffff" : GemaTheme.textColor
                font.pixelSize: row.font.pixelSize
                font.weight: row.selected ? Font.DemiBold : Font.Medium
                style: Text.Raised
                styleColor: GemaTheme.textShadow
            }
            Text {
                Layout.fillWidth: true
                text: new Date(row.updatedAt).toLocaleDateString()
                maximumLineCount: 1
                elide: Text.ElideRight
                color: GemaTheme.subtleColor
                font.pixelSize: 10
                style: Text.Raised
                styleColor: GemaTheme.textShadow
            }
        }
        ActionButton {
            id: renameButton
            objectName: "chatRenameButton"
            implicitWidth: 26
            implicitHeight: 26
            horizontalPadding: 5
            verticalPadding: 5
            Accessible.name: "Renombrar conversación: " + row.title
            ToolTip.visible: hovered
            ToolTip.delay: 400
            ToolTip.text: "Editar título"
            onClicked: row.renameRequested(row.chatId, row.title)
            contentItem: Item {
                Item {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    rotation: -45
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 2.5
                        width: 7
                        height: 3.5
                        radius: 1
                        color: "transparent"
                        border.width: 1
                        border.color: renameButton.hovered ? "#ffffff" : "#aaaaaa"
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 0
                        width: 2.5
                        height: 2
                        radius: 0.8
                        color: "transparent"
                        border.width: 1
                        border.color: renameButton.hovered ? "#ffffff" : "#aaaaaa"
                    }
                }
            }
        }
        ActionButton {
            id: deleteButton
            implicitWidth: 26
            implicitHeight: 26
            horizontalPadding: 5
            verticalPadding: 5
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
                    width: 9; height: 10; radius: 2
                    color: "transparent"
                    border.width: 1
                    border.color: deleteButton.hovered ? "#ffffff" : "#aaaaaa"
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 4.5
                    width: 12; height: 1
                    color: deleteButton.hovered ? "#ffffff" : "#aaaaaa"
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 7
                    width: 5; height: 2.5; radius: 1
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
        highlighted: row.activeFocus || row.selected
        topColor: row.selected
                  ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2affffff")
                  : (GemaTheme.synced ? GemaTheme.accentAlpha(0.18) : "#20ffffff")
        bottomColor: "#22060a10"
        edgeColor: row.selected
                   ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.68) : "#58ffffff")
                   : "#3cffffff"
    }
}
