import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "ui"

// Carpeta temporal real, sin OAuth: ventana, sondeo, texto y cambio de espacio.
ShellRoot {
    id: scenario
    property int stage: 0
    property var explorer: null
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
                const button = inspector.findChild(chat, "workExplorerButton");
                if (!scenario.check(!!scenario.explorer && button.visible && button.enabled, "ventana o botón ausente")) return;
                inspector.mouseClick(button);
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
                scenario.explorer.visible = false;
                if (!scenario.check(Object.keys(scenario.explorer.pending).length === 0
                    && scenario.viewer.visible, "cerrar árbol afecta al visor")) return;
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
                inspector.mouseClick(inspector.findChild(scenario.viewer, "projectFileClose"));
                if (!scenario.check(!scenario.viewer.visible && scenario.explorer.visible
                    && !scenario.viewer.pendingId, "cerrar visor afecta al árbol")) return;
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
                inspector.mouseClick(inspector.findChild(chat, "workExplorerButton"));
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
                agent.selectArea("chat");
                scenario.stage = 20;
            } else if (scenario.stage === 20) {
                if (agent.areaBusy || agent.activeArea !== "chat") return;
                if (!scenario.check(!scenario.explorer.visible && scenario.explorer.fileWindows.every(viewer =>
                    !viewer.visible && !viewer.filePath && !viewer.preview), "cambio de área conserva ventana o texto")) return;
                console.log("EXPLORER_OK: dos visores, límite, reutilización, ventanas separadas, vidrio mate, carpetas, texto, cambios, cierre nativo, reapertura y limpieza por área");
                steps.stop(); Qt.callLater(Qt.quit);
            }
        }
    }
}
