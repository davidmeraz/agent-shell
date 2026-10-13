import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "../../ui"

// Tarea interna de IA por HTTP local y programa real, sin mensajes de chat.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property string firstExecution: ""
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 600; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }

    function check(value, message) {
        if (value) return true;
        console.error("PROJECT_RUN_FAILED: " + message);
        agent.stopProject(); steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    Timer {
        id: steps
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            if (scenario.stepping) return;
            scenario.stepping = true;
            try {
                if (stage === 0) {
                    if (!agent.canSend) return;
                    agent.createProject("Programa de prueba", agent.workspace);
                    stage = 1;
                } else if (stage === 1) {
                    if (agent.areaBusy || !agent.projectId) return;
                    const prompt = inspector.findChild(chat, "chatPrompt");
                    prompt.text = "Borrador conservado";
                    inspector.mouseMove(chat.contentItem, chat.width - 24, 100);
                    inspector.findChild(chat, "chatSidebarDrawer").close();
                    inspector.wait(180);
                    const button = inspector.findChild(chat, "workRunButton");
                    if (!check(button && button.visible && button.enabled && button.text === "Ejecutar"
                        && !inspector.findChild(chat, "workExplorerButton"), "cabecera de Work incorrecta")) return;
                    inspector.mouseClick(button);
                    if (!check(agent.projectRunPending && prompt.text === "Borrador conservado"
                        && !agent.messages.count && !agent.busy, "Ejecutar modifica el borrador o el chat")) return;
                    stage = 2;
                } else if (stage === 2) {
                    if (!check(!agent.projectRunNotice, agent.projectRunNotice)) return;
                    if (agent.projectRun.phase !== "running" || !agent.projectRun.cache_available
                        || agent.projectRun.output.indexOf("run-ready") < 0) return;
                    scenario.firstExecution = agent.projectRun.execution_id;
                    const button = inspector.findChild(chat, "workRunButton");
                    if (!check(button.text === "Detener" && button.enabled && agent.canSend
                        && !agent.messages.count && !agent.currentChatId && !agent.conversations.count
                        && !agent.performanceHistory.length, "ejecución interna contamina historial o bloquea chat")) return;
                    agent.submit("Hola");
                    stage = 3;
                } else if (stage === 3) {
                    if (agent.busy) return;
                    if (!check(agent.messages.count === 2 && agent.projectRunActive,
                        "el programa no permite conversar o se detuvo con el chat")) return;
                    const prompt = inspector.findChild(chat, "chatPrompt");
                    if (!check(prompt.text === "Borrador conservado", "el botón pierde el borrador")) return;
                    inspector.mouseClick(inspector.findChild(chat, "workRunButton"));
                    stage = 4;
                } else if (stage === 4) {
                    if (agent.projectRunActive) return;
                    const button = inspector.findChild(chat, "workRunButton");
                    if (!check(agent.projectRun.phase === "interrupted" && button.text === "Ejecutar"
                        && button.enabled && agent.messages.count === 2,
                        "Detener afecta al chat o no permite repetir")) return;
                    inspector.mouseClick(button);
                    stage = 5;
                } else if (stage === 5) {
                    if (agent.projectRun.phase !== "running") return;
                    if (!check(agent.projectRun.execution_id !== firstExecution && agent.projectRun.source === "cache"
                        && agent.messages.count === 2,
                        "repetición conserva ejecución antigua o añade mensajes")) return;
                    agent.selectArea("chat");
                    stage = 6;
                } else if (stage === 6) {
                    if (agent.areaBusy || agent.activeArea !== "chat") return;
                    if (!check(agent.projectRunActive && !agent.messages.count, "cambiar de área mezcla historial o mata el programa")) return;
                    agent.selectArea("work", agent.projectRun.project_id);
                    stage = 7;
                } else if (stage === 7) {
                    if (agent.areaBusy || !agent.projectRunHere) return;
                    if (!check(inspector.findChild(chat, "workRunButton").text === "Detener"
                        && agent.messages.count === 2, "volver al proyecto no conserva el proceso")) return;
                    inspector.mouseClick(inspector.findChild(chat, "workRunButton"));
                    stage = 8;
                } else if (stage === 8) {
                    if (agent.projectRunActive) return;
                    if (!check(agent.projectRun.phase === "interrupted" && agent.messages.count === 2,
                        "segunda detención incorrecta")) return;
                    console.log("PROJECT_RUN_OK: Ejecutar/Detener, detección interna, caché y repetición sin IA, proceso real, salida, sin mensajes/historial/métricas, borrador, chat simultáneo y Chat/Work");
                    steps.stop(); Qt.quit();
                }
            } finally { scenario.stepping = false; }
        }
    }
    Timer { interval: 9000; running: true; onTriggered: scenario.check(false,
        "Tiempo agotado en etapa " + stage + ": " + agent.projectRunNotice + " · " + agent.projectRun.message) }
}
