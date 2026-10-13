import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../js/FileChanges.js" as FileChanges
import "../shared"

// Visor independiente: sólo lee el archivo abierto y descarta respuestas tardías.
FloatingWindow {
    id: viewer
    required property AgentBridge bridge
    required property int viewerId
    property string mainWindowTitle: ""
    property string projectId: ""
    property string projectName: ""
    objectName: "projectFileWindow"
    title: "Visor " + viewerId + " · " + (filePath || projectName)
    implicitWidth: 820
    implicitHeight: viewerId === 1 ? 1330 : 655
    minimumSize: Qt.size(420, 320)
    color: "transparent"
    visible: false
    // Permite reabrir tras cerrar con el atajo del compositor o la decoración.
    onClosed: viewer.visible = false
    BackgroundEffect.blurRegion: Region { item: matteSurface; radius: matteSurface.radius }
    property string filePath: ""
    property string preview: ""
    property bool previewTruncated: false
    property int previewLines: -1
    property string pendingId: ""
    property int serial: 0
    property string activityState: ""
    property bool deleted: false
    property real changeGlow: 0
    property int changeStart: 0
    property int changeEnd: 0
    property real changeTop: 0
    property real changeHeight: 0
    property int changeRevision: 0
    property real contentProgress: 1
    readonly property bool writing: writeReveal.running
    readonly property string displayedPreview: code.text
    property bool followWriting: true
    readonly property var scroller: codeScroll.contentItem
    onActivityStateChanged: {
        if (["interrupted", "failed", "error", "timeout"].includes(activityState)) writeReveal.finish();
    }
    FileWriteReveal {
        id: writeReveal
        editor: code
        onAdvanced: Qt.callLater(viewer.followWritingCursor)
    }
    function followWritingCursor() {
        if (!visible || !writing || !followWriting || scroller.moving || code.selectedText) return;
        const cursor = code.positionToRectangle(Math.min(writeReveal.position, code.length));
        if (cursor.y < scroller.contentY) scroller.contentY = Math.max(0, cursor.y - 12);
        else if (cursor.y + cursor.height > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height),
                cursor.y + cursor.height - scroller.height + 12);
    }
    Connections {
        target: viewer.scroller
        function onMovementStarted() { viewer.followWriting = false; }
        function onMovementEnded() { viewer.followWriting = viewer.scroller.atYEnd; }
    }

    function updateChangeGeometry() {
        const first = code.positionToRectangle(Math.min(changeStart, code.length));
        const last = code.positionToRectangle(Math.min(changeEnd, code.length));
        changeTop = first.y;
        changeHeight = Math.max(first.height, last.y + last.height - first.y);
    }

    function applyPreview(data, animated) {
        const changed = preview !== data.text;
        const text = FileChanges.visibleText(data.text);
        const range = changed ? FileChanges.range(previewLines < 0 ? "" : FileChanges.visibleText(preview), text) : null;
        preview = data.text;
        previewTruncated = data.truncated;
        previewLines = text ? text.split("\n").length - (text.endsWith("\n") ? 1 : 0) : 0;
        writeReveal.apply(data.text, animated && visible && !deleted);
        if (changed) {
            changeStart = range.start;
            changeEnd = range.end;
            const revision = ++changeRevision;
            Qt.callLater(function() {
                if (!viewer.visible || viewer.changeRevision !== revision) return;
                viewer.updateChangeGeometry();
                if (animated) highlight.restart();
            });
        }
    }
    function followChange(data) {
        if (!visible || filePath !== data.path) openFile(data.path, true);
        // La instantánea del disco invalida cualquier lectura periódica anterior.
        pendingId = "";
        deleted = false;
        activityState = "running";
        applyPreview(data.preview, true);
    }
    function markDeleted() {
        writeReveal.finish();
        pendingId = "";
        deleted = true;
        activityState = "deleted";
    }
    SequentialAnimation {
        id: highlight
        NumberAnimation { target: viewer; property: "changeGlow"; to: 0.035; duration: 90 }
        NumberAnimation { target: viewer; property: "changeGlow"; to: 0; duration: 800; easing.type: Easing.OutCubic }
    }
    NumberAnimation {
        id: fileTransition
        target: viewer
        property: "contentProgress"
        from: 0.65; to: 1; duration: 200
        easing.type: Easing.OutCubic
    }

    function clear() {
        visible = false;
        pendingId = "";
        filePath = "";
        preview = "";
        writeReveal.reset("");
        previewTruncated = false;
        previewLines = -1;
        activityState = ""; deleted = false;
        highlight.stop(); changeGlow = 0;
        ++changeRevision; changeStart = 0; changeEnd = 0; changeHeight = 0;
    }
    function openFile(path, following = false) {
        const wasVisible = visible;
        const switching = wasVisible && filePath !== path;
        highlight.stop(); changeGlow = 0; ++changeRevision; changeHeight = 0;
        pendingId = "";
        filePath = path;
        preview = following ? "" : "Cargando…";
        writeReveal.reset(preview);
        followWriting = true;
        previewTruncated = false;
        previewLines = -1;
        activityState = ""; deleted = false;
        visible = true;
        if (!following) refresh();
        if (switching) fileTransition.restart();
        // Wayland delega la posición al compositor; sólo se aplica al abrir.
        if (!wasVisible && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") {
            placement.command = [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python",
                Quickshell.shellDir + "/scripts/place-text-viewer.py",
                String(Quickshell.processId), title, String(viewerId), mainWindowTitle];
            placement.running = true;
        }
    }
    function refresh() {
        if (!visible || !filePath || pendingId || deleted || writing || !bridge.ready
            || !projectId) return;
        pendingId = "file-viewer-" + viewerId + "-" + (++serial);
        bridge.sendCommand({ type: "explorer.read", project_id: projectId,
                             request_id: pendingId, path: filePath });
    }
    onVisibleChanged: {
        if (!visible) {
            pendingId = "";
            writeReveal.finish();
            placement.running = false;
            highlight.stop(); changeGlow = 0;
            fileTransition.stop(); contentProgress = 1;
            ++changeRevision;
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del visor: " + data) }
    }
    Connections {
        target: viewer.bridge
        function onReadyChanged() { viewer.clear(); }
        function onEventReceived(event) {
            const data = event.data;
            if (!viewer.visible || !viewer.pendingId || data.project_id !== viewer.projectId
                || data.request_id !== viewer.pendingId) return;
            if (event.type === "explorer.file" && data.path === viewer.filePath) {
                viewer.pendingId = "";
                viewer.applyPreview(data, viewer.activityState === "running");
            } else if (event.type === "explorer.error") {
                viewer.pendingId = "";
                viewer.preview = data.message;
                writeReveal.reset(data.message);
                viewer.previewTruncated = false;
                viewer.previewLines = -1;
            }
        }
    }
    Timer { interval: 1500; repeat: true; running: viewer.visible && viewer.bridge.ready; onTriggered: viewer.refresh() }
    ViewerMotion {
        id: windowMotion
        anchors.fill: parent
        shown: viewer.visible
        MattePanel {
            id: matteSurface
            objectName: "projectFileMatteSurface"
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#90303030"
            bottomColor: "#a01c1c1c"
            edgeColor: "#50ffffff"
            Rectangle {
                anchors.fill: parent
                radius: 20
                color: "white"
                opacity: viewer.changeGlow
            }
        }
        ColumnLayout {
            focus: true
            Keys.onEscapePressed: event => { viewer.visible = false; event.accepted = true; }
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            Item {
                Layout.fillWidth: true
                implicitHeight: 20
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: viewer.filePath
                    textFormat: Text.PlainText
                    color: "#bbbbbb"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    HoverHandler { id: pathHover }
                    ToolTip {
                        id: pathTip
                        visible: pathHover.hovered
                        text: viewer.bridge.workspace + "/" + viewer.filePath
                        contentItem: Text { text: pathTip.text; textFormat: Text.PlainText; color: pathTip.palette.toolTipText; font: pathTip.font }
                        delay: 500
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: viewer.startSystemMove()
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#1affffff" }
            ScrollView {
                id: codeScroll
                objectName: "projectCodeScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                opacity: viewer.contentProgress
                transform: Translate { x: 6 * (1 - viewer.contentProgress) }
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                // TextEdit conserva el control del desplazamiento en el visor;
                // TextArea desplaza automáticamente al insertar incluso sin foco.
                TextEdit {
                    id: code
                    objectName: "projectExplorerPreview"
                    text: ""
                    width: codeScroll.availableWidth
                    textFormat: TextEdit.PlainText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: "#eeeeee"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    padding: 0
                    leftPadding: 10
                    onTextChanged: Qt.callLater(viewer.updateChangeGeometry)
                    onWidthChanged: Qt.callLater(viewer.updateChangeGeometry)
                    Rectangle {
                        objectName: "projectCodeWritingCursor"
                        readonly property rect location: {
                            const currentText = code.text;
                            return code.positionToRectangle(Math.min(writeReveal.position, currentText.length));
                        }
                        x: location.x
                        y: location.y + 1
                        width: 1
                        height: Math.max(1, location.height - 2)
                        color: "white"
                        opacity: 0.7
                        visible: viewer.writing
                    }
                    Rectangle {
                        objectName: "projectCodeChangeBand"
                        z: -1
                        x: 0
                        y: viewer.changeTop
                        width: code.width
                        height: viewer.changeHeight
                        radius: 3
                        color: "white"
                        opacity: viewer.changeGlow * 2
                    }
                    Rectangle {
                        objectName: "projectCodeChangeMarker"
                        x: 0
                        y: viewer.changeTop
                        width: 2
                        height: viewer.changeHeight
                        radius: 1
                        color: "white"
                        opacity: viewer.changeGlow * 18
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                WorkStatusNote {
                    Layout.fillWidth: true
                    busy: (viewer.writing || viewer.activityState === "running") && !viewer.deleted
                    windowVisible: viewer.visible
                    text: viewer.deleted ? "Archivo eliminado · última vista"
                          : viewer.writing ? "Mostrando cambios"
                          : viewer.activityState === "running" ? "IA · cambios en vivo"
                          : viewer.activityState === "completed" ? "Actualizado · solo lectura"
                          : viewer.activityState === "interrupted" ? "Detenido · solo lectura"
                          : "Solo lectura"
                    HoverHandler { id: statusHover }
                    ToolTip {
                        visible: statusHover.hovered
                        text: "La escritura animada muestra texto ya recibido del archivo. Esc para cerrar."
                        delay: 500
                    }
                }
                Text {
                    visible: viewer.previewLines >= 0
                    text: viewer.previewLines + (viewer.previewLines === 1 ? " línea" : " líneas")
                          + (viewer.previewTruncated ? " · vista parcial (128 KiB)" : "")
                    color: "#888888"
                    font.pixelSize: 11
                }
            }
        }
    }
}
