import QtQuick
import Quickshell
import Quickshell.Io
import "Performance.js" as Performance
import "ChatCommands.js" as ChatCommands

// Estado del chat. Python administra la sesión y el streaming directo con ChatGPT.
QtObject {
    id: bridge
    property bool ready: false
    property bool authenticated: false
    property bool busy: false
    property bool loginBusy: false
    property bool accountBusy: false
    property bool usageBusy: false
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
    property string activeArea: "chat"
    property string projectId: ""
    property string projectName: ""
    property bool areaBusy: false
    property string areaError: ""
    readonly property string areaKey: activeArea === "chat" ? "chat" : "work:" + projectId
    readonly property bool workspaceSelected: activeArea === "chat" || !!projectId
    property int shellTimeout: 120
    property string status: "Preparando Agent Shell…"
    property string appVersion: ""
    property string email: ""
    property string plan: ""
    property string modelName: ""
    property string authUrl: ""
    property string historyDirectory: ""
    property string currentChatId: ""
    property string currentTitle: ""
    property var messageRows: ({})
    property var performanceHistory: []
    property bool performanceBusy: false
    property var latestPerformance: ({})
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
    readonly property ListModel availableModels: ListModel {}
    readonly property ListModel registeredAccounts: ListModel {}
    property int activeAccountIndex: -1
    readonly property bool canBrowseHistory: historyReady && !busy && !loginBusy && !openingChat && !deletingChatId && !areaBusy
    readonly property bool canSelectArea: ready && canBrowseHistory && !accountBusy
    readonly property bool canSend: ready && authenticated && availableModels.count > 0
                                   && !busy && !loginBusy && !accountBusy && !openingChat && !deletingChatId && !areaBusy && workspaceSelected
    readonly property bool canRunShell: ready && historyReady && !busy && !loginBusy && !accountBusy
                                      && !openingChat && !deletingChatId && !areaBusy && workspaceSelected
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
        if (!ready || usageBusy || accountBusy || loginBusy) return;
        usageBusy = true;
        usageError = "";
        usageRequestId = "usage-" + (++usageSequence);
        sendCommand({ type: "usage.read", request_id: usageRequestId });
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
            if (command.name === "/modelos" && command.model) {
                for (let i = 0; i < availableModels.count; ++i) {
                    if (availableModels.get(i).slug === command.model) {
                        selectModel(command.model);
                        status = "Cambiando modelo…";
                        return true;
                    }
                }
                status = "El modelo solicitado no está disponible en tu cuenta.";
                return false;
            }
            if (command.name === "/nuevo") newChat();
            else if (command.name === "/detener") cancel();
            else localCommandRequested(command.name);
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

    function deleteProject(projectId) {
        if (!canSelectArea || !projectId) return;
        areaBusy = true;
        areaError = "";
        status = "Eliminando proyecto…";
        sendCommand({ type: "project.delete", project_id: projectId });
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

    function configureShell(workdir) {
        if (!ready || busy || loginBusy) return;
        sendCommand({ type: "shell.configure", workdir: workdir });
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
        if (!ready || busy || loginBusy || accountBusy) return;
        loginBusy = true;
        status = "Preparando el inicio de sesión…";
        sendCommand({ type: "auth.login", new_account: newAccount });
    }

    function selectAccount(accountId) {
        if (!ready || busy || loginBusy || accountBusy) return;
        accountBusy = true;
        sendCommand({ type: "auth.select", account_id: accountId });
    }

    function cancelLogin() { sendCommand({ type: "auth.cancel" }); }
    function refreshAccount() {
        if (!ready || busy || loginBusy || accountBusy) return;
        accountBusy = true;
        sendCommand({ type: "auth.refresh" });
    }

    function logout() {
        if (!ready || busy || loginBusy || accountBusy) return;
        accountBusy = true;
        sendCommand({ type: "auth.logout" });
    }

    function selectModel(slug) { if (canSend) sendCommand({ type: "model.select", model: slug }); }

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
            if (messages.get(i).turnId === measurement.turn_id && !messages.get(i).toolJson) {
                messages.setProperty(i, "performanceJson", "");
                target = i;
            }
        }
        if (target >= 0) messages.setProperty(target, "performanceJson", JSON.stringify(measurement));
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

    function updateMessage(itemId, text, append, turnId) {
        const row = messageRows[itemId];
        if (row === undefined) {
            messageRows[itemId] = messages.count;
            messages.append({ author: "CHATGPT", body: text, imageUrl: "", turnId: turnId || "", performanceJson: "", toolJson: "" });
        } else {
            messages.setProperty(row, "body", append ? messages.get(row).body + text : text);
        }
        conversationChanged();
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
        if (event.type === "clipboard.result") {
            clipboardResult(data);
        } else if (event.type === "area.state") {
            const previousKey = areaKey;
            activeArea = data.area;
            projectId = data.project ? data.project.project_id : "";
            projectName = data.project ? data.project.name : "";
            areaBusy = false;
            areaError = "";
            if (previousKey !== areaKey) areaChanged(previousKey, areaKey);
        } else if (event.type === "area.rejected") {
            areaBusy = false;
            areaError = data.message;
            status = data.message;
        } else if (event.type === "project.deleted") {
            areaBusy = false;
            areaError = "";
            performanceHistory = performanceHistory.filter(row => data.chat_ids.indexOf(row.chat_id) < 0);
            status = "Proyecto eliminado. La carpeta local se conserva.";
        } else if (event.type === "projects.list") {
            projects.clear();
            for (const project of data.projects)
                projects.append({ projectId: project.project_id, name: project.name, workdir: project.workdir });
        } else if (event.type === "shell.state") {
            workspace = data.workdir;
            shellTimeout = data.timeout_seconds;
            status = "Terminal disponible · ejecución automática.";
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
            openingChat = false;
            status = authenticated ? "Conversación recuperada. Puedes continuar."
                     : "Conversación recuperada. Conecta ChatGPT para continuar.";
            conversationChanged();
        } else if (event.type === "backend.ready") {
            ready = true;
            appVersion = data.app_version;
            status = "Comprobando tu sesión…";
        } else if (event.type === "auth.state") {
            const active = (data.accounts || []).find(account => account.active);
            const identity = (data.authenticated ? "connected:" : "offline:") + (active ? active.id : "") + ":" + (data.email || "");
            if (identity !== usageAccountKey) {
                usageAccountKey = identity;
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
            if (!busy && !loginBusy && !accountBusy)
                status = authenticated ? "Conectado con tu cuenta de ChatGPT."
                         : data.method === "chatgpt" ? "Conecta de nuevo tu cuenta y autoriza el uso de tu plan."
                         : "Inicia sesión con ChatGPT para empezar.";
        } else if (event.type === "usage.state" && data.request_id === usageRequestId) {
            accountUsage = data;
            usageError = "";
        } else if (event.type === "usage.error" && data.request_id === usageRequestId) {
            accountUsage = ({});
            usageError = data.message;
        } else if (event.type === "usage.finished" && data.request_id === usageRequestId) {
            usageBusy = false;
        } else if (event.type === "auth.refresh.started") {
            accountBusy = true;
            status = "Actualizando la cuenta y los modelos…";
        } else if (event.type === "auth.refresh.finished") {
            accountBusy = false;
            if (authenticated && availableModels.count > 0)
                status = "Conectado. Usando tu plan de ChatGPT.";
            else if (!authenticated)
                status = email ? "Conecta de nuevo tu cuenta y autoriza el uso de tu plan."
                               : "Conecta tu cuenta de ChatGPT para conversar.";
        } else if (event.type === "models.list") {
            availableModels.clear();
            for (const model of data.models)
                availableModels.append({ slug: model.slug, displayName: model.display_name });
            modelName = data.selected || "";
        } else if (event.type === "model.selected") {
            modelName = data.model || "";
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
            busy = true;
            activeTurnId = data.turn_id || "";
            if (messages.count && messages.get(messages.count - 1).author === "TÚ")
                messages.setProperty(messages.count - 1, "turnId", activeTurnId);
        } else if (event.type === "chat.thread") {
            modelName = data.model || "";
        } else if (event.type === "chat.delta") {
            recordFirstText(data.turn_id, data.text);
            updateMessage(data.item_id, data.text, true, data.turn_id);
            status = "ChatGPT está respondiendo…";
        } else if (event.type === "chat.message") {
            // El texto final reemplaza los deltas; evita respuestas duplicadas.
            recordFirstText(data.turn_id, data.text);
            updateMessage(data.item_id, data.text, false, data.turn_id);
        } else if (event.type === "chat.finished") {
            busy = false;
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
            status = authenticated ? "Nuevo chat listo." : "Inicia sesión con ChatGPT para empezar.";
        } else if (event.type === "error" || event.type === "chat.notice" || event.type === "history.notice") {
            openingChat = false;
            if (event.type === "error") deletingChatId = "";
            status = data.message;
            messages.append({ author: "SISTEMA", body: data.message, imageUrl: "", turnId: "", performanceJson: "", toolJson: "" });
            conversationChanged();
        } else if (event.type === "backend.disconnected") {
            usageBusy = false;
            accountUsage = ({});
            usageError = "Motor desconectado. Reinicia Agent Shell.";
            areaBusy = false;
            shellRunning = false;
            ready = false;
            authenticated = false;
            busy = false;
            loginBusy = false;
            accountBusy = false;
            performanceBusy = false;
            framePending = false;
            deletingChatId = "";
            status = data.message;
        }
        eventReceived(event);
    }

    readonly property Process backend: Process {
        command: [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python", "-u",
                  Quickshell.env("AGENT_SHELL_BACKEND_ENTRY") || Quickshell.shellDir + "/backend/main.py"]
        workingDirectory: Quickshell.shellDir
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => bridge.receive(data) }
        stderr: SplitParser { onRead: data => console.warn("Error del backend: " + data) }
        onExited: (exitCode, exitStatus) => {
            bridge.usageBusy = false;
            bridge.accountUsage = ({});
            bridge.usageError = "Motor desconectado. Reinicia Agent Shell.";
            bridge.areaBusy = false;
            bridge.ready = false;
            bridge.authenticated = false;
            bridge.busy = false;
            bridge.shellRunning = false;
            bridge.loginBusy = false;
            bridge.accountBusy = false;
            bridge.performanceBusy = false;
            bridge.framePending = false;
            bridge.historyReady = false;
            bridge.openingChat = false;
            bridge.deletingChatId = "";
            bridge.status = "Motor desconectado (" + exitCode + "). Reinicia Agent Shell.";
        }
    }
}
