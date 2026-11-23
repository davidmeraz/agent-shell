import QtQuick
import QtTest
import AgentShell.Native
import "../../ui"

// Modo unificado con datos inyectados: equipo, tres tarjetas de uso y regreso a la ventana única.
NativeScope {
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
            unified_team: [{ role: "explorer", workers: [worker("chatgpt", "GPT-6-Luna", 74)] },
                { role: "builder", workers: [worker("agy", "Claude Sonnet 5.5", 98)] },
                { role: "specialist", workers: [] }] });
    }
    function subagent(id, role, status, extra) {
        receive("unified.agent", Object.assign({ id: id, turn_id: "t1", role: role, task: "Crear calc.py", status: status,
            worker: worker("agy", "Gemini 3.8 Flash", 12), lines: ["read_file calc.py"], tool_calls: 1, files_changed: [],
            tokens_used: 0, summary: "", error: "", started_at: Date.now() / 1000, duration_ms: 0 }, extra || {}));
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
                if (!check(inspector.findChild(chat, "unifiedWorkerName_explorer").text.indexOf("GPT-6-Luna") >= 0
                    && inspector.findChild(chat, "unifiedWorkerName_specialist").text === "No disponible", "equipo incorrecto")) return;
                if (!check(cards[1].limits.length === 1, "Gemini no arranca contraído")) return;
                if (!check(inspector.findChild(cards[2], "providerUsageNotice_claude").text === "Consultando uso…", "sin estado de carga")) return;
                cards[1].geminiOnly = false;
                agent.receive(JSON.stringify({ version: 2, type: "usage.provider", data: { provider: "chatgpt", error: "Sin conexión" } }));
                if (!check(chat.agentWindows.cards.every(card => !card.visible), "hay subagentes sin delegar")) return;
                receive("chat.busy", { turn_id: "t1" });
                receive("chat.finished", { status: "completed" });
                const state = inspector.findChild(chat, "unifiedArchitectState");
                if (!check(state.text === "ARQUITECTO · SIN DELEGAR", "no avisa que el arquitecto no delegó: " + state.text)) return;
                receive("chat.busy", { turn_id: "t2" });
                subagent("a1", "explorer", "running");
            } else if (stage === 2) {
                const cards = chat.unifiedUsage.cards;
                if (!check(cards[1].limits.length === 2 && new Set(cards.map(card => card.implicitHeight)).size === 1
                    && cards[0].implicitHeight >= cards[1].naturalHeight, "expandir no iguala la fila")) return;
                if (!check(cards[0].hasData && cards[0].usage.error === "Sin conexión", "un error borra la última medición")) return;
                if (!check(inspector.findChild(cards[1], "providerUsageRole_agy").text === "Trabajando"
                    && inspector.findChild(chat, "unifiedWorkerName_explorer").text.indexOf("Gemini 3.8 Flash") >= 0, "obrero activo no visible")) return;
                const [explorer, builder, specialist, reviewer] = chat.agentWindows.cards;
                if (!check(explorer.visible && !builder.visible && !specialist.visible && !reviewer.visible,
                    "no aparece solo la ventana del subagente usado")) return;
                if (!check(explorer.width >= 500 && explorer.height >= 300 && (explorer.flags & Qt.ToolTip) !== Qt.ToolTip,
                    "la ventana no es flotante o es pequeña")) return;
                if (!check(inspector.findChild(explorer, "agentModel_explorer").text.indexOf("Gemini 3.8 Flash") >= 0
                    && inspector.findChild(explorer, "agentActivity_explorer").model.get(0).target === "calc.py"
                    && !explorer.showReport
                    && inspector.findChild(explorer, "agentState_explorer").text === "Trabajando", "actividad en vivo ausente")) return;
                const many = Array.from({ length: 40 }, (_, i) => "read_file f" + i);
                subagent("a1", "explorer", "running", { lines: many });
                subagent("a1", "explorer", "running", { lines: many.slice(1).concat("apply_patch z.py") });
                const activity = inspector.findChild(explorer, "agentActivity_explorer");
                if (!check(activity.count === 40 && activity.model.get(39).verb === "Editó" && activity.model.get(39).target === "z.py",
                    "la línea de tiempo pierde o repite acciones")) return;
                subagent("a1", "explorer", "completed", { summary: "Todo claro", duration_ms: 65000 });
                subagent("a2", "builder", "running");
                subagent("a3", "builder", "failed", { error: "Sin permiso" });
                if (!check(inspector.findChild(explorer, "agentState_explorer").text === "Listo"
                    && explorer.elapsedText === "1 min 5 s" && explorer.showReport && explorer.outcome === "✓"
                    && inspector.findChild(explorer, "agentReport_explorer").text === "Todo claro"
                    && builder.visible && builder.slot === 1
                    && inspector.findChild(builder, "agentTitle_builder").text === "Constructor ×2"
                    && inspector.findChild(builder, "agentReport_builder").text === "Sin permiso", "resultado o apilado incorrecto")) return;
                explorer.dismissed();
                if (!check(!explorer.wanted && builder.wanted, "cerrar un subagente afecta a otro")) return;
                receive("chat.finished", { status: "completed" });
                if (!check(builder.visible && inspector.findChild(chat, "unifiedArchitectState").text === "ARQUITECTO · 3 DELEGACIONES",
                    "las ventanas no permanecen al terminar o la cuenta es incorrecta")) return;
                receive("chat.busy", { turn_id: "t3" });
                if (!check(!agent.agents.length && !builder.wanted && builder.shown, "un turno nuevo conserva subagentes anteriores")) return;
                receive("chat.finished", { status: "completed" });
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
