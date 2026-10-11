import QtQuick
import Quickshell
import Quickshell.Io

// Estado del chat. Python traduce el protocolo oficial de Codex a estos eventos.
QtObject {
    id: bridge
    property bool ready: false
    property bool authenticated: false
    property bool busy: false
    property bool loginBusy: false
    property bool historyReady: false
    property bool openingChat: false
    property string status: "Conectando con Codex…"
    property string appVersion: ""
    property string email: ""
    property string plan: ""
    property string modelName: ""
    property string authUrl: ""
    property string historyDirectory: ""
    property string currentChatId: ""
    property string currentTitle: ""
    property var messageRows: ({})
    readonly property ListModel messages: ListModel {}
    readonly property ListModel conversations: ListModel {}
    readonly property bool canBrowseHistory: historyReady && !busy && !loginBusy && !openingChat
    readonly property bool canSend: ready && authenticated && !busy && !loginBusy && !openingChat
    signal eventReceived(var event)
    signal conversationChanged()

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
        messages.append({ author: "TÚ", body: text });
        busy = true;
        status = "Codex está preparando la respuesta…";
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
        if (!ready || busy || loginBusy) return;
        loginBusy = true;
        status = "Preparando el inicio de sesión…";
        sendCommand({ type: "auth.login" });
    }

    function cancelLogin() { sendCommand({ type: "auth.cancel" }); }
    function refreshAccount() { sendCommand({ type: "auth.refresh" }); }

    function updateMessage(itemId, text, append) {
        const row = messageRows[itemId];
        if (row === undefined) {
            messageRows[itemId] = messages.count;
            messages.append({ author: "CODEX", body: text });
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
            for (const message of chat.messages) {
                if (message.role === "assistant") messageRows[message.id] = messages.count;
                messages.append({ author: message.role === "user" ? "TÚ"
                                 : message.role === "assistant" ? "CODEX" : "SISTEMA", body: message.text });
            }
            currentChatId = chat.chat_id;
            currentTitle = chat.title;
            modelName = chat.model || "";
            openingChat = false;
            status = authenticated ? "Conversación recuperada. Puedes continuar."
                     : "Conversación recuperada. Conecta Codex para continuar.";
            conversationChanged();
        } else if (event.type === "backend.ready") {
            ready = true;
            appVersion = data.app_version;
            status = "Comprobando tu sesión…";
        } else if (event.type === "auth.state") {
            authenticated = data.authenticated;
            email = data.email;
            plan = data.plan;
            if (!busy && !loginBusy)
                status = authenticated ? "Conectado con tu cuenta de ChatGPT."
                         : data.method === "apiKey" ? "La CLI usa una API key. Inicia sesión con ChatGPT."
                         : "Inicia sesión con ChatGPT para empezar.";
        } else if (event.type === "auth.login.started") {
            authUrl = data.url;
            status = "Completa el inicio de sesión en tu navegador.";
            // Este evento sólo se solicita al pulsar Iniciar sesión.
            Qt.openUrlExternally(authUrl);
        } else if (event.type === "auth.login.finished") {
            loginBusy = false;
            authUrl = "";
            status = data.success ? "Comprobando la cuenta…" : data.message || "Inicio de sesión cancelado.";
        } else if (event.type === "chat.busy") {
            busy = true;
        } else if (event.type === "chat.thread") {
            modelName = data.model || "";
        } else if (event.type === "chat.delta") {
            updateMessage(data.item_id, data.text, true);
            status = "Codex está respondiendo…";
        } else if (event.type === "chat.message") {
            // El texto final reemplaza los deltas; evita respuestas duplicadas.
            updateMessage(data.item_id, data.text, false);
        } else if (event.type === "chat.finished") {
            busy = false;
            status = data.status === "completed" ? "Respuesta completada."
                     : data.status === "interrupted" ? "Respuesta detenida."
                     : data.message || "Codex no pudo completar la respuesta.";
            if (data.status === "failed") messages.append({ author: "SISTEMA", body: status });
        } else if (event.type === "chat.reset") {
            messages.clear();
            messageRows = ({});
            modelName = "";
            currentChatId = "";
            currentTitle = "";
            status = authenticated ? "Nuevo chat listo." : "Inicia sesión con ChatGPT para empezar.";
        } else if (event.type === "error" || event.type === "chat.notice" || event.type === "history.notice") {
            openingChat = false;
            status = data.message;
            messages.append({ author: "SISTEMA", body: data.message });
            conversationChanged();
        } else if (event.type === "backend.disconnected") {
            ready = false;
            authenticated = false;
            busy = false;
            loginBusy = false;
            status = data.message;
        }
        eventReceived(event);
    }

    readonly property Process backend: Process {
        command: ["python3", "-u", Quickshell.shellDir + "/backend/main.py"]
        workingDirectory: Quickshell.shellDir
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => bridge.receive(data) }
        stderr: SplitParser { onRead: data => console.warn("Error del puente de Codex: " + data) }
        onExited: (exitCode, exitStatus) => {
            bridge.ready = false;
            bridge.authenticated = false;
            bridge.busy = false;
            bridge.loginBusy = false;
            bridge.historyReady = false;
            bridge.openingChat = false;
            bridge.status = "Motor desconectado (" + exitCode + "). Reinicia Agent Shell.";
        }
    }
}
