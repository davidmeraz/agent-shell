import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AgentShell.Native
import "../.."
import "../../js/CodeSyntax.js" as CodeSyntax
import "../shared"

// Navegador de carpetas; soporta vista en árbol compacta y vista de iconos grandes.
NativeWindow {
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
    visible: false
    // El cierre nativo debe actualizar también la intención de visibilidad de Qt.
    onClosed: explorer.visible = false
    property var folders: ({})
    property var expanded: ({ "": true })
    property var rows: []
    readonly property ListModel treeEntries: ListModel {}
    readonly property ListModel gridEntries: ListModel {}
    property string viewMode: "icons"
    property string currentBrowsePath: ""
    property real gridTransitionProgress: 1
    property var pending: ({})
    property int serial: 0
    readonly property ProjectFileWindow firstFileWindow: ProjectFileWindow {
        bridge: explorer.bridge; viewerId: 1; mainWindowTitle: explorer.mainWindowTitle
        projectId: explorer.projectId; projectName: explorer.projectName
        onVisibleChanged: explorer.bumpOpenState()
        onFilePathChanged: explorer.bumpOpenState()
    }
    readonly property ProjectFileWindow secondFileWindow: ProjectFileWindow {
        bridge: explorer.bridge; viewerId: 2; mainWindowTitle: explorer.mainWindowTitle
        projectId: explorer.projectId; projectName: explorer.projectName
        onVisibleChanged: explorer.bumpOpenState()
        onFilePathChanged: explorer.bumpOpenState()
    }
    readonly property var fileWindows: [firstFileWindow, secondFileWindow]
    property var floatingWindows: []
    property int floatingSerial: 2
    property int openRevision: 0
    readonly property var allFileWindows: fileWindows.concat(floatingWindows)
    property var activeFileWindow: firstFileWindow
    readonly property var openPaths: {
        const _rev = openRevision;
        return allFileWindows.filter(viewer => viewer && viewer.visible).map(viewer => viewer.filePath);
    }
    readonly property var syntaxPalette: GemaTheme.codePalette
    Component {
        id: floatingViewerFactory
        ProjectFileWindow { floatingMode: true }
    }
    function bumpOpenState() { openRevision += 1; }
    function clearFloatingWindows() {
        for (const fw of floatingWindows) {
            if (!fw) continue;
            fw.clear();
            fw.destroy();
        }
        floatingWindows = [];
        floatingSerial = 2;
        bumpOpenState();
    }
    readonly property var breadcrumbSegments: {
        const parts = currentBrowsePath ? currentBrowsePath.split("/") : [];
        const items = [{ label: projectName || "Raíz", path: "" }];
        let acc = "";
        for (let i = 0; i < parts.length; ++i) {
            acc += (acc ? "/" : "") + parts[i];
            items.push({ label: parts[i], path: acc });
        }
        return items;
    }
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

    function viewerNumber(path) {
        const _rev = openRevision;
        for (const viewer of allFileWindows) {
            if (viewer && viewer.visible && viewer.filePath === path)
                return viewer.viewerId;
        }
        return 0;
    }

    function setViewMode(mode) {
        if (mode !== "tree" && mode !== "icons") return;
        if (viewMode === mode) return;
        viewMode = mode;
        if (mode === "icons") {
            if (currentBrowsePath && !folders[currentBrowsePath]) request("list", currentBrowsePath);
            rebuildGrid();
            gridTransition.restart();
        }
    }

    function navigateToFolder(path) {
        const target = path || "";
        if (currentBrowsePath === target) {
            refreshFolder(target);
            return;
        }
        currentBrowsePath = target;
        if (target) {
            let acc = "";
            const parts = target.split("/");
            for (let i = 0; i < parts.length; ++i) {
                acc += (acc ? "/" : "") + parts[i];
                expanded[acc] = true;
            }
        }
        if (!folders[target]) request("list", target);
        else refreshFolder(target);
        rebuildGrid();
        gridTransition.restart();
    }

    function navigateUp() {
        if (!currentBrowsePath) return;
        const slash = currentBrowsePath.lastIndexOf("/");
        navigateToFolder(slash >= 0 ? currentBrowsePath.slice(0, slash) : "");
    }

    function setProject(next) {
        const changed = projectId !== (next.project_id || "") || projectWorkdir !== (next.workdir || "");
        if (changed) {
            clearActivity();
            currentBrowsePath = "";
            for (const viewer of fileWindows) viewer.clear();
            clearFloatingWindows();
        }
        project = next;
        if (!projectId) visible = false;
        if (changed) reset();
        else if (visible) refresh();
    }

    function reset() {
        folders = ({}); expanded = ({ "": true }); rows = []; pending = ({}); refreshAfter = ({});
        treeEntries.clear();
        gridEntries.clear();
        currentBrowsePath = "";
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
        // En vista de iconos, acompaña la carpeta afectada cuando la IA crea o edita archivos.
        if (viewMode === "icons" && data.action !== "deleted") {
            const targetFolder = data.directory ? data.path : parent;
            if (targetFolder !== currentBrowsePath) {
                currentBrowsePath = targetFolder;
                gridTransition.restart();
            }
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
            for (const viewer of allFileWindows) {
                if (viewer && (viewer.filePath === data.path || (data.directory && viewer.filePath.startsWith(data.path + "/"))))
                    viewer.markDeleted();
            }
            if (data.directory && (currentBrowsePath === data.path || currentBrowsePath.startsWith(data.path + "/"))) {
                currentBrowsePath = parent;
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
    function syncModel(model, result) {
        const wanted = new Set(result.map(row => row.path));
        for (let i = model.count - 1; i >= 0; --i)
            if (!wanted.has(model.get(i).path)) model.remove(i);
        for (let i = 0; i < result.length; ++i) {
            let found = i;
            while (found < model.count && model.get(found).path !== result[i].path) ++found;
            if (found === model.count) model.insert(i, result[i]);
            else {
                if (found !== i) model.move(found, i, 1);
                const old = model.get(i);
                for (const key of Object.keys(result[i]))
                    if (old[key] !== result[i][key]) model.setProperty(i, key, result[i][key]);
            }
        }
    }
    function rebuildGrid() {
        const entries = (folders[currentBrowsePath] || []).map(entry => ({
            path: entry.path,
            name: entry.name,
            directory: entry.directory,
            depth: 0,
            changed: activityMarks[entry.path] || entry.changed || "",
            opened: !!expanded[entry.path],
            revision: activityRevisions[entry.path] || 0
        }));
        syncModel(gridEntries, entries);
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
        syncModel(treeEntries, result);
        rebuildGrid();
    }
    function refresh() {
        request("list", "");
        if (currentBrowsePath) request("list", currentBrowsePath);
        for (const row of rows) if (row.directory && expanded[row.path]) request("list", row.path);
    }
    function openFile(path) {
        // Si el archivo ya está abierto (derecha, izquierda o flotante), seleccionarlo de nuevo lo cierra.
        const existing = allFileWindows.find(viewer => viewer && viewer.visible && viewer.filePath === path);
        if (existing) {
            existing.visible = false;
            viewerNotice = "";
            bumpOpenState();
            return;
        }
        // 1° archivo a la derecha (#1), 2° archivo a la izquierda (#2).
        const available = fileWindows.find(viewer => !viewer.visible);
        if (available) {
            viewerNotice = "";
            activeFileWindow = available;
            available.openFile(path);
            bumpOpenState();
            return;
        }
        // Con los dos visores fijos ocupados, abre archivos adicionales en ventanas flotantes.
        let floating = floatingWindows.find(viewer => viewer && !viewer.visible);
        if (!floating) {
            const nextId = ++floatingSerial;
            floating = floatingViewerFactory.createObject(explorer, {
                bridge: explorer.bridge,
                viewerId: nextId,
                mainWindowTitle: Qt.binding(() => explorer.mainWindowTitle),
                projectId: Qt.binding(() => explorer.projectId),
                projectName: Qt.binding(() => explorer.projectName)
            });
            floating.visibleChanged.connect(() => explorer.bumpOpenState());
            floating.filePathChanged.connect(() => explorer.bumpOpenState());
            floatingWindows = floatingWindows.concat([floating]);
        }
        viewerNotice = "";
        activeFileWindow = floating;
        floating.openFile(path);
        bumpOpenState();
    }
    function select(row) {
        if (row.directory) {
            if (viewMode === "icons") {
                navigateToFolder(row.path);
            } else {
                expanded[row.path] = !expanded[row.path];
                if (expanded[row.path]) request("list", row.path);
                rebuild();
            }
        } else {
            openFile(row.path);
        }
    }
    NumberAnimation {
        id: gridTransition
        target: explorer
        property: "gridTransitionProgress"
        from: 0.72; to: 1; duration: GemaTheme.animations ? 220 : 0
        easing.type: Easing.OutCubic
    }
    Shortcut {
        sequence: "Ctrl+1"
        context: Qt.WindowShortcut
        enabled: explorer.visible
        onActivated: explorer.setViewMode("icons")
    }
    Shortcut {
        sequence: "Ctrl+2"
        context: Qt.WindowShortcut
        enabled: explorer.visible
        onActivated: explorer.setViewMode("tree")
    }
    onVisibleChanged: {
        if (visible) {
            reset();
            if (NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE") && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen") {
                placement.command = [NativeApp.pythonExecutable,
                    NativeApp.placementScript,
                    String(NativeApp.processId), title, "0", mainWindowTitle];
                placement.running = true;
            }
        } else {
            pending = ({});
            refreshAfter = ({});
            placement.running = false;
        }
    }
    NativeProcess {
        id: placement
        errorOutput: LineParser { onRead: data => console.warn("Posición del explorador: " + data) }
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
                        if (explorer.currentBrowsePath === prior.path
                            || explorer.currentBrowsePath.startsWith(prior.path + "/")) {
                            explorer.currentBrowsePath = data.path;
                        }
                    }
                }
                explorer.notice = data.truncated ? "Listado limitado a 1000 entradas por carpeta." : "";
                explorer.rebuild();
            } else if (event.type === "explorer.error") {
                explorer.notice = data.message;
                if (key.startsWith("list:")) {
                    const failedPath = key.slice(5);
                    explorer.folders[failedPath] = [];
                    if (explorer.currentBrowsePath && (explorer.currentBrowsePath === failedPath
                        || explorer.currentBrowsePath.startsWith(failedPath + "/"))) {
                        const slash = failedPath.lastIndexOf("/");
                        explorer.currentBrowsePath = slash >= 0 ? failedPath.slice(0, slash) : "";
                    }
                    explorer.rebuild();
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
        GlassToolTipTheme {}
        ColumnLayout {
            focus: true
            Keys.onEscapePressed: event => { explorer.visible = false; event.accepted = true; }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Backspace && explorer.viewMode === "icons" && explorer.currentBrowsePath) {
                    explorer.navigateUp();
                    event.accepted = true;
                }
            }
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10
            // Cabecera arrastrable con selector de vista (Árbol / Iconos grandes).
            Item {
                Layout.fillWidth: true
                implicitHeight: 26
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    // Zona arrastrable (deja libres los botones del selector de vista).
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        MouseArea {
                            anchors.fill: parent
                            onPressed: explorer.startSystemMove()
                        }
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
                                GlassToolTip {
                                    id: pathTip
                                    visible: pathHover.hovered
                                    text: explorer.projectWorkdir
                                    delay: 500
                                }
                            }
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
                        implicitHeight: 20
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
                    // Selector de vista: Iconos grandes (predeterminada) | Árbol compacto.
                    GlassPanel {
                        objectName: "explorerViewModeSwitcher"
                        implicitWidth: 56
                        implicitHeight: 24
                        radius: 7
                        reflective: false
                        topColor: "#14ffffff"
                        bottomColor: "#12060a10"
                        edgeColor: GemaTheme.accentAlpha(0.30)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 2
                            Button {
                                id: iconsModeBtn
                                objectName: "explorerIconsModeButton"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                padding: 0
                                hoverEnabled: true
                                readonly property bool active: explorer.viewMode === "icons"
                                Accessible.name: "Vista de iconos grandes"
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                ToolTip.text: "Vista iconos grandes (Ctrl+1)"
                                onClicked: explorer.setViewMode("icons")
                                background: Rectangle {
                                    radius: 5
                                    color: iconsModeBtn.active ? GemaTheme.accentAlpha(0.28)
                                           : (iconsModeBtn.hovered ? GemaTheme.accentAlpha(0.14) : "transparent")
                                    border.width: iconsModeBtn.active ? 1 : 0
                                    border.color: GemaTheme.accentAlpha(0.65)
                                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                                }
                                contentItem: Item {
                                    // Icono vectorial 2x2 de cuadrícula de iconos grandes.
                                    Grid {
                                        anchors.centerIn: parent
                                        columns: 2
                                        spacing: 2
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                width: 4.5; height: 4.5; radius: 1.2
                                                color: iconsModeBtn.active ? GemaTheme.accent
                                                       : (iconsModeBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                id: treeModeBtn
                                objectName: "explorerTreeModeButton"
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                padding: 0
                                hoverEnabled: true
                                readonly property bool active: explorer.viewMode === "tree"
                                Accessible.name: "Vista en árbol"
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                ToolTip.text: "Vista árbol (Ctrl+2)"
                                onClicked: explorer.setViewMode("tree")
                                background: Rectangle {
                                    radius: 5
                                    color: treeModeBtn.active ? GemaTheme.accentAlpha(0.28)
                                           : (treeModeBtn.hovered ? GemaTheme.accentAlpha(0.14) : "transparent")
                                    border.width: treeModeBtn.active ? 1 : 0
                                    border.color: GemaTheme.accentAlpha(0.65)
                                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                                }
                                contentItem: Item {
                                    // Icono vectorial de árbol jerárquico.
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2.5
                                        Rectangle {
                                            width: 11; height: 1.5; radius: 0.75
                                            color: treeModeBtn.active ? GemaTheme.accent : (treeModeBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                                        }
                                        Rectangle {
                                            x: 3; width: 8; height: 1.5; radius: 0.75
                                            color: treeModeBtn.active ? GemaTheme.accent : (treeModeBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                                        }
                                        Rectangle {
                                            x: 5; width: 6; height: 1.5; radius: 0.75
                                            color: treeModeBtn.active ? GemaTheme.accent : (treeModeBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                                        }
                                    }
                                }
                            }
                        }
                    }
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
            // Barra de ruta navegable (breadcrumbs) para la vista de iconos grandes.
            RowLayout {
                objectName: "explorerIconBreadcrumbs"
                Layout.fillWidth: true
                visible: explorer.viewMode === "icons"
                spacing: 6
                Button {
                    id: upButton
                    objectName: "explorerUpButton"
                    implicitWidth: 26
                    implicitHeight: 24
                    padding: 0
                    hoverEnabled: true
                    enabled: explorer.currentBrowsePath !== ""
                    Accessible.name: "Subir una carpeta"
                    ToolTip.visible: hovered && enabled
                    ToolTip.delay: 400
                    ToolTip.text: "Carpeta anterior (Retroceso)"
                    onClicked: explorer.navigateUp()
                    background: GlassPanel {
                        radius: 6
                        reflective: false
                        topColor: upButton.hovered && upButton.enabled ? GemaTheme.accentAlpha(0.22) : "#14ffffff"
                        bottomColor: "#14060a10"
                        edgeColor: upButton.hovered && upButton.enabled ? GemaTheme.accentAlpha(0.55) : "#28ffffff"
                        opacity: upButton.enabled ? 1.0 : 0.42
                    }
                    contentItem: Text {
                        text: "←"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: upButton.enabled ? (upButton.hovered ? GemaTheme.accent : GemaTheme.textColor) : GemaTheme.subtleColor
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
                Flickable {
                    Layout.fillWidth: true
                    implicitHeight: 24
                    contentWidth: crumbsRow.implicitWidth
                    contentHeight: 24
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    Row {
                        id: crumbsRow
                        height: 24
                        spacing: 4
                        Repeater {
                            model: explorer.breadcrumbSegments
                            delegate: Row {
                                id: crumbDelegate
                                required property var modelData
                                required property int index
                                readonly property bool isCurrent: index === explorer.breadcrumbSegments.length - 1
                                height: 24
                                spacing: 4
                                Text {
                                    visible: crumbDelegate.index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "›"
                                    color: GemaTheme.subtleColor
                                    font.pixelSize: 12
                                }
                                Button {
                                    id: crumbBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitHeight: 22
                                    leftPadding: 7
                                    rightPadding: 7
                                    topPadding: 0
                                    bottomPadding: 0
                                    hoverEnabled: true
                                    onClicked: explorer.navigateToFolder(crumbDelegate.modelData.path)
                                    background: Rectangle {
                                        radius: 6
                                        color: crumbDelegate.isCurrent ? GemaTheme.accentAlpha(0.18)
                                               : (crumbBtn.hovered ? GemaTheme.accentAlpha(0.12) : "transparent")
                                        border.width: crumbDelegate.isCurrent ? 1 : 0
                                        border.color: GemaTheme.accentAlpha(0.42)
                                    }
                                    contentItem: Text {
                                        text: crumbDelegate.modelData.label
                                        textFormat: Text.PlainText
                                        verticalAlignment: Text.AlignVCenter
                                        color: crumbDelegate.isCurrent ? GemaTheme.accentInk
                                               : (crumbBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                                        font.pixelSize: 11
                                        font.weight: crumbDelegate.isCurrent ? Font.DemiBold : Font.Normal
                                        style: Text.Raised
                                        styleColor: GemaTheme.textShadow
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    text: explorer.gridEntries.count + (explorer.gridEntries.count === 1 ? " elemento" : " elementos")
                    color: GemaTheme.subtleColor
                    font.pixelSize: 10
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
            // Contenedor dual: Vista Árbol o Vista Iconos Grandes.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: tree
                    objectName: "projectExplorerTree"
                    anchors.fill: parent
                    visible: explorer.viewMode === "tree"
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

                // Vista de cuadrícula con iconos grandes de carpetas y archivos.
                GridView {
                    id: iconGrid
                    objectName: "projectExplorerIconGrid"
                    anchors.fill: parent
                    visible: explorer.viewMode === "icons"
                    opacity: explorer.gridTransitionProgress
                    transform: Translate { y: 10 * (1 - explorer.gridTransitionProgress) }
                    clip: true
                    topMargin: 4
                    bottomMargin: 8
                    readonly property int columns: Math.max(2, Math.floor(Math.max(width, 240) / 128))
                    cellWidth: Math.floor(Math.max(width, 240) / columns)
                    cellHeight: 134
                    model: explorer.gridEntries
                    populate: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 240; easing.type: Easing.OutCubic }
                        }
                    }
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 240; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 240; easing.type: Easing.OutCubic }
                    }
                    delegate: Item {
                        id: gridSlot
                        required property string path
                        required property string name
                        required property bool directory
                        required property string changed
                        required property int revision
                        readonly property var langInfo: directory ? null : CodeSyntax.detectLanguage(name)
                        width: iconGrid.cellWidth
                        height: iconGrid.cellHeight
                        ExplorerIconCard {
                            anchors.fill: parent
                            anchors.margins: 5
                            path: gridSlot.path
                            name: gridSlot.name
                            directory: gridSlot.directory
                            changed: gridSlot.changed
                            revision: gridSlot.revision
                            itemAccent: gridSlot.directory
                                ? explorer.syntaxPalette.folder
                                : CodeSyntax.roleColor(explorer.syntaxPalette, gridSlot.langInfo ? gridSlot.langInfo.role : "plain")
                            langLabel: gridSlot.langInfo ? gridSlot.langInfo.label : ""
                            isOpen: explorer.openPaths.includes(gridSlot.path)
                            isActive: explorer.activePath === gridSlot.path
                            viewerNumber: explorer.viewerNumber(gridSlot.path)
                            changeBadgeColor: gridSlot.changed === "Modificado"
                                ? explorer.syntaxPalette.badgeModified : explorer.syntaxPalette.badgeCreated
                            activityRunning: explorer.activityState === "running"
                            onClicked: explorer.select({
                                path: gridSlot.path,
                                name: gridSlot.name,
                                directory: gridSlot.directory,
                                depth: 0,
                                changed: gridSlot.changed
                            })
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                    Text {
                        anchors.centerIn: parent
                        visible: explorer.gridEntries.count === 0
                        text: "Carpeta vacía"
                        color: GemaTheme.subtleColor
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
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
                    GlassToolTip {
                        visible: statusHover.hovered
                        text: "Actualiza cada 1,5 s. Ctrl+1 iconos grandes, Ctrl+2 árbol. Esc para cerrar."
                        delay: 500
                    }
                }
                Text {
                    text: explorer.viewMode === "icons"
                          ? explorer.gridEntries.count + (explorer.gridEntries.count === 1 ? " elemento en carpeta" : " elementos en carpeta")
                          : explorer.rows.length + " entradas visibles"
                    color: GemaTheme.subtleColor
                    font.pixelSize: 11
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
        }
    }
}
