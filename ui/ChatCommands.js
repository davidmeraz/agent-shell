.pragma library

// Catálogo único para sugerencias, ayuda y despacho local. Sin llamadas al modelo.
const commands = [
    { name: "/ayuda", description: "Ver los comandos disponibles" },
    { name: "/nuevo", description: "Crear una conversación nueva" },
    { name: "/historial", description: "Abrir las conversaciones guardadas" },
    { name: "/modelos", description: "Elegir el modelo de IA" },
    { name: "/terminal", description: "Configurar la terminal y su directorio" },
    { name: "/detener", description: "Cancelar la respuesta o ejecución actual" },
    { name: "/shell", description: "Ejecutar un comando local sin IA; por ejemplo /shell pwd" }
];

function parse(text) {
    const value = text.replace(/^\s+/, "");
    if (!value.startsWith("/")) return null;
    const match = /^\/([^\s]+)(?:\s+([\s\S]*))?$/.exec(value);
    const token = match ? "/" + match[1].toLowerCase() : value;
    const command = commands.find(item => item.name === token);
    if (!command)
        return { error: "Comando desconocido. Escribe /ayuda para ver los disponibles." };
    if (command.name === "/shell") {
        const shellCommand = match[2] || "";
        if (!shellCommand.trim()) return { error: "Escribe /shell seguido de un comando, por ejemplo /shell pwd." };
        if (shellCommand.length > 8000 || shellCommand.includes("\0"))
            return { error: "El comando debe tener como máximo 8000 caracteres y no contener caracteres NUL." };
        return { name: command.name, command: shellCommand };
    }
    if (match[2] && match[2].trim() && command.name !== "/modelos") return { error: token + " no acepta argumentos." };
    return { name: command.name, model: command.name === "/modelos" ? (match[2] || "").trim() : "" };
}

function suggestions(text) {
    if (/^\/shell\s/i.test(text.replace(/^\s+/, ""))) return [];
    const value = text.trim().toLowerCase();
    if (!/^\/[a-z]*$/.test(value)) return [];
    return commands.filter(command => command.name.startsWith(value));
}

function modelQuery(text) {
    const match = /^\/modelos(?:\s+([^\n]*))?$/i.exec(text.trim());
    return match ? (match[1] || "").trim().toLowerCase() : null;
}

function blockedReason(name, bridge) {
    if (name === "/ayuda") return "";
    if (name === "/historial") return bridge.historyReady ? "" : "El historial todavía no está disponible.";
    if (name === "/detener") return bridge.busy ? "" : "No hay una respuesta o ejecución en curso.";
    if (name === "/nuevo") return bridge.canBrowseHistory ? "" : "Espera a que termine la operación actual y esté disponible el historial.";
    if (name === "/terminal") return bridge.ready && !bridge.busy && !bridge.loginBusy ? "" : "Espera a que el motor esté disponible y termine la operación actual.";
    if (name === "/shell") return bridge.canRunShell ? "" : "Espera a que termine la operación actual y esté disponible la terminal.";
    if (name === "/modelos") return bridge.canSend ? "" : "Conecta ChatGPT y espera a que termine la operación actual para elegir modelo.";
    return "Comando desconocido.";
}
