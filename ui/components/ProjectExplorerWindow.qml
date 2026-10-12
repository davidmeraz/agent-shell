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

    function reset() {
        folders = ({}); expanded = ({ "": true }); rows = []; pending = ({});
        notice = ""; viewerNotice = "";
        if (visible) refresh();
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
                                depth: depth, changed: entry.changed || "" });
                if (entry.directory && expanded[entry.path]) visit(entry.path, depth + 1);
            }
        }
        visit("", 0); rows = result;
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
            placement.running = false;
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del explorador: " + data) }
    }
    Connections {
        target: explorer.bridge
        function onAreaChanged() { explorer.visible = false; explorer.reset(); }
        function onWorkspaceChanged() { explorer.reset(); }
        function onReadyChanged() { explorer.reset(); }
        function onEventReceived(event) {
            const data = event.data;
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
        }
    }
    Timer { interval: 1500; repeat: true; running: explorer.visible && explorer.bridge.ready; onTriggered: explorer.refresh() }
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
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "Carpetas · " + explorer.bridge.projectName; textFormat: Text.PlainText; color: "white"; font.pixelSize: 18; elide: Text.ElideRight }
            ActionButton { text: "Actualizar"; onClicked: explorer.refresh() }
            ActionButton { text: "Cerrar"; onClicked: explorer.visible = false }
        }
        Text { Layout.fillWidth: true; text: explorer.bridge.workspace; textFormat: Text.PlainText; color: "#aaaaaa"; elide: Text.ElideMiddle }
        ListView {
            id: tree
            objectName: "projectExplorerTree"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: explorer.rows
            delegate: ItemDelegate {
                id: row
                required property var modelData
                width: tree.width
                leftPadding: 10 + modelData.depth * 16
                onClicked: explorer.select(modelData)
                contentItem: Text {
                    text: (row.modelData.directory ? (explorer.expanded[row.modelData.path] ? "▾ " : "▸ ") : "  ")
                          + row.modelData.name + (row.modelData.changed ? " · " + row.modelData.changed : "")
                    textFormat: Text.PlainText
                    color: row.modelData.changed ? "white" : "#bbbbbb"
                    elide: Text.ElideRight
                }
                background: GlassPanel {
                    radius: 6
                    reflective: false
                    highlighted: row.activeFocus
                    topColor: row.hovered || explorer.openPaths.includes(row.modelData.path) ? "#30555555" : "#00000000"
                    bottomColor: row.hovered || explorer.openPaths.includes(row.modelData.path) ? "#24333333" : "#00000000"
                    edgeColor: explorer.openPaths.includes(row.modelData.path) ? "#40ffffff" : "#00000000"
                }
            }
            ScrollBar.vertical: ScrollBar {}
            Text { anchors.centerIn: parent; visible: !explorer.rows.length; text: "Sin entradas visibles"; color: "#888888" }
        }
        Text { Layout.fillWidth: true; visible: !!explorer.notice || !!explorer.viewerNotice; text: explorer.viewerNotice || explorer.notice; color: "#dddddd"; wrapMode: Text.Wrap }
        Text { Layout.fillWidth: true; text: "Cambios desde la apertura · actualización cada 1,5 s · sin atribución a la IA"; color: "#888888"; font.pixelSize: 11; wrapMode: Text.Wrap }
    }
}
