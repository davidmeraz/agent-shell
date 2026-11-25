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
        spacing: 16

        // Cabecera centrada y refinada
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                GlassPanel {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: 10
                    topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#22ffffff"
                    bottomColor: "#0cffffff"
                    edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#44ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: panel.isAppArea ? GemaTheme.gemSymbol : "❖"
                        color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                        font.pixelSize: 15
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                }

                Text {
                    text: panel.isAppArea ? "Aplicaciones" : "Proyectos"
                    color: GemaTheme.textColor
                    font.pixelSize: 26
                    font.bold: true
                    font.letterSpacing: -0.4
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }

                GlassPanel {
                    visible: panel.isAppArea
                    implicitWidth: kitBadge.implicitWidth + 14
                    implicitHeight: 22
                    radius: 7
                    topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.18) : "#1cffffff"
                    bottomColor: "#0affffff"
                    edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.45) : "#34ffffff"
                    Text {
                        id: kitBadge
                        anchors.centerIn: parent
                        text: "Gema UI Kit"
                        color: GemaTheme.synced ? GemaTheme.accent : GemaTheme.mutedColor
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.3
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 160
                implicitHeight: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.5; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#48ffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
        }

        // Banner en vivo cuando una aplicación o proyecto está en ejecución o reportó error
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

        Text {
            Layout.fillWidth: true
            visible: !!panel.bridge.areaError
            text: panel.bridge.areaError
            color: "#f0d0d0"
            font.pixelSize: 12
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        // Lista de tarjetas de aplicaciones / proyectos con tarjeta minimalista "+" al final
        ListView {
            id: projectList
            objectName: "workProjectList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            topMargin: 2
            bottomMargin: 8
            leftMargin: 4
            rightMargin: 4
            spacing: 10
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

                readonly property bool isRunningThis: panel.bridge.projectRunActive
                                                      && panel.bridge.projectRun.project_id === projectId
                readonly property bool canLaunchThis: folderExists && panel.bridge.canLaunchProjectId(projectId)

                objectName: "workProjectRow"
                width: projectList.width - projectList.leftMargin - projectList.rightMargin
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

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    visible: panel.isAppArea && projectRow.hasRunScript
                                    text: "✓ Lanzador Quickshell"
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    visible: panel.isAppArea && projectRow.hasCheckScript
                                    text: (projectRow.hasRunScript ? "·  " : "") + "✓ Check IPC/QML"
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    visible: projectRow.hasGit
                                    text: ((panel.isAppArea && (projectRow.hasRunScript || projectRow.hasCheckScript)) ? "·  " : "") + "⎇ Git"
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    readonly property bool hasPrev: projectRow.hasGit
                                                                    || (panel.isAppArea && (projectRow.hasRunScript || projectRow.hasCheckScript))
                                    text: (hasPrev ? "·  " : "")
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

            // Tarjeta minimalista "+" al final de la lista para crear una nueva app o proyecto
            footer: Item {
                width: projectList.width - projectList.leftMargin - projectList.rightMargin
                height: createCard.implicitHeight + (projectList.count > 0 ? 10 : 0)

                ItemDelegate {
                    id: createCard
                    objectName: "workNewProject"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    implicitHeight: 54
                    hoverEnabled: true
                    enabled: panel.bridge.canSelectArea
                    scale: createCard.down ? 0.99 : (createCard.hovered ? 1.006 : 1.0)
                    Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                    Accessible.name: panel.isAppArea ? "Nueva aplicación" : "Nuevo proyecto"
                    ToolTip.visible: hovered
                    ToolTip.delay: 350
                    ToolTip.text: panel.isAppArea ? "Crear nueva aplicación Gema UI Kit" : "Vincular nuevo proyecto"
                    onClicked: panel.newProjectRequested()

                    contentItem: Item {
                        // Ícono minimalista "+" centrado
                        Item {
                            anchors.centerIn: parent
                            width: 18
                            height: 18

                            Rectangle {
                                anchors.centerIn: parent
                                width: 16
                                height: 1.6
                                radius: 0.8
                                color: createCard.hovered
                                       ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                                       : GemaTheme.mutedColor
                                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 1.6
                                height: 16
                                radius: 0.8
                                color: createCard.hovered
                                       ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                                       : GemaTheme.mutedColor
                                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                            }
                        }
                    }

                    background: GlassPanel {
                        radius: 13
                        reflective: createCard.hovered
                        highlighted: createCard.activeFocus || createCard.hovered
                        topColor: createCard.hovered
                                  ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.20) : "#20ffffff")
                                  : "#0cffffff"
                        bottomColor: "#0a060a10"
                        edgeColor: createCard.hovered
                                   ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.62) : "#50ffffff")
                                   : "#24ffffff"
                    }
                }
            }
        }
    }
}
