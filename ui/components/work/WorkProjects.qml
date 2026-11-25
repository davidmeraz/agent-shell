import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Centro de gestión de aplicaciones Gema UI Kit y proyectos de Work.
GlassPanel {
    id: panel
    required property AgentBridge bridge
    readonly property bool isAppArea: bridge.activeArea === "app"
    property string searchQuery: ""
    property string engineFilter: "all"
    property bool showKitInfo: false
    readonly property ListModel activeModel: isAppArea ? bridge.apps : bridge.projects
    readonly property string runningProjectId: bridge.projectRunActive && bridge.projectRun.project_id
                                               ? String(bridge.projectRun.project_id) : ""

    signal newProjectRequested()
    signal renameProjectRequested(string projectId, string name)
    signal deleteProjectRequested(string projectId, string name, string workdir)

    radius: 16
    topColor: "#00000000"
    bottomColor: "#00000000"
    edgeColor: "#00000000"
    reflective: false

    onIsAppAreaChanged: {
        searchQuery = "";
        engineFilter = "all";
        showKitInfo = false;
    }

    function formatUpdatedDate(isoText) {
        if (!isoText) return "";
        const parsed = new Date(isoText);
        if (isNaN(parsed.getTime())) return "";
        const now = new Date();
        const diffMs = now.getTime() - parsed.getTime();
        const diffMin = Math.floor(diffMs / 60000);
        if (diffMin < 1) return "ahora";
        if (diffMin < 60) return "hace " + diffMin + " min";
        const diffHours = Math.floor(diffMin / 60);
        if (diffHours < 24) return "hace " + diffHours + " h";
        const diffDays = Math.floor(diffHours / 24);
        if (diffDays < 30) return "hace " + diffDays + " d";
        return Qt.formatDate(parsed, "dd/MM/yyyy");
    }

    function matchesRow(name, workdir, engine, desktopInstalled) {
        if (panel.isAppArea) {
            if (panel.engineFilter === "python" && engine !== "python") return false;
            if (panel.engineFilter === "rust" && engine !== "rust") return false;
            if (panel.engineFilter === "desktop" && !desktopInstalled) return false;
        }
        const q = panel.searchQuery.trim().toLowerCase();
        if (!q) return true;
        return (name || "").toLowerCase().indexOf(q) >= 0
            || (workdir || "").toLowerCase().indexOf(q) >= 0
            || (engine || "").toLowerCase().indexOf(q) >= 0;
    }

    function countAppsBy(predicateName) {
        let total = 0;
        const m = panel.activeModel;
        for (let i = 0; i < m.count; ++i) {
            const row = m.get(i);
            if (!row) continue;
            if (predicateName === "rust" && row.engine === "rust") total++;
            else if (predicateName === "python" && row.engine !== "rust") total++;
            else if (predicateName === "desktop" && row.desktopInstalled) total++;
        }
        return total;
    }

    function findProjectName(targetId) {
        if (!targetId) return "";
        const m = panel.activeModel;
        for (let i = 0; i < m.count; ++i) {
            const row = m.get(i);
            if (row && row.projectId === targetId) return row.name;
        }
        return "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

        // Cabecera principal con título, botón de arquitectura Gema UI Kit y creación.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    spacing: 8
                    Text {
                        text: panel.isAppArea ? GemaTheme.gemSymbol : "❖"
                        color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                        font.pixelSize: 20
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    Text {
                        Layout.fillWidth: true
                        text: panel.isAppArea ? "App · Gema UI Kit" : "Work · Proyectos"
                        color: GemaTheme.textColor
                        font.pixelSize: 24
                        font.bold: true
                        font.letterSpacing: -0.3
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                        elide: Text.ElideRight
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: panel.isAppArea
                        ? "Gestiona, inicia e instala tus aplicaciones nativas Matte Transparent Glassmorphism (Quickshell + Python/Rust)."
                        : "Un espacio para construir, explorar y ejecutar tus proyectos con la IA."
                    color: GemaTheme.mutedColor
                    font.pixelSize: 12
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                    wrapMode: Text.Wrap
                }
            }

            ActionButton {
                objectName: "appStackInfoToggle"
                visible: panel.isAppArea
                text: panel.showKitInfo ? "Ocultar Stack" : "◈ Stack UI"
                accent: panel.showKitInfo
                font.pixelSize: 12
                horizontalPadding: 11
                verticalPadding: 8
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: "Ver componentes y arquitectura del stack Gema UI Kit"
                onClicked: panel.showKitInfo = !panel.showKitInfo
            }

            ActionButton {
                objectName: "workNewProject"
                text: panel.isAppArea ? "+  Nueva App" : "+  Nuevo proyecto"
                accent: panel.isAppArea
                enabled: panel.bridge.canSelectArea
                onClicked: panel.newProjectRequested()
            }
        }

        // Tarjeta desplegable de referencia del Stack Gema UI Kit (oculta por defecto para dar protagonismo a las apps).
        GlassPanel {
            Layout.fillWidth: true
            visible: panel.isAppArea && (panel.showKitInfo || panel.bridge.apps.count === 0)
            implicitHeight: kitInfo.implicitHeight + 22
            radius: 12
            topColor: "#1affffff"
            bottomColor: "#0cffffff"
            edgeColor: "#34ffffff"
            ColumnLayout {
                id: kitInfo
                anchors.fill: parent
                anchors.margins: 11
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "Stack Gema UI Kit · Matte Transparent Glassmorphism"
                        color: "#f2f4f8"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Text {
                        text: "Wayland / Hyprland · JSON-Lines v2"
                        color: GemaTheme.synced ? GemaTheme.accent : "#c4dcff"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Cada aplicación incluye ventana translúcida con blur nativo (MattePanel, GlassPanel, WaterReflection, ActionButton, GlassDialog, GlassComboBox), puente IPC stdio en Python o Rust, validación qmllint y lanzador para el menú del sistema."
                    color: "#c4ccd8"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        // Banner en vivo cuando una aplicación o proyecto está en ejecución o acaba de reportar estado.
        GlassPanel {
            id: liveRunBanner
            objectName: "appHubRunBanner"
            Layout.fillWidth: true
            readonly property string runOwnerName: panel.findProjectName(panel.bridge.projectRun.project_id || "")
            visible: (panel.bridge.projectRunActive || panel.bridge.projectRun.phase === "failed" || !!panel.bridge.projectRunNotice)
                     && (!!runOwnerName || !!panel.bridge.projectRunNotice)
            implicitHeight: liveRunLayout.implicitHeight + 20
            radius: 12
            topColor: panel.bridge.projectRun.phase === "failed" || !!panel.bridge.projectRunNotice
                      ? "#24ff7070"
                      : (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#22ffffff")
            bottomColor: "#10080c12"
            edgeColor: panel.bridge.projectRun.phase === "failed" || !!panel.bridge.projectRunNotice
                       ? "#66ff8888"
                       : (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#50ffffff")

            RowLayout {
                id: liveRunLayout
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Rectangle {
                    implicitWidth: 9
                    implicitHeight: 9
                    radius: 4.5
                    color: panel.bridge.projectRun.phase === "failed" || !!panel.bridge.projectRunNotice
                           ? "#ff8888"
                           : (GemaTheme.synced ? GemaTheme.accent : "#78e8a0")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: (liveRunBanner.runOwnerName ? liveRunBanner.runOwnerName + " · " : "")
                              + (panel.bridge.projectRunPending ? "Iniciando…"
                                 : (panel.bridge.projectRunNotice || panel.bridge.projectRun.message || "En ejecución"))
                        color: GemaTheme.textColor
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!(panel.bridge.projectRun.command || panel.bridge.projectRun.output)
                        text: {
                            const out = (panel.bridge.projectRun.output || "").trim();
                            if (out) {
                                const lines = out.split("\n");
                                return lines[lines.length - 1];
                            }
                            return panel.bridge.projectRun.command || "";
                        }
                        color: GemaTheme.subtleColor
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                }

                ActionButton {
                    visible: !!panel.bridge.projectRun.project_id && panel.bridge.canSelectArea
                    text: "Abrir en IA"
                    font.pixelSize: 11
                    horizontalPadding: 10
                    verticalPadding: 6
                    onClicked: panel.bridge.selectArea(panel.isAppArea ? "app" : "work", panel.bridge.projectRun.project_id)
                }

                ActionButton {
                    objectName: "appHubStopButton"
                    visible: panel.bridge.projectRunActive
                    text: "■  Detener"
                    accent: true
                    enabled: panel.bridge.projectRun.phase !== "stopping"
                    font.pixelSize: 11
                    horizontalPadding: 10
                    verticalPadding: 6
                    onClicked: panel.bridge.stopProject()
                }
            }
        }

        // Barra de búsqueda, métricas y filtros por motor/instalación.
        ColumnLayout {
            Layout.fillWidth: true
            visible: panel.activeModel.count > 0
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // Buscador rápido
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 10
                    topColor: searchField.activeFocus ? "#22ffffff" : "#15ffffff"
                    bottomColor: "#0cffffff"
                    edgeColor: searchField.activeFocus
                               ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.70) : "#68ffffff")
                               : "#30ffffff"
                    highlighted: searchField.activeFocus

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: "⌕"
                            color: GemaTheme.subtleColor
                            font.pixelSize: 14
                        }
                        TextInput {
                            id: searchField
                            objectName: "workProjectSearch"
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: GemaTheme.textColor
                            selectionColor: "#ffffff"
                            selectedTextColor: "#000000"
                            font.pixelSize: 12
                            selectByMouse: true
                            clip: true
                            onTextChanged: panel.searchQuery = text

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !searchField.text
                                text: panel.isAppArea
                                      ? "Buscar aplicación por nombre, ruta o motor…"
                                      : "Buscar proyecto por nombre o carpeta…"
                                color: "#8892a0"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        ActionButton {
                            visible: searchField.text.length > 0
                            text: "×"
                            implicitWidth: 22
                            implicitHeight: 22
                            horizontalPadding: 0
                            verticalPadding: 0
                            font.pixelSize: 12
                            onClicked: {
                                searchField.text = "";
                                panel.searchQuery = "";
                            }
                        }
                    }
                }

                // Filtros rápidos en modo App
                RowLayout {
                    visible: panel.isAppArea
                    spacing: 5

                    Repeater {
                        model: [
                            { id: "all", label: "Todas (" + panel.bridge.apps.count + ")" },
                            { id: "python", label: "Python (" + panel.countAppsBy("python") + ")" },
                            { id: "rust", label: "Rust (" + panel.countAppsBy("rust") + ")" },
                            { id: "desktop", label: "En menú (" + panel.countAppsBy("desktop") + ")" }
                        ]
                        delegate: ActionButton {
                            required property var modelData
                            text: modelData.label
                            accent: panel.engineFilter === modelData.id
                            font.pixelSize: 11
                            horizontalPadding: 10
                            verticalPadding: 7
                            onClicked: panel.engineFilter = modelData.id
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }

        Text {
            Layout.fillWidth: true
            visible: !!panel.bridge.areaError
            text: panel.bridge.areaError
            color: "#f0d0d0"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        // Estado vacío cuando aún no hay aplicaciones o proyectos creados.
        GlassPanel {
            Layout.fillWidth: true
            visible: panel.activeModel.count === 0
            implicitHeight: emptyCol.implicitHeight + 36
            radius: 14
            topColor: "#14ffffff"
            bottomColor: "#08ffffff"
            edgeColor: "#28ffffff"

            ColumnLayout {
                id: emptyCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: panel.isAppArea
                        ? "Crea tu primera aplicación Gema UI Kit"
                        : "Vincula tu primer proyecto local"
                    color: GemaTheme.textColor
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: panel.isAppArea
                        ? "Pulsa '+ Nueva App' para generar una aplicación nativa con diseño Matte Transparent Glassmorphism, motor Python o Rust, ejecución con un clic e integración directa en el menú de Hyprland."
                        : "Vincula una carpeta local para crear, modificar y probar proyectos con la IA. Cada proyecto conserva su propio historial y herramientas."
                    color: GemaTheme.mutedColor
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
            }
        }

        // Lista de tarjetas de aplicaciones / proyectos.
        ListView {
            id: projectList
            objectName: "workProjectList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            topMargin: 2
            bottomMargin: 4
            leftMargin: 4
            rightMargin: 4
            spacing: (panel.searchQuery.trim() === "" && panel.engineFilter === "all") ? 10 : 4
            model: panel.activeModel
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: ItemDelegate {
                id: projectRow
                required property string projectId
                required property string name
                required property string workdir
                required property string engine
                property string updatedAt: ""
                property bool folderExists: true
                property bool hasLaunchProfile: false
                property bool hasRunScript: false
                property bool hasCheckScript: false
                property bool hasGit: false
                property int chatCount: 0
                property bool desktopInstalled: false

                readonly property bool matchesFilter: panel.matchesRow(name, workdir, engine, desktopInstalled)
                readonly property bool isRunningThis: panel.bridge.projectRunActive
                                                      && panel.bridge.projectRun.project_id === projectId
                readonly property bool canLaunchThis: folderExists && panel.bridge.canLaunchProjectId(projectId)

                objectName: "workProjectRow"
                width: projectList.width - projectList.leftMargin - projectList.rightMargin
                visible: matchesFilter
                height: matchesFilter ? implicitHeight : 0
                padding: panel.isAppArea ? 15 : 14
                hoverEnabled: true
                enabled: panel.bridge.canSelectArea
                scale: projectRow.down ? 0.992 : (projectRow.hovered ? 1.005 : 1.0)
                Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                onClicked: panel.bridge.selectArea(panel.isAppArea ? "app" : "work", projectId)

                contentItem: ColumnLayout {
                    spacing: panel.isAppArea ? 10 : 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        // Emblema de cristal con punto de estado en vivo
                        GlassPanel {
                            implicitWidth: panel.isAppArea ? 44 : 38
                            implicitHeight: panel.isAppArea ? 44 : 38
                            radius: panel.isAppArea ? 12 : 10
                            topColor: projectRow.isRunningThis
                                      ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.38) : "#36ffffff")
                                      : projectRow.hovered
                                        ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#28ffffff")
                                        : (GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#18ffffff")
                            bottomColor: "#0cffffff"
                            edgeColor: projectRow.isRunningThis
                                       ? (GemaTheme.synced ? GemaTheme.accent : "#90ffffff")
                                       : projectRow.hovered
                                         ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#50ffffff")
                                         : "#28ffffff"

                            Text {
                                anchors.centerIn: parent
                                text: panel.isAppArea ? GemaTheme.gemSymbol : "❖"
                                color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                                font.pixelSize: panel.isAppArea ? 18 : 16
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                            }

                            Rectangle {
                                visible: panel.isAppArea || projectRow.isRunningThis || !projectRow.folderExists
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 3
                                width: 8
                                height: 8
                                radius: 4
                                color: !projectRow.folderExists ? "#ff9070"
                                       : projectRow.isRunningThis ? "#68f098"
                                       : projectRow.hasRunScript || projectRow.hasLaunchProfile
                                         ? (GemaTheme.synced ? GemaTheme.accent : "#a8d4ff")
                                         : "#707884"
                                border.width: 1
                                border.color: "#80000000"
                            }
                        }

                        // Información principal: nombre, insignias, ruta y metadatos
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 7

                                Text {
                                    Layout.fillWidth: true
                                    text: projectRow.name
                                    textFormat: Text.PlainText
                                    color: GemaTheme.textColor
                                    font.pixelSize: 16
                                    font.bold: true
                                    style: Text.Raised
                                    styleColor: GemaTheme.textShadow
                                    elide: Text.ElideRight
                                }

                                // Insignia de ejecución activa
                                GlassPanel {
                                    visible: projectRow.isRunningThis
                                    implicitWidth: runBadgeText.implicitWidth + 14
                                    implicitHeight: 20
                                    radius: 6
                                    topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.32) : "#2c68f098"
                                    bottomColor: "#14ffffff"
                                    edgeColor: GemaTheme.synced ? GemaTheme.accent : "#8068f098"
                                    Text {
                                        id: runBadgeText
                                        anchors.centerIn: parent
                                        text: "● " + (panel.bridge.projectRun.phase === "running" ? "En ejecución" : "Iniciando…")
                                        color: "#ffffff"
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }

                                // Insignia de alerta si la carpeta fue movida o eliminada
                                GlassPanel {
                                    visible: !projectRow.folderExists
                                    implicitWidth: missingBadgeText.implicitWidth + 14
                                    implicitHeight: 20
                                    radius: 6
                                    topColor: "#28ff8060"
                                    bottomColor: "#14000000"
                                    edgeColor: "#70ff9070"
                                    Text {
                                        id: missingBadgeText
                                        anchors.centerIn: parent
                                        text: "Carpeta no encontrada"
                                        color: "#ffd0c0"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // Insignia de acceso directo instalado en el sistema
                                GlassPanel {
                                    visible: panel.isAppArea && projectRow.desktopInstalled
                                    implicitWidth: menuBadgeText.implicitWidth + 14
                                    implicitHeight: 20
                                    radius: 6
                                    topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#22ffffff"
                                    bottomColor: "#10ffffff"
                                    edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#44ffffff"
                                    Text {
                                        id: menuBadgeText
                                        anchors.centerIn: parent
                                        text: "⬡ En menú"
                                        color: GemaTheme.textColor
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // Insignia de motor Gema UI Kit
                                GlassPanel {
                                    visible: panel.isAppArea
                                    implicitWidth: engineTag.implicitWidth + 14
                                    implicitHeight: 20
                                    radius: 6
                                    topColor: "#1cffffff"
                                    bottomColor: "#10ffffff"
                                    Text {
                                        id: engineTag
                                        anchors.centerIn: parent
                                        text: "Gema UI · " + (projectRow.engine === "rust" ? "Rust" : "Python")
                                        color: GemaTheme.mutedColor
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        style: Text.Raised
                                        styleColor: GemaTheme.textShadow
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: projectRow.workdir
                                textFormat: Text.PlainText
                                color: GemaTheme.subtleColor
                                font.pixelSize: 11
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                                elide: Text.ElideMiddle
                            }

                            // Fila de metadatos y estado técnico
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    visible: panel.isAppArea
                                    text: projectRow.hasRunScript ? "✓ Lanzador Quickshell" : "⚠ Sin scripts/run.sh"
                                    color: projectRow.hasRunScript ? GemaTheme.mutedColor : "#e0b090"
                                    font.pixelSize: 10
                                }
                                Text {
                                    visible: panel.isAppArea && projectRow.hasCheckScript
                                    text: "·  ✓ Check IPC/QML"
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    visible: projectRow.hasGit
                                    text: (panel.isAppArea ? "·  " : "") + "⎇ Git"
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: ((panel.isAppArea || projectRow.hasGit) ? "·  " : "")
                                          + (projectRow.chatCount > 0
                                             ? (projectRow.chatCount + (projectRow.chatCount === 1 ? " conversación IA" : " conversaciones IA"))
                                             : "Sin conversaciones aún")
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    readonly property string relDate: panel.formatUpdatedDate(projectRow.updatedAt)
                                    visible: relDate.length > 0
                                    text: "·  " + relDate
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 10
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        // Controles rápidos en la misma fila para proyectos de Work (y edición/borrado en ambos)
                        ActionButton {
                            objectName: "workRowRunButton"
                            visible: !panel.isAppArea && (projectRow.isRunningThis || projectRow.hasLaunchProfile)
                            text: projectRow.isRunningThis ? "■ Detener" : "▶ Ejecutar"
                            accent: projectRow.isRunningThis
                            enabled: projectRow.isRunningThis
                                     ? panel.bridge.projectRun.phase !== "stopping"
                                     : projectRow.canLaunchThis
                            font.pixelSize: 11
                            horizontalPadding: 10
                            verticalPadding: 6
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: projectRow.isRunningThis ? "Detener proyecto en ejecución" : "Ejecutar inicio guardado"
                            onClicked: {
                                if (projectRow.isRunningThis) panel.bridge.stopProject();
                                else panel.bridge.runProjectById(projectRow.projectId);
                            }
                        }

                        ActionButton {
                            id: renameProjectButton
                            objectName: "workRenameProject"
                            enabled: panel.bridge.canSelectArea
                            implicitWidth: 30
                            implicitHeight: 30
                            horizontalPadding: 7
                            verticalPadding: 7
                            Accessible.name: "Editar nombre: " + projectRow.name
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: "Editar nombre"
                            onClicked: panel.renameProjectRequested(projectRow.projectId, projectRow.name)
                            contentItem: Item {
                                Item {
                                    anchors.centerIn: parent
                                    width: 14
                                    height: 14
                                    rotation: -45
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 3
                                        width: 8
                                        height: 4
                                        radius: 1
                                        color: "transparent"
                                        border.width: 1
                                        border.color: renameProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: 0
                                        width: 3
                                        height: 2
                                        radius: 1
                                        color: renameProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                    }
                                }
                            }
                        }

                        ActionButton {
                            id: deleteProjectButton
                            objectName: "workDeleteProject"
                            enabled: !(panel.bridge.projectRunActive && panel.bridge.projectRun.project_id === projectRow.projectId)
                            implicitWidth: 30
                            implicitHeight: 30
                            horizontalPadding: 7
                            verticalPadding: 7
                            Accessible.name: "Eliminar proyecto: " + projectRow.name
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: panel.isAppArea ? "Eliminar aplicación de la lista" : "Eliminar proyecto"
                            onClicked: panel.deleteProjectRequested(projectRow.projectId, projectRow.name, projectRow.workdir)
                            contentItem: Item {
                                Rectangle {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: 2
                                    width: 10; height: 11; radius: 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: deleteProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height / 2 - 5
                                    width: 14; height: 1
                                    color: deleteProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height / 2 - 8
                                    width: 6; height: 3; radius: 1
                                    color: "transparent"
                                    border.width: 1
                                    border.color: deleteProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                }
                            }
                        }
                    }

                    // Barra inferior de acciones rápidas exclusiva para cada tarjeta de App
                    Rectangle {
                        visible: panel.isAppArea
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: "#18ffffff"
                    }

                    RowLayout {
                        visible: panel.isAppArea
                        Layout.fillWidth: true
                        spacing: 8

                        ActionButton {
                            objectName: "appCardRunButton"
                            text: projectRow.isRunningThis ? "■  Detener App" : "▶  Iniciar App"
                            accent: true
                            enabled: projectRow.isRunningThis
                                     ? panel.bridge.projectRun.phase !== "stopping"
                                     : projectRow.canLaunchThis
                            font.pixelSize: 11
                            horizontalPadding: 12
                            verticalPadding: 6
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: projectRow.isRunningThis
                                          ? "Detener la ventana en ejecución de " + projectRow.name
                                          : "Lanzar inmediatamente la ventana de " + projectRow.name + " en Hyprland"
                            onClicked: {
                                if (projectRow.isRunningThis) panel.bridge.stopProject();
                                else panel.bridge.runProjectById(projectRow.projectId);
                            }
                        }

                        ActionButton {
                            objectName: "appCardOpenButton"
                            text: "✦  Editar con IA"
                            enabled: panel.bridge.canSelectArea && projectRow.folderExists
                            font.pixelSize: 11
                            horizontalPadding: 11
                            verticalPadding: 6
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: "Abrir el estudio de IA, explorador de archivos y flujo Git de " + projectRow.name
                            onClicked: panel.bridge.selectArea("app", projectRow.projectId)
                        }

                        ActionButton {
                            objectName: "appCardTestButton"
                            text: "✓  Probar"
                            enabled: panel.bridge.canSelectArea && projectRow.folderExists && !panel.bridge.busy
                            font.pixelSize: 11
                            horizontalPadding: 10
                            verticalPadding: 6
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: "Abrir y validar sintaxis QML (qmllint) + motor IPC de " + projectRow.name
                            onClicked: panel.bridge.testAppById(projectRow.projectId)
                        }

                        Item { Layout.fillWidth: true }

                        ActionButton {
                            objectName: "appCardDesktopButton"
                            text: projectRow.desktopInstalled ? "⬡  En menú ✓" : "⬡  Instalar en menú"
                            accent: projectRow.desktopInstalled
                            enabled: panel.bridge.canSelectArea && projectRow.folderExists
                            font.pixelSize: 11
                            horizontalPadding: 10
                            verticalPadding: 6
                            ToolTip.visible: hovered
                            ToolTip.delay: 400
                            ToolTip.text: projectRow.desktopInstalled
                                          ? "Instalada en el menú de aplicaciones (~/.local/share/applications). Pulsa para quitar el acceso directo."
                                          : "Crear lanzador .desktop para abrir " + projectRow.name + " desde rofi, walker o tu menú de Hyprland."
                            onClicked: panel.bridge.toggleAppDesktop(projectRow.projectId, !projectRow.desktopInstalled)
                        }
                    }
                }

                background: GlassPanel {
                    radius: 13
                    highlighted: projectRow.activeFocus || projectRow.hovered || projectRow.isRunningThis
                    topColor: projectRow.isRunningThis
                              ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2affffff")
                              : projectRow.hovered
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#24ffffff")
                                : "#1affffff"
                    bottomColor: "#22060a10"
                    edgeColor: projectRow.isRunningThis
                               ? (GemaTheme.synced ? GemaTheme.accent : "#80ffffff")
                               : projectRow.hovered
                                 ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#58ffffff")
                                 : "#3cffffff"
                }
                ToolTip.visible: hovered
                ToolTip.delay: 650
                ToolTip.text: workdir
                Accessible.name: name + ", " + workdir
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: panel.isAppArea
                    ? "Inicia tus apps directamente desde cada tarjeta, instálalas en tu menú de escritorio o pulsa en ellas para evolucionarlas con la IA."
                    : "La terminal trabaja en la carpeta del proyecto."
                color: "#888888"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
    }
}
