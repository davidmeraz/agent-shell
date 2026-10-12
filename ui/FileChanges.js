.pragma library

// Índices UTF-16 compatibles con TextEdit; las fronteras no parten pares Unicode.
function highSurrogate(value) { return value >= 0xd800 && value <= 0xdbff; }
function lowSurrogate(value) { return value >= 0xdc00 && value <= 0xdfff; }

// El documento de Qt usa un salto por párrafo; la instantánea original no cambia.
function visibleText(text) { return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n"); }

function span(before, after) {
    let prefix = 0;
    const common = Math.min(before.length, after.length);
    while (prefix < common && before[prefix] === after[prefix]) ++prefix;
    if (prefix > 0 && highSurrogate(after.charCodeAt(prefix - 1))) --prefix;
    let suffix = 0;
    while (suffix < common - prefix
        && before[before.length - suffix - 1] === after[after.length - suffix - 1]) ++suffix;
    if (suffix > 0 && lowSurrogate(after.charCodeAt(after.length - suffix))) --suffix;
    return {start: prefix, oldEnd: before.length - suffix, newEnd: after.length - suffix};
}

// Extiende el intervalo modificado a líneas completas para el resaltado.
function range(before, after) {
    const changed = span(before, after);
    const prefix = changed.start;
    const start = prefix > 0 ? after.lastIndexOf("\n", prefix - 1) + 1 : 0;
    let last = Math.max(start, changed.newEnd - 1);
    while (last > start && after[last] === "\n") --last;
    const newline = after.indexOf("\n", last);
    return { start: start, end: newline < 0 ? after.length : newline };
}

// Mantiene juntos pares Unicode, CRLF, acentos y uniones comunes de emoji.
function nextBoundary(text, end, limit) {
    while (end < limit) {
        const value = text.charCodeAt(end);
        const previous = text.charCodeAt(end - 1);
        if ((highSurrogate(previous) && lowSurrogate(value))
            || (previous === 13 && value === 10)
            || (value >= 0x0300 && value <= 0x036f)
            || (value >= 0xfe00 && value <= 0xfe0f)
            || value === 0x200d || previous === 0x200d
            || (value === 0xd83c && text.charCodeAt(end + 1) >= 0xdffb
                && text.charCodeAt(end + 1) <= 0xdfff)) ++end;
        else break;
    }
    return end;
}
