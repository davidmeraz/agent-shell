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
    readonly property bool isAppMode: bridge.activeArea === "app"
    property string selectedEngine: "python"
    property bool customDirectoryEdited: false
    title: isAppMode ? "Nueva aplicación · Gema UI Kit" : "Nuevo proyecto"
    modal: true
    closePolicy: bridge.areaBusy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function parentWorkspaceDir(rawPath) {
        const cleaned = (rawPath || "").replace(/\/+$/, "");
        if (!cleaned) return "";
        const slash = cleaned.lastIndexOf("/");
        return slash > 0 ? cleaned.slice(0, slash) : cleaned;
    }

    function slugifyAppName(rawName) {
        return (rawName || "")
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9áéíóúñü_-]+/g, "-")
            .replace(/^-+|-+$/g, "");
    }

    onOpened: {
        projectName.text = "";
        customDirectoryEdited = false;
        directory.text = bridge.workspace;
        selectedEngine = "python";
        bridge.areaError = "";
        projectName.forceActiveFocus();
    }
    Connections {
        target: dialog.bridge
        function onAreaChanged(previousKey, currentKey) {
            if (dialog.visible && (currentKey.startsWith("work:") || currentKey.startsWith("app:")) && dialog.bridge.projectId) dialog.close();
        }
    }
    FolderDialog {
        id: folderPicker
        title: dialog.isAppMode ? "Carpeta de la aplicación" : "Carpeta del proyecto"
        onAccepted: {
            dialog.customDirectoryEdited = true;
            directory.text = decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, ""));
        }
    }
    contentItem: ColumnLayout {
        spacing: 12
        Text { text: "Nombre"; color: "#dddddd"; font.pixelSize: 12 }
        TextField {
            id: projectName
            objectName: "workProjectName"
            Layout.fillWidth: true
            placeholderText: dialog.isAppMode ? "Mis Notas Gema" : "Mi proyecto"
            maximumLength: 80
            enabled: !dialog.bridge.areaBusy
            color: "#ffffff"
            placeholderTextColor: "#888888"
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            padding: 12
            background: GlassPanel { radius: 10; highlighted: projectName.activeFocus }
            onTextEdited: {
                if (!dialog.isAppMode || dialog.customDirectoryEdited) return;
                const base = dialog.parentWorkspaceDir(dialog.bridge.workspace);
                const slug = dialog.slugifyAppName(projectName.text);
                if (base && slug) directory.text = base + "/" + slug;
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: dialog.isAppMode
            spacing: 6
            Text { text: "Stack y motor de Gema UI Kit"; color: "#dddddd"; font.pixelSize: 12 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ActionButton {
                    objectName: "appEnginePython"
                    Layout.fillWidth: true
                    text: "Quickshell + Python"
                    accent: dialog.selectedEngine === "python"
                    enabled: !dialog.bridge.areaBusy
                    onClicked: dialog.selectedEngine = "python"
                }
                ActionButton {
                    objectName: "appEngineRust"
                    Layout.fillWidth: true
                    text: "Quickshell + Rust"
                    accent: dialog.selectedEngine === "rust"
                    enabled: !dialog.bridge.areaBusy
                    onClicked: dialog.selectedEngine = "rust"
                }
            }
            Text {
                Layout.fillWidth: true
                text: dialog.selectedEngine === "rust"
                    ? "Motor Rust compilado sin dependencias externas + interfaz QML Glassmorphism conectada por stdio JSON-Lines v2."
                    : "Motor Python ágil con librería estándar + interfaz QML Glassmorphism conectada por stdio JSON-Lines v2."
                color: GemaTheme.subtleColor
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
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
            placeholderText: dialog.isAppMode ? "/home/usuario/apps/mi-app-gema" : "/home/usuario/proyectos/mi-proyecto"
            enabled: !dialog.bridge.areaBusy
            color: "#ffffff"
            placeholderTextColor: "#888888"
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            padding: 12
            background: GlassPanel { radius: 10; highlighted: directory.activeFocus }
            onTextEdited: dialog.customDirectoryEdited = true
        }
        Text {
            Layout.fillWidth: true
            text: dialog.isAppMode
                ? "Si la carpeta no existe se creará automáticamente con toda la estructura Gema UI Kit (shell.qml, ui/components/*, backend y scripts). Si ya contiene una app Gema, se vinculará sin sobrescribir tus archivos."
                : "Elige una carpeta existente, vacía o con un proyecto. Work conservará sus conversaciones por separado."
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
                text: dialog.bridge.areaBusy ? "Creando…" : (dialog.isAppMode ? "Crear aplicación" : "Crear proyecto")
                accent: true
                enabled: dialog.bridge.canSelectArea && !!projectName.text.trim() && !!directory.text.trim()
                onClicked: {
                    if (dialog.isAppMode) dialog.bridge.createApp(projectName.text.trim(), directory.text.trim(), dialog.selectedEngine);
                    else dialog.bridge.createProject(projectName.text.trim(), directory.text.trim());
                }
            }
        }
    }
}
