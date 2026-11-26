import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AgentShell.Native
import "../.."
import "../shared"

// Visor lateral derecho del flujo de commits Git para Work y App (Matte Glassmorphism).
NativeWindow {
    id: gitWin
    objectName: "gitFlowWindow"
    required property AgentBridge bridge
    property string mainWindowTitle: ""
    property var project: ({})
    readonly property string projectId: project.project_id || ""
    readonly property string projectName: project.name || ""
    readonly property string projectWorkdir: project.workdir || ""
    signal fileRequested(string path)

    title: "Git · " + (projectName || "Flujo de commits")
    implicitWidth: 680
    implicitHeight: 1000
    minimumSize: Qt.size(420, 400)
    color: "transparent"
    visible: false
    onClosed: gitWin.visible = false

    property bool loading: false
    property bool isRepo: true
    property string errorMessage: ""
    property string branchName: ""
    property string upstreamName: ""
    property int aheadCount: 0
    property int behindCount: 0
    property string headHash: ""
    property bool workingClean: true
    property int stagedCount: 0
    property int modifiedCount: 0
    property int untrackedCount: 0
    property var stagedFiles: []
    property var modifiedFiles: []
    property var untrackedFiles: []
    property var branches: []
    property var commits: []
    property int graphLanes: 1
    property bool showPendingFiles: false
    property string selectedHash: ""
    property var commitDetail: ({})
    property bool detailLoading: false
    property string pendingFlowId: ""
    property string pendingDetailId: ""
    property int serial: 0
    property bool hashCopied: false

    readonly property color pendingAccent: "#7dd3fc"

    readonly property var laneColors: [
        GemaTheme.synced ? GemaTheme.accent : "#8be9fd",
        GemaTheme.codePalette.type || "#c8b6ff",
        GemaTheme.codePalette.func || "#86e8c8",
        "#7dd3fc",
        GemaTheme.codePalette.decorator || "#f29cb8",
        GemaTheme.codePalette.string || "#a6e3a1"
    ]

    function laneColor(index) {
        return laneColors[Math.abs(index) % laneColors.length];
    }

    function kindColor(kind) {
        switch (kind) {
        case "feat": return GemaTheme.synced ? GemaTheme.accent : "#8be9fd";
        case "fix": return "#ff9b9b";
        case "refactor": return GemaTheme.codePalette.type || "#c8b6ff";
        case "docs": return GemaTheme.codePalette.func || "#86e8c8";
        case "test": return "#7dd3fc";
        case "perf": return GemaTheme.codePalette.decorator || "#f29cb8";
        default: return GemaTheme.subtleColor;
        }
    }

    function splitPath(fullPath) {
        const p = (fullPath || "").trim();
        const idx = p.lastIndexOf("/");
        if (idx < 0) return { name: p, dir: "" };
        return { name: p.slice(idx + 1), dir: p.slice(0, idx) };
    }

    function parseConventional(rawSubject) {
        const text = (rawSubject || "").trim();
        const match = /^([a-z]+)(?:\(([^)]+)\))?!?:\s*(.+)$/i.exec(text);
        if (!match) return { scope: "", title: text || "(sin mensaje)" };
        const title = match[3].trim();
        return {
            scope: (match[2] || "").trim(),
            title: title ? title.charAt(0).toUpperCase() + title.slice(1) : text
        };
    }

    function setProject(next) {
        const nextObj = next || ({});
        const changed = projectId !== (nextObj.project_id || "") || projectWorkdir !== (nextObj.workdir || "");
        project = nextObj;
        if (!projectId) {
            visible = false;
            clearData();
            return;
        }
        if (changed) {
            clearData();
            if (visible) refresh();
        } else if (visible) {
            refresh();
        }
    }

    function clearData() {
        loading = false;
        errorMessage = "";
        isRepo = true;
        branchName = "";
        upstreamName = "";
        aheadCount = 0;
        behindCount = 0;
        headHash = "";
        workingClean = true;
        stagedCount = 0;
        modifiedCount = 0;
        untrackedCount = 0;
        stagedFiles = [];
        modifiedFiles = [];
        untrackedFiles = [];
        branches = [];
        commits = [];
        graphLanes = 1;
        selectedHash = "";
        commitDetail = ({});
        detailLoading = false;
        pendingFlowId = "";
        pendingDetailId = "";
        showPendingFiles = false;
    }

    function openForProject(projectInfo) {
        if (projectInfo && projectInfo.project_id)
            setProject(projectInfo);
        if (!projectId) return;
        const wasVisible = visible;
        visible = true;
        refresh();
        if (!wasVisible) schedulePlacement();
    }

    function toggleForProject(projectInfo) {
        if (visible && projectInfo && projectInfo.project_id === projectId) {
            visible = false;
            return;
        }
        openForProject(projectInfo);
    }

    function schedulePlacement() {
        if (visible && NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE") && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen") {
            placementDelay.restart();
        }
    }

    function refresh() {
        if (!visible || !bridge.ready || !projectId) return;
        loading = true;
        errorMessage = "";
        pendingFlowId = "git-flow-" + (++serial);
        bridge.sendCommand({
            type: "git.flow",
            project_id: projectId,
            request_id: pendingFlowId,
            max_commits: 80
        });
    }

    function selectCommit(commitHash) {
        if (!commitHash || !bridge.ready || !projectId) return;
        if (selectedHash === commitHash && commitDetail.hash === commitHash) {
            selectedHash = "";
            commitDetail = ({});
            detailLoading = false;
            return;
        }
        selectedHash = commitHash;
        commitDetail = ({});
        detailLoading = true;
        pendingDetailId = "git-detail-" + (++serial);
        bridge.sendCommand({
            type: "git.commit",
            project_id: projectId,
            request_id: pendingDetailId,
            hash: commitHash
        });
    }

    onVisibleChanged: {
        if (!visible) {
            pendingFlowId = "";
            pendingDetailId = "";
            placementDelay.stop();
            placement.running = false;
        }
    }

    Timer {
        id: placementDelay
        interval: 60
        repeat: false
        onTriggered: {
            if (!gitWin.visible || !gitWin.projectId) return;
            placement.running = false;
            placement.command = [
                NativeApp.pythonExecutable,
                NativeApp.placementScript,
                String(NativeApp.processId),
                gitWin.title,
                "1",
                gitWin.mainWindowTitle
            ];
            placement.running = true;
        }
    }

    Timer {
        id: autoRefreshTimer
        interval: 8000
        repeat: true
        running: gitWin.visible && gitWin.bridge.ready && !!gitWin.projectId
        onTriggered: {
            if (!gitWin.loading) gitWin.refresh();
        }
    }

    Timer {
        id: hashCopiedTimer
        interval: 1400
        repeat: false
        onTriggered: gitWin.hashCopied = false
    }

    NativeProcess {
        id: placement
        errorOutput: LineParser { onRead: data => console.warn("Posición del visor Git: " + data) }
    }

    Connections {
        target: gitWin.bridge
        function onReadyChanged() {
            if (!gitWin.bridge.ready) gitWin.setProject({});
        }
        function onEventReceived(event) {
            const data = event.data;
            if (event.type === "area.state" && (data.area === "work" || data.area === "app")) {
                gitWin.setProject(data.project || {});
                return;
            }
            if (event.type === "project.deleted" && data.project_id === gitWin.projectId) {
                gitWin.setProject({});
                return;
            }
            if (gitWin.visible && (event.type === "chat.finished" || event.type === "shell.finished"
                || (event.type === "work.activity" && data.status !== "running" && data.project_id === gitWin.projectId))) {
                gitWin.refresh();
                return;
            }
            if (!event.type.startsWith("git.") || data.project_id !== gitWin.projectId) return;
            if (event.type === "git.flow.state" && data.request_id === gitWin.pendingFlowId) {
                gitWin.pendingFlowId = "";
                gitWin.loading = false;
                gitWin.errorMessage = "";
                gitWin.isRepo = !!data.is_repo;
                gitWin.branchName = data.branch || "";
                gitWin.upstreamName = data.upstream || "";
                gitWin.aheadCount = data.ahead || 0;
                gitWin.behindCount = data.behind || 0;
                gitWin.headHash = data.head_hash || "";
                gitWin.workingClean = !!data.clean;
                gitWin.stagedCount = data.staged_count || 0;
                gitWin.modifiedCount = data.modified_count || 0;
                gitWin.untrackedCount = data.untracked_count || 0;
                gitWin.stagedFiles = data.staged || [];
                gitWin.modifiedFiles = data.modified || [];
                gitWin.untrackedFiles = data.untracked || [];
                gitWin.branches = data.branches || [];
                gitWin.commits = data.commits || [];
                gitWin.graphLanes = data.graph_lanes || 1;
                if (gitWin.workingClean) gitWin.showPendingFiles = false;
                if (gitWin.selectedHash && !gitWin.commits.some(c => c.hash === gitWin.selectedHash)) {
                    gitWin.selectedHash = "";
                    gitWin.commitDetail = ({});
                }
            } else if (event.type === "git.commit.detail" && data.request_id === gitWin.pendingDetailId) {
                gitWin.pendingDetailId = "";
                gitWin.detailLoading = false;
                gitWin.commitDetail = data;
            } else if (event.type === "git.flow.error") {
                if (data.request_id === gitWin.pendingFlowId) {
                    gitWin.pendingFlowId = "";
                    gitWin.loading = false;
                    gitWin.errorMessage = data.message || "No se pudo consultar Git.";
                } else if (data.request_id === gitWin.pendingDetailId) {
                    gitWin.pendingDetailId = "";
                    gitWin.detailLoading = false;
                }
            }
        }
    }

    ViewerMotion {
        anchors.fill: parent
        shown: gitWin.visible

        MattePanel {
            id: matteSurface
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#54141c26"
            bottomColor: "#680c121a"
            edgeColor: "#4cffffff"
        }

        Item {
            anchors.fill: parent
            focus: true

            GlassToolTipTheme {}

            Shortcut {
                sequence: "Esc"
                context: Qt.WindowShortcut
                enabled: gitWin.visible
                onActivated: {
                    if (gitWin.selectedHash) {
                        gitWin.selectedHash = "";
                        gitWin.commitDetail = ({});
                    } else {
                        gitWin.visible = false;
                    }
                }
            }
            Shortcut {
                sequence: "F5"
                context: Qt.WindowShortcut
                enabled: gitWin.visible
                onActivated: gitWin.refresh()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Cabecera arrastrable con rama activa, estado del árbol y acciones.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: headerCol.implicitHeight
                    DragHandler {
                        target: null
                        acceptedButtons: Qt.LeftButton
                        onActiveChanged: { if (active) gitWin.startSystemMove(); }
                    }

                    ColumnLayout {
                        id: headerCol
                        anchors.fill: parent
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            GlassPanel {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: 10
                                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.26) : "#26c4dcff"
                                bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#10c4dcff"
                                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.56) : "#4ec4dcff"
                                Text {
                                    anchors.centerIn: parent
                                    text: "⎇"
                                    color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: "Flujo Git · " + (gitWin.projectName || "Proyecto")
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: GemaTheme.textColor
                                    font.pixelSize: 14
                                    font.bold: true
                                    style: Text.Raised
                                    styleColor: GemaTheme.textShadow
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: gitWin.isRepo
                                        ? (gitWin.commits.length + " commits" + (gitWin.branches.length > 1 ? " · " + gitWin.branches.length + " ramas" : "") + (gitWin.headHash ? " · HEAD " + gitWin.headHash : ""))
                                        : "Sin repositorio Git inicializado"
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 10
                                }
                            }

                            ActionButton {
                                objectName: "gitFlowRefreshButton"
                                implicitWidth: 30
                                implicitHeight: 30
                                horizontalPadding: 0
                                verticalPadding: 0
                                text: gitWin.loading ? "…" : "↻"
                                font.pixelSize: 13
                                enabled: !gitWin.loading && !!gitWin.projectId
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                ToolTip.text: "Actualizar historial Git (F5)"
                                onClicked: gitWin.refresh()
                            }

                            ActionButton {
                                objectName: "gitFlowCloseButton"
                                implicitWidth: 30
                                implicitHeight: 30
                                horizontalPadding: 0
                                verticalPadding: 0
                                text: "×"
                                font.pixelSize: 15
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                ToolTip.text: "Cerrar visor Git (Esc)"
                                onClicked: gitWin.visible = false
                            }
                        }

                        // Fila de estado minimalista: rama actual a la izquierda y estado de cambios a la derecha.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: gitWin.isRepo
                            spacing: 8

                            GlassPanel {
                                visible: !!gitWin.branchName
                                implicitWidth: branchRow.implicitWidth + 18
                                implicitHeight: 30
                                radius: 9
                                reflective: false
                                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.20) : "#20c4dcff"
                                bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.08) : "#0cc4dcff"
                                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.48) : "#40c4dcff"
                                RowLayout {
                                    id: branchRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        text: gitWin.branchName
                                        textFormat: Text.PlainText
                                        color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        visible: gitWin.aheadCount > 0 || gitWin.behindCount > 0
                                        text: (gitWin.aheadCount > 0 ? "↑" + gitWin.aheadCount : "")
                                              + (gitWin.aheadCount > 0 && gitWin.behindCount > 0 ? " " : "")
                                              + (gitWin.behindCount > 0 ? "↓" + gitWin.behindCount : "")
                                        textFormat: Text.PlainText
                                        color: GemaTheme.mutedColor
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Button {
                                id: statusPill
                                readonly property int totalChanges: gitWin.stagedCount + gitWin.modifiedCount + gitWin.untrackedCount
                                implicitWidth: statusPillText.implicitWidth + 22
                                implicitHeight: 30
                                padding: 0
                                hoverEnabled: !gitWin.workingClean
                                enabled: !gitWin.workingClean
                                onClicked: gitWin.showPendingFiles = !gitWin.showPendingFiles
                                contentItem: Text {
                                    id: statusPillText
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: gitWin.workingClean
                                        ? "✓ Árbol limpio"
                                        : ("● " + statusPill.totalChanges
                                           + (statusPill.totalChanges === 1 ? " cambio " : " cambios ")
                                           + (gitWin.showPendingFiles ? "▴" : "▾"))
                                    textFormat: Text.PlainText
                                    color: gitWin.workingClean ? "#86e8c8" : gitWin.pendingAccent
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                background: GlassPanel {
                                    radius: 9
                                    reflective: false
                                    topColor: gitWin.workingClean
                                        ? "#1686e8c8"
                                        : (gitWin.showPendingFiles || statusPill.hovered
                                            ? Qt.alpha(gitWin.pendingAccent, 0.22)
                                            : Qt.alpha(gitWin.pendingAccent, 0.13))
                                    bottomColor: "#08000000"
                                    edgeColor: gitWin.workingClean
                                        ? "#3c86e8c8"
                                        : Qt.alpha(gitWin.pendingAccent, gitWin.showPendingFiles ? 0.62 : 0.44)
                                }
                            }
                        }
                    }
                }

                // Panel desplegable animado de cambios locales pendientes antes del siguiente commit.
                GlassPanel {
                    id: pendingPanel
                    Layout.fillWidth: true
                    readonly property bool expanded: gitWin.isRepo && !gitWin.workingClean && gitWin.showPendingFiles
                    readonly property int targetHeight: expanded ? Math.min(220, Math.max(66, pendingColumn.implicitHeight + 24)) : 0
                    Layout.preferredHeight: targetHeight
                    visible: Layout.preferredHeight > 1 || expanded
                    opacity: expanded ? 1.0 : 0.0
                    clip: true
                    radius: 13
                    reflective: false
                    topColor: Qt.alpha(gitWin.pendingAccent, 0.12)
                    bottomColor: "#14080e18"
                    edgeColor: Qt.alpha(gitWin.pendingAccent, 0.36)

                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: GemaTheme.animations ? 220 : 0; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: GemaTheme.animations ? 160 : 0; easing.type: Easing.OutCubic }
                    }

                    ScrollView {
                        id: pendingScroll
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            id: pendingColumn
                            width: pendingScroll.availableWidth
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    implicitWidth: 6
                                    implicitHeight: 6
                                    radius: 3
                                    color: gitWin.pendingAccent
                                }

                                Text {
                                    text: "Cambios locales"
                                    color: "#f2f7ff"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    visible: gitWin.stagedCount > 0
                                    implicitWidth: stagedBadgeText.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: 6
                                    color: "#1a86e8c8"
                                    border.width: 1
                                    border.color: "#4486e8c8"
                                    Text {
                                        id: stagedBadgeText
                                        anchors.centerIn: parent
                                        text: gitWin.stagedCount + " en stage"
                                        color: "#86e8c8"
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    visible: gitWin.modifiedCount > 0
                                    implicitWidth: modBadgeText.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: 6
                                    color: Qt.alpha(gitWin.pendingAccent, 0.16)
                                    border.width: 1
                                    border.color: Qt.alpha(gitWin.pendingAccent, 0.44)
                                    Text {
                                        id: modBadgeText
                                        anchors.centerIn: parent
                                        text: gitWin.modifiedCount + (gitWin.modifiedCount === 1 ? " modificado" : " modificados")
                                        color: gitWin.pendingAccent
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Rectangle {
                                    visible: gitWin.untrackedCount > 0
                                    implicitWidth: untrackBadgeText.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: 6
                                    color: "#16ffffff"
                                    border.width: 1
                                    border.color: "#32ffffff"
                                    Text {
                                        id: untrackBadgeText
                                        anchors.centerIn: parent
                                        text: gitWin.untrackedCount + (gitWin.untrackedCount === 1 ? " nuevo" : " nuevos")
                                        color: GemaTheme.mutedColor
                                        font.pixelSize: 9
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: "#18ffffff"
                            }

                            Repeater {
                                model: gitWin.stagedFiles.map(f => ({
                                            code: f.status || "A",
                                            label: "stage",
                                            color: "#86e8c8",
                                            path: f.path
                                        }))
                                    .concat(gitWin.modifiedFiles.map(f => ({
                                            code: f.status || "M",
                                            label: f.status === "D" ? "eliminado" : "modificado",
                                            color: f.status === "D" ? "#ff9b9b" : gitWin.pendingAccent,
                                            path: f.path
                                        })))
                                    .concat(gitWin.untrackedFiles.map(f => ({
                                            code: "?",
                                            label: "nuevo",
                                            color: "#a7b4c8",
                                            path: f.path
                                        })))
                                delegate: Rectangle {
                                    id: pendingRow
                                    required property var modelData
                                    readonly property var parts: gitWin.splitPath(modelData.path)
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    radius: 7
                                    color: pendingRowMouse.containsMouse ? "#16ffffff" : "#08ffffff"
                                    border.width: 1
                                    border.color: pendingRowMouse.containsMouse ? Qt.alpha(modelData.color, 0.35) : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 7
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Rectangle {
                                            implicitWidth: 20
                                            implicitHeight: 18
                                            radius: 5
                                            color: Qt.alpha(pendingRow.modelData.color, 0.16)
                                            border.width: 1
                                            border.color: Qt.alpha(pendingRow.modelData.color, 0.42)
                                            Text {
                                                anchors.centerIn: parent
                                                text: pendingRow.modelData.code
                                                color: pendingRow.modelData.color
                                                font.family: "monospace"
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }

                                        Text {
                                            text: pendingRow.parts.name
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            color: "#f4f8ff"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            visible: !!pendingRow.parts.dir
                                            text: pendingRow.parts.dir
                                            textFormat: Text.PlainText
                                            elide: Text.ElideMiddle
                                            color: GemaTheme.subtleColor
                                            font.family: "monospace"
                                            font.pixelSize: 10
                                        }

                                        Item {
                                            visible: !pendingRow.parts.dir
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: pendingRow.modelData.label
                                            textFormat: Text.PlainText
                                            color: Qt.alpha(pendingRow.modelData.color, 0.85)
                                            font.pixelSize: 9
                                            font.weight: Font.Medium
                                        }
                                    }

                                    MouseArea {
                                        id: pendingRowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: gitWin.fileRequested(pendingRow.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#1cffffff" }

                // Mensaje de error o estado sin repositorio Git.
                GlassPanel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !!gitWin.errorMessage || !gitWin.isRepo || (!gitWin.loading && gitWin.commits.length === 0)
                    radius: 14
                    reflective: false
                    topColor: "#10ffffff"
                    bottomColor: "#06ffffff"
                    edgeColor: "#24ffffff"

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 40, 360)
                        spacing: 10
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "⎇"
                            color: GemaTheme.synced ? GemaTheme.accent : "#c4dcff"
                            font.pixelSize: 30
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: gitWin.errorMessage ? "Error al consultar Git"
                                  : !gitWin.isRepo ? "Sin repositorio Git"
                                  : "Todavía no hay commits"
                            color: GemaTheme.textColor
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: gitWin.errorMessage || (!gitWin.isRepo
                                ? "Esta carpeta de proyecto todavía no está inicializada con Git. Puedes iniciar un repositorio con git init."
                                : "Haz tu primer commit para visualizar el flujo de ramas y cambios aquí.")
                            color: GemaTheme.subtleColor
                            font.pixelSize: 12
                        }
                    }
                }

                // Lista interactiva del grafo de commits.
                ListView {
                    id: commitList
                    objectName: "gitFlowCommitList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: gitWin.isRepo && !gitWin.errorMessage && gitWin.commits.length > 0
                    clip: true
                    spacing: 0
                    model: gitWin.commits
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                    delegate: Item {
                        id: commitRow
                        required property var modelData
                        required property int index
                        readonly property bool selected: modelData.hash === gitWin.selectedHash
                        readonly property int laneSpacing: 16
                        readonly property int graphPad: 14
                        readonly property int graphWidth: Math.max(36, Math.min(132, gitWin.graphLanes * laneSpacing + graphPad))
                        readonly property var parsed: gitWin.parseConventional(modelData.subject)
                        width: commitList.width
                        height: 54

                        GlassPanel {
                            anchors.fill: parent
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 11
                            reflective: false
                            visible: commitRow.selected || rowMouse.containsMouse
                            topColor: commitRow.selected
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#24c4dcff")
                                : "#12ffffff"
                            bottomColor: commitRow.selected
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.08) : "#0cc4dcff")
                                : "#06ffffff"
                            edgeColor: commitRow.selected
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#4ec4dcff")
                                : "#22ffffff"
                        }

                        // Carriles y curvas vectoriales del flujo de commits.
                        Canvas {
                            id: graphCanvas
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: commitRow.graphWidth
                            antialiasing: true
                            readonly property var rowData: commitRow.modelData
                            readonly property var paletteRef: gitWin.laneColors
                            onRowDataChanged: requestPaint()
                            onPaletteRefChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const d = rowData;
                                if (!d) return;
                                const cy = height * 0.5;
                                const xOf = col => commitRow.graphPad + col * commitRow.laneSpacing;
                                const nodeX = xOf(d.lane || 0);
                                ctx.lineWidth = 2;
                                ctx.lineCap = "round";

                                // Carriles continuos que atraviesan esta fila sin detenerse.
                                for (const col of (d.pass_lanes || [])) {
                                    const px = xOf(col);
                                    ctx.strokeStyle = gitWin.laneColor(col);
                                    ctx.globalAlpha = 0.65;
                                    ctx.beginPath();
                                    ctx.moveTo(px, 0);
                                    ctx.lineTo(px, height);
                                    ctx.stroke();
                                }

                                // Aristas entrantes desde commits superiores hacia este nodo.
                                for (const edge of (d.in_edges || [])) {
                                    const fx = xOf(edge.from);
                                    const tx = xOf(edge.to);
                                    ctx.strokeStyle = gitWin.laneColor(edge.from);
                                    ctx.globalAlpha = 0.85;
                                    ctx.beginPath();
                                    ctx.moveTo(fx, 0);
                                    if (fx === tx) {
                                        ctx.lineTo(tx, cy);
                                    } else {
                                        ctx.bezierCurveTo(fx, cy * 0.65, tx, cy * 0.35, tx, cy);
                                    }
                                    ctx.stroke();
                                }

                                // Aristas salientes desde este nodo hacia sus commits padres.
                                for (const edge of (d.out_edges || [])) {
                                    const fx = xOf(edge.from);
                                    const tx = xOf(edge.to);
                                    ctx.strokeStyle = gitWin.laneColor(edge.merge ? edge.to : edge.from);
                                    ctx.globalAlpha = 0.85;
                                    ctx.beginPath();
                                    ctx.moveTo(fx, cy);
                                    if (fx === tx) {
                                        ctx.lineTo(tx, height);
                                    } else {
                                        ctx.bezierCurveTo(fx, cy + (height - cy) * 0.65, tx, cy + (height - cy) * 0.35, tx, height);
                                    }
                                    ctx.stroke();
                                }

                                // Conexión punteada superior hacia cambios pendientes en el nodo HEAD.
                                if (d.is_head && !gitWin.workingClean) {
                                    ctx.strokeStyle = gitWin.pendingAccent;
                                    ctx.globalAlpha = 0.85;
                                    ctx.setLineDash([3, 3]);
                                    ctx.beginPath();
                                    ctx.moveTo(nodeX, 0);
                                    ctx.lineTo(nodeX, cy);
                                    ctx.stroke();
                                    ctx.setLineDash([]);
                                }

                                // Nodo del commit.
                                const cColor = gitWin.laneColor(d.lane || 0);
                                if (d.is_head) {
                                    ctx.globalAlpha = 0.30;
                                    ctx.fillStyle = cColor;
                                    ctx.beginPath();
                                    ctx.arc(nodeX, cy, 9.5, 0, Math.PI * 2);
                                    ctx.fill();
                                }

                                ctx.globalAlpha = 1.0;
                                ctx.fillStyle = "#101622";
                                ctx.beginPath();
                                ctx.arc(nodeX, cy, d.is_merge ? 6.5 : 5.5, 0, Math.PI * 2);
                                ctx.fill();

                                ctx.fillStyle = cColor;
                                ctx.beginPath();
                                ctx.arc(nodeX, cy, d.is_merge ? 4.8 : 4.2, 0, Math.PI * 2);
                                ctx.fill();

                                if (d.is_head || d.is_merge) {
                                    ctx.fillStyle = d.is_head ? "#ffffff" : "#101622";
                                    ctx.beginPath();
                                    ctx.arc(nodeX, cy, 1.9, 0, Math.PI * 2);
                                    ctx.fill();
                                }
                            }
                        }

                        // Metadatos minimalistas: tipo/ámbito sin duplicar, título limpio y hash/tiempo alineados a la derecha.
                        ColumnLayout {
                            anchors.left: graphCanvas.right
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6
                            anchors.rightMargin: 12
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    visible: !!commitRow.modelData.kind
                                    implicitWidth: kindLabel.implicitWidth + 10
                                    implicitHeight: 17
                                    radius: 5
                                    color: Qt.alpha(gitWin.kindColor(commitRow.modelData.kind), 0.14)
                                    border.width: 1
                                    border.color: Qt.alpha(gitWin.kindColor(commitRow.modelData.kind), 0.42)
                                    Text {
                                        id: kindLabel
                                        anchors.centerIn: parent
                                        text: commitRow.modelData.kind
                                        textFormat: Text.PlainText
                                        color: gitWin.kindColor(commitRow.modelData.kind)
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: commitRow.parsed.title
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: commitRow.modelData.is_head ? "#ffffff" : GemaTheme.textColor
                                    font.pixelSize: 12
                                    font.weight: commitRow.modelData.is_head || commitRow.selected ? Font.DemiBold : Font.Normal
                                }

                                Repeater {
                                    model: (commitRow.modelData.refs || []).slice(0, 2)
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitWidth: refLabel.implicitWidth + 10
                                        implicitHeight: 17
                                        radius: 5
                                        color: modelData.kind === "head"
                                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#288be9fd")
                                            : modelData.kind === "tag" ? "#2086e8c8"
                                            : modelData.kind === "branch" ? "#1ec8b6ff" : "#14ffffff"
                                        border.width: 1
                                        border.color: modelData.kind === "head"
                                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.62) : "#668be9fd")
                                            : modelData.kind === "tag" ? "#5486e8c8"
                                            : modelData.kind === "branch" ? "#42c8b6ff" : "#26ffffff"
                                        Text {
                                            id: refLabel
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            textFormat: Text.PlainText
                                            color: modelData.kind === "tag" ? "#86e8c8"
                                                   : modelData.kind === "head" ? "#ffffff" : GemaTheme.textColor
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    visible: !!commitRow.parsed.scope
                                    text: commitRow.parsed.scope
                                    textFormat: Text.PlainText
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (commitRow.parsed.scope ? "·  " : "") + (commitRow.modelData.author || "")
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: commitRow.modelData.relative_date || ""
                                    textFormat: Text.PlainText
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 10
                                }
                                Text {
                                    text: commitRow.modelData.short_hash || ""
                                    textFormat: Text.PlainText
                                    color: GemaTheme.synced ? GemaTheme.accentAlpha(0.85) : "#a8d8ff"
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: gitWin.selectCommit(commitRow.modelData.hash)
                        }
                    }
                }

                // Inspector inferior animado de detalle del commit seleccionado (aprovecha todo el ancho).
                GlassPanel {
                    id: detailPanel
                    objectName: "gitCommitDetailPanel"
                    Layout.fillWidth: true
                    readonly property bool expanded: !!gitWin.selectedHash
                    readonly property int targetHeight: expanded ? Math.min(280, Math.max(132, detailInner.implicitHeight + 24)) : 0
                    Layout.preferredHeight: targetHeight
                    visible: Layout.preferredHeight > 1 || expanded
                    opacity: expanded ? 1.0 : 0.0
                    clip: true
                    radius: 14
                    reflective: false
                    topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.14) : "#18c4dcff"
                    bottomColor: "#24080d16"
                    edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.45) : "#42c4dcff"

                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: GemaTheme.animations ? 220 : 0; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: GemaTheme.animations ? 160 : 0; easing.type: Easing.OutCubic }
                    }

                    ScrollView {
                        id: detailScroll
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColumnLayout {
                            id: detailInner
                            width: detailScroll.availableWidth
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: gitWin.commitDetail.short_hash || gitWin.selectedHash.slice(0, 7)
                                    textFormat: Text.PlainText
                                    color: GemaTheme.synced ? GemaTheme.accent : "#8be9fd"
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                ActionButton {
                                    text: gitWin.hashCopied ? "Copiado ✓" : "Copiar"
                                    font.pixelSize: 10
                                    implicitHeight: 24
                                    horizontalPadding: 9
                                    verticalPadding: 0
                                    onClicked: {
                                        NativeApp.clipboardText = gitWin.commitDetail.hash || gitWin.selectedHash;
                                        gitWin.hashCopied = true;
                                        hashCopiedTimer.restart();
                                    }
                                }

                                Text {
                                    visible: !gitWin.detailLoading && !!gitWin.commitDetail.hash
                                    text: "+" + (gitWin.commitDetail.total_added || 0)
                                    color: "#86e8c8"
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Text {
                                    visible: !gitWin.detailLoading && !!gitWin.commitDetail.hash
                                    text: "-" + (gitWin.commitDetail.total_deleted || 0)
                                    color: "#ff9b9b"
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                ActionButton {
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    horizontalPadding: 0
                                    verticalPadding: 0
                                    text: "×"
                                    font.pixelSize: 13
                                    onClicked: {
                                        gitWin.selectedHash = "";
                                        gitWin.commitDetail = ({});
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: gitWin.detailLoading
                                text: "Cargando detalle del commit…"
                                color: GemaTheme.subtleColor
                                font.pixelSize: 11
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !gitWin.detailLoading && !!gitWin.commitDetail.subject
                                text: gitWin.commitDetail.subject || ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !gitWin.detailLoading && !!gitWin.commitDetail.body
                                text: gitWin.commitDetail.body || ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: GemaTheme.mutedColor
                                font.pixelSize: 11
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !gitWin.detailLoading && !!gitWin.commitDetail.author
                                text: (gitWin.commitDetail.author || "") + " · " + (gitWin.commitDetail.relative_date || "")
                                      + " · " + (gitWin.commitDetail.file_count || 0) + " archivos"
                                textFormat: Text.PlainText
                                color: GemaTheme.subtleColor
                                font.pixelSize: 10
                            }

                            Repeater {
                                model: !gitWin.detailLoading ? (gitWin.commitDetail.files || []) : []
                                delegate: Rectangle {
                                    id: fileRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: 6
                                    color: fileRowMouse.containsMouse ? "#16ffffff" : "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: fileRow.modelData.path
                                            textFormat: Text.PlainText
                                            elide: Text.ElideMiddle
                                            color: GemaTheme.textColor
                                            font.family: "monospace"
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: fileRow.modelData.binary ? "bin" : ("+" + fileRow.modelData.added)
                                            color: fileRow.modelData.binary ? GemaTheme.subtleColor : "#86e8c8"
                                            font.family: "monospace"
                                            font.pixelSize: 10
                                        }
                                        Text {
                                            visible: !fileRow.modelData.binary
                                            text: "-" + fileRow.modelData.deleted
                                            color: "#ff9b9b"
                                            font.family: "monospace"
                                            font.pixelSize: 10
                                        }
                                    }
                                    MouseArea {
                                        id: fileRowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: gitWin.fileRequested(fileRow.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
