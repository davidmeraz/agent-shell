import QtQuick
import QtTest
import Quickshell
import "../../ui"

// Modo unificado con datos inyectados: equipo, tres tarjetas de uso y regreso a la ventana única.
ShellRoot {
    id: scenario
    property int stage: 0
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 820; implicitHeight: 760 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }

    function check(value, message) {
        if (value) return true;
        console.error("UNIFIED_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function worker(provider, name, remaining) {
        return { provider: provider, model: name, name: name, effort: "medium", remaining: remaining };
    }
    function limit(used, minutes) {
        return { used_percent: used, window_minutes: minutes, resets_at: Date.now() / 1000 + 9000 };
    }
    function usage(id, name, used) {
        return { error: "", checked_at: "now", limits: [{ id: id, name: name, description: "",
            primary: limit(used, 300), secondary: limit(used + 10, 10080) }] };
    }
    function receive(type, data) {
        agent.receive(JSON.stringify({ version: 2, type: type, data: data }));
    }
    function publishTeam(architect) {
        receive("provider.state", { provider: "chatgpt", agy_available: true,
            claude_available: true, claude_authenticated: true, unified_mode: true,
            unified_architect: architect,
            unified_team: [{ level: "simple", workers: [worker("chatgpt", "GPT-6-Luna", 74)] },
                { level: "standard", workers: [worker("agy", "Claude Sonnet 5.5", 98)] },
                { level: "hard", workers: [] }] });
    }
    Timer {
        id: steps
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (stage === 0) {
                if (!agent.canSend || !chat.usageWindow.visible) return;
                // La consulta real devolvería el estado del backend de prueba, que no tiene CLIs.
                agent.teamUsageBusy = true;
                publishTeam(worker("claude", "Claude Opus", 90));
                const both = usage("gemini", "Gemini Models", 85);
                both.limits.push(usage("claude-gpt", "Claude and GPT models", 2).limits[0]);
                agent.providerUsage = { chatgpt: usage("codex", "codex", 3), agy: both };
            } else if (stage === 1) {
                const cards = chat.unifiedUsage.cards;
                const pill = inspector.findChild(chat, "chatUnifiedArchitect");
                const label = inspector.findChild(chat, "chatUnifiedArchitectName");
                if (!check(pill && pill.visible && label && label.text.indexOf(agent.unifiedArchitect.name) >= 0
                    && label.text.indexOf("Claude") >= 0 && label.text.indexOf(agent.unifiedArchitect.effort) >= 0, "arquitecto o motor incorrecto")) return;
                const composer = inspector.findChild(chat, "chatComposer");
                const prompt = inspector.findChild(chat, "chatPrompt");
                const send = inspector.findChild(chat, "chatSendButton");
                prompt.text = "/mode";
                if (!check(!composer.completions.some(option => option.value === "/modelos"), "/modelos ofrecido en modo unificado")) return;
                prompt.text = "/modelos";
                composer.send();
                if (!check(!composer.modelMode && prompt.text === "/modelos"
                    && agent.status.indexOf("solo lectura") >= 0, "/modelos abre el selector")) return;
                prompt.text = "";
                if (!check(!send.enabled, "permite enviar sin contenido")) return;
                prompt.text = "Un borrador";
                agent.availableModels.clear();
                if (!check(send.enabled, "exige el catálogo manual aunque hay arquitecto")) return;
                const architect = agent.unifiedArchitect;
                agent.unifiedArchitect = ({});
                if (!check(!send.enabled, "permite enviar sin arquitecto")) return;
                agent.unifiedArchitect = architect;
                prompt.text = "";
                receive("chat.delta", { item_id: "test", text: "Respuesta de prueba" });
                if (!check(agent.status.indexOf("Claude") >= 0, "atribuye la respuesta al motor manual")) return;
                receive("chat.finished", { status: "completed" });
                publishTeam(worker("claude", "Claude Opus", 89));
                if (!check(agent.status === "Respuesta completada.", "el sondeo borra el estado del turno")) return;
                if (!check(!chat.usageWindow.visible && cards.every(card => card.visible), "no hay tres tarjetas")) return;
                if (!check(new Set(cards.map(card => card.implicitHeight)).size === 1, "alturas distintas")) return;
                if (!check(inspector.findChild(chat, "unifiedWorkerName_simple").text.indexOf("GPT-6-Luna") >= 0
                    && inspector.findChild(chat, "unifiedWorkerName_hard").text === "Sin obrero disponible", "equipo incorrecto")) return;
                if (!check(cards[1].limits.length === 1, "Gemini no arranca contraído")) return;
                if (!check(inspector.findChild(cards[2], "providerUsageNotice_claude").text === "Consultando uso…", "sin estado de carga")) return;
                cards[1].geminiOnly = false;
                agent.receive(JSON.stringify({ version: 2, type: "usage.provider", data: { provider: "chatgpt", error: "Sin conexión" } }));
                agent.receive(JSON.stringify({ version: 2, type: "unified.worker",
                    data: { active: true, level: "simple", worker: worker("agy", "Gemini 3.8 Flash", 12) } }));
            } else if (stage === 2) {
                const cards = chat.unifiedUsage.cards;
                if (!check(cards[1].limits.length === 2 && new Set(cards.map(card => card.implicitHeight)).size === 1
                    && cards[0].implicitHeight >= cards[1].naturalHeight, "expandir no iguala la fila")) return;
                if (!check(cards[0].hasData && cards[0].usage.error === "Sin conexión", "un error borra la última medición")) return;
                if (!check(inspector.findChild(cards[1], "providerUsageRole_agy").text === "Trabajando"
                    && inspector.findChild(chat, "unifiedWorkerName_simple").text.indexOf("Gemini 3.8 Flash") >= 0, "obrero activo no visible")) return;
                cards[2].dismissed();
                if (!check(!cards[2].visible && cards[0].visible, "cerrar una tarjeta afecta a las demás")) return;
                chat.openUsage();
                if (!check(cards[2].visible, "el acceso al uso no reabre las tarjetas")) return;
                agent.unifiedMode = false;
            } else {
                if (!check(chat.usageWindow.visible && chat.unifiedUsage.cards.every(card => !card.visible), "no vuelve la ventana única")) return;
                const composer = inspector.findChild(chat, "chatComposer");
                composer.openModels();
                if (!check(composer.modelMode, "no vuelve el selector de modelos manual")) return;
                console.log("UNIFIED_OK: arquitecto automático, selector bloqueado, envío, equipo y tarjetas de uso");
                steps.stop(); Qt.quit();
            }
            ++stage;
        }
    }
    Timer { interval: 8000; running: true; onTriggered: scenario.check(false, "Tiempo agotado en etapa " + scenario.stage) }
}
