import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Explorador nativo Gema Glassmorphism para elegir o crear carpetas de proyectos y aplicaciones.
GlassDialog {
    id: picker
    objectName: "glassFolderDialog"
    required property AgentBridge bridge
    property string initialPath: ""
    property string currentPath: ""
    property string parentPath: ""
    property string selectedPath: ""
    property bool showHidden: false
    property bool creatingFolder: false
    property string filterText: ""
    property string errorMessage: ""
    property string pendingRequestId: ""
    property var shortcuts: []
    property var rawEntries: []

    readonly property var visibleEntries: {
        const q = filterText.trim().toLowerCase();
        if (!q) return rawEntries;
        return rawEntries.filter(item => (item.name || "").toLowerCase().indexOf(q) >= 0);
    }

    readonly property var breadcrumbs: {
        if (!currentPath) return [];
        const parts = currentPath.split("/").filter(p => p.length > 0);
        const result = [{ label: "/", path: "/" }];
        let acc = "";
        for (let i = 0; i < parts.length; ++i) {
            acc += "/" + parts[i];
            result.push({ label: parts[i], path: acc });
        }
        return result.slice(-4);
    }

    signal folderSelected(string path)

    title: "Seleccionar carpeta"
    modal: true
    padding: 16

    function openAt(startPath) {
        initialPath = startPath || bridge.workspace || "";
        selectedPath = "";
        filterText = "";
        creatingFolder = false;
        errorMessage = "";
        open();
        browse(initialPath);
    }

    function browse(path) {
        errorMessage = "";
        filterText = "";
        selectedPath = "";
        pendingRequestId = bridge.listFolders(path, showHidden);
    }

    function submitNewFolder() {
        const cleaned = newFolderInput.text.trim();
        if (!cleaned || !currentPath) return;
        errorMessage = "";
        pendingRequestId = bridge.createFolder(currentPath, cleaned, showHidden);
    }

    Connections {
        target: picker.bridge
        function onFsListed(data) {
            if (!picker.visible || (picker.pendingRequestId && data.request_id && data.request_id !== picker.pendingRequestId))
                return;
            picker.pendingRequestId = "";
            picker.currentPath = data.path || "";
            picker.parentPath = data.parent || "";
            picker.shortcuts = data.shortcuts || [];
            picker.rawEntries = data.entries || [];
            picker.selectedPath = "";
            picker.creatingFolder = false;
            newFolderInput.text = "";
            picker.errorMessage = data.error || "";
        }
        function onFsError(data) {
            if (!picker.visible || (picker.pendingRequestId && data.request_id && data.request_id !== picker.pendingRequestId))
                return;
            picker.pendingRequestId = "";
            picker.errorMessage = data.message || "No se pudo completar la operación.";
        }
    }

    contentItem: ColumnLayout {
        spacing: 10

        // Accesos rápidos (Inicio, Dev, Quickshell, Actual…)
        Flickable {
            Layout.fillWidth: true
            implicitHeight: 28
            contentWidth: shortcutsRow.implicitWidth
            contentHeight: height
            clip: true
            visible: picker.shortcuts.length > 0

            Row {
                id: shortcutsRow
                spacing: 6
                Repeater {
                    model: picker.shortcuts
                    delegate: ActionButton {
                        required property var modelData
                        text: modelData.label
                        accent: picker.currentPath === modelData.path
                        font.pixelSize: 11
                        implicitHeight: 26
                        horizontalPadding: 10
                        verticalPadding: 0
                        onClicked: picker.browse(modelData.path)
                    }
                }
            }
        }

        // Barra de navegación: subir nivel + migas de pan + ocultos + nueva carpeta
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ActionButton {
                implicitWidth: 30
                implicitHeight: 30
                horizontalPadding: 0
                verticalPadding: 0
                text: "↑"
                font.pixelSize: 13
                enabled: !!picker.parentPath
                ToolTip.visible: hovered
                ToolTip.delay: 350
                ToolTip.text: "Subir a la carpeta padre"
                onClicked: picker.browse(picker.parentPath)
            }

            GlassPanel {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 9
                reflective: false
                topColor: "#14ffffff"
                bottomColor: "#08ffffff"
                edgeColor: "#28ffffff"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 2

                    Repeater {
                        model: picker.breadcrumbs
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            spacing: 2
                            Text {
                                visible: index > 0
                                text: "›"
                                color: "#788494"
                                font.pixelSize: 11
                            }
                            Button {
                                id: crumbBtn
                                padding: 3
                                hoverEnabled: true
                                onClicked: picker.browse(modelData.path)
                                contentItem: Text {
                                    text: modelData.label
                                    textFormat: Text.PlainText
                                    color: index === picker.breadcrumbs.length - 1
                                           ? GemaTheme.textColor
                                           : (crumbBtn.hovered ? "#ffffff" : GemaTheme.subtleColor)
                                    font.pixelSize: 11
                                    font.weight: index === picker.breadcrumbs.length - 1 ? Font.DemiBold : Font.Normal
                                }
                                background: Rectangle {
                                    radius: 5
                                    color: crumbBtn.hovered ? "#1effffff" : "transparent"
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            ActionButton {
                implicitWidth: 30
                implicitHeight: 30
                horizontalPadding: 0
                verticalPadding: 0
                text: ".*"
                font.pixelSize: 10
                accent: picker.showHidden
                ToolTip.visible: hovered
                ToolTip.delay: 350
                ToolTip.text: picker.showHidden ? "Ocultar carpetas ocultas" : "Mostrar carpetas ocultas"
                onClicked: {
                    picker.showHidden = !picker.showHidden;
                    picker.browse(picker.currentPath);
                }
            }

            ActionButton {
                objectName: "folderPickerNewFolderBtn"
                implicitWidth: 30
                implicitHeight: 30
                horizontalPadding: 0
                verticalPadding: 0
                accent: picker.creatingFolder
                ToolTip.visible: hovered
                ToolTip.delay: 350
                ToolTip.text: "Crear nueva carpeta aquí"
                onClicked: {
                    picker.creatingFolder = !picker.creatingFolder;
                    if (picker.creatingFolder) Qt.callLater(() => newFolderInput.forceActiveFocus());
                }
                contentItem: Item {
                    GemaIcon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 14
                        color: picker.creatingFolder ? "#ffffff" : GemaTheme.textColor
                    }
                }
            }
        }

        // Creación rápida de carpeta en línea
        RowLayout {
            Layout.fillWidth: true
            visible: picker.creatingFolder
            spacing: 6

            GlassPanel {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: 9
                reflective: false
                highlighted: newFolderInput.activeFocus
                TextInput {
                    id: newFolderInput
                    objectName: "folderPickerNewFolderInput"
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 80
                    color: "#ffffff"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    font.pixelSize: 12
                    selectByMouse: true
                    onAccepted: picker.submitNewFolder()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !newFolderInput.text
                        text: "Nombre de la nueva carpeta…"
                        color: "#80ffffff"
                        font.pixelSize: 12
                    }
                }
            }
            ActionButton {
                text: "Crear"
                accent: true
                implicitHeight: 32
                verticalPadding: 0
                font.pixelSize: 11
                enabled: newFolderInput.text.trim().length > 0
                onClicked: picker.submitNewFolder()
            }
        }

        // Filtro instantáneo de subcarpetas
        GlassPanel {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 9
            reflective: false
            topColor: filterInput.activeFocus ? "#1effffff" : "#10ffffff"
            bottomColor: "#06ffffff"
            edgeColor: filterInput.activeFocus
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.60) : "#58ffffff")
                : "#22ffffff"

            TextInput {
                id: filterInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: GemaTheme.textColor
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                font.pixelSize: 12
                selectByMouse: true
                text: picker.filterText
                onTextEdited: picker.filterText = text
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !filterInput.text
                    text: "Filtrar carpetas…"
                    color: "#768292"
                    font.pixelSize: 12
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !!picker.errorMessage
            text: picker.errorMessage
            textFormat: Text.PlainText
            color: "#ff9b9b"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }

        // Lista de carpetas estilo Gema
        GlassPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: 240
            radius: 12
            reflective: false
            topColor: "#0effffff"
            bottomColor: "#08060a10"
            edgeColor: "#24ffffff"

            ListView {
                id: folderList
                objectName: "folderPickerList"
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 4
                model: picker.visibleEntries
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: ItemDelegate {
                    id: folderRow
                    required property var modelData
                    readonly property bool isSelected: picker.selectedPath === modelData.path
                    width: folderList.width
                    implicitHeight: 36
                    padding: 8
                    hoverEnabled: true
                    onClicked: picker.selectedPath = modelData.path
                    onDoubleClicked: picker.browse(modelData.path)

                    contentItem: RowLayout {
                        spacing: 9
                        GemaIcon {
                            name: folderRow.modelData.is_gema_app ? "app" : "work"
                            size: 16
                            color: folderRow.isSelected || folderRow.hovered
                                   ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                                   : GemaTheme.mutedColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: folderRow.modelData.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: folderRow.isSelected ? "#ffffff" : GemaTheme.textColor
                            font.pixelSize: 12
                            font.weight: folderRow.isSelected ? Font.DemiBold : Font.Normal
                        }
                        Text {
                            visible: !!folderRow.modelData.is_gema_app
                            text: "Gema App"
                            color: GemaTheme.synced ? GemaTheme.accent : "#a8d4ff"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Text {
                            visible: !!folderRow.modelData.has_git && !folderRow.modelData.is_gema_app
                            text: "Git"
                            color: GemaTheme.subtleColor
                            font.pixelSize: 10
                        }
                        Button {
                            implicitWidth: 24
                            implicitHeight: 24
                            padding: 0
                            hoverEnabled: true
                            ToolTip.visible: hovered
                            ToolTip.delay: 350
                            ToolTip.text: "Abrir carpeta"
                            onClicked: picker.browse(folderRow.modelData.path)
                            contentItem: Text {
                                text: "›"
                                color: parent.hovered ? "#ffffff" : GemaTheme.subtleColor
                                font.pixelSize: 16
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? "#22ffffff" : "transparent"
                            }
                        }
                    }

                    background: GlassPanel {
                        radius: 9
                        reflective: false
                        visible: folderRow.isSelected || folderRow.hovered
                        topColor: folderRow.isSelected
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2affffff")
                            : "#18ffffff"
                        bottomColor: "#0a060a10"
                        edgeColor: folderRow.isSelected
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.68) : "#58ffffff")
                            : "#28ffffff"
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: picker.visibleEntries.length === 0 && !picker.pendingRequestId
                text: picker.filterText.trim() ? "Sin carpetas que coincidan" : "Sin subcarpetas aquí"
                color: GemaTheme.subtleColor
                font.pixelSize: 12
            }
        }
    }

    footer: Pane {
        padding: 14
        background: null
        contentItem: RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: picker.selectedPath || picker.currentPath
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: GemaTheme.subtleColor
                font.pixelSize: 11
            }
            ActionButton {
                text: "Cancelar"
                onClicked: picker.close()
            }
            ActionButton {
                objectName: "folderPickerSelectBtn"
                text: "Seleccionar"
                accent: true
                enabled: !!(picker.selectedPath || picker.currentPath)
                onClicked: {
                    const chosen = picker.selectedPath || picker.currentPath;
                    picker.close();
                    picker.folderSelected(chosen);
                }
            }
        }
    }
}
