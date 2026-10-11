import QtQuick
import Quickshell
import Quickshell.Io
import "Performance.js" as Performance

// Estado del chat. Python administra la sesión y el streaming directo con ChatGPT.
QtObject {
    id: bridge
    property bool ready: false
    property bool authenticated: false
    property bool busy: false
    property bool loginBusy: false
    property bool accountBusy: false
    property bool planEnabled: false
    property bool historyReady: false
    property bool openingChat: false
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
    property double submittedAt: 0
    property double firstReceivedAt: 0
    property bool framePending: false
    readonly property var modelPerformance: Performance.models(performanceHistory)
    readonly property ListModel messages: ListModel {}
    readonly property ListModel conversations: ListModel {}
    readonly property ListModel availableModels: ListModel {}
    readonly property bool canBrowseHistory: historyReady && !busy && !loginBusy && !openingChat
    readonly property bool canSend: ready && authenticated && availableModels.count > 0
                                   && !busy && !loginBusy && !accountBusy && !openingChat
    signal eventReceived(var event)
    signal conversationChanged()
    signal planConnected()

    function sendCommand(command) {
        if (backend.running) backend.write(JSON.stringify(command) + "\n");
    }

    function submit(prompt) {
        const text = prompt.trim();
        if (!canSend || !text) return;
        if (text.length > 16000) {
            status = "El mensaje puede tener como máximo 16000 caracteres.";
            return;
        }
        submittedAt = Date.now();
        firstReceivedAt = 0;
        framePending = false;
        activeTurnId = "";
        latestPerformance = ({});
        messages.append({ author: "TÚ", body: text, turnId: "", performanceJson: "" });
        busy = true;
        status = "Preparando la respuesta…";
        sendCommand({ type: "chat.send", prompt: text });
        conversationChanged();
    }

    function cancel() {
        if (!busy) return;
        status = "Deteniendo la respuesta…";
        sendCommand({ type: "chat.cancel" });
    }

    function newChat() {
        if (canBrowseHistory) sendCommand({ type: "chat.new" });
    }

    function openChat(chatId) {
        if (!canBrowseHistory) return;
        openingChat = true;
        sendCommand({ type: "chat.open", chat_id: chatId });
    }

    function refreshHistory() {
        if (canBrowseHistory) sendCommand({ type: "history.list" });
    }

    function login() {
        if (!ready || busy || loginBusy || accountBusy) return;
        loginBusy = true;
        status = "Preparando el inicio de sesión…";
        sendCommand({ type: "auth.login" });
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
            if (messages.get(i).turnId === measurement.turn_id) {
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
            messages.append({ author: "CHATGPT", body: text, turnId: turnId || "", performanceJson: "" });
        } else {
            messages.setProperty(row, "body", append ? messages.get(row).body + text : text);
        }
        conversationChanged();
    }

    function receive(line) {
        let event;
        try {
            event = JSON.parse(line);
            if (event.version !== 1 || !event.data || typeof event.type !== "string")
                throw new Error("Versión o formato incompatible");
        } catch (error) {
            status = "Error de comunicación: " + error.message;
            return;
        }
        const data = event.data;
        if (event.type === "history.ready") {
            historyDirectory = data.directory;
            historyReady = true;
        } else if (event.type === "history.list") {
            conversations.clear();
            for (const chat of data.chats)
                conversations.append({ chatId: chat.chat_id, title: chat.title, updatedAt: chat.updated_at });
        } else if (event.type === "chat.saved") {
            currentChatId = data.chat_id;
            currentTitle = data.title;
        } else if (event.type === "chat.loaded") {
            messages.clear();
            messageRows = ({});
            const chat = data.chat;
            activeTurnId = "";
            framePending = false;
            latestPerformance = ({});
            for (const message of chat.messages) {
                if (message.role === "assistant") messageRows[message.id] = messages.count;
                messages.append({ author: message.role === "user" ? "TÚ"
                                 : message.role === "assistant" ? "CHATGPT" : "SISTEMA", body: message.text,
                                 turnId: message.turn_id || "", performanceJson: "" });
            }
            for (const measurement of chat.performance || [])
                updatePerformance(Object.assign({}, measurement, { chat_id: chat.chat_id }));
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
            authenticated = data.authenticated;
            planEnabled = !!data.plan_enabled;
            email = data.email;
            plan = data.plan;
            if (!busy && !loginBusy && !accountBusy)
                status = authenticated ? "Conectado con tu cuenta de ChatGPT."
                         : data.method === "chatgpt" ? "Conecta de nuevo tu cuenta y autoriza el uso de tu plan."
                         : "Inicia sesión con ChatGPT para empezar.";
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
                     : data.status === "interrupted" ? "Respuesta detenida."
                     : data.message || "No se pudo completar la respuesta.";
            if (data.status === "failed") messages.append({ author: "SISTEMA", body: status, turnId: "", performanceJson: "" });
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
            status = data.message;
            messages.append({ author: "SISTEMA", body: data.message, turnId: "", performanceJson: "" });
            conversationChanged();
        } else if (event.type === "backend.disconnected") {
            ready = false;
            authenticated = false;
            busy = false;
            loginBusy = false;
            accountBusy = false;
            performanceBusy = false;
            framePending = false;
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
            bridge.ready = false;
            bridge.authenticated = false;
            bridge.busy = false;
            bridge.loginBusy = false;
            bridge.accountBusy = false;
            bridge.performanceBusy = false;
            bridge.framePending = false;
            bridge.historyReady = false;
            bridge.openingChat = false;
            bridge.status = "Motor desconectado (" + exitCode + "). Reinicia Agent Shell.";
        }
    }
}
