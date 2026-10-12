import QtQuick
import QtTest
import Quickshell
import "ui"

// La IA de prueba pide shell por HTTP; el motor ejecuta y observa archivos reales.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool sawPartial: false
    property bool sawAnimation: false
    property bool sawRotation: false
    property bool sawLineBand: false
    property bool sawEntryEntrance: false
    property bool sawWindowEntrance: false
    property bool sawFileTransition: false
    property bool sawStableRow: false
    property var originalRow: null
    property var changes: []
    property string oldCall: ""
    readonly property var explorer: chat.explorerWindow
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 700; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function check(value, message) {
        if (value) return true;
        console.error("ACTIVITY_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    Connections {
        target: agent
        function onEventReceived(event) {
            if (event.type === "work.changed" && event.data.path) {
                scenario.changes.push(event.data);
                scenario.oldCall = event.data.call_id;
            }
        }
    }
    Timer {
        id: steps
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            const windows = scenario.explorer.fileWindows;
            if (scenario.stage === 0) {
                if (!agent.canSend) return;
                agent.createProject("Construcción en vivo", agent.workspace);
                scenario.stage = 1;
            } else if (scenario.stage === 1) {
                if (!agent.canSend || agent.activeArea !== "work" || !agent.projectId) return;
                agent.submit("shell-live");
                scenario.stage = 2;
            } else if (scenario.stage === 2) {
                const tree = inspector.findChild(scenario.explorer, "projectExplorerTree");
                const motion = inspector.findChild(scenario.explorer, "projectViewerMotion");
                if (motion.progress > 0 && motion.progress < 1) scenario.sawWindowEntrance = true;
                for (let i = 0; i < tree.count; ++i) {
                    const row = tree.itemAtIndex(i);
                    if (!row) continue;
                    if (row.opacity > 0 && row.opacity < 1) scenario.sawEntryEntrance = true;
                    if (row.path === "src/a.txt" && windows[0].preview === "uno\n" && !scenario.originalRow)
                        scenario.originalRow = row;
                    if (row.path === "src/a.txt" && windows[0].preview === "uno\ndos\n")
                        scenario.sawStableRow = row === scenario.originalRow;
                }
                for (const viewer of windows) {
                    if (viewer.contentProgress > 0.65 && viewer.contentProgress < 1) scenario.sawFileTransition = true;
                    if (viewer.preview !== "uno\ndos\n") continue;
                    const code = inspector.findChild(viewer, "projectExplorerPreview");
                    const band = inspector.findChild(viewer, "projectCodeChangeBand");
                    const secondLine = code.positionToRectangle(4);
                    if (viewer.changeStart === 4 && viewer.changeEnd === 7 && band.opacity > 0
                        && Math.abs(band.y - secondLine.y) < 1 && band.height > 0)
                        scenario.sawLineBand = true;
                }
                if (windows.some(viewer => viewer.preview === "uno\n" && viewer.visible) && agent.busy)
                    scenario.sawPartial = true;
                if (windows.some(viewer => viewer.changeGlow > 0)) scenario.sawAnimation = true;
                if (windows[0].filePath === "src/c.txt" && windows[1].filePath === "src/b.txt")
                    scenario.sawRotation = true;
                if (agent.busy) return;
                if (!scenario.check(scenario.explorer.visible && windows.every(viewer => viewer.visible),
                    "la IA no abre automáticamente las tres ventanas")) return;
                if (!scenario.check(scenario.sawPartial && scenario.sawAnimation && scenario.sawRotation,
                    "faltan escritura intermedia, animación o rotación de visores: "
                    + scenario.sawPartial + ", " + scenario.sawAnimation + ", " + scenario.sawRotation)) return;
                if (!scenario.check(scenario.sawLineBand && scenario.sawEntryEntrance && scenario.sawWindowEntrance
                    && scenario.sawFileTransition && scenario.sawStableRow,
                    "animaciones o identidad del árbol: líneas=" + scenario.sawLineBand
                    + ", entradas=" + scenario.sawEntryEntrance + ", ventanas=" + scenario.sawWindowEntrance
                    + ", archivos=" + scenario.sawFileTransition + ", árbol estable=" + scenario.sawStableRow)) return;
                if (!scenario.check(scenario.explorer.expanded.src && scenario.changes.some(c => c.directory && c.path === "src")
                    && scenario.changes.some(c => c.action === "deleted" && c.path === "src/a.txt"),
                    "faltan carpetas o eliminación real")) return;
                scenario.explorer.followChange({action: "notice", message: "Aviso de seguimiento parcial"});
                scenario.explorer.reset();
                if (!scenario.check(scenario.explorer.activityNotice === "Aviso de seguimiento parcial",
                    "la actualización del árbol pierde el aviso de seguimiento")) return;
                if (!scenario.check(windows.some(viewer => viewer.filePath === "src/c.txt" && viewer.preview === "terminado")
                    && windows.some(viewer => viewer.filePath === "src/renamed.txt" && viewer.preview === "b")
                    && windows.every(viewer => viewer.activityState === "completed"),
                    "contenido final, renombrado o estado incorrecto")) return;
                scenario.explorer.closed();
                for (const viewer of windows) viewer.closed();
                agent.eventReceived({type: "work.changed", data: {project_id: agent.projectId,
                    call_id: scenario.oldCall, sequence: 999, path: "stale.txt", action: "created",
                    directory: false, preview: {text: "obsoleto", truncated: false}}});
                if (!scenario.check(!scenario.explorer.visible && windows.every(viewer => !viewer.visible),
                    "un evento tardío reabre las ventanas")) return;
                agent.submit("shell-live");
                scenario.stage = 3;
            } else if (scenario.stage === 3) {
                if (!agent.busy || !scenario.explorer.visible || !windows.some(viewer => viewer.visible)) return;
                if (!scenario.check(scenario.explorer.activityState === "running", "el siguiente turno no reactiva el seguimiento")) return;
                agent.cancel();
                scenario.stage = 4;
            } else if (scenario.stage === 4) {
                if (agent.busy) return;
                if (!scenario.check(!scenario.explorer.activityCall && scenario.explorer.activityState === "interrupted",
                    "cancelar no detiene el seguimiento")) return;
                agent.selectArea("chat");
                scenario.stage = 5;
            } else if (scenario.stage === 5) {
                if (agent.areaBusy || agent.activeArea !== "chat") return;
                if (!scenario.check(!scenario.explorer.visible && !scenario.explorer.activityCall
                    && windows.every(viewer => !viewer.visible && !viewer.filePath), "el seguimiento cruza áreas")) return;
                console.log("ACTIVITY_OK: IA por HTTP, comandos reales, carpetas, escritura en vivo, visores automáticos, rotación, entrada de ventanas/archivos, líneas modificadas, árbol estable, renombrado, cierre, reapertura, cancelación y aislamiento");
                steps.stop(); Qt.callLater(Qt.quit);
            }
        }
    }
}
