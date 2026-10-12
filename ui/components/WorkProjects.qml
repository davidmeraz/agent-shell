import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

// Inicio de Work: proyectos locales; cada carpeta conserva conversaciones propias.
GlassPanel {
    id: panel
    required property AgentBridge bridge
    signal newProjectRequested()
    radius: 16
    topColor: "#14292929"
    bottomColor: "#24171717"
    edgeColor: "#20ffffff"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Text { Layout.fillWidth: true; text: "Work"; color: "#f5f5f5"; font.pixelSize: 26; font.bold: true }
                Text { Layout.fillWidth: true; text: "Un espacio para construir."; color: "#aaaaaa"; font.pixelSize: 13; wrapMode: Text.Wrap }
            }
            ActionButton {
                objectName: "workNewProject"
                text: "+  Nuevo proyecto"
                enabled: panel.bridge.canSelectArea
                onClicked: panel.newProjectRequested()
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        Text {
            Layout.fillWidth: true
            visible: !!panel.bridge.areaError
            text: panel.bridge.areaError
            color: "#dddddd"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: !panel.bridge.projects.count
            text: "Vincula una carpeta local para crear, modificar y probar proyectos con la IA. Cada proyecto tiene su propio historial."
            color: "#bbbbbb"
            font.pixelSize: 14
            wrapMode: Text.Wrap
        }
        ListView {
            id: projectList
            objectName: "workProjectList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10
            model: panel.bridge.projects
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
            delegate: ItemDelegate {
                id: projectRow
                required property string projectId
                required property string name
                required property string workdir
                objectName: "workProjectRow"
                width: projectList.width
                padding: 16
                enabled: panel.bridge.canSelectArea
                onClicked: panel.bridge.selectArea("work", projectId)
                contentItem: Column {
                    spacing: 6
                    Text { width: parent.width; text: projectRow.name; textFormat: Text.PlainText; color: "#f5f5f5"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                    Text { width: parent.width; text: projectRow.workdir; textFormat: Text.PlainText; color: "#aaaaaa"; font.pixelSize: 11; elide: Text.ElideMiddle }
                }
                background: GlassPanel {
                    radius: 12
                    highlighted: projectRow.activeFocus
                    topColor: projectRow.hovered ? "#30555555" : "#183b3b3b"
                    edgeColor: "#24ffffff"
                }
                ToolTip.visible: hovered
                ToolTip.delay: 650
                ToolTip.text: workdir
                Accessible.name: name + ", " + workdir
            }
        }
        Text {
            Layout.fillWidth: true
            text: "La terminal trabaja en la carpeta del proyecto."
            color: "#888888"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
