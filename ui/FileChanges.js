.pragma library

// Intervalo real afectado: prefijo/sufijo comunes, extendido a líneas completas.
// Índices UTF-16, como TextEdit; no crea texto ni reproduce caracteres ficticios.
function range(before, after) {
    let prefix = 0;
    const common = Math.min(before.length, after.length);
    while (prefix < common && before[prefix] === after[prefix]) ++prefix;
    let suffix = 0;
    while (suffix < common - prefix
        && before[before.length - suffix - 1] === after[after.length - suffix - 1]) ++suffix;
    const start = prefix > 0 ? after.lastIndexOf("\n", prefix - 1) + 1 : 0;
    let last = Math.max(start, after.length - suffix - 1);
    while (last > start && after[last] === "\n") --last;
    const newline = after.indexOf("\n", last);
    return { start: start, end: newline < 0 ? after.length : newline };
}
