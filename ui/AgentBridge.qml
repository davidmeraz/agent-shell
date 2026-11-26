import QtQuick
import AgentShell.Native
import "js/Performance.js" as Performance
import "js/ChatCommands.js" as ChatCommands

// Estado del chat. Python administra la sesión y el streaming directo con ChatGPT.
QtObject {
    id: bridge
    property bool ready: false
    property bool authenticated: false
    property string provider: "chatgpt"
    property bool agyAvailable: false
    property bool claudeAvailable: false
    property bool claudeAuthenticated: false
    property string claudeEmail: ""
    property string claudePlan: ""
    property bool claudeLoginBusy: false
    property bool providerBusy: false
    property bool unifiedMode: false
    property var unifiedArchitect: ({})
    property var unifiedCascade: []
    property var unifiedTeam: []
    property var unifiedConfig: ({})
    property string unifiedConfigError: ""
    property var providerCatalogs: ({})
    property var resolvedModels: ({})
    // Subagentes del turno actual o del último; `agentTurn` indica que hubo un turno unificado.
    property var agents: []
    property bool agentTurn: false
    readonly property var activeAgents: agents.filter(agent => agent.status === "running")
    readonly property var activeAgent: activeAgents.length ? activeAgents[0] : null
    property var providerUsage: ({})
    property bool teamUsageBusy: false
    readonly property bool engineReady: unifiedMode ? !!unifiedArchitect.model : (provider === "agy" && agyAvailable)
                                        || (provider === "claude" && claudeAvailable && claudeAuthenticated)
                                        || (provider === "chatgpt" && authenticated)
    property bool busy: false
    property bool loginBusy: false
    property bool accountBusy: false
    property bool usageBusy: false
    property bool backendUsageBusy: false
    property string activeBackendUsageId: ""
    property bool usageRetryPending: false
    property var accountUsage: ({})
    property string usageError: ""
    property string usageRequestId: ""
    property int usageSequence: 0
    property string usageAccountKey: ""
    property bool planEnabled: false
    property bool historyReady: false
    property bool openingChat: false
    property string deletingChatId: ""
    readonly property bool shellEnabled: true
    property string workspace: ""
    property int agentShellTimeout: 300
    property string activeArea: "chat"
    property string projectId: ""
    property string projectName: ""
    property string projectEngine: "python"
    property bool projectDesktopInstalled: false
    property bool projectHasRunScript: false
    property bool projectHasCheckScript: false
    property bool projectFolderExists: true
    property bool areaBusy: false
    property string areaError: ""
    property var projectRun: ({})
    property bool projectRunPending: false
    property string projectRunNotice: ""
    property var projectRunCaches: ({})
    readonly property bool projectRunActive: projectRunPending || ["preparing", "inspecting", "starting", "running", "stopping"].indexOf(projectRun.phase) >= 0
    readonly property bool projectRunHere: !!projectId && projectRun.project_id === projectId
    readonly property bool projectRunPreparing: projectRunActive && projectRun.phase !== "running"
    readonly property string areaKey: activeArea === "chat" ? "chat" : activeArea + ":" + projectId
    readonly property bool workspaceSelected: activeArea === "chat" || !!projectId
    property int shellTimeout: 120
    property string limitsProfile: "equilibrado"
    property int compactThresholdTokens: 60000
    property int maxCompactions: 3
    property int maxTurnBillableTokens: 0
    property int maxTurnTokens: 0
    property int maxSteps: 32
    property int maxToolCalls: 64
    property int contextOutputChars: 6000
    property int chatCompactionCount: 0
    property string limitsError: ""
    property string status: "Preparando Agent Shell…"
    property string appVersion: ""
    property string displayName: ""
    property string profileError: ""
    property string email: ""
    property string plan: ""
    property string modelName: ""
    property string reasoningEffort: ""
    property string authUrl: ""
    property string historyDirectory: ""
    property string currentChatId: ""
    property string currentTitle: ""
    property var messageRows: ({})
    property var pendingTextUpdates: ({})
    property var performanceHistory: []
    property bool performanceBusy: false
    property var latestPerformance: ({})
    property var chatQuota: ({})
    property bool chatQuotaMeasuring: false
    property string activeTurnId: ""
    property bool shellRunning: false
    property double submittedAt: 0
    property double firstReceivedAt: 0
    property bool framePending: false
    property int clipboardSequence: 0
    readonly property var modelPerformance: Performance.models(performanceHistory)
    readonly property ListModel messages: ListModel {}
    readonly property ListModel conversations: ListModel {}
    readonly property ListModel projects: ListModel {}
    readonly property ListModel apps: ListModel {}
    readonly property ListModel availableModels: ListModel {}
    readonly property ListModel registeredAccounts: ListModel {}
    property int activeAccountIndex: -1
    readonly property bool canBrowseHistory: historyReady && !busy && !loginBusy && !claudeLoginBusy && !openingChat && !deletingChatId && !areaBusy
    readonly property bool canSelectArea: ready && canBrowseHistory && !accountBusy && !providerBusy
    readonly property bool canSend: ready && engineReady && (unifiedMode || availableModels.count > 0)
                                   && !busy && !loginBusy && !claudeLoginBusy && !accountBusy && !providerBusy && !openingChat && !deletingChatId && !areaBusy && workspaceSelected
    readonly property bool canRunShell: ready && historyReady && !busy && !loginBusy && !claudeLoginBusy && !accountBusy && !providerBusy
                                      && !openingChat && !deletingChatId && !areaBusy && workspaceSelected
    readonly property bool canRunProject: canRunShell && (activeArea === "work" || activeArea === "app") && !!projectId && !projectRunActive
                                         && ((authenticated && availableModels.count > 0) || !!projectRunCaches[projectId])
    readonly property bool canTestApp: canRunShell && activeArea === "app" && !!projectId
    signal eventReceived(var event)
    signal conversationChanged()
    signal planConnected()
    signal localCommandRequested(string command)
    signal areaChanged(string previousKey, string currentKey)
    signal clipboardResult(var result)

    function sendCommand(command) {
        if (backend.running) backend.write(JSON.stringify(command) + "\n");
    }

    function refreshUsage() {
        if (!ready) return;
        if (usageBusy || backendUsageBusy || accountBusy || loginBusy || claudeLoginBusy || providerBusy) {
            usageRetryPending = true;
            return;
        }
        usageRetryPending = false;
        usageBusy = true;
        backendUsageBusy = true;
        usageError = "";
        usageRequestId = "usage-" + (++usageSequence);
        sendCommand({ type: "usage.read", request_id: usageRequestId });
    }

    function maybeRetryUsage() {
        if (usageRetryPending && ready && engineReady && !usageBusy && !backendUsageBusy
            && !accountBusy && !loginBusy && !claudeLoginBusy && !providerBusy) {
            refreshUsage();
        }
    }

    function pasteClipboard() {
        if (!ready) return "";
        const requestId = "clipboard-" + Date.now() + "-" + (++clipboardSequence);
        sendCommand({ type: "clipboard.paste", request_id: requestId });
        return requestId;
    }

    function submit(prompt, image = "") {
        const text = prompt.trim();
        const command = ChatCommands.parse(prompt);
        if (command) {
            if (unifiedMode && command.name === "/modelos") {
                status = "El modo unificado elige automáticamente el modelo del arquitecto.";
                return false;
            }
            const reason = command.error || ChatCommands.blockedReason(command.name, bridge);
            if (reason) { status = reason; return false; }
            if (command.name === "/shell") {
                submittedAt = Date.now();
                activeTurnId = "";
                framePending = false;
                shellRunning = true;
                busy = true;
                status = "Ejecutando comando local…";
                sendCommand({ type: "shell.execute", command: command.command });
                return true;
            }
            if (command.name === "/modelos" && command.family
                && !Array.from({length: availableModels.count}, (_, i) => availableModels.get(i).family).includes(command.family)) {
                status = "La familia solicitada no está disponible en tu cuenta.";
                return false;
            }
            if (command.name === "/modelos" && command.model) {
                for (let i = 0; i < availableModels.count; ++i) {
                    const model = availableModels.get(i);
                    if (model.slug === command.model && (!command.family || model.family === command.family)) {
                        const effort = command.effort === "auto" ? "" : command.effort;
                        if (command.hasEffort && effort && !JSON.parse(model.reasoningEfforts).includes(effort)) {
                            status = "Ese esfuerzo de razonamiento no está disponible para el modelo seleccionado.";
                            return false;
                        }
                        selectModel(command.model, command.hasEffort ? effort : undefined);
                        status = "Cambiando modelo y esfuerzo…";
                        return true;
                    }
                }
                status = "El modelo solicitado no está disponible en tu cuenta.";
                return false;
            }
            if (command.name === "/nuevo") newChat();
            else if (command.name === "/detener") cancel();
            else if (command.name === "/compact") compactChat();
            else localCommandRequested(command.name === "/modelos" && command.family
                                       ? "/modelos " + command.family : command.name);
            return true;
        }
        if (!canSend || (!text && !image)) return false;
        if (text.length > 16000) {
            status = "El mensaje puede tener como máximo 16000 caracteres.";
            return false;
        }
        submittedAt = Date.now();
        firstReceivedAt = 0;
        framePending = false;
        activeTurnId = "";
        latestPerformance = ({});
        messages.append({ author: "TÚ", body: text, imageUrl: image, turnId: "", performanceJson: "", toolJson: "" });
        busy = true;
        status = "Preparando la respuesta…";
        const request = { type: "chat.send", prompt: text };
        if (image) request.image = image;
        sendCommand(request);
        conversationChanged();
        return true;
    }

    function cancel() {
        if (!busy) return;
        status = shellRunning ? "Deteniendo comando local…" : "Deteniendo la respuesta…";
        sendCommand({ type: "chat.cancel" });
    }

    function newChat() {
        if (canBrowseHistory) sendCommand({ type: "chat.new" });
    }

    function compactChat() {
        if (!canSend || !currentChatId) return;
        busy = true;
        status = "Compactando contexto…";
        sendCommand({ type: "chat.compact" });
    }

    function selectArea(area, projectId) {
        if (!canSelectArea) return;
        areaBusy = true;
        areaError = "";
        const request = { type: "area.select", area: area };
        if (projectId !== undefined) request.project_id = projectId;
        sendCommand(request);
    }

    function createProject(name, workdir) {
        if (!canSelectArea) return;
        areaBusy = true;
        areaError = "";
        sendCommand({ type: "project.create", name: name, workdir: workdir });
    }

    function createApp(name, workdir, engine = "python") {
        if (!canSelectArea) return;
        areaBusy = true;
        areaError = "";
        sendCommand({ type: "app.create", name: name, workdir: workdir, engine: engine });
    }

    function deleteProject(projectId) {
        if (!canSelectArea || !projectId) return;
        areaBusy = true;
        areaError = "";
        status = activeArea === "app" ? "Eliminando aplicación…" : "Eliminando proyecto…";
        sendCommand({ type: activeArea === "app" ? "app.delete" : "project.delete", project_id: projectId });
    }

    function renameProject(projectId, name) {
        if (!canSelectArea || !projectId) return;
        areaBusy = true;
        areaError = "";
        sendCommand({ type: activeArea === "app" ? "app.rename" : "project.rename", project_id: projectId, name: name });
    }

    function testApp() {
        if (!canTestApp) return;
        testAppById(projectId);
    }

    function testAppById(targetId) {
        const id = targetId || projectId;
        if (!id || !ready || !historyReady || busy || loginBusy || claudeLoginBusy || accountBusy || providerBusy
            || openingChat || deletingChatId || areaBusy || activeArea !== "app")
            return;
        submittedAt = Date.now();
        activeTurnId = "";
        framePending = false;
        shellRunning = true;
        busy = true;
        status = "Probando aplicación Gema UI Kit…";
        sendCommand({ type: "app.test", project_id: id });
    }

    function canLaunchProjectId(targetId) {
        const id = targetId || projectId;
        if (!id || !ready || !historyReady || busy || loginBusy || claudeLoginBusy || accountBusy || providerBusy
            || openingChat || deletingChatId || areaBusy || projectRunActive)
            return false;
        return (authenticated && availableModels.count > 0) || !!projectRunCaches[id];
    }

    function runProject() {
        if (!canRunProject) return;
        runProjectById(projectId);
    }

    function runProjectById(targetId) {
        const id = targetId || projectId;
        if (!canLaunchProjectId(id)) return;
        projectRunPending = true;
        projectRunNotice = "";
        sendCommand({ type: "project.run", project_id: id });
    }

    function stopProject() {
        if (!projectRunActive || !projectRun.execution_id) return;
        sendCommand({ type: "project.run.stop", project_id: projectRun.project_id, execution_id: projectRun.execution_id });
    }

    function toggleAppDesktop(targetId, install) {
        const id = targetId || projectId;
        if (!canSelectArea || !id) return;
        areaError = "";
        const request = { type: "app.desktop", project_id: id };
        if (install !== undefined) request.install = !!install;
        sendCommand(request);
    }

    function _normalizeProjectRow(item) {
        return {
            projectId: item.project_id,
            name: item.name,
            workdir: item.workdir,
            engine: item.engine || "python",
            updatedAt: item.updated_at || "",
            createdAt: item.created_at || "",
            folderExists: item.folder_exists !== false,
            hasLaunchProfile: !!item.has_launch_profile,
            hasRunScript: !!item.has_run_script,
            hasCheckScript: !!item.has_check_script,
            hasGit: !!item.has_git,
            chatCount: item.chat_count || 0,
            desktopInstalled: !!item.desktop_installed
        };
    }

    function openChat(chatId) {
        if (!canBrowseHistory) return;
        openingChat = true;
        sendCommand({ type: "chat.open", chat_id: chatId });
    }

    function refreshHistory() {
        if (canBrowseHistory) sendCommand({ type: "history.list" });
    }

    function deleteChat(chatId) {
        if (!canBrowseHistory || !chatId) return;
        deletingChatId = chatId;
        status = "Borrando conversación…";
        sendCommand({ type: "chat.delete", chat_id: chatId });
    }

    function renameChat(chatId, title) {
        if (!canBrowseHistory || !chatId) return;
        sendCommand({ type: "chat.rename", chat_id: chatId, title: title });
    }

    function configureShell(workdir) {
        if (!ready || busy || loginBusy) return;
        sendCommand({ type: "shell.configure", workdir: workdir });
    }

    function configureLimits(config) {
        if (!ready || busy || loginBusy) return;
        limitsError = "";
        sendCommand(Object.assign({ type: "limits.configure" }, config));
    }

    function updateTool(call) {
        const key = "tool:" + call.id;
        if (messageRows[key] === undefined) {
            messageRows[key] = messages.count;
            messages.append({ author: "TERMINAL", body: "", turnId: call.turn_id || "",
                              imageUrl: "", performanceJson: "", toolJson: JSON.stringify(call) });
        } else messages.setProperty(messageRows[key], "toolJson", JSON.stringify(call));
        conversationChanged();
    }

    function login(newAccount = false) {
        if (!ready || busy || loginBusy || accountBusy || projectRunPreparing) return;
        loginBusy = true;
        status = "Preparando el inicio de sesión…";
        sendCommand({ type: "auth.login", new_account: newAccount });
    }

    function selectAccount(accountId) {
        if (!ready || busy || loginBusy || accountBusy || projectRunPreparing) return;
        accountBusy = true;
        sendCommand({ type: "auth.select", account_id: accountId });
    }

    function removeAccount(accountId) {
        if (!ready || busy || loginBusy || accountBusy || projectRunPreparing || !accountId) return;
        accountBusy = true;
        status = "Quitando cuenta…";
        sendCommand({ type: "auth.remove", account_id: accountId });
    }

    function updateProfile(name) {
        if (!ready) return;
        profileError = "";
        sendCommand({ type: "profile.update", display_name: (name || "").trim() });
    }

    function cancelLogin() { sendCommand({ type: "auth.cancel" }); }
    function refreshAccount() {
        if (!ready || busy || loginBusy || accountBusy || projectRunPreparing) return;
        accountBusy = true;
        sendCommand({ type: "auth.refresh" });
    }

    function logout() {
        if (!ready || busy || loginBusy || accountBusy || projectRunPreparing) return;
        accountBusy = true;
        sendCommand({ type: "auth.logout" });
    }

    function selectModel(slug, effort) {
        if (unifiedMode || !canSend) return;
        const request = { type: "model.select", model: slug };
        if (effort !== undefined) request.reasoning_effort = effort;
        sendCommand(request);
    }

    function refreshTeamUsage() {
        if (!ready || !unifiedMode || teamUsageBusy) return;
        teamUsageBusy = true;
        sendCommand({ type: "unified.usage" });
    }

    function storeProviderUsage(providerId, data) {
        providerUsage = Object.assign({}, providerUsage, { [providerId]: data });
    }

    function toggleUnifiedMode() {
        if (!ready || busy) return;
        sendCommand({ type: "unified.toggle" });
    }

    function prepareUnified() {
        if (!ready) return;
        sendCommand({ type: "unified.prepare" });
    }

    function configureUnified(config) {
        if (!ready || busy) return;
        unifiedConfigError = "";
        sendCommand(Object.assign({ type: "unified.configure" }, config));
    }

    function resetUnifiedConfig() {
        if (!ready || busy) return;
        unifiedConfigError = "";
        sendCommand({ type: "unified.configure", reset: true });
    }

    function selectProvider(nextProvider) {
        if (unifiedMode) return;
        if (!ready || busy || loginBusy || claudeLoginBusy || accountBusy || providerBusy || projectRunPreparing) return;
        if (nextProvider !== "chatgpt" && nextProvider !== "agy" && nextProvider !== "claude") return;
        if (nextProvider === "agy" && !agyAvailable) return;
        if (nextProvider === "claude" && !claudeAvailable) return;
        sendCommand({ type: "provider.select", provider: nextProvider });
    }

    function loginClaude() {
        if (!ready || busy || loginBusy || claudeLoginBusy || accountBusy || providerBusy || projectRunPreparing || !claudeAvailable) return;
        claudeLoginBusy = true;
        status = "Iniciando sesión en Claude Code en tu navegador…";
        sendCommand({ type: "claude.login" });
    }

    function refreshClaudeAuth() {
        if (!ready || busy || loginBusy || claudeLoginBusy || accountBusy || providerBusy || projectRunPreparing || !claudeAvailable) return;
        sendCommand({ type: "claude.refresh" });
    }

    function refreshPerformance() {
        if (!ready || performanceBusy) return;
        performanceBusy = true;
        sendCommand({ type: "performance.list" });
    }

    function updatePerformance(measurement) {
        const rows = performanceHistory.filter(row => row.turn_id !== measurement.turn_id);
        rows.push(measurement);
        rows.sort((a, b) => b.started_at.localeCompare(a.started_at));
        performanceHistory = rows.slice(0, 200);
        if (measurement.turn_id === activeTurnId) latestPerformance = measurement;
        let target = -1;
        for (let i = 0; i < messages.count; ++i) {
            if (messages.get(i).turnId === measurement.turn_id && !messages.get(i).toolJson)
                target = i;
        }
        for (let i = 0; i < messages.count; ++i) {
            if (i !== target && messages.get(i).turnId === measurement.turn_id
                && !messages.get(i).toolJson && messages.get(i).performanceJson !== "") {
                messages.setProperty(i, "performanceJson", "");
            }
        }
        if (target >= 0) {
            const encoded = JSON.stringify(measurement);
            if (messages.get(target).performanceJson !== encoded)
                messages.setProperty(target, "performanceJson", encoded);
        }
    }

    function recordFirstText(turnId, text) {
        if (turnId !== activeTurnId || !text || firstReceivedAt || !submittedAt) return;
        firstReceivedAt = Date.now();
        framePending = true;
    }

    function confirmPresentation() {
        if (!framePending) return;
        framePending = false;
        const now = Date.now();
        if (now < firstReceivedAt || now < submittedAt) return;
        sendCommand({ type: "performance.presented", turn_id: activeTurnId,
                      first_visible_ms: now - submittedAt, ui_frame_ms: now - firstReceivedAt });
    }

    readonly property Timer deltaFlushTimer: Timer {
        interval: 16
        repeat: false
        onTriggered: bridge.flushPendingText()
    }

    function flushPendingText() {
        deltaFlushTimer.stop();
        const keys = Object.keys(pendingTextUpdates);
        if (!keys.length) return;
        const updates = pendingTextUpdates;
        pendingTextUpdates = ({});
        for (const itemId of keys) {
            const row = messageRows[itemId];
            if (row !== undefined && row < messages.count)
                messages.setProperty(row, "body", updates[itemId]);
        }
        conversationChanged();
    }

    function updateMessage(itemId, text, append, turnId) {
        const row = messageRows[itemId];
        if (row === undefined) {
            flushPendingText();
            messageRows[itemId] = messages.count;
            messages.append({ author: "CHATGPT", body: text, imageUrl: "", turnId: turnId || "", performanceJson: "", toolJson: "" });
            conversationChanged();
            return;
        }
        if (!append) {
            delete pendingTextUpdates[itemId];
            flushPendingText();
            messages.setProperty(row, "body", text);
            conversationChanged();
            return;
        }
        const current = pendingTextUpdates[itemId] !== undefined
            ? pendingTextUpdates[itemId]
            : messages.get(row).body;
        pendingTextUpdates[itemId] = current + text;
        if (!deltaFlushTimer.running)
            deltaFlushTimer.start();
    }

    function receive(line) {
        let event;
        try {
            event = JSON.parse(line);
            if (event.version !== 2 || !event.data || typeof event.type !== "string")
                throw new Error("Versión o formato incompatible");
        } catch (error) {
            status = "Error de comunicación: " + error.message;
            return;
        }
        const data = event.data;
        if (event.type !== "chat.delta" && event.type !== "performance.updated")
            flushPendingText();
        if (event.type === "clipboard.result") {
            clipboardResult(data);
        } else if (event.type === "area.state") {
            const previousKey = areaKey;
            activeArea = data.area;
            projectId = data.project ? data.project.project_id : "";
            projectName = data.project ? data.project.name : "";
            projectEngine = data.project && data.project.engine ? data.project.engine : "python";
            projectDesktopInstalled = !!(data.project && data.project.desktop_installed);
            projectHasRunScript = !!(data.project && data.project.has_run_script);
            projectHasCheckScript = !!(data.project && data.project.has_check_script);
            projectFolderExists = data.project ? data.project.folder_exists !== false : true;
            if (data.project) projectRunCaches = Object.assign({}, projectRunCaches,
                { [data.project.project_id]: !!data.project.has_launch_profile });
            areaBusy = false;
            areaError = "";
            if (previousKey !== areaKey) areaChanged(previousKey, areaKey);
        } else if (event.type === "app.desktop.state") {
            if (data.project_id === projectId) projectDesktopInstalled = !!data.installed;
            status = data.message || (data.installed ? "Acceso directo instalado en el sistema." : "Acceso directo retirado del sistema.");
        } else if (event.type === "area.rejected") {
            areaBusy = false;
            areaError = data.message;
            status = data.message;
        } else if (event.type === "project.run.cache") {
            projectRunCaches = Object.assign({}, projectRunCaches, { [data.project_id]: !!data.available });
        } else if (event.type === "project.run.state") {
            projectRunPending = false;
            projectRun = data;
            projectRunNotice = "";
        } else if (event.type === "project.run.rejected") {
            projectRunPending = false;
            projectRunNotice = data.message;
        } else if (event.type === "project.deleted") {
            areaBusy = false;
            areaError = "";
            performanceHistory = performanceHistory.filter(row => data.chat_ids.indexOf(row.chat_id) < 0);
            if (projectRun.project_id === data.project_id) projectRun = ({});
            const caches = Object.assign({}, projectRunCaches);
            delete caches[data.project_id];
            projectRunCaches = caches;
            status = data.kind === "app" ? "Aplicación eliminada. La carpeta local se conserva." : "Proyecto eliminado. La carpeta local se conserva.";
        } else if (event.type === "projects.list") {
            projects.clear();
            for (const project of data.projects || [])
                projects.append(_normalizeProjectRow(project));
            apps.clear();
            for (const app of data.apps || [])
                apps.append(_normalizeProjectRow(app));
            const allItems = (data.projects || []).concat(data.apps || []);
            projectRunCaches = Object.assign({}, projectRunCaches, ...allItems.map(project =>
                ({ [project.project_id]: !!project.has_launch_profile })));
        } else if (event.type === "shell.state") {
            workspace = data.workdir;
            shellTimeout = data.timeout_seconds;
            agentShellTimeout = data.agent_timeout_seconds ?? data.timeout_seconds;
            status = "Terminal disponible · ejecución automática.";
        } else if (event.type === "limits.state") {
            limitsProfile = data.profile || "personalizado";
            compactThresholdTokens = data.compact_threshold_tokens ?? 60000;
            maxCompactions = data.max_compactions ?? 3;
            maxTurnBillableTokens = data.max_turn_billable_tokens ?? 0;
            maxTurnTokens = data.max_turn_tokens ?? 0;
            maxSteps = data.max_steps ?? 32;
            maxToolCalls = data.max_tool_calls ?? 64;
            contextOutputChars = data.context_output_chars ?? 6000;
            chatCompactionCount = data.chat_compaction_count ?? 0;
            limitsError = "";
        } else if (event.type === "limits.rejected") {
            limitsError = data.message;
            status = data.message;
        } else if (event.type === "profile.state") {
            displayName = data.display_name || "";
            profileError = "";
        } else if (event.type === "profile.rejected") {
            profileError = data.message;
            status = data.message;
        } else if (event.type === "provider.state") {
            const nextProvider = (data.provider === "agy" || data.provider === "claude") ? data.provider : "chatgpt";
            const nextClaudeAuth = !!data.claude_authenticated;
            const wasUnified = unifiedMode;
            const hadArchitect = !!unifiedArchitect.model;
            if (typeof data.refreshing === "boolean") providerBusy = data.refreshing;
            if (nextProvider !== provider || (nextProvider === "claude" && nextClaudeAuth !== claudeAuthenticated)) {
                accountUsage = ({});
                usageError = "";
                usageRequestId = "";
                usageBusy = false;
            }
            provider = nextProvider;
            agyAvailable = !!data.agy_available;
            claudeAvailable = !!data.claude_available;
            claudeAuthenticated = nextClaudeAuth;
            claudeEmail = data.claude_email || "";
            claudePlan = data.claude_plan || "";
            if (typeof data.unified_mode === "boolean") unifiedMode = data.unified_mode;
            unifiedArchitect = data.unified_architect || ({});
            unifiedCascade = data.unified_cascade || [];
            unifiedTeam = data.unified_team || [];
            if (data.unified_config) unifiedConfig = data.unified_config;
            if (data.provider_catalogs) providerCatalogs = data.provider_catalogs;
            resolvedModels = data.resolved_models || {};
            if (!busy && !loginBusy && !claudeLoginBusy && !accountBusy && !providerBusy) {
                if (unifiedMode) {
                    // El sondeo de cuotas no debe borrar el resultado del último turno.
                    if (!wasUnified || hadArchitect !== engineReady)
                        status = engineReady ? "Arquitecto automático listo." : "Buscando modelos para el arquitecto…";
                } else if (provider === "agy")
                    status = availableModels.count > 0 ? "Conectado con Antigravity (agy)." : "Antigravity (agy) listo.";
                else if (provider === "claude")
                    status = claudeAuthenticated
                        ? ("Conectado con Claude Code" + (claudePlan ? " (" + claudePlan + ")" : "") + ".")
                        : "Inicia sesión en Claude Code para empezar.";
                else if (authenticated)
                    status = "Conectado con tu cuenta de ChatGPT.";
            }
        } else if (event.type === "provider.refresh.started") {
            providerBusy = true;
            status = provider === "claude"
                ? "Comprobando sesión de Claude Code…"
                : "Cargando modelos de Antigravity (agy)…";
        } else if (event.type === "provider.refresh.finished") {
            providerBusy = false;
            if (provider === "agy")
                status = availableModels.count > 0
                    ? "Conectado con Antigravity (agy)."
                    : "No se encontraron modelos en Antigravity (agy).";
            else if (provider === "claude")
                status = claudeAuthenticated
                    ? ("Conectado con Claude Code" + (claudePlan ? " (" + claudePlan + ")" : "") + ".")
                    : "Inicia sesión en Claude Code para conversar.";
            maybeRetryUsage();
        } else if (event.type === "usage.provider") {
            // Un fallo temporal conserva la última medición válida.
            const previous = providerUsage[data.provider];
            storeProviderUsage(data.provider, data.error && previous && previous.checked_at
                ? Object.assign({}, previous, { error: data.error }) : data);
        } else if (event.type === "unified.usage.finished") {
            teamUsageBusy = false;
        } else if (event.type === "unified.config.state") {
            unifiedConfig = data.config || unifiedConfig;
            unifiedConfigError = "";
            status = "Configuración del modo unificado guardada.";
        } else if (event.type === "unified.config.rejected") {
            unifiedConfigError = data.message || "No se pudo guardar la configuración del modo unificado.";
            status = unifiedConfigError;
        } else if (event.type === "unified.agent") {
            agents = agents.some(agent => agent.id === data.id)
                ? agents.map(agent => agent.id === data.id ? data : agent) : agents.concat(data);
        } else if (event.type === "provider.rejected") {
            providerBusy = false;
            status = data.message;
        } else if (event.type === "claude.login.started") {
            claudeLoginBusy = true;
            status = "Completa el inicio de sesión de Claude en tu navegador…";
        } else if (event.type === "claude.login.finished") {
            claudeLoginBusy = false;
            status = data.message || (data.success ? "Sesión de Claude Code conectada." : "Inicio de sesión en Claude cancelado.");
        } else if (event.type === "tool.updated") {
            updateTool(data.call);
            if (data.call.status === "running") status = data.call.source === "local" ? "Ejecutando comando local…" : "Ejecutando comando…";
        } else if (event.type === "history.ready") {
            historyDirectory = data.directory;
            historyReady = true;
        } else if (event.type === "history.list") {
            conversations.clear();
            for (const chat of data.chats)
                conversations.append({ chatId: chat.chat_id, title: chat.title, updatedAt: chat.updated_at });
        } else if (event.type === "chat.saved") {
            currentChatId = data.chat_id;
            currentTitle = data.title;
        } else if (event.type === "chat.deleted") {
            deletingChatId = "";
            for (let i = conversations.count - 1; i >= 0; --i)
                if (conversations.get(i).chatId === data.chat_id) conversations.remove(i);
            performanceHistory = performanceHistory.filter(row => row.chat_id !== data.chat_id);
            status = "Conversación borrada del historial local.";
        } else if (event.type === "chat.renamed") {
            if (currentChatId === data.chat_id) currentTitle = data.title;
            for (let i = 0; i < conversations.count; ++i)
                if (conversations.get(i).chatId === data.chat_id)
                    conversations.setProperty(i, "title", data.title);
            status = "Título de conversación actualizado.";
        } else if (event.type === "chat.loaded") {
            messages.clear();
            messageRows = ({});
            const chat = data.chat;
            activeTurnId = "";
            framePending = false;
            latestPerformance = ({});
            for (let index = 0; index <= chat.messages.length; ++index) {
                for (const call of chat.tool_calls || [])
                    if ((call.message_index === undefined ? chat.messages.length : call.message_index) === index)
                        updateTool(call);
                if (index === chat.messages.length) break;
                const message = chat.messages[index];
                if (message.role === "assistant") messageRows[message.id] = messages.count;
                messages.append({ author: message.role === "user" ? "TÚ"
                                 : message.role === "assistant" ? "CHATGPT" : "SISTEMA", body: message.text,
                                 imageUrl: message.image || "",
                                 turnId: message.turn_id || "", performanceJson: "", toolJson: "" });
            }
            for (const measurement of chat.performance || [])
                updatePerformance(Object.assign({}, measurement, { chat_id: chat.chat_id }));
            if (chat.performance && chat.performance.length)
                latestPerformance = Object.assign({}, chat.performance[chat.performance.length - 1], { chat_id: chat.chat_id });
            currentChatId = chat.chat_id;
            currentTitle = chat.title;
            chatQuota = chat.quota_spent || ({});
            chatQuotaMeasuring = false;
            openingChat = false;
            status = engineReady ? "Conversación recuperada. Puedes continuar."
                     : "Conversación recuperada. Conecta un motor de IA para continuar.";
            conversationChanged();
        } else if (event.type === "backend.ready") {
            ready = true;
            if (data.provider === "agy" || data.provider === "claude" || data.provider === "chatgpt") provider = data.provider;
            appVersion = data.app_version;
            status = "Comprobando tu sesión…";
        } else if (event.type === "auth.state") {
            const active = (data.accounts || []).find(account => account.active);
            const identity = (data.authenticated ? "connected:" : "offline:") + (active ? active.id : "") + ":" + (data.email || "");
            if (identity !== usageAccountKey) {
                usageAccountKey = identity;
                storeProviderUsage("chatgpt", undefined);
                accountUsage = ({});
                usageError = "";
                usageRequestId = "";
                usageBusy = false;
            }
            authenticated = data.authenticated;
            planEnabled = !!data.plan_enabled;
            email = data.email;
            plan = data.plan;
            registeredAccounts.clear();
            activeAccountIndex = -1;
            for (const account of data.accounts || []) {
                if (account.active) activeAccountIndex = registeredAccounts.count;
                registeredAccounts.append({ accountId: account.id,
                                            displayName: account.label + (account.email ? " · " + account.email : "") });
            }
            if (!busy && !loginBusy && !claudeLoginBusy && !accountBusy && !providerBusy && provider === "chatgpt")
                status = authenticated ? "Conectado con tu cuenta de ChatGPT."
                         : data.method === "chatgpt" ? "Conecta de nuevo tu cuenta y autoriza el uso de tu plan."
                         : "Inicia sesión con ChatGPT para empezar.";
        } else if (event.type === "usage.started") {
            backendUsageBusy = true;
            activeBackendUsageId = data.request_id || "";
        } else if (event.type === "usage.state" && (data.request_id === usageRequestId || data.auto === true)) {
            accountUsage = data;
            usageError = "";
            storeProviderUsage(data.source === "codex" ? "chatgpt" : data.source, Object.assign({ error: "" }, data));
        } else if (event.type === "chat.quota.updated") {
            if (!currentChatId || data.chat_id === currentChatId) {
                chatQuota = data.quota_spent || ({});
                chatQuotaMeasuring = !!data.measuring;
            }
        } else if (event.type === "usage.error" && data.request_id === usageRequestId) {
            accountUsage = ({});
            if (data.code === "busy" || data.code === "account_changed") {
                usageError = "";
                usageRetryPending = true;
            } else {
                usageError = data.message;
            }
        } else if (event.type === "usage.finished") {
            if (!activeBackendUsageId || data.request_id === activeBackendUsageId) {
                backendUsageBusy = false;
                activeBackendUsageId = "";
            }
            if (data.request_id === usageRequestId) usageBusy = false;
            maybeRetryUsage();
        } else if (event.type === "auth.refresh.started") {
            accountBusy = true;
            status = "Actualizando la cuenta y los modelos…";
        } else if (event.type === "auth.refresh.finished") {
            accountBusy = false;
            if (provider === "agy") {
                if (!providerBusy && availableModels.count > 0)
                    status = "Conectado con Antigravity (agy).";
            } else if (provider === "claude") {
                if (!providerBusy && !claudeLoginBusy && claudeAuthenticated)
                    status = "Conectado con Claude Code" + (claudePlan ? " (" + claudePlan + ")" : "") + ".";
            } else if (authenticated && availableModels.count > 0)
                status = "Conectado. Usando tu plan de ChatGPT.";
            else if (!authenticated)
                status = email ? "Conecta de nuevo tu cuenta y autoriza el uso de tu plan."
                               : "Conecta tu cuenta de ChatGPT para conversar.";
            maybeRetryUsage();
        } else if (event.type === "models.list") {
            availableModels.clear();
            for (const model of data.models)
                availableModels.append({ slug: model.slug, displayName: model.display_name,
                    family: model.family || "otros", reasoningEfforts: JSON.stringify(model.reasoning_efforts || []),
                    defaultReasoningEffort: model.default_reasoning_effort || "" });
            modelName = data.selected || "";
            reasoningEffort = data.reasoning_effort || "";
        } else if (event.type === "model.selected") {
            modelName = data.model || "";
            reasoningEffort = data.reasoning_effort || "";
            if (status === "Cambiando modelo y esfuerzo…") status = "Modelo y esfuerzo actualizados.";
        } else if (event.type === "auth.login.started") {
            authUrl = data.url;
            status = "Completa el inicio de sesión en tu navegador.";
            // Este evento sólo se solicita al pulsar Iniciar sesión.
            Qt.openUrlExternally(authUrl);
        } else if (event.type === "auth.login.finished") {
            loginBusy = false;
            authUrl = "";
            status = data.success ? "Comprobando la cuenta…" : data.message || "Inicio de sesión cancelado.";
            if (data.success && data.show_plan_welcome) planConnected();
        } else if (event.type === "shell.started") {
            busy = true;
            shellRunning = true;
            activeTurnId = data.turn_id;
        } else if (event.type === "shell.finished") {
            if (shellRunning && (!data.turn_id || !activeTurnId || data.turn_id === activeTurnId)) {
                busy = false;
                shellRunning = false;
                status = data.message || ({ completed: "Comando local completado.", interrupted: "Comando local detenido.",
                    timeout: "Comando local: tiempo agotado.", error: "El comando local terminó con error." })[data.status];
            }
        } else if (event.type === "shell.rejected") {
            if (shellRunning && !activeTurnId) {
                shellRunning = false;
                busy = false;
            }
            status = data.message;
        } else if (event.type === "chat.busy") {
            if (data.turn_id !== activeTurnId || !busy) { agents = []; agentTurn = unifiedMode; }
            busy = true;
            activeTurnId = data.turn_id || "";
            if (messages.count && messages.get(messages.count - 1).author === "TÚ")
                messages.setProperty(messages.count - 1, "turnId", activeTurnId);
        } else if (event.type === "chat.thread") {
            if (!unifiedMode) modelName = data.model || "";
        } else if (event.type === "chat.delta") {
            recordFirstText(data.turn_id, data.text);
            updateMessage(data.item_id, data.text, true, data.turn_id);
            const respondingProvider = unifiedMode ? unifiedArchitect.provider : provider;
            status = respondingProvider === "agy" ? "Antigravity está respondiendo…"
                   : respondingProvider === "claude" ? "Claude está respondiendo…"
                   : respondingProvider === "chatgpt" ? "ChatGPT está respondiendo…"
                   : "El arquitecto está respondiendo…";
        } else if (event.type === "chat.message") {
            // El texto final reemplaza los deltas; evita respuestas duplicadas.
            recordFirstText(data.turn_id, data.text);
            updateMessage(data.item_id, data.text, false, data.turn_id);
        } else if (event.type === "chat.compacted") {
            if (data.manual) busy = false;
            status = data.message || "Contexto compactado.";
            if (data.status === "failed")
                messages.append({ author: "SISTEMA", body: status, imageUrl: "", turnId: "", performanceJson: "", toolJson: "" });
        } else if (event.type === "chat.finished") {
            busy = false;
            refreshTeamUsage();
            status = data.status === "completed" ? "Respuesta completada."
                     : data.status === "interrupted" ? data.message || "Respuesta detenida."
                     : data.message || "No se pudo completar la respuesta.";
            if (data.status === "failed") messages.append({ author: "SISTEMA", body: status, imageUrl: "", turnId: "", performanceJson: "", toolJson: "" });
        } else if (event.type === "performance.updated") {
            updatePerformance(data.measurement);
        } else if (event.type === "performance.list") {
            performanceHistory = data.measurements;
            performanceBusy = false;
        } else if (event.type === "chat.reset") {
            messages.clear();
            messageRows = ({});
            currentChatId = "";
            currentTitle = "";
            activeTurnId = "";
            framePending = false;
            latestPerformance = ({});
            chatQuota = ({});
            chatQuotaMeasuring = false;
            status = engineReady ? "Nuevo chat listo." : "Inicia sesión con ChatGPT para empezar.";
        } else if (event.type === "error" || event.type === "chat.notice" || event.type === "history.notice") {
            openingChat = false;
            if (event.type === "error") deletingChatId = "";
            status = data.message;
            messages.append({ author: "SISTEMA", body: data.message, imageUrl: "", turnId: "", performanceJson: "", toolJson: "" });
            conversationChanged();
        } else if (event.type === "backend.disconnected") {
            projectRunPending = false;
            projectRun = ({});
            projectRunNotice = "Motor desconectado. Reinicia Agent Shell.";
            usageBusy = false;
            backendUsageBusy = false;
            activeBackendUsageId = "";
            usageRetryPending = false;
            accountUsage = ({});
            usageError = "Motor desconectado. Reinicia Agent Shell.";
            areaBusy = false;
            shellRunning = false;
            ready = false;
            authenticated = false;
            busy = false;
            loginBusy = false;
            claudeLoginBusy = false;
            accountBusy = false;
            providerBusy = false;
            chatQuotaMeasuring = false;
            performanceBusy = false;
            framePending = false;
            deletingChatId = "";
            status = data.message;
        }
        eventReceived(event);
    }

    readonly property NativeProcess backend: NativeProcess {
        command: [NativeApp.pythonExecutable, "-u", NativeApp.backendEntry]
        workingDirectory: NativeApp.initialWorkspace
        stdinEnabled: true
        running: true
        output: LineParser { onRead: data => bridge.receive(data) }
        errorOutput: LineParser { onRead: data => console.warn("Error del backend: " + data) }
        onExited: (exitCode, exitStatus) => {
            bridge.projectRunPending = false;
            bridge.projectRun = ({});
            bridge.projectRunNotice = "Motor desconectado. Reinicia Agent Shell.";
            bridge.usageBusy = false;
            bridge.teamUsageBusy = false;
            bridge.agents = [];
            bridge.backendUsageBusy = false;
            bridge.activeBackendUsageId = "";
            bridge.usageRetryPending = false;
            bridge.accountUsage = ({});
            bridge.usageError = "Motor desconectado. Reinicia Agent Shell.";
            bridge.areaBusy = false;
            bridge.ready = false;
            bridge.authenticated = false;
            bridge.busy = false;
            bridge.shellRunning = false;
            bridge.loginBusy = false;
            bridge.claudeLoginBusy = false;
            bridge.accountBusy = false;
            bridge.providerBusy = false;
            bridge.chatQuotaMeasuring = false;
            bridge.performanceBusy = false;
            bridge.framePending = false;
            bridge.historyReady = false;
            bridge.openingChat = false;
            bridge.deletingChatId = "";
            bridge.status = "Motor desconectado (" + exitCode + "). Reinicia Agent Shell.";
        }
    }
}
