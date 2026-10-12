import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Visor independiente: sólo lee el archivo abierto y descarta respuestas tardías.
FloatingWindow {
    id: viewer
    required property AgentBridge bridge
    required property int viewerId
    objectName: "projectFileWindow"
    title: "Visor " + viewerId + " · " + (filePath || bridge.projectName)
    implicitWidth: viewerId === 1 ? 781 : 857
    implicitHeight: viewerId === 1 ? 1334 : 662
    minimumSize: Qt.size(420, 320)
    color: "transparent"
    visible: false
    // Permite reabrir tras cerrar con el atajo del compositor o la decoración.
    onClosed: viewer.visible = false
    BackgroundEffect.blurRegion: Region { item: matteSurface; radius: matteSurface.radius }
    property string filePath: ""
    property string preview: ""
    property bool previewTruncated: false
    property string pendingId: ""
    property int serial: 0

    function clear() {
        visible = false;
        pendingId = "";
        filePath = "";
        preview = "";
        previewTruncated = false;
    }
    function openFile(path) {
        pendingId = "";
        filePath = path;
        preview = "Cargando…";
        previewTruncated = false;
        visible = true;
        refresh();
        // Wayland delega la posición al compositor; sólo se aplica al abrir.
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") {
            placement.command = [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python",
                Quickshell.shellDir + "/scripts/place-text-viewer.py",
                String(Quickshell.processId), title, String(viewerId)];
            placement.running = true;
        }
    }
    function refresh() {
        if (!visible || !filePath || pendingId || !bridge.ready
            || bridge.activeArea !== "work" || !bridge.projectId) return;
        pendingId = "file-viewer-" + viewerId + "-" + (++serial);
        bridge.sendCommand({ type: "explorer.read", project_id: bridge.projectId,
                             request_id: pendingId, path: filePath });
    }
    onVisibleChanged: {
        if (!visible) {
            pendingId = "";
            placement.running = false;
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del visor: " + data) }
    }
    Connections {
        target: viewer.bridge
        function onAreaChanged() { viewer.clear(); }
        function onWorkspaceChanged() { viewer.clear(); }
        function onReadyChanged() { viewer.clear(); }
        function onEventReceived(event) {
            const data = event.data;
            if (!viewer.visible || !viewer.pendingId || data.project_id !== viewer.bridge.projectId
                || data.request_id !== viewer.pendingId) return;
            if (event.type === "explorer.file" && data.path === viewer.filePath) {
                viewer.pendingId = "";
                viewer.preview = data.text;
                viewer.previewTruncated = data.truncated;
            } else if (event.type === "explorer.error") {
                viewer.pendingId = "";
                viewer.preview = data.message;
                viewer.previewTruncated = false;
            }
        }
    }
    Timer { interval: 1500; repeat: true; running: viewer.visible && viewer.bridge.ready; onTriggered: viewer.refresh() }
    MattePanel {
        id: matteSurface
        objectName: "projectFileMatteSurface"
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
            Text { Layout.fillWidth: true; text: "Visor de archivos " + viewer.viewerId + " / 2"; color: "white"; font.pixelSize: 18 }
            ActionButton { text: "Actualizar"; onClicked: viewer.refresh() }
            ActionButton { objectName: "projectFileClose"; text: "Cerrar"; onClicked: viewer.visible = false }
        }
        Text { Layout.fillWidth: true; text: viewer.filePath; textFormat: Text.PlainText; color: "#dddddd"; elide: Text.ElideMiddle }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            TextArea {
                objectName: "projectExplorerPreview"
                text: viewer.preview
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                font.family: "monospace"
                font.pixelSize: 12
                color: "#eeeeee"
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                background: GlassPanel {
                    radius: 10
                    reflective: false
                    topColor: "#20181818"
                    bottomColor: "#30101010"
                    edgeColor: "#24ffffff"
                }
            }
        }
        Text { visible: viewer.previewTruncated; text: "Vista previa limitada a 128 KiB."; color: "#aaaaaa" }
        Text { Layout.fillWidth: true; text: "Solo lectura · actualización cada 1,5 s"; color: "#888888"; font.pixelSize: 11 }
    }
}
