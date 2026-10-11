import QtQuick
import Quickshell
import "ui"
import "ui/Performance.js" as Performance

// Escenario con backend real y HTTP/SSE local. Nunca inicia OAuth ni un modelo.
ShellRoot {
    id: test
    property int stage: 0
    property string savedChatId: ""
    AgentBridge {
        id: agent
        onEventReceived: event => {
            if (event.type === "auth.refresh.finished" && test.stage === 0) {
                if (!agent.canSend || !agent.appVersion || agent.availableModels.count !== 2) {
                    test.fail("cuenta o versión ausente");
                    return;
                }
                agent.planConnected(); // Comprueba también el diálogo de uso del plan.
                test.stage = 1;
                agent.submit("hola");
            } else if (event.type === "chat.finished" && test.stage === 1) {
                if (agent.busy || agent.messages.count !== 2
                    || agent.messages.get(1).body !== "Hola desde ChatGPT. 🎵"
                    || !agent.messages.get(1).performanceJson
                    || agent.latestPerformance.status !== "completed"
                    || agent.latestPerformance.first_text_ms === null
                    || agent.latestPerformance.usage.output_tokens !== 8) {
                    test.fail("respuesta o reconciliación de deltas incorrecta");
                    return;
                }
                test.savedChatId = agent.currentChatId;
                test.stage = 2;
                nextRun.start();
            } else if (event.type === "chat.delta" && test.stage === 2) {
                test.stage = 3;
                agent.cancel();
            } else if (event.type === "chat.finished" && test.stage === 3) {
                if (event.data.status !== "interrupted" || agent.busy) {
                    test.fail("cancelación incorrecta");
                    return;
                }
                test.stage = 4;
                agent.newChat();
            } else if (event.type === "chat.reset" && test.stage === 4) {
                if (agent.messages.count !== 0) test.fail("historial no vaciado");
                else {
                    test.stage = 5;
                    agent.openChat(test.savedChatId);
                }
            } else if (event.type === "chat.loaded" && test.stage === 5) {
                if (agent.messages.count !== 4 || !agent.historyDirectory
                    || agent.currentChatId !== test.savedChatId
                    || agent.latestPerformance.chat_id !== test.savedChatId
                    || agent.latestPerformance.turn_id !== event.data.chat.performance[event.data.chat.performance.length - 1].turn_id
                    || agent.messages.get(1).body !== "Hola desde ChatGPT. 🎵") {
                    test.fail("historial no restaurado");
                } else {
                    if (!agent.messages.get(1).performanceJson || !agent.messages.get(3).performanceJson) {
                        test.fail("mediciones no restauradas");
                        return;
                    }
                    test.stage = 6;
                    chatWindow.openPerformance();
                }
            } else if (event.type === "performance.list" && test.stage === 6) {
                const summary = agent.modelPerformance[0];
                if (agent.performanceHistory.length !== 2 || summary.completed !== 1
                    || summary.interrupted !== 1 || summary.totalP95 !== null
                    || summary.totalMedian === null) {
                    test.fail("historial o comparación de rendimiento incorrectos");
                    return;
                }
                const samples = [];
                for (let i = 1; i <= 20; ++i)
                    samples.push({ model: "test", status: "completed", first_text_ms: i, total_ms: i * 10 });
                samples.push({ model: "test", status: "failed", first_text_ms: 999, total_ms: 9999 });
                samples.push({ model: "test", status: "completed", tool_calls: 1, first_text_ms: 999, total_ms: 9999 });
                const statistics = Performance.models(samples)[0];
                if (statistics.totalMedian !== 105 || statistics.totalP95 !== 190 || statistics.failed !== 1 || statistics.agentTurns !== 1) {
                    test.fail("estadísticas mezclan fallos o calculan mal p95");
                    return;
                }
                chatWindow.showPerformance(agent.performanceHistory[0]);
                finishRun.start();
            } else if (event.type === "chat.deleted" && test.stage === 7) {
                if (event.data.chat_id !== test.savedChatId || agent.deletingChatId
                    || agent.currentChatId || agent.messages.count || agent.conversations.count
                    || agent.performanceHistory.length || agent.framePending || !agent.canSend) {
                    test.fail("borrado no limpia conversación, historial o mediciones");
                    return;
                }
                test.stage = 8;
            } else if (event.type === "performance.list" && test.stage === 8) {
                if (agent.performanceHistory.length || agent.modelPerformance.length)
                    test.fail("mediciones borradas reaparecen");
                else {
                    test.stage = 9;
                    agent.configureShell(agent.workspace);
                }
            } else if (event.type === "shell.state" && test.stage === 9) {
                if (!agent.shellEnabled || !agent.workspace) { test.fail("terminal no activada"); return; }
                test.stage = 11;
                agent.submit("shell-pwd");
            } else if (event.type === "chat.finished" && test.stage === 11) {
                if (event.data.status !== "completed" || agent.messages.count !== 3
                    || !agent.messages.get(1).toolJson || agent.messages.get(2).body.indexOf(agent.workspace) < 0
                    || JSON.parse(agent.messages.get(1).toolJson).status !== "completed"
                    || agent.latestPerformance.model_calls !== 2 || agent.latestPerformance.tool_calls !== 1
                    || agent.modelPerformance[0].agentTurns !== 1 || agent.modelPerformance[0].totalMedian !== null) {
                    test.fail("ciclo de shell o métricas incorrectos"); return;
                }
                test.savedChatId = agent.currentChatId;
                test.stage = 12;
                agent.newChat();
            } else if (event.type === "chat.reset" && test.stage === 12) {
                test.stage = 13;
                agent.openChat(test.savedChatId);
            } else if (event.type === "chat.loaded" && test.stage === 13) {
                if (agent.messages.count !== 3 || JSON.parse(agent.messages.get(1).toolJson).status !== "completed") {
                    test.fail("shell no restaurada"); return;
                }
                test.stage = 14;
                agent.configureShell(agent.workspace);
            } else if (event.type === "shell.state" && test.stage === 14) {
                if (!agent.shellEnabled) { test.fail("terminal dejó de estar disponible"); return; }
                test.stage = 15;
                agent.submit("continúa");
            } else if (event.type === "chat.finished" && test.stage === 15) {
                if (event.data.status !== "completed" || agent.messages.count !== 5)
                    test.fail("continuación tras shell incorrecta");
                else {
                    console.log("SMOKE_OK: cuenta, modelos, HTTP/SSE, cancelación, historial, rendimiento, borrado y shell automática con recuperación");
                    Qt.quit();
                }
            } else if (event.type === "error" || event.type === "backend.disconnected") {
                test.fail(event.data.message);
            }
        }
    }
    Timer {
        id: nextRun
        interval: 100
        onTriggered: {
            if (agent.latestPerformance.first_visible_ms === null || agent.latestPerformance.ui_frame_ms === null)
                test.fail("presentación del primer texto no medida");
            else agent.submit("cancel");
        }
    }
    Timer {
        id: finishRun
        interval: 100
        onTriggered: {
            test.stage = 7;
            agent.deleteChat(test.savedChatId);
        }
    }
    ChatWindow { id: chatWindow; bridge: agent }
    function fail(message) {
        console.error("SMOKE_FAILED: " + message);
        Qt.quit();
    }
}
