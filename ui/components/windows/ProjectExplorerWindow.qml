import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../js/CodeSyntax.js" as CodeSyntax
import "../shared"

// Navegador de carpetas; abre los archivos en un visor independiente.
FloatingWindow {
    id: explorer
    required property AgentBridge bridge
    property string mainWindowTitle: ""
    property var project: ({})
    readonly property string projectId: project.project_id || ""
    readonly property string projectName: project.name || ""
    readonly property string projectWorkdir: project.workdir || ""
    objectName: "projectExplorerWindow"
    title: "Explorador · " + projectName
    implicitWidth: 820
    implicitHeight: 655
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
    readonly property ProjectFileWindow firstFileWindow: ProjectFileWindow {
        bridge: explorer.bridge; viewerId: 1; mainWindowTitle: explorer.mainWindowTitle
        projectId: explorer.projectId; projectName: explorer.projectName
    }
    readonly property ProjectFileWindow secondFileWindow: ProjectFileWindow {
        bridge: explorer.bridge; viewerId: 2; mainWindowTitle: explorer.mainWindowTitle
        projectId: explorer.projectId; projectName: explorer.projectName
    }
    readonly property var fileWindows: [firstFileWindow, secondFileWindow]
    property var activeFileWindow: firstFileWindow
    readonly property var openPaths: [firstFileWindow, secondFileWindow]
        .filter(viewer => viewer.visible).map(viewer => viewer.filePath)
    readonly property var syntaxPalette: GemaTheme.codePalette
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

    function setProject(next) {
        const changed = projectId !== (next.project_id || "") || projectWorkdir !== (next.workdir || "");
        if (changed) {
            clearActivity();
            for (const viewer of fileWindows) viewer.clear();
        }
        project = next;
        if (!projectId) visible = false;
        if (changed) reset();
        else if (visible) refresh();
    }

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
        if (!visible || !bridge.ready || !projectId) return;
        const key = kind + ":" + path;
        if (pending[key]) return;
        const id = "explorer-" + (++serial);
        pending[key] = id;
        bridge.sendCommand({ type: "explorer." + kind, project_id: projectId,
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
                    String(Quickshell.processId), title, "0", mainWindowTitle];
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
        function onReadyChanged() {
            if (!explorer.bridge.ready) explorer.setProject({});
        }
        function onEventReceived(event) {
            const data = event.data;
            if (event.type === "area.state" && (data.area === "work" || data.area === "app")) {
                explorer.setProject(data.project || {});
                return;
            }
            if (event.type === "project.deleted" && data.project_id === explorer.projectId) {
                explorer.setProject({});
                return;
            }
            if (event.type === "chat.finished" && explorer.activityCall) {
                explorer.stopActivity(data.status);
                explorer.activityCall = "";
            }
            if (event.type === "work.activity" && (explorer.bridge.activeArea === "work" || explorer.bridge.activeArea === "app")
                && data.project_id === explorer.projectId) {
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
            if (event.type === "work.changed" && (explorer.bridge.activeArea === "work" || explorer.bridge.activeArea === "app")
                && data.project_id === explorer.projectId && data.call_id === explorer.activityCall
                && explorer.activityState === "running") {
                // Si el usuario cerró una ventana, un nuevo cambio relevante puede reabrirla.
                explorer.visible = true;
                explorer.followChange(data);
                return;
            }
            if (!explorer.visible || !event.type.startsWith("explorer.") || data.project_id !== explorer.projectId) return;
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
            topColor: "#54141c26"
            bottomColor: "#680c121a"
            edgeColor: "#4cffffff"
            highlighted: explorer.activityState === "running"
        }
        ColumnLayout {
            focus: true
            Keys.onEscapePressed: event => { explorer.visible = false; event.accepted = true; }
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            // Cabecera arrastrable armonizada con GemaTheme.
            Item {
                Layout.fillWidth: true
                implicitHeight: 26
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    GlassPanel {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: 6
                        reflective: false
                        topColor: GemaTheme.accentAlpha(0.24)
                        bottomColor: GemaTheme.accentAlpha(0.10)
                        edgeColor: GemaTheme.accentAlpha(0.50)
                        Text {
                            anchors.centerIn: parent
                            text: GemaTheme.gemSymbol
                            color: GemaTheme.accent
                            font.pixelSize: 11
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                        }
                    }
                    Text {
                        visible: !!explorer.projectName
                        text: explorer.projectName
                        textFormat: Text.PlainText
                        color: GemaTheme.textColor
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        verticalAlignment: Text.AlignVCenter
                        text: (explorer.projectName ? "· " : "") + explorer.projectWorkdir
                        textFormat: Text.PlainText
                        color: GemaTheme.subtleColor
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                        HoverHandler { id: pathHover }
                        ToolTip {
                            id: pathTip
                            visible: pathHover.hovered
                            text: explorer.projectWorkdir
                            contentItem: Text { text: pathTip.text; textFormat: Text.PlainText; color: pathTip.palette.toolTipText; font: pathTip.font }
                            delay: 500
                        }
                    }
                    Rectangle {
                        visible: explorer.activityState === "running"
                        implicitWidth: liveRow.implicitWidth + 12
                        implicitHeight: 20
                        radius: 6
                        color: GemaTheme.accentAlpha(0.18)
                        border.width: 1
                        border.color: GemaTheme.accentAlpha(0.55)
                        RowLayout {
                            id: liveRow
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                width: 5; height: 5; radius: 2.5
                                color: GemaTheme.accent
                                SequentialAnimation on opacity {
                                    running: explorer.activityState === "running" && explorer.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.35; duration: 500; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.35; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                text: "EN VIVO"
                                color: GemaTheme.accentInk
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                        }
                    }
                    Rectangle {
                        visible: explorer.openPaths.length > 0 && explorer.activityState !== "running"
                        implicitWidth: openBadge.implicitWidth + 10
                        implicitHeight: 19
                        radius: 6
                        color: GemaTheme.accentAlpha(0.14)
                        border.width: 1
                        border.color: GemaTheme.accentAlpha(0.36)
                        Text {
                            id: openBadge
                            anchors.centerIn: parent
                            text: explorer.openPaths.length + "/2"
                            color: GemaTheme.accentInk
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: explorer.startSystemMove()
                }
            }
            // Separador especular tintado con el acento Gema.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00ffffff" }
                    GradientStop { position: 0.22; color: GemaTheme.accentAlpha(0.45) }
                    GradientStop { position: 0.72; color: "#28ffffff" }
                    GradientStop { position: 1.0; color: "#00ffffff" }
                }
            }
            ListView {
                id: tree
                objectName: "projectExplorerTree"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: explorer.treeEntries
                populate: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "x"; from: 10; to: 0; duration: 260; easing.type: Easing.OutCubic }
                    }
                }
                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "x"; from: 10; to: 0; duration: 260; easing.type: Easing.OutCubic }
                    }
                }
                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }
                displaced: Transition { NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic } }
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
                    readonly property var langInfo: row.directory ? null : CodeSyntax.detectLanguage(row.name)
                    readonly property color itemAccent: row.directory
                        ? explorer.syntaxPalette.folder
                        : CodeSyntax.roleColor(explorer.syntaxPalette, langInfo ? langInfo.role : "plain")
                    readonly property bool isOpen: explorer.openPaths.includes(row.path)
                    readonly property bool isActive: explorer.activePath === row.path
                    readonly property color changeBadgeColor: row.changed === "Modificado"
                        ? explorer.syntaxPalette.badgeModified : explorer.syntaxPalette.badgeCreated
                    property real glow: 0
                    onRevisionChanged: { if (revision > 0) rowHighlight.restart(); }
                    Component.onCompleted: { if (revision > 0) rowHighlight.restart(); }
                    SequentialAnimation {
                        id: rowHighlight
                        NumberAnimation { target: row; property: "glow"; to: 0.24; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: row; property: "glow"; to: 0; duration: 820; easing.type: Easing.OutCubic }
                    }
                    width: tree.width
                    topPadding: 5
                    bottomPadding: 5
                    rightPadding: 10
                    leftPadding: 10 + modelData.depth * 16
                    onClicked: explorer.select(modelData)

                    // Guías verticales discretas de jerarquía para subcarpetas.
                    Repeater {
                        model: row.depth
                        Rectangle {
                            required property int index
                            x: 15 + index * 16
                            y: 0
                            width: 1
                            height: row.height
                            color: GemaTheme.accentAlpha(0.14)
                        }
                    }

                    contentItem: RowLayout {
                        spacing: 7
                        Text {
                            Layout.preferredWidth: 10
                            horizontalAlignment: Text.AlignHCenter
                            text: "›"
                            opacity: row.directory ? 1 : 0
                            color: row.opened || row.hovered ? GemaTheme.accent : GemaTheme.subtleColor
                            font.pixelSize: 13
                            font.bold: row.opened
                            rotation: row.opened ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                        }
                        // Icono vectorial nativo: carpeta o indicador de tipo de archivo armonizado con Gema.
                        Item {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            Layout.alignment: Qt.AlignVCenter
                            // Icono de carpeta
                            Item {
                                anchors.fill: parent
                                visible: row.directory
                                Rectangle {
                                    x: 1; y: 2; width: 6; height: 3; radius: 1
                                    color: row.opened ? GemaTheme.accent : row.itemAccent
                                    opacity: row.opened ? 0.95 : 0.72
                                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                                }
                                Rectangle {
                                    x: 1; y: 4; width: 12; height: 8; radius: 2
                                    color: Qt.rgba(row.opened ? GemaTheme.accent.r : row.itemAccent.r,
                                                   row.opened ? GemaTheme.accent.g : row.itemAccent.g,
                                                   row.opened ? GemaTheme.accent.b : row.itemAccent.b,
                                                   row.opened ? 0.34 : 0.20)
                                    border.width: 1
                                    border.color: row.opened ? GemaTheme.accent : row.itemAccent
                                    Behavior on border.color { ColorAnimation { duration: GemaTheme.animDuration } }
                                }
                            }
                            // Indicador de archivo codificado por color de lenguaje
                            Item {
                                anchors.fill: parent
                                visible: !row.directory
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 12; height: 12; radius: 6
                                    color: row.itemAccent
                                    opacity: row.isOpen || row.isActive ? 0.24 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: GemaTheme.animDuration } }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: row.isOpen || row.isActive ? 7 : 6
                                    height: row.isOpen || row.isActive ? 7 : 6
                                    radius: 3.5
                                    color: row.itemAccent
                                    opacity: row.isOpen || row.isActive || row.hovered || row.changed ? 1.0 : 0.78
                                    border.width: row.isOpen ? 1 : 0
                                    border.color: "#88ffffff"
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.name
                            textFormat: Text.PlainText
                            color: row.isActive || row.isOpen || row.changed || row.hovered
                                   ? GemaTheme.textColor
                                   : (row.directory ? GemaTheme.mutedColor : GemaTheme.subtleColor)
                            font.pixelSize: 12
                            font.weight: row.isOpen || row.isActive ? Font.DemiBold : (row.directory ? Font.Medium : Font.Normal)
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        Rectangle {
                            visible: !!row.changed
                            implicitWidth: changeLabel.implicitWidth + 10
                            implicitHeight: 17
                            radius: 5
                            color: Qt.rgba(row.changeBadgeColor.r, row.changeBadgeColor.g, row.changeBadgeColor.b, 0.16)
                            border.width: 1
                            border.color: Qt.rgba(row.changeBadgeColor.r, row.changeBadgeColor.g, row.changeBadgeColor.b, 0.48)
                            opacity: row.changed ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            Text {
                                id: changeLabel
                                anchors.centerIn: parent
                                text: row.changed
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: row.changeBadgeColor
                            }
                        }
                    }
                    background: GlassPanel {
                        radius: 7
                        reflective: false
                        highlighted: row.activeFocus || row.isOpen
                        topColor: row.isOpen ? GemaTheme.accentAlpha(0.20)
                                  : row.hovered ? GemaTheme.accentAlpha(0.12) : "#00000000"
                        bottomColor: row.isOpen ? GemaTheme.accentAlpha(0.08)
                                     : row.hovered ? "#12060a10" : "#00000000"
                        edgeColor: row.isOpen ? GemaTheme.accentAlpha(0.55)
                                   : row.hovered ? GemaTheme.accentAlpha(0.26) : "#00000000"
                        Rectangle {
                            anchors.fill: parent
                            radius: 7
                            color: GemaTheme.accent
                            opacity: Math.max(row.glow,
                                explorer.activityState === "running" && row.isActive ? 0.10 : 0)
                        }
                        Rectangle {
                            visible: row.isOpen || (explorer.activityState === "running" && row.isActive)
                            x: 2
                            y: 4
                            width: 2.5
                            height: Math.max(4, parent.height - 8)
                            radius: 1.25
                            color: GemaTheme.accent
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                Text {
                    anchors.centerIn: parent
                    visible: !explorer.rows.length
                    text: "Sin entradas visibles"
                    color: GemaTheme.subtleColor
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !!explorer.notice || !!explorer.viewerNotice || !!explorer.activityNotice
                text: explorer.viewerNotice || explorer.activityNotice || explorer.notice
                color: GemaTheme.mutedColor
                font.pixelSize: 11
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                wrapMode: Text.Wrap
            }
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
                Text {
                    text: explorer.rows.length + " entradas visibles"
                    color: GemaTheme.subtleColor
                    font.pixelSize: 11
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
        }
    }
}
