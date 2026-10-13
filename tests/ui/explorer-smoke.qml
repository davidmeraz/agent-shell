import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtTest
import Quickshell
import "../../ui"

// Carpeta temporal real, sin OAuth: ventana, sondeo, texto y cambio de espacio.
ShellRoot {
    id: scenario
    property int stage: 0
    property var explorer: null
    property string savedProjectId: ""
    readonly property var viewer: explorer ? explorer.activeFileWindow : null
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 700; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function check(value, message) {
        if (value) return true;
        console.error("EXPLORER_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function row(path) { return explorer.rows.find(entry => entry.path === path); }
    Timer {
        id: steps
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (scenario.stage === 0) {
                if (!agent.canRunShell) return;
                agent.createProject("Explorador de prueba", agent.workspace);
                scenario.stage = 1;
            } else if (scenario.stage === 1) {
                if (agent.areaBusy || !agent.projectId) return;
                agent.submit("/shell mkdir -p src node_modules; printf inicial > src/existing.txt");
                scenario.stage = 2;
            } else if (scenario.stage === 2) {
                if (agent.busy) return;
                scenario.explorer = chat.explorerWindow;
                if (!scenario.check(!!scenario.explorer && !inspector.findChild(chat, "workExplorerButton"), "ventana ausente o botón manual conservado")) return;
                if (!scenario.check(scenario.explorer.mainWindowTitle === chat.title
                    && scenario.explorer.firstFileWindow.mainWindowTitle === chat.title
                    && scenario.explorer.secondFileWindow.mainWindowTitle === chat.title,
                    "el explorador o los visores no siguen la identidad de la ventana principal")) return;
                scenario.explorer.visible = true;
                const surface = inspector.findChild(scenario.explorer, "projectExplorerMatteSurface");
                if (!scenario.check(!!surface && surface.waterReflection && surface.radius === 20
                    && surface.topColor.a < 1 && surface.bottomColor.a < 1
                    && scenario.explorer.color.a === 0, "fondo no es vidrio mate translúcido")) return;
                scenario.stage = 3;
            } else if (scenario.stage === 3) {
                if (!scenario.explorer.rows.length) return;
                if (!scenario.check(scenario.explorer.visible && !!scenario.row("src") && !scenario.row("node_modules"), "ventana, árbol o exclusiones")) return;
                scenario.explorer.select(scenario.row("src"));
                scenario.stage = 4;
            } else if (scenario.stage === 4) {
                if (!scenario.row("src/existing.txt")) return;
                scenario.explorer.select(scenario.row("src/existing.txt"));
                scenario.stage = 5;
            } else if (scenario.stage === 5) {
                if (scenario.viewer.preview !== "inicial") return;
                if (!scenario.check(scenario.viewer.visible && scenario.explorer.visible
                    && scenario.viewer !== scenario.explorer, "el archivo no abre en otra ventana")) return;
                const surface = inspector.findChild(scenario.viewer, "projectFileMatteSurface");
                if (!scenario.check(!!surface && surface.waterReflection && surface.topColor.a < 1
                    && scenario.viewer.color.a === 0, "visor sin vidrio mate")) return;
                const preview = inspector.findChild(scenario.viewer, "projectExplorerPreview");
                if (!scenario.check(preview.readOnly && preview.textFormat === TextEdit.PlainText, "vista previa no es texto de solo lectura")) return;
                agent.submit("/shell printf '<b>nuevo</b>' > src/new.txt; printf modificado > src/existing.txt");
                scenario.stage = 6;
            } else if (scenario.stage === 6) {
                if (agent.busy || !scenario.row("src/new.txt") || scenario.viewer.preview !== "modificado") return;
                if (!scenario.check(scenario.row("src/new.txt").changed === "Nuevo"
                    && scenario.row("src/existing.txt").changed === "Modificado", "marcas de cambios no actualizadas")) return;
                scenario.explorer.select(scenario.row("src/new.txt"));
                scenario.stage = 7;
            } else if (scenario.stage === 7) {
                if (scenario.viewer.preview !== "<b>nuevo</b>") return;
                agent.submit("/shell mv src/new.txt src/renamed.txt; rm src/existing.txt");
                scenario.stage = 8;
            } else if (scenario.stage === 8) {
                if (agent.busy || !scenario.row("src/renamed.txt") || scenario.row("src/new.txt") || scenario.row("src/existing.txt")) return;
                scenario.viewer.visible = false;
                scenario.explorer.select(scenario.row("src/renamed.txt"));
                const tree = inspector.findChild(scenario.explorer, "projectExplorerTree");
                tree.forceActiveFocus();
                tree.Window.window.requestActivate();
                inspector.wait(20);
                inspector.keyClick(Qt.Key_Escape);
                if (!scenario.check(Object.keys(scenario.explorer.pending).length === 0
                    && !scenario.explorer.visible && scenario.viewer.visible, "Esc no cierra sólo el árbol")) return;
                scenario.stage = 9;
            } else if (scenario.stage === 9) {
                if (scenario.viewer.preview !== "<b>nuevo</b>") return;
                agent.submit("/shell printf independiente > src/renamed.txt");
                scenario.stage = 10;
            } else if (scenario.stage === 10) {
                if (agent.busy || scenario.viewer.preview !== "independiente") return;
                if (!scenario.check(!scenario.explorer.visible && scenario.viewer.visible,
                    "el visor no actualiza independientemente")) return;
                scenario.explorer.visible = true;
                scenario.stage = 11;
            } else if (scenario.stage === 11) {
                if (!scenario.row("src")) return;
                scenario.explorer.select(scenario.row("src"));
                scenario.stage = 12;
            } else if (scenario.stage === 12) {
                if (!scenario.row("src/renamed.txt")) return;
                const preview = inspector.findChild(scenario.viewer, "projectExplorerPreview");
                inspector.mouseClick(preview);
                preview.forceActiveFocus();
                preview.Window.window.requestActivate();
                inspector.wait(20);
                inspector.keyClick(Qt.Key_Escape);
                if (!scenario.check(!scenario.viewer.visible && scenario.explorer.visible
                    && !scenario.viewer.pendingId, "Esc no cierra sólo el visor: visor=" + scenario.viewer.visible
                    + ", árbol=" + scenario.explorer.visible + ", lectura=" + scenario.viewer.pendingId)) return;
                scenario.explorer.select(scenario.row("src/renamed.txt"));
                scenario.stage = 13;
            } else if (scenario.stage === 13) {
                if (scenario.viewer.preview !== "independiente") return;
                // Una respuesta antigua no debe sustituir el contenido actual.
                agent.eventReceived({ type: "explorer.file", data: { project_id: agent.projectId,
                    request_id: "file-viewer-0-0", path: "src/renamed.txt", text: "obsoleto" } });
                if (!scenario.check(scenario.viewer.preview === "independiente", "respuesta tardía aplicada")) return;
                agent.submit("/shell printf cuarto > src/fourth.txt");
                scenario.stage = 14;
            } else if (scenario.stage === 14) {
                if (agent.busy || !scenario.row("src/fourth.txt")) return;
                const windows = scenario.explorer.fileWindows;
                if (!scenario.check(windows.length === 2 && windows.every(viewer => viewer.visible)
                    && new Set(windows.map(viewer => viewer.viewerId)).size === 2,
                    "no hay dos visores independientes")) return;
                const paths = windows.map(viewer => viewer.filePath).join("|");
                scenario.explorer.select(scenario.row("src/renamed.txt"));
                if (!scenario.check(windows.map(viewer => viewer.filePath).join("|") === paths
                    && !scenario.explorer.viewerNotice, "archivo abierto duplicado")) return;
                scenario.explorer.select(scenario.row("src/fourth.txt"));
                if (!scenario.check(!!scenario.explorer.viewerNotice
                    && windows.map(viewer => viewer.filePath).join("|") === paths,
                    "tercer archivo reemplaza un visor ocupado")) return;
                windows[0].visible = false;
                scenario.explorer.select(scenario.row("src/fourth.txt"));
                if (!scenario.check(windows[0].visible && windows[0].filePath === "src/fourth.txt"
                    && windows[1].visible, "no reutiliza el visor libre")) return;
                scenario.stage = 15;
            } else if (scenario.stage === 15) {
                if (scenario.explorer.firstFileWindow.preview !== "cuarto") return;
                if (!scenario.check(scenario.explorer.secondFileWindow.preview === "independiente",
                    "las respuestas de texto se mezclan")) return;
                // closed() llega desde el compositor; es distinto de asignar visible=false.
                scenario.explorer.refresh();
                for (const viewer of scenario.explorer.fileWindows) viewer.refresh();
                scenario.explorer.closed();
                for (const viewer of scenario.explorer.fileWindows) viewer.closed();
                if (!scenario.check(!scenario.explorer.visible && !Object.keys(scenario.explorer.pending).length
                    && scenario.explorer.fileWindows.every(viewer => !viewer.visible && !viewer.pendingId),
                    "cierre nativo conserva visibilidad o lecturas pendientes")) return;
                scenario.stage = 16;
            } else if (scenario.stage === 16) {
                scenario.explorer.visible = true;
                if (!scenario.check(scenario.explorer.visible && scenario.explorer.fileWindows.every(viewer => !viewer.visible),
                    "el explorador no reabre independientemente tras cierre nativo")) return;
                scenario.stage = 17;
            } else if (scenario.stage === 17) {
                if (!scenario.row("src")) return;
                scenario.explorer.select(scenario.row("src"));
                scenario.stage = 18;
            } else if (scenario.stage === 18) {
                if (!scenario.row("src/fourth.txt") || !scenario.row("src/renamed.txt")) return;
                scenario.explorer.select(scenario.row("src/fourth.txt"));
                scenario.explorer.select(scenario.row("src/renamed.txt"));
                scenario.stage = 19;
            } else if (scenario.stage === 19) {
                const windows = scenario.explorer.fileWindows;
                if (windows[0].preview !== "cuarto" || windows[1].preview !== "independiente") return;
                if (!scenario.check(windows.every(viewer => viewer.visible), "los visores no reabren tras cierre nativo")) return;
                scenario.savedProjectId = agent.projectId;
                agent.selectArea("chat");
                scenario.stage = 20;
            } else if (scenario.stage === 20) {
                if (agent.areaBusy || agent.activeArea !== "chat") return;
                const windows = scenario.explorer.fileWindows;
                if (!scenario.check(scenario.explorer.visible && windows.every(viewer => viewer.visible)
                    && windows[0].preview === "cuarto" && windows[1].preview === "independiente"
                    && scenario.explorer.projectId === savedProjectId && !agent.projectId
                    && scenario.explorer.expanded["src"], "Chat pierde las vistas, el contexto o las carpetas expandidas")) return;
                agent.submit("/shell printf desde-chat > src/fourth.txt; printf segundo-chat > src/renamed.txt; touch src/in-chat.txt");
                scenario.stage = 21;
            } else if (scenario.stage === 21) {
                if (agent.busy) return;
                scenario.explorer.refresh();
                for (const viewer of scenario.explorer.fileWindows) viewer.refresh();
                if (scenario.explorer.fileWindows[0].preview !== "desde-chat"
                    || scenario.explorer.fileWindows[1].preview !== "segundo-chat" || !scenario.row("src/in-chat.txt")) return;
                agent.selectArea("work", savedProjectId);
                scenario.stage = 22;
            } else if (scenario.stage === 22) {
                if (agent.areaBusy || agent.activeArea !== "work") return;
                if (!scenario.check(scenario.explorer.expanded["src"] && scenario.row("src/in-chat.txt")
                    && scenario.explorer.fileWindows.every(viewer => viewer.visible && viewer.projectId === savedProjectId),
                    "volver al mismo proyecto reinicia los visores")) return;
                agent.submit("/shell mkdir -p next-project; printf nuevo > next-project/main.txt");
                scenario.stage = 23;
            } else if (scenario.stage === 23) {
                if (agent.busy) return;
                agent.createProject("Otro proyecto", agent.workspace + "/next-project");
                scenario.stage = 24;
            } else if (scenario.stage === 24) {
                if (agent.areaBusy || agent.projectId === savedProjectId || !scenario.row("main.txt")) return;
                if (!scenario.check(scenario.explorer.projectId === agent.projectId
                    && scenario.explorer.projectWorkdir === agent.workspace
                    && !scenario.row("src") && scenario.explorer.fileWindows.every(viewer => !viewer.visible && !viewer.preview),
                    "otro proyecto hereda archivos o rutas del anterior")) return;
                scenario.savedProjectId = agent.projectId;
                scenario.explorer.openFile("main.txt");
                scenario.stage = 25;
            } else if (scenario.stage === 25) {
                if (scenario.viewer.preview !== "nuevo") return;
                agent.selectArea("chat");
                scenario.stage = 26;
            } else if (scenario.stage === 26) {
                if (agent.areaBusy || agent.activeArea !== "chat") return;
                if (!scenario.check(scenario.viewer.visible && scenario.viewer.preview === "nuevo", "Chat pierde el segundo proyecto")) return;
                agent.deleteProject(savedProjectId);
                scenario.stage = 27;
            } else if (scenario.stage === 27) {
                if (agent.areaBusy) return;
                if (!scenario.check(!scenario.explorer.visible && !scenario.explorer.projectId
                    && scenario.explorer.fileWindows.every(viewer => !viewer.visible && !viewer.preview),
                    "eliminar en Chat conserva los visores del proyecto retirado")) return;
                console.log("EXPLORER_OK: dos visores, límite, lectura viva en Chat, vuelta a Work sin perder carpetas/archivos, aislamiento al cambiar de proyecto, eliminación desde Chat, cierre nativo y reapertura");
                steps.stop(); Qt.callLater(Qt.quit);
            }
        }
    }
}
