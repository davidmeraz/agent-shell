import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Navegador de carpetas; abre los archivos en un visor independiente.
FloatingWindow {
    id: explorer
    required property AgentBridge bridge
    objectName: "projectExplorerWindow"
    title: "Explorador · " + bridge.projectName
    implicitWidth: 553
    implicitHeight: 640
    minimumSize: Qt.size(320, 400)
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: matteSurface; radius: matteSurface.radius }
    visible: false
    // El cierre nativo debe actualizar también la intención de visibilidad de Qt.
    onClosed: explorer.visible = false
    property var folders: ({})
    property var expanded: ({ "": true })
    property var rows: []
    readonly property ListModel treeEntries: ListModel {}
    property var pending: ({})
    property int serial: 0
    readonly property ProjectFileWindow firstFileWindow: ProjectFileWindow { bridge: explorer.bridge; viewerId: 1 }
    readonly property ProjectFileWindow secondFileWindow: ProjectFileWindow { bridge: explorer.bridge; viewerId: 2 }
    readonly property var fileWindows: [firstFileWindow, secondFileWindow]
    property var activeFileWindow: firstFileWindow
    readonly property var openPaths: [firstFileWindow, secondFileWindow]
        .filter(viewer => viewer.visible).map(viewer => viewer.filePath)
    property string viewerNotice: ""
    property string notice: ""
    property string activityCall: ""
    property string activityNotice: ""
    property string activityState: ""
    property string activePath: ""
    property int activitySequence: 0
    property int nextActivityViewer: 0
    property var activityMarks: ({})
    property var activityRevisions: ({})
    property int changeRevision: 0
    property var refreshAfter: ({})

    function reset() {
        folders = ({}); expanded = ({ "": true }); rows = []; pending = ({}); refreshAfter = ({});
        treeEntries.clear();
        notice = ""; viewerNotice = "";
        if (visible) refresh();
    }
    function stopActivity(status) {
        activityState = status;
        activePath = "";
        for (const viewer of fileWindows) viewer.activityState = status;
    }
    function clearActivity() {
        activityCall = ""; activitySequence = 0; activityState = ""; activePath = "";
        activityNotice = "";
        nextActivityViewer = 0; activityMarks = ({});
        activityRevisions = ({});
    }
    function followChange(data) {
        if (data.action === "notice") { activityNotice = data.message; return; }
        if (!data.path || data.sequence <= activitySequence) return;
        activitySequence = data.sequence;
        activePath = data.path;
        activityMarks[data.path] = data.action === "created" ? "Creado" : "Modificado";
        activityRevisions[data.path] = ++changeRevision;
        let parent = "";
        const parts = data.path.split("/");
        for (let i = 0; i < parts.length - 1; ++i) {
            parent += (parent ? "/" : "") + parts[i];
            expanded[parent] = true;
            refreshFolder(parent);
        }
        refreshFolder("");
        if (data.directory && data.action !== "deleted") {
            expanded[data.path] = true;
            refreshFolder(data.path);
        }
        if (!data.directory && data.action !== "deleted" && data.preview) {
            let viewer = fileWindows.find(item => item.visible && item.filePath === data.path);
            if (!viewer) viewer = fileWindows.find(item => !item.visible);
            if (!viewer) {
                viewer = fileWindows[nextActivityViewer];
                nextActivityViewer = (nextActivityViewer + 1) % fileWindows.length;
            }
            activeFileWindow = viewer;
            viewer.followChange(data);
        } else if (data.action === "deleted") {
            for (const viewer of fileWindows) {
                if (viewer.filePath === data.path || (data.directory && viewer.filePath.startsWith(data.path + "/")))
                    viewer.markDeleted();
            }
        }
        rebuild();
    }
    function refreshFolder(path) {
        if (pending["list:" + path]) refreshAfter[path] = true;
        else request("list", path);
    }
    function request(kind, path) {
        if (!visible || !bridge.ready || bridge.activeArea !== "work" || !bridge.projectId) return;
        const key = kind + ":" + path;
        if (pending[key]) return;
        const id = "explorer-" + (++serial);
        pending[key] = id;
        bridge.sendCommand({ type: "explorer." + kind, project_id: bridge.projectId,
                               request_id: id, path: path });
    }
    function rebuild() {
        const result = [];
        function visit(path, depth) {
            for (const entry of folders[path] || []) {
                result.push({ path: entry.path, name: entry.name, directory: entry.directory,
                                depth: depth, changed: activityMarks[entry.path] || entry.changed || "",
                                opened: !!expanded[entry.path], revision: activityRevisions[entry.path] || 0 });
                if (entry.directory && expanded[entry.path]) visit(entry.path, depth + 1);
            }
        }
        visit("", 0); rows = result;
        // Conserva los delegados y la posición al sondear: sólo anima cambios reales.
        const wanted = new Set(result.map(row => row.path));
        for (let i = treeEntries.count - 1; i >= 0; --i)
            if (!wanted.has(treeEntries.get(i).path)) treeEntries.remove(i);
        for (let i = 0; i < result.length; ++i) {
            let found = i;
            while (found < treeEntries.count && treeEntries.get(found).path !== result[i].path) ++found;
            if (found === treeEntries.count) treeEntries.insert(i, result[i]);
            else {
                if (found !== i) treeEntries.move(found, i, 1);
                const old = treeEntries.get(i);
                for (const key of Object.keys(result[i]))
                    if (old[key] !== result[i][key]) treeEntries.setProperty(i, key, result[i][key]);
            }
        }
    }
    function refresh() {
        request("list", "");
        for (const row of rows) if (row.directory && expanded[row.path]) request("list", row.path);
    }
    function openFile(path) {
        const existing = fileWindows.find(viewer => viewer.visible && viewer.filePath === path);
        if (existing) {
            activeFileWindow = existing;
            existing.refresh();
            viewerNotice = "";
            return;
        }
        const available = fileWindows.find(viewer => !viewer.visible);
        if (!available) {
            viewerNotice = "Los 2 visores están abiertos. Cierra uno para abrir otro archivo.";
            return;
        }
        viewerNotice = "";
        activeFileWindow = available;
        available.openFile(path);
    }
    function select(row) {
        if (row.directory) {
            expanded[row.path] = !expanded[row.path];
            if (expanded[row.path]) request("list", row.path);
            rebuild();
        } else {
            openFile(row.path);
        }
    }
    onVisibleChanged: {
        if (visible) {
            reset();
            if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") {
                placement.command = [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python",
                    Quickshell.shellDir + "/scripts/place-text-viewer.py",
                    String(Quickshell.processId), title, "0"];
                placement.running = true;
            }
        } else {
            pending = ({});
            refreshAfter = ({});
            placement.running = false;
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del explorador: " + data) }
    }
    Connections {
        target: explorer.bridge
        function onAreaChanged() { explorer.visible = false; explorer.clearActivity(); explorer.reset(); }
        function onWorkspaceChanged() { explorer.clearActivity(); explorer.reset(); }
        function onReadyChanged() { explorer.clearActivity(); explorer.reset(); }
        function onEventReceived(event) {
            const data = event.data;
            if (event.type === "chat.finished" && explorer.activityCall) {
                explorer.stopActivity(data.status);
                explorer.activityCall = "";
            }
            if (event.type === "work.activity" && explorer.bridge.activeArea === "work"
                && data.project_id === explorer.bridge.projectId) {
                if (data.status === "running") {
                    explorer.activityCall = data.call_id;
                    explorer.activitySequence = 0;
                    explorer.activityState = "running";
                    explorer.activityNotice = "";
                    explorer.activePath = "";
                    explorer.visible = true;
                    explorer.refresh();
                } else if (data.call_id === explorer.activityCall) explorer.stopActivity(data.status);
                return;
            }
            if (event.type === "work.changed" && explorer.bridge.activeArea === "work"
                && data.project_id === explorer.bridge.projectId && data.call_id === explorer.activityCall
                && explorer.activityState === "running") {
                // Si el usuario cerró una ventana, un nuevo cambio relevante puede reabrirla.
                explorer.visible = true;
                explorer.followChange(data);
                return;
            }
            if (!explorer.visible || !event.type.startsWith("explorer.") || data.project_id !== explorer.bridge.projectId) return;
            const key = Object.keys(explorer.pending).find(k => explorer.pending[k] === data.request_id);
            if (key === undefined) return;
            delete explorer.pending[key];
            if (event.type === "explorer.list") {
                const old = explorer.folders[data.path];
                const entries = data.entries.map(entry => {
                    const previous = old ? old.find(row => row.path === entry.path) : null;
                    entry.changed = old && !previous ? "Nuevo" : previous &&
                        !entry.directory && (previous.modified_ns !== entry.modified_ns || previous.size !== entry.size)
                        ? "Modificado" : previous ? previous.changed : "";
                    return entry;
                });
                explorer.folders[data.path] = entries;
                if (old) for (const prior of old) {
                    if (prior.directory && !entries.some(row => row.path === prior.path && row.directory)) {
                        for (const path of Object.keys(explorer.expanded)) {
                            if (path === prior.path || path.startsWith(prior.path + "/")) {
                                delete explorer.expanded[path]; delete explorer.folders[path];
                            }
                        }
                    }
                }
                explorer.notice = data.truncated ? "Listado limitado a 1000 entradas por carpeta." : "";
                explorer.rebuild();
            } else if (event.type === "explorer.error") {
                explorer.notice = data.message;
                if (key.startsWith("list:")) {
                    explorer.folders[key.slice(5)] = []; explorer.rebuild();
                }
            }
            if (key.startsWith("list:") && explorer.refreshAfter[key.slice(5)]) {
                delete explorer.refreshAfter[key.slice(5)];
                explorer.request("list", key.slice(5));
            }
        }
    }
    Timer { interval: 1500; repeat: true; running: explorer.visible && explorer.bridge.ready; onTriggered: explorer.refresh() }
    ViewerMotion {
        id: windowMotion
        anchors.fill: parent
        shown: explorer.visible
        // Vidrio mate compartido: se conserva translúcido sin soporte de blur nativo.
        MattePanel {
            id: matteSurface
            objectName: "projectExplorerMatteSurface"
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#90303030"
            bottomColor: "#a01c1c1c"
            edgeColor: "#50ffffff"
        }
        ColumnLayout {
            focus: true
            Keys.onEscapePressed: event => { explorer.visible = false; event.accepted = true; }
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            Item {
                Layout.fillWidth: true
                implicitHeight: 20
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: explorer.bridge.workspace
                    textFormat: Text.PlainText
                    color: "#aaaaaa"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    HoverHandler { id: pathHover }
                    ToolTip {
                        id: pathTip
                        visible: pathHover.hovered
                        text: explorer.bridge.workspace
                        contentItem: Text { text: pathTip.text; textFormat: Text.PlainText; color: pathTip.palette.toolTipText; font: pathTip.font }
                        delay: 500
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: explorer.startSystemMove()
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#1affffff" }
            ListView {
                id: tree
                objectName: "projectExplorerTree"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: explorer.treeEntries
                populate: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { property: "x"; from: 8; to: 0; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { property: "x"; from: 8; to: 0; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 120 } }
                displaced: Transition { NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic } }
                delegate: ItemDelegate {
                    id: row
                    required property string path
                    required property string name
                    required property bool directory
                    required property int depth
                    required property string changed
                    required property bool opened
                    required property int revision
                    readonly property var modelData: ({path: path, name: name, directory: directory, depth: depth, changed: changed})
                    property real glow: 0
                    onRevisionChanged: { if (revision > 0) rowHighlight.restart(); }
                    Component.onCompleted: { if (revision > 0) rowHighlight.restart(); }
                    SequentialAnimation {
                        id: rowHighlight
                        NumberAnimation { target: row; property: "glow"; to: 0.12; duration: 90 }
                        NumberAnimation { target: row; property: "glow"; to: 0; duration: 650; easing.type: Easing.OutCubic }
                    }
                    width: tree.width
                    leftPadding: 10 + modelData.depth * 16
                    onClicked: explorer.select(modelData)
                    contentItem: RowLayout {
                        spacing: 7
                        Text {
                            Layout.preferredWidth: 10
                            text: "›"
                            opacity: row.directory ? 1 : 0
                            color: "#aaaaaa"
                            rotation: row.opened ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.name
                            textFormat: Text.PlainText
                            color: explorer.activePath === row.path || row.changed ? "white" : "#bbbbbb"
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Text {
                            text: row.changed
                            font.pixelSize: 10
                            color: "#aaaaaa"
                            opacity: row.changed ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                    }
                    background: GlassPanel {
                        radius: 6
                        reflective: false
                        highlighted: row.activeFocus
                        topColor: row.hovered || explorer.openPaths.includes(row.modelData.path) ? "#30555555" : "#00000000"
                        bottomColor: row.hovered || explorer.openPaths.includes(row.modelData.path) ? "#24333333" : "#00000000"
                        edgeColor: explorer.openPaths.includes(row.modelData.path) ? "#40ffffff" : "#00000000"
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: "white"
                            opacity: Math.max(row.glow,
                                explorer.activityState === "running" && explorer.activePath === row.path ? 0.04 : 0)
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                Text { anchors.centerIn: parent; visible: !explorer.rows.length; text: "Sin entradas visibles"; color: "#888888" }
            }
            Text { Layout.fillWidth: true; visible: !!explorer.notice || !!explorer.viewerNotice || !!explorer.activityNotice; text: explorer.viewerNotice || explorer.activityNotice || explorer.notice; color: "#dddddd"; wrapMode: Text.Wrap }
            RowLayout {
                Layout.fillWidth: true
                WorkStatusNote {
                    Layout.fillWidth: true
                    busy: explorer.activityState === "running"
                    windowVisible: explorer.visible
                    text: explorer.activityState === "running" ? "IA · " + (explorer.activePath ? "Cambios en vivo" : "Ejecutando")
                          : explorer.activityState === "completed" ? "Trabajo completado"
                          : explorer.activityState === "interrupted" ? "Trabajo detenido"
                          : explorer.activityState === "error" || explorer.activityState === "failed" || explorer.activityState === "timeout" ? "Revisar resultado"
                          : "Actualización automática"
                    HoverHandler { id: statusHover }
                    ToolTip {
                        visible: statusHover.hovered
                        text: "Actualiza cada 1,5 s. Las marcas indican cambios desde la apertura. Esc para cerrar."
                        delay: 500
                    }
                }
                Text { text: explorer.rows.length + " entradas visibles"; color: "#888888"; font.pixelSize: 11 }
            }
        }
    }
}
