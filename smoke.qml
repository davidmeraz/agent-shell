import QtQuick
import Quickshell
import "ui"

// Escenario de prueba con App Server simulado. Nunca inicia OAuth ni un modelo.
ShellRoot {
    id: test
    property int stage: 0
    property string savedChatId: ""
    AgentBridge {
        id: agent
        onEventReceived: event => {
            if (event.type === "auth.state" && test.stage === 0) {
                if (!agent.authenticated || !agent.appVersion) {
                    test.fail("cuenta o versión ausente");
                    return;
                }
                test.stage = 1;
                agent.submit("hola");
            } else if (event.type === "chat.finished" && test.stage === 1) {
                if (agent.busy || agent.messages.count !== 2
                    || agent.messages.get(1).body !== "Hola desde Codex. 🎵") {
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
                    || agent.messages.get(1).body !== "Hola desde Codex. 🎵") {
                    test.fail("historial no restaurado");
                } else {
                    console.log("SMOKE_OK: cuenta, chat, streaming, cancelación e historial persistente (Codex simulado)");
                    Qt.quit();
                }
            } else if (event.type === "error" || event.type === "backend.disconnected") {
                test.fail(event.data.message);
            }
        }
    }
    Timer { id: nextRun; interval: 50; onTriggered: agent.submit("cancel") }
    ChatWindow { bridge: agent }
    function fail(message) {
        console.error("SMOKE_FAILED: " + message);
        Qt.quit();
    }
}
