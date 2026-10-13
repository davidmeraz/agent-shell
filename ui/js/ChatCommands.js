.pragma library

// Catálogo único para sugerencias, ayuda y despacho local. Sin llamadas al modelo.
const commands = [
    { name: "/ayuda", description: "Ver los comandos disponibles" },
    { name: "/nuevo", description: "Crear una conversación nueva" },
    { name: "/historial", description: "Abrir las conversaciones guardadas" },
    { name: "/modelos", description: "Elegir familia, modelo y esfuerzo de razonamiento" },
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
    if (command.name !== "/modelos") return { name: command.name };
    const parts = (match[2] || "").trim().split(/\s+/).filter(part => !!part);
    let family = "";
    if (parts.length && /^(gpt-\d+|otros)$/i.test(parts[0])) {
        family = parts.shift().toLowerCase();
        if (parts[0] && parts[0].toLowerCase() === "modelos") parts.shift();
    }
    if (parts.length > 2) return { error: "Usa /modelos familia modelo esfuerzo." };
    return { name: command.name, family: family, model: parts[0] || "",
             effort: (parts[1] || "").toLowerCase(), hasEffort: parts.length === 2 };
}

function effortLabel(value) {
    return ({ auto: "Auto", none: "Sin razonamiento", minimal: "Mínimo", low: "Bajo",
              medium: "Medio", high: "Alto", xhigh: "Muy alto", max: "Máximo", ultra: "Ultra" })[value] || value;
}

function modelChoices(text, models, activeModel, activeEffort) {
    const query = modelQuery(text);
    if (query === null) return [];
    const parts = query.split(/\s+/).filter(part => !!part);
    const families = Array.from(new Set(models.map(model => model.family)));
    families.sort((a, b) => a === "otros" ? 1 : b === "otros" ? -1 : Number(b.slice(4)) - Number(a.slice(4)));
    const family = families.includes(parts[0]) ? parts.shift() : "";
    if (family && parts[0] === "modelos") parts.shift();
    const candidates = models.filter(model => !family || model.family === family);
    const exact = candidates.find(model => model.slug.toLowerCase() === parts[0]);
    const base = "/modelos " + (family ? family + " " : "");
    if (exact && exact.efforts.length && parts.length <= 2) {
        const filter = parts[1] || "";
        return ["auto"].concat(exact.efforts).filter(effort =>
            !filter || effort.startsWith(filter) || effortLabel(effort).toLowerCase().startsWith(filter)).map(effort => ({
                label: effortLabel(effort), value: effort, command: base + exact.slug + " " + effort,
                kind: "effort", final: true, selected: activeModel === exact.slug && (activeEffort || "auto") === effort,
                description: effort === "auto" ? "Predeterminado del servidor" + (exact.defaultEffort ? " · " + effortLabel(exact.defaultEffort) : "")
                    : "Esfuerzo " + effortLabel(effort).toLowerCase() + " · " + exact.displayName
            }));
    }
    if (parts.length > 1) return [];
    if (!family && (!query || families.some(name => name.startsWith(query)))) {
        return families.filter(name => !query || name.startsWith(query)).map(name => ({
            label: name === "otros" ? "Otros" : name.toUpperCase(), value: name,
            command: "/modelos " + name + " ", kind: "family", final: false,
            selected: models.some(model => model.slug === activeModel && model.family === name),
            description: candidates.filter(model => model.family === name).length + " modelos disponibles"
        }));
    }
    const filter = parts[0] || "";
    return candidates.filter(model => !filter || (model.slug + " " + model.displayName).toLowerCase().includes(filter))
        .map(model => ({ label: model.displayName, value: model.slug, kind: "model",
            command: base + model.slug + (model.efforts.length ? " " : ""), final: !model.efforts.length,
            selected: model.slug === activeModel,
            description: model.slug + (model.efforts.length ? " · Elegir esfuerzo" : " · Configuración del servidor") }));
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
