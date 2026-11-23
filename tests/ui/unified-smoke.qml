import QtQuick
import QtTest
import AgentShell.Native
import "../../ui"

// Modo unificado: cascada con umbral 35%, 2 obreros (ChatGPT y Claude) en paralelo, tarjetas de uso y configuración.
NativeScope {
    id: scenario
    property int stage: 0
    property bool prepareRequested: false
    AgentBridge {
        id: agent
        // El escenario inyecta provider.state; el backend real no está en modo unificado.
        function prepareUnified() { scenario.prepareRequested = true; }
    }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 820; implicitHeight: 760 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }

    function check(value, message) {
        if (value) return true;
        console.error("UNIFIED_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    // Repeater inserta sus delegados en el árbol visual, no en el árbol de QObject.
    function findVisualChild(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const match = findVisualChild(child, name);
            if (match) return match;
        }
        return null;
    }
    function worker(provider, name, remaining, effort) {
        return { provider: provider, model: name, name: name, effort: effort || "medium", remaining: remaining };
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
        receive("provider.state", {
            provider: "chatgpt", agy_available: true,
            claude_available: true, claude_authenticated: true, unified_mode: true,
            unified_architect: architect,
            unified_cascade: [
                { provider: "agy", model: "gemini-4-neon-xhigh", name: "Gemini 4 Neon", effort: "xhigh", remaining: 76, available: true, active: architect.provider === "agy", below_threshold: false },
                { provider: "claude", model: "claude-opus", name: "Claude Opus 5.5", effort: "xhigh", remaining: 88, available: true, active: architect.provider === "claude", below_threshold: false },
                { provider: "chatgpt", model: "gpt-6.2-astra", name: "GPT-6.2-Astra", effort: "high", remaining: 94, available: true, active: architect.provider === "chatgpt", below_threshold: false }
            ],
            unified_config: {
                quota_threshold: 35,
                parallel_workers: true,
                architect_cascade: [
                    { provider: "agy", model: "gemini-4-neon-xhigh", effort: "xhigh" },
                    { provider: "claude", model: "claude-opus", effort: "xhigh" },
                    { provider: "chatgpt", model: "gpt-6.2-astra", effort: "high" }
                ],
                workers: [
                    { slot: "chatgpt", provider: "chatgpt", model: "", effort: "medium", tier: "balanced" },
                    { slot: "claude", provider: "claude", model: "", effort: "medium", tier: "balanced" }
                ]
            },
            provider_catalogs: {
                agy: [{ slug: "gemini-4-neon-xhigh", display_name: "Gemini 4 Neon (XHigh)" }],
                claude: [{ slug: "claude-opus", display_name: "Claude Opus" }, { slug: "claude-sonnet", display_name: "Claude Sonnet" }],
                chatgpt: [{ slug: "gpt-6.2-astra", display_name: "GPT-6.2-Astra" }, { slug: "gpt-6.1-terra", display_name: "GPT-6.1-Terra" }]
            },
            unified_team: [
                { role: "chatgpt", slot: "chatgpt", provider: "chatgpt", workers: [worker("chatgpt", "GPT-6.1-Terra", 74, "medium")] },
                { role: "claude", slot: "claude", provider: "claude", workers: [worker("claude", "Claude Sonnet 5.5", 88, "medium")] }
            ]
        });
    }
    function subagent(id, role, status, workerObj, extra) {
        receive("unified.agent", Object.assign({
            id: id, turn_id: "t1", role: role, task: "Crear calc.py", status: status,
            worker: workerObj || worker(role, role === "chatgpt" ? "GPT-6.1-Terra" : "Claude Sonnet 5.5", 74),
            lines: ["read_file calc.py"], tool_calls: 1, files_changed: [],
            tokens_used: 0, summary: "", error: "", started_at: Date.now() / 1000, duration_ms: 0
        }, extra || {}));
    }
    Timer {
        id: steps
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (stage === 0) {
                if (!agent.canSend || !chat.usageWindow.visible) return;
                agent.teamUsageBusy = true;
                publishTeam(worker("agy", "Gemini 4 Neon", 76, "xhigh"));
                const both = usage("gemini", "Gemini Models", 24);
                both.limits.push(usage("claude-gpt", "Claude and GPT models", 62).limits[0]);
                agent.providerUsage = { chatgpt: usage("codex", "codex", 6), agy: both };
            } else if (stage === 1) {
                const cards = chat.unifiedUsage.cards;
                const pill = inspector.findChild(chat, "chatUnifiedArchitect");
                const label = inspector.findChild(chat, "chatUnifiedArchitectName");
                if (!check(pill && pill.visible && label && label.text.indexOf("Gemini 4 Neon") >= 0
                    && label.text.indexOf("xhigh") >= 0, "arquitecto o esfuerzo incorrecto")) return;
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
                if (!check(agent.status.indexOf("Antigravity") >= 0, "atribuye la respuesta al motor manual")) return;
                receive("chat.finished", { status: "completed" });
                publishTeam(worker("agy", "Gemini 4 Neon", 75, "xhigh"));
                if (!check(agent.status === "Respuesta completada.", "el sondeo borra el estado del turno")) return;
                if (!check(!chat.usageWindow.visible && cards.every(card => card.visible), "no hay tres tarjetas")) return;
                if (!check(new Set(cards.map(card => card.implicitHeight)).size === 1, "alturas distintas")) return;
                const chatgptWorker = findVisualChild(chat.contentItem, "unifiedWorkerName_chatgpt");
                const claudeWorker = findVisualChild(chat.contentItem, "unifiedWorkerName_claude");
                if (!check(chatgptWorker && chatgptWorker.text.indexOf("GPT-6.1-Terra") >= 0
                    && claudeWorker && claudeWorker.text.indexOf("Claude Sonnet 5.5") >= 0, "obreros dedicados incorrectos")) return;
                const badge = inspector.findChild(chat, "unifiedThresholdBadge");
                if (!check(badge && badge.text.indexOf("35%") >= 0, "umbral 35% ausente en UnifiedTeam")) return;
                if (!check(cards[1].limits.length === 1, "Gemini no arranca contraído")) return;
                if (!check(inspector.findChild(cards[2], "providerUsageNotice_claude").text === "Consultando uso…", "sin estado de carga")) return;
                cards[1].geminiOnly = false;
                agent.receive(JSON.stringify({ version: 2, type: "usage.provider", data: { provider: "chatgpt", error: "Sin conexión" } }));
                if (!check(chat.agentWindows.cards.every(card => !card.visible), "hay subagentes sin delegar")) return;
                receive("chat.busy", { turn_id: "t1" });
                receive("chat.finished", { status: "completed" });
                const state = inspector.findChild(chat, "unifiedArchitectState");
                if (!check(state.text === "ARQUITECTO · SIN DELEGAR", "no avisa que el arquitecto no delegó: " + state.text)) return;
                // Lanzar ambos obreros (ChatGPT y Claude) en paralelo
                receive("chat.busy", { turn_id: "t2" });
                subagent("a1", "chatgpt", "running", worker("chatgpt", "GPT-6.1-Terra", 74, "medium"));
                subagent("a2", "claude", "running", worker("claude", "Claude Sonnet 5.5", 88, "medium"));
            } else if (stage === 2) {
                const cards = chat.unifiedUsage.cards;
                if (!check(cards[1].limits.length === 2 && new Set(cards.map(card => card.implicitHeight)).size === 1
                    && cards[0].implicitHeight >= cards[1].naturalHeight, "expandir no iguala la fila")) return;
                if (!check(cards[0].hasData && cards[0].usage.error === "Sin conexión", "un error borra la última medición")) return;
                // Ambos proveedores marcan "Trabajando" simultáneamente
                if (!check(inspector.findChild(cards[0], "providerUsageRole_chatgpt").text === "Trabajando"
                    && inspector.findChild(cards[2], "providerUsageRole_claude").text === "Trabajando",
                    "obreros en paralelo no aparecen activos en sus tarjetas de uso")) return;
                const [chatgptWin, claudeWin, agyWin] = chat.agentWindows.cards;
                if (!check(chatgptWin.visible && claudeWin.visible && !agyWin.visible,
                    "no aparecen exactamente los dos obreros usados en paralelo")) return;
                if (!check(chatgptWin.width >= 440 && chatgptWin.height >= 360 && !chatgptWin.compact
                    && claudeWin.width >= 440 && claudeWin.height >= 360 && !claudeWin.compact
                    && (chatgptWin.flags & Qt.ToolTip) !== Qt.ToolTip,
                    "las dos ventanas paralelas no arrancan expandidas")) return;
                if (!check(inspector.findChild(chatgptWin, "agentModel_chatgpt").text.indexOf("GPT-6.1-Terra") >= 0
                    && inspector.findChild(claudeWin, "agentModel_claude").text.indexOf("Claude Sonnet 5.5") >= 0
                    && inspector.findChild(chatgptWin, "agentActivity_chatgpt").model.get(0).target === "calc.py"
                    && !chatgptWin.showReport
                    && inspector.findChild(chatgptWin, "agentState_chatgpt").text === "Trabajando", "actividad en vivo ausente")) return;
                const many = Array.from({ length: 40 }, (_, i) => "read_file f" + i);
                subagent("a1", "chatgpt", "running", worker("chatgpt", "GPT-6.1-Terra", 74), { lines: many });
                subagent("a1", "chatgpt", "running", worker("chatgpt", "GPT-6.1-Terra", 74), { lines: many.slice(1).concat("apply_patch z.py") });
                const activity = inspector.findChild(chatgptWin, "agentActivity_chatgpt");
                if (!check(activity.count === 40 && activity.model.get(39).verb === "Editó" && activity.model.get(39).target === "z.py",
                    "la línea de tiempo pierde o repite acciones")) return;
                // ChatGPT termina primero mientras Claude sigue trabajando -> ChatGPT se compacta, Claude sigue expandido
                subagent("a1", "chatgpt", "completed", worker("chatgpt", "GPT-6.1-Terra", 74), { summary: "Todo claro", duration_ms: 65000 });
                if (!check(chatgptWin.compact && chatgptWin.height <= 140
                    && !claudeWin.compact && claudeWin.height >= 360,
                    "el obrero terminado no se compacta mientras el otro sigue trabajando")) return;
                chatgptWin.toggleCompact();
                if (!check(!chatgptWin.compact && chatgptWin.height >= 360,
                    "expandir manualmente el obrero terminado no restaura su altura")) return;
                subagent("a3", "claude", "failed", worker("claude", "Claude Sonnet 5.5", 88), { error: "Sin permiso" });
                if (!check(inspector.findChild(chatgptWin, "agentState_chatgpt").text === "Listo"
                    && chatgptWin.elapsedText === "1 min 5 s" && chatgptWin.showReport && chatgptWin.outcome === "✓"
                    && inspector.findChild(chatgptWin, "agentReport_chatgpt").text === "Todo claro"
                    && claudeWin.visible && claudeWin.slot === 1
                    && inspector.findChild(claudeWin, "agentTitle_claude").text === "Obrero Claude ×2"
                    && inspector.findChild(claudeWin, "agentReport_claude").text === "Sin permiso", "resultado o apilado incorrecto")) return;
                chatgptWin.dismissed();
                if (!check(!chatgptWin.wanted && claudeWin.wanted, "cerrar un obrero afecta al otro")) return;
                receive("chat.finished", { status: "completed" });
                if (!check(claudeWin.visible && inspector.findChild(chat, "unifiedArchitectState").text === "ARQUITECTO · 3 DELEGACIONES",
                    "las ventanas no permanecen al terminar o la cuenta es incorrecta")) return;
                // Abrir el diálogo de configuración unificada desde el botón ⚙
                const configBtn = inspector.findChild(chat, "unifiedConfigButton");
                if (!check(configBtn && configBtn.visible, "falta botón de configuración en UnifiedTeam")) return;
                configBtn.clicked();
            } else if (stage === 3) {
                const dlg = inspector.findChild(chat, "unifiedConfigDialog");
                if (!check(dlg && dlg.visible && prepareRequested, "el diálogo no se abrió o no solicitó sus catálogos")) return;
                const thresholdInput = inspector.findChild(dlg, "unifiedThresholdInput");
                if (!check(thresholdInput && thresholdInput.text === "35", "el umbral inicial no es 35")) return;
                dlg.close();
                receive("chat.busy", { turn_id: "t3" });
                const [, claudeWin] = chat.agentWindows.cards;
                if (!check(!agent.agents.length && !claudeWin.wanted && claudeWin.shown, "un turno nuevo conserva obreros anteriores")) return;
                receive("chat.finished", { status: "completed" });
                const cards = chat.unifiedUsage.cards;
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
                console.log("UNIFIED_OK: cascada 35%, 2 obreros en paralelo, ventanas flotantes y diálogo de configuración");
                steps.stop(); Qt.quit();
            }
            ++stage;
        }
    }
    Timer { interval: 10000; running: true; onTriggered: scenario.check(false, "Tiempo agotado en etapa " + scenario.stage) }
}
