import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../.."
import "../shared"

GlassDialog {
    id: dialog
    objectName: "workProjectDialog"
    required property AgentBridge bridge
    title: "Nuevo proyecto"
    modal: true
    closePolicy: bridge.areaBusy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: {
        projectName.text = "";
        directory.text = bridge.workspace;
        bridge.areaError = "";
        projectName.forceActiveFocus();
    }
    Connections {
        target: dialog.bridge
        function onAreaChanged(previousKey, currentKey) {
            if (dialog.visible && currentKey.startsWith("work:") && dialog.bridge.projectId) dialog.close();
        }
    }
    FolderDialog {
        id: folderPicker
        title: "Carpeta del proyecto"
        onAccepted: directory.text = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""))
    }
    contentItem: ColumnLayout {
        spacing: 12
        Text { text: "Nombre"; color: "#dddddd"; font.pixelSize: 12 }
        TextField {
            id: projectName
            objectName: "workProjectName"
            Layout.fillWidth: true
            placeholderText: "Mi proyecto"
            maximumLength: 80
            enabled: !dialog.bridge.areaBusy
            color: "#ffffff"
            placeholderTextColor: "#888888"
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            padding: 12
            background: GlassPanel { radius: 10; highlighted: projectName.activeFocus }
        }
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Carpeta local"; color: "#dddddd"; font.pixelSize: 12 }
            ActionButton {
                text: "Elegir carpeta"
                enabled: !dialog.bridge.areaBusy
                font.pixelSize: 11
                verticalPadding: 6
                onClicked: folderPicker.open()
            }
        }
        TextField {
            id: directory
            objectName: "workProjectDirectory"
            Layout.fillWidth: true
            placeholderText: "/home/usuario/proyectos/mi-proyecto"
            enabled: !dialog.bridge.areaBusy
            color: "#ffffff"
            placeholderTextColor: "#888888"
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            padding: 12
            background: GlassPanel { radius: 10; highlighted: directory.activeFocus }
        }
        Text {
            Layout.fillWidth: true
            text: "Elige una carpeta existente, vacía o con un proyecto. Work conservará sus conversaciones por separado."
            color: "#aaaaaa"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "workProjectError"
            Layout.fillWidth: true
            visible: !!dialog.bridge.areaError
            text: dialog.bridge.areaError
            color: "#eeeeee"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
    footer: Pane {
        padding: 16
        background: null
        contentItem: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancelar"; enabled: !dialog.bridge.areaBusy; onClicked: dialog.close() }
            ActionButton {
                objectName: "workCreateProject"
                text: dialog.bridge.areaBusy ? "Abriendo…" : "Crear proyecto"
                accent: true
                enabled: dialog.bridge.canSelectArea && !!projectName.text.trim() && !!directory.text.trim()
                onClicked: dialog.bridge.createProject(projectName.text.trim(), directory.text.trim())
            }
        }
    }
}
