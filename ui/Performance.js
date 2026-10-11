.pragma library

function duration(value) {
    if (value === null || value === undefined || !isFinite(value)) return "—";
    return value < 1000 ? value.toFixed(1) + " ms" : (value / 1000).toFixed(2) + " s";
}

function rate(value) {
    return value === null || value === undefined ? "—" : value.toFixed(1) + " car./s";
}

function tokens(value) {
    if (typeof value !== "number" || !isFinite(value) || value < 0) return "—";
    return value >= 1000 ? (value / 1000).toFixed(1) + "k" : value.toFixed(0);
}

function tokenRate(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 ? value.toFixed(1) + " tok/s" : "—";
}

function tokenSummary(row) {
    const parts = [];
    if (row.context_tokens !== null && row.context_tokens !== undefined)
        parts.push("Contexto: " + tokens(row.context_tokens) + " tokens");
    if (row.tokens_per_second !== null && row.tokens_per_second !== undefined)
        parts.push("Media: " + tokenRate(row.tokens_per_second));
    return parts.join(" · ");
}

function status(value) {
    return ({ streaming: "En curso", completed: "Completada", failed: "Fallida",
              interrupted: "Interrumpida" })[value] || value;
}

function summary(row) {
    if (!row || !row.turn_id) return "";
    return "Primer texto: " + duration(row.first_visible_ms !== null && row.first_visible_ms !== undefined
                                      ? row.first_visible_ms : row.first_text_ms)
           + " · " + (row.status === "streaming" ? "Transcurrido: " : "Total: ")
           + duration(row.status === "streaming" ? row.elapsed_ms : row.total_ms)
           + (tokenSummary(row) ? " · " + tokenSummary(row) : " · " + rate(row.characters_per_second));
}

function compactSummary(row) {
    if (!row || !row.turn_id) return "";
    if (row.status === "streaming") return "En curso";
    const parts = [];
    if (row.total_ms !== null && row.total_ms !== undefined) parts.push(duration(row.total_ms));
    if (row.tokens_per_second !== null && row.tokens_per_second !== undefined)
        parts.push("Media: " + tokenRate(row.tokens_per_second));
    else if (row.characters_per_second !== null && row.characters_per_second !== undefined)
        parts.push(rate(row.characters_per_second));
    return parts.join(" · ") || status(row.status);
}

function details(row) {
    if (!row || !row.turn_id) return "";
    const usage = row.usage || {};
    const lines = [
        "Modelo: " + row.model,
        "Estado: " + status(row.status),
        "Fecha: " + new Date(row.started_at).toLocaleString(),
        "Primer texto recibido por el backend: " + duration(row.first_text_ms),
        "Enviar → primer texto en Qt (aprox.): " + duration(row.first_visible_ms),
        "Total del backend: " + duration(row.total_ms),
        "Contexto de la última llamada: " + (row.context_tokens === null || row.context_tokens === undefined ? "—" : row.context_tokens + " tokens"),
        "Velocidad media de las llamadas a la IA: " + tokenRate(row.tokens_per_second),
        "Tiempo HTTP acumulado de la IA: " + duration(row.model_request_ms),
        "Solicitudes al modelo: " + (row.model_calls === undefined || row.model_calls === null ? "—" : row.model_calls),
        "Comandos solicitados: " + (row.tool_calls || 0),
        "Ejecución de terminal: " + duration(row.tool_ms),
        "Espera de confirmación: " + duration(row.approval_ms),
        "Preparación local: " + duration(row.prepare_ms),
        "Sesión y renovación: " + duration(row.session_ms),
        "Hasta las cabeceras HTTP: " + duration(row.headers_ms),
        "Solicitud → primer texto (red + servicio): " + duration(row.request_first_text_ms),
        "Desde el primer texto hasta terminar: " + duration(row.stream_ms),
        "Recepción en Qt → siguiente fotograma: " + duration(row.ui_frame_ms),
        "Velocidad entre fragmentos de texto: " + rate(row.characters_per_second),
        "Caracteres de respuesta: " + (row.characters === null ? "—" : row.characters),
        "Contexto visible inicial: " + row.context_messages + " mensajes · " + row.input_characters + " caracteres",
        "Consumo acumulado reportado del turno:",
        "Tokens de entrada: " + (usage.input_tokens === undefined ? "—" : usage.input_tokens),
        "Tokens de salida: " + (usage.output_tokens === undefined ? "—" : usage.output_tokens),
        "Tokens totales: " + (usage.total_tokens === undefined ? "—" : usage.total_tokens),
        "Tokens de razonamiento: " + (usage.reasoning_tokens === undefined ? "—" : usage.reasoning_tokens),
        "Tokens de entrada en caché: " + (usage.cached_tokens === undefined ? "—" : usage.cached_tokens),
        "",
        "Contexto corresponde a la entrada de la última llamada, no a la suma del turno ni a un porcentaje del límite del modelo. Media usa todos los tokens de salida reportados / tiempo HTTP observado de las llamadas a la IA; incluye red, razonamiento y recepción local, y excluye terminal, preparación entre llamadas y renovación de sesión. Se muestra al completar el turno con conteos y tiempos de todas las llamadas. El consumo puede ser parcial si OpenAI omite datos. Un fragmento no equivale a un token. La medida de Qt aproxima el primer fotograma; no mide el monitor."
    ];
    return lines.join("\n");
}

function median(values) {
    if (!values.length) return null;
    values.sort((a, b) => a - b);
    const middle = Math.floor(values.length / 2);
    return values.length % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
}

function models(rows) {
    const groups = Object.create(null);
    for (const row of rows) {
        if (!groups[row.model]) groups[row.model] = { model: row.model, completed: 0,
            failed: 0, interrupted: 0, agentTurns: 0, first: [], total: [] };
        const group = groups[row.model];
        if (row.tool_calls > 0) { group.agentTurns++; continue; }
        if (row.status === "completed") {
            group.completed++;
            if (row.first_text_ms !== null) group.first.push(row.first_text_ms);
            if (row.total_ms !== null) group.total.push(row.total_ms);
        } else if (row.status === "failed") group.failed++;
        else if (row.status === "interrupted") group.interrupted++;
    }
    return Object.keys(groups).sort().map(key => {
        const group = groups[key];
        return { model: key, completed: group.completed, failed: group.failed,
                 interrupted: group.interrupted, agentTurns: group.agentTurns, firstMedian: median(group.first),
                 totalMedian: median(group.total),
                 totalP95: group.total.length >= 20 ? group.total[Math.ceil(group.total.length * 0.95) - 1] : null };
    });
}
