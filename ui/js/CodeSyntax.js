.pragma library

// Resaltado de sintaxis ligero y generación de paleta armónica adaptada al tema Gema.
// Solo emite <span style="color:..."> dentro de <pre style="margin:0;white-space:pre-wrap;">
// para mantener alineación exacta de 0 px con TextEdit.PlainText y nunca perder caracteres.

function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function hexToRgb(hex) {
    if (typeof hex !== "string") return { r: 0.77, g: 0.86, b: 1.0 };
    const clean = hex.trim().replace(/^#/, "");
    const six = clean.length === 8 ? clean.slice(2) : clean;
    if (!/^[0-9a-fA-F]{6}$/.test(six)) return { r: 0.77, g: 0.86, b: 1.0 };
    return {
        r: parseInt(six.slice(0, 2), 16) / 255,
        g: parseInt(six.slice(2, 4), 16) / 255,
        b: parseInt(six.slice(4, 6), 16) / 255
    };
}

function rgbToHsl(r, g, b) {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) * 0.5;
    if (max === min) return { h: 214, s: 0, l: l };
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h = 0;
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    return { h: (h * 60 + 360) % 360, s: s, l: l };
}

function hslToHex(h, s, l) {
    h = ((h % 360) + 360) % 360;
    s = clamp(s, 0, 1);
    l = clamp(l, 0, 1);
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = l - c * 0.5;
    let r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; }
    else if (h < 120) { r = x; g = c; }
    else if (h < 180) { g = c; b = x; }
    else if (h < 240) { g = x; b = c; }
    else if (h < 300) { r = x; b = c; }
    else { r = c; b = x; }
    function byteHex(v) {
        const n = Math.round(clamp((v + m) * 255, 0, 255));
        return (n < 16 ? "0" : "") + n.toString(16);
    }
    return "#" + byteHex(r) + byteHex(g) + byteHex(b);
}

// Compensa la luminosidad perceptual: los azules/índigo se ven más oscuros en HSL puro
// que los amarillos/verdes, especialmente sobre vidrio esmerilado oscuro.
function balancedColor(hue, sat, light, darkText) {
    const h = ((hue % 360) + 360) % 360;
    let l = light;
    if (!darkText) {
        if (h >= 210 && h <= 285) {
            const k = Math.sin(((h - 210) / 75) * Math.PI);
            l += 0.065 * k;
        } else if (h >= 50 && h <= 145) {
            const k = Math.sin(((h - 50) / 95) * Math.PI);
            l -= 0.03 * k;
        }
    } else {
        if (h >= 45 && h <= 155) {
            const k = Math.sin(((h - 45) / 110) * Math.PI);
            l -= 0.065 * k;
        } else if (h >= 210 && h <= 280) {
            const k = Math.sin(((h - 210) / 70) * Math.PI);
            l += 0.035 * k;
        }
    }
    return hslToHex(h, sat, clamp(l, 0.16, 0.95));
}

// Construye una paleta de sintaxis completa armonizada con el acento principal de Gema:
// análogos (+42°, +78°, -65°) + complementarios divididos (+150°, +205°) + neutros tintados.
function buildPalette(accentHex, darkText, synced) {
    const rgb = hexToRgb(accentHex);
    const hsl = rgbToHsl(rgb.r, rgb.g, rgb.b);
    const baseHue = (!synced || hsl.s < 0.08) ? 214 : hsl.h;
    const vivid = synced && hsl.s >= 0.15;
    const satBoost = vivid ? 1.0 : 0.84;

    if (darkText) {
        return {
            accent: balancedColor(baseHue, 0.78 * satBoost, 0.36, true),
            plain: hslToHex(baseHue, 0.22, 0.16),
            keyword: balancedColor(baseHue, 0.80 * satBoost, 0.36, true),
            type: balancedColor(baseHue + 42, 0.76 * satBoost, 0.35, true),
            func: balancedColor(baseHue + 78, 0.78 * satBoost, 0.36, true),
            string: balancedColor(baseHue - 65, 0.72 * satBoost, 0.34, true),
            number: balancedColor(baseHue + 150, 0.76 * satBoost, 0.37, true),
            property: balancedColor(baseHue + 20, 0.56 * satBoost, 0.30, true),
            decorator: balancedColor(baseHue + 205, 0.74 * satBoost, 0.38, true),
            operator: hslToHex(baseHue + 12, 0.20, 0.38),
            comment: hslToHex(baseHue, 0.18, 0.48),
            lineNumber: hslToHex(baseHue, 0.18, 0.52),
            lineNumberActive: balancedColor(baseHue, 0.82 * satBoost, 0.34, true),
            folder: balancedColor(baseHue + 36, 0.72 * satBoost, 0.38, true),
            badgeCreated: balancedColor(baseHue, 0.78 * satBoost, 0.35, true),
            badgeModified: balancedColor(baseHue + 42, 0.74 * satBoost, 0.36, true),
            selectionBg: hslToHex(baseHue, 0.58 * satBoost, 0.78),
            selectionFg: hslToHex(baseHue, 0.28, 0.12)
        };
    }

    return {
        accent: balancedColor(baseHue, 0.84 * satBoost, 0.67, false),
        plain: hslToHex(baseHue, 0.14, 0.94),
        keyword: balancedColor(baseHue, 0.82 * satBoost, 0.68, false),
        type: balancedColor(baseHue + 46, 0.76 * satBoost, 0.74, false),
        func: balancedColor(baseHue + 86, 0.78 * satBoost, 0.76, false),
        string: balancedColor(baseHue - 62, 0.70 * satBoost, 0.76, false),
        number: balancedColor(baseHue + 148, 0.76 * satBoost, 0.75, false),
        property: balancedColor(baseHue - 22, 0.44 * satBoost, 0.86, false),
        decorator: balancedColor(baseHue + 205, 0.76 * satBoost, 0.75, false),
        operator: hslToHex(baseHue + 12, 0.22, 0.78),
        comment: hslToHex(baseHue, 0.22, 0.62),
        lineNumber: hslToHex(baseHue, 0.20, 0.60),
        lineNumberActive: balancedColor(baseHue, 0.88 * satBoost, 0.72, false),
        folder: balancedColor(baseHue + 40, 0.74 * satBoost, 0.74, false),
        badgeCreated: balancedColor(baseHue, 0.82 * satBoost, 0.69, false),
        badgeModified: balancedColor(baseHue + 46, 0.78 * satBoost, 0.74, false),
        selectionBg: hslToHex(baseHue, 0.46 * satBoost, 0.30),
        selectionFg: "#ffffff"
    };
}

function detectLanguage(filePath) {
    if (!filePath || typeof filePath !== "string")
        return { id: "plain", label: "TXT", role: "plain" };
    const slash = filePath.lastIndexOf("/");
    const base = slash >= 0 ? filePath.slice(slash + 1) : filePath;
    const lowerBase = base.toLowerCase();
    if (lowerBase === "pkgbuild" || lowerBase === "makefile" || lowerBase === "dockerfile")
        return { id: "shell", label: base.toUpperCase().slice(0, 4), role: "keyword" };
    if (lowerBase === "qmldir")
        return { id: "config", label: "QML", role: "keyword" };
    if (lowerBase === "cmakelists.txt")
        return { id: "config", label: "CMAKE", role: "property" };
    const dot = lowerBase.lastIndexOf(".");
    const ext = dot > 0 ? lowerBase.slice(dot + 1) : "";
    switch (ext) {
    case "qml": return { id: "qml", label: "QML", role: "keyword" };
    case "js": case "mjs": case "cjs": case "jsx": return { id: "js", label: "JS", role: "string" };
    case "ts": case "tsx": return { id: "ts", label: "TS", role: "func" };
    case "py": case "pyi": return { id: "python", label: "PY", role: "func" };
    case "rs": return { id: "rust", label: "RS", role: "decorator" };
    case "sh": case "bash": case "zsh": case "fish": return { id: "shell", label: "SH", role: "keyword" };
    case "json": case "jsonc": return { id: "json", label: "JSON", role: "number" };
    case "md": case "markdown": return { id: "markdown", label: "MD", role: "type" };
    case "html": case "htm": return { id: "markup", label: "HTML", role: "decorator" };
    case "xml": return { id: "markup", label: "XML", role: "decorator" };
    case "svg": return { id: "markup", label: "SVG", role: "decorator" };
    case "css": case "scss": case "qss": return { id: "css", label: ext.toUpperCase(), role: "type" };
    case "toml": return { id: "config", label: "TOML", role: "property" };
    case "yaml": case "yml": return { id: "config", label: "YAML", role: "property" };
    case "ini": case "conf": case "cfg": case "service": case "desktop": case "env":
        return { id: "config", label: ext.toUpperCase().slice(0, 4), role: "property" };
    case "c": case "h": return { id: "clike", label: ext.toUpperCase(), role: "type" };
    case "cpp": case "cc": case "cxx": case "hpp": return { id: "clike", label: "C++", role: "type" };
    case "go": return { id: "clike", label: "GO", role: "type" };
    case "java": case "kt": case "cs": return { id: "clike", label: ext.toUpperCase(), role: "type" };
    case "sql": return { id: "sql", label: "SQL", role: "number" };
    case "txt": case "log": return { id: "plain", label: ext.toUpperCase(), role: "plain" };
    default: return { id: "plain", label: ext ? ext.toUpperCase().slice(0, 4) : "FILE", role: "plain" };
    }
}

function roleColor(palette, role) {
    if (!palette) return "#f3f5f8";
    return palette[role] || palette.plain || "#f3f5f8";
}

function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function computeLineOffsets(text) {
    const offsets = [0];
    if (!text) return offsets;
    let idx = text.indexOf("\n");
    while (idx >= 0) {
        offsets.push(idx + 1);
        idx = text.indexOf("\n", idx + 1);
    }
    return offsets;
}

const KEYWORDS = {
    qml: new Set([
        "import", "pragma", "as", "property", "readonly", "required", "default", "alias",
        "signal", "component", "function", "return", "const", "let", "var", "if", "else",
        "for", "while", "do", "switch", "case", "break", "continue", "try", "catch", "finally",
        "throw", "new", "delete", "typeof", "instanceof", "in", "of", "void", "this", "super",
        "class", "extends", "async", "await", "yield", "enum", "on", "Behavior"
    ]),
    js: new Set([
        "import", "export", "from", "default", "as", "function", "return", "const", "let", "var",
        "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "try", "catch",
        "finally", "throw", "new", "delete", "typeof", "instanceof", "in", "of", "void", "this",
        "super", "class", "extends", "static", "get", "set", "async", "await", "yield"
    ]),
    ts: new Set([
        "import", "export", "from", "default", "as", "function", "return", "const", "let", "var",
        "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "try", "catch",
        "finally", "throw", "new", "delete", "typeof", "instanceof", "in", "of", "void", "this",
        "super", "class", "extends", "implements", "interface", "type", "enum", "namespace",
        "readonly", "private", "protected", "public", "abstract", "declare", "keyof", "infer",
        "static", "get", "set", "async", "await", "yield"
    ]),
    python: new Set([
        "def", "class", "return", "yield", "if", "elif", "else", "for", "while", "break",
        "continue", "pass", "try", "except", "finally", "raise", "with", "as", "import", "from",
        "in", "not", "and", "or", "is", "lambda", "global", "nonlocal", "assert", "del",
        "async", "await", "match", "case"
    ]),
    rust: new Set([
        "fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "for", "in", "while",
        "loop", "match", "if", "else", "return", "use", "mod", "crate", "super", "self", "Self",
        "async", "await", "move", "ref", "where", "type", "const", "static", "unsafe", "extern",
        "dyn", "as", "break", "continue"
    ]),
    shell: new Set([
        "if", "then", "elif", "else", "fi", "for", "in", "do", "done", "while", "until", "case",
        "esac", "function", "local", "export", "readonly", "return", "exit", "set", "unset",
        "trap", "shift", "source", "echo", "printf", "cd", "exec", "eval", "test", "true", "false"
    ]),
    clike: new Set([
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
        "return", "goto", "struct", "union", "enum", "class", "namespace", "template", "typename",
        "public", "private", "protected", "virtual", "override", "final", "const", "constexpr",
        "static", "extern", "inline", "volatile", "mutable", "auto", "void", "new", "delete",
        "try", "catch", "throw", "using", "typedef", "sizeof", "func", "package", "import",
        "defer", "go", "chan", "select", "range", "interface", "map", "var", "type", "extends",
        "implements", "throws", "final", "synchronized", "this", "super"
    ]),
    sql: new Set([
        "select", "from", "where", "join", "inner", "left", "right", "outer", "full", "cross",
        "on", "as", "insert", "into", "values", "update", "set", "delete", "create", "alter",
        "drop", "table", "index", "view", "trigger", "pragma", "if", "not", "exists", "primary",
        "foreign", "key", "references", "unique", "check", "default", "order", "group", "by",
        "having", "limit", "offset", "union", "all", "distinct", "and", "or", "in", "is", "like",
        "between", "case", "when", "then", "else", "end", "asc", "desc", "begin", "commit", "rollback"
    ])
};

const CONSTANTS = new Set([
    "true", "false", "null", "undefined", "NaN", "Infinity",
    "True", "False", "None", "self", "cls", "nullptr", "nil", "NULL"
]);

const BUILTIN_TYPES = new Set([
    "int", "real", "double", "float", "bool", "string", "url", "color", "var", "list",
    "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize",
    "f32", "f64", "char", "str", "byte", "rune", "size_t", "uint8_t", "uint32_t", "int64_t",
    "dict", "set", "tuple", "bytes", "object", "any", "unknown", "never", "number", "boolean",
    "integer", "text", "blob", "Qt", "Math", "JSON", "Date", "Object", "Array", "Map", "Set",
    "Promise", "Error", "RegExp", "console", "id"
]);

const NON_FUNC_KEYWORDS = new Set([
    "if", "for", "while", "switch", "catch", "return", "typeof", "delete", "await", "yield",
    "elif", "assert", "with", "match", "sizeof"
]);

function isIdentStart(ch) {
    const c = ch.charCodeAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95 || c === 36;
}

function isIdentPart(ch) {
    const c = ch.charCodeAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 95 || c === 36;
}

function isDigit(ch) {
    const c = ch.charCodeAt(0);
    return c >= 48 && c <= 57;
}

function isHex(ch) {
    const c = ch.charCodeAt(0);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
}

function makeWriter(palette) {
    const parts = [];
    let currentRole = "";
    let buf = "";

    function flush() {
        if (!buf) return;
        const escaped = escapeHtml(buf);
        if (!currentRole || currentRole === "plain") {
            parts.push(escaped);
        } else {
            parts.push('<span style="color:' + (palette[currentRole] || palette.plain) + '">');
            parts.push(escaped);
            parts.push("</span>");
        }
        buf = "";
    }

    return {
        emit: function(role, slice) {
            if (!slice) return;
            if (role !== currentRole) {
                flush();
                currentRole = role;
            }
            buf += slice;
        },
        finish: function() {
            flush();
            return parts.join("");
        }
    };
}

function readQuoted(text, i, quote, multiline) {
    const n = text.length;
    i += 1;
    while (i < n) {
        const ch = text[i];
        if (ch === "\\") {
            i = Math.min(n, i + 2);
            continue;
        }
        if (ch === quote) return i + 1;
        if (!multiline && ch === "\n") return i;
        i += 1;
    }
    return n;
}

function readTripleQuoted(text, i, quote) {
    const n = text.length;
    const mark = quote + quote + quote;
    i += 3;
    while (i < n) {
        if (text[i] === "\\") {
            i = Math.min(n, i + 2);
            continue;
        }
        if (text.startsWith(mark, i)) return i + 3;
        i += 1;
    }
    return n;
}

function tokenizeCode(text, langId, palette) {
    const out = makeWriter(palette);
    const n = text.length;
    const kw = KEYWORDS[langId] || KEYWORDS.js;
    const hashComments = langId === "python" || langId === "shell";
    const slashComments = langId !== "python" && langId !== "shell" && langId !== "sql";
    const dashComments = langId === "sql";
    const isQml = langId === "qml";
    const isPython = langId === "python";
    const isRust = langId === "rust";
    const isShell = langId === "shell";
    const isSql = langId === "sql";

    let i = 0;
    while (i < n) {
        const ch = text[i];
        const next = i + 1 < n ? text[i + 1] : "";

        // Espacios y saltos tal cual (agrupados en un solo tramo para velocidad).
        if (ch === " " || ch === "\t" || ch === "\n") {
            let j = i + 1;
            while (j < n && (text[j] === " " || text[j] === "\t" || text[j] === "\n")) ++j;
            out.emit("plain", text.slice(i, j));
            i = j;
            continue;
        }

        // Comentarios // o /* */
        if (slashComments && ch === "/" && next === "/") {
            let j = text.indexOf("\n", i + 2);
            if (j < 0) j = n;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }
        if (slashComments && ch === "/" && next === "*") {
            let j = text.indexOf("*/", i + 2);
            j = j < 0 ? n : j + 2;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }

        // Comentarios # (Python / Shell) y shebang #!/...
        if (hashComments && ch === "#") {
            let j = text.indexOf("\n", i + 1);
            if (j < 0) j = n;
            const role = (i === 0 && next === "!") ? "decorator" : "comment";
            out.emit(role, text.slice(i, j));
            i = j;
            continue;
        }

        // Comentarios SQL -- y /* */
        if (dashComments && ch === "-" && next === "-") {
            let j = text.indexOf("\n", i + 2);
            if (j < 0) j = n;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }
        if (dashComments && ch === "/" && next === "*") {
            let j = text.indexOf("*/", i + 2);
            j = j < 0 ? n : j + 2;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }

        // Preprocesador C/C++ (#include, #define) o atributos Rust (#[...], #![...])
        if (ch === "#" && (langId === "clike" || isRust)) {
            if (isRust && (next === "[" || (next === "!" && text[i + 2] === "["))) {
                let j = i + 2;
                let depth = 1;
                if (next === "!") j += 1;
                while (j < n && depth > 0) {
                    if (text[j] === "[") ++depth;
                    else if (text[j] === "]") --depth;
                    ++j;
                }
                out.emit("decorator", text.slice(i, j));
                i = j;
                continue;
            }
            if (langId === "clike") {
                let j = i + 1;
                while (j < n && (text[j] === " " || text[j] === "\t")) ++j;
                while (j < n && isIdentPart(text[j])) ++j;
                out.emit("decorator", text.slice(i, j));
                i = j;
                continue;
            }
        }

        // Decoradores (@decorator)
        if (ch === "@" && next && isIdentStart(next)) {
            let j = i + 2;
            while (j < n && (isIdentPart(text[j]) || text[j] === ".")) ++j;
            out.emit("decorator", text.slice(i, j));
            i = j;
            continue;
        }

        // Variables de Shell ($VAR, ${VAR})
        if (isShell && ch === "$") {
            let j = i + 1;
            if (next === "{") {
                j = text.indexOf("}", i + 2);
                j = j < 0 ? n : j + 1;
            } else {
                while (j < n && isIdentPart(text[j])) ++j;
                if (j === i + 1 && next && "?$#@!*0123456789".indexOf(next) >= 0) ++j;
            }
            out.emit("property", text.slice(i, j));
            i = j;
            continue;
        }

        // Cadenas con prefijo en Python (f"...", r'...', b"""...""")
        if (isPython && "fFrRbBuU".indexOf(ch) >= 0) {
            let p = i + 1;
            if (p < n && "fFrRbBuU".indexOf(text[p]) >= 0) ++p;
            if (p < n && (text[p] === '"' || text[p] === "'")) {
                const q = text[p];
                const end = text.startsWith(q + q + q, p)
                    ? readTripleQuoted(text, p, q)
                    : readQuoted(text, p, q, false);
                out.emit("string", text.slice(i, end));
                i = end;
                continue;
            }
        }

        // Cadenas triple-comilla (Python)
        if (isPython && (ch === '"' || ch === "'") && text.startsWith(ch + ch + ch, i)) {
            const end = readTripleQuoted(text, i, ch);
            out.emit("string", text.slice(i, end));
            i = end;
            continue;
        }

        // Lifetimes en Rust ('a, 'static) vs literales de carácter ('x')
        if (isRust && ch === "'" && next && isIdentStart(next) && text[i + 2] !== "'") {
            let j = i + 2;
            while (j < n && isIdentPart(text[j])) ++j;
            out.emit("decorator", text.slice(i, j));
            i = j;
            continue;
        }

        // Cadenas normales y template literals
        if (ch === '"' || ch === "'" || ch === "`") {
            const end = readQuoted(text, i, ch, ch === "`" || isShell);
            out.emit("string", text.slice(i, end));
            i = end;
            continue;
        }

        // Números (hex, bin, oct, decimales, científicos, sufijos)
        if (isDigit(ch) || (ch === "." && next && isDigit(next))) {
            let j = i + 1;
            if (ch === "0" && (next === "x" || next === "X")) {
                j += 1;
                while (j < n && (isHex(text[j]) || text[j] === "_")) ++j;
            } else {
                while (j < n && (isDigit(text[j]) || text[j] === "_" || text[j] === ".")) ++j;
                if (j < n && (text[j] === "e" || text[j] === "E")) {
                    ++j;
                    if (j < n && (text[j] === "+" || text[j] === "-")) ++j;
                    while (j < n && isDigit(text[j])) ++j;
                }
            }
            while (j < n && isIdentStart(text[j])) ++j;
            out.emit("number", text.slice(i, j));
            i = j;
            continue;
        }

        // Identificadores, palabras clave, tipos, propiedades y llamadas a función
        if (isIdentStart(ch)) {
            let j = i + 1;
            while (j < n && isIdentPart(text[j])) ++j;
            const word = text.slice(i, j);
            let k = j;
            while (k < n && (text[k] === " " || text[k] === "\t")) ++k;
            const after = k < n ? text[k] : "";

            let role = "plain";
            const lookup = isSql ? word.toLowerCase() : word;

            if (isRust && after === "!" && text[k + 1] !== "=") {
                out.emit("decorator", text.slice(i, k + 1));
                i = k + 1;
                continue;
            } else if (CONSTANTS.has(word)) {
                role = "number";
            } else if (kw.has(lookup)) {
                role = "keyword";
            } else if (isQml && word.length > 2 && word.startsWith("on")
                       && word.charCodeAt(2) >= 65 && word.charCodeAt(2) <= 90 && after === ":") {
                role = "func";
            } else if (after === ":" && text[k + 1] !== ":" && (isQml || langId === "js" || langId === "ts")) {
                role = "property";
            } else if (BUILTIN_TYPES.has(word)) {
                role = "type";
            } else if (after === "(" && !NON_FUNC_KEYWORDS.has(lookup)) {
                role = (word.charCodeAt(0) >= 65 && word.charCodeAt(0) <= 90) ? "type" : "func";
            } else if (word.charCodeAt(0) >= 65 && word.charCodeAt(0) <= 90 && /[a-z]/.test(word)) {
                role = "type";
            } else if (word.length >= 2 && word === word.toUpperCase() && /[A-Z]/.test(word)) {
                role = "number";
            } else if (i > 0 && text[i - 1] === ".") {
                role = "property";
            }

            out.emit(role, word);
            i = j;
            continue;
        }

        // Operadores y signos de puntuación
        if ("{}[]().,;:+-*/%=!<>&|^~?".indexOf(ch) >= 0) {
            out.emit("operator", ch);
            i += 1;
            continue;
        }

        out.emit("plain", ch);
        i += 1;
    }
    return out.finish();
}

function tokenizeJson(text, palette) {
    const out = makeWriter(palette);
    const n = text.length;
    let i = 0;
    while (i < n) {
        const ch = text[i];
        if (ch === " " || ch === "\t" || ch === "\n") {
            let j = i + 1;
            while (j < n && (text[j] === " " || text[j] === "\t" || text[j] === "\n")) ++j;
            out.emit("plain", text.slice(i, j));
            i = j;
            continue;
        }
        if (ch === "/" && text[i + 1] === "/") {
            let j = text.indexOf("\n", i + 2);
            if (j < 0) j = n;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }
        if (ch === '"') {
            const end = readQuoted(text, i, '"', false);
            let k = end;
            while (k < n && (text[k] === " " || text[k] === "\t")) ++k;
            const role = text[k] === ":" ? "property" : "string";
            out.emit(role, text.slice(i, end));
            i = end;
            continue;
        }
        if (ch === "-" || isDigit(ch)) {
            let j = i + 1;
            while (j < n && (isDigit(text[j]) || ".eE+-".indexOf(text[j]) >= 0)) ++j;
            out.emit("number", text.slice(i, j));
            i = j;
            continue;
        }
        if (isIdentStart(ch)) {
            let j = i + 1;
            while (j < n && isIdentPart(text[j])) ++j;
            const word = text.slice(i, j);
            out.emit(CONSTANTS.has(word) ? "number" : "plain", word);
            i = j;
            continue;
        }
        if ("{}[],:".indexOf(ch) >= 0) {
            out.emit("operator", ch);
            i += 1;
            continue;
        }
        out.emit("plain", ch);
        i += 1;
    }
    return out.finish();
}

function tokenizeConfig(text, palette) {
    const out = makeWriter(palette);
    const lines = text.split("\n");
    for (let li = 0; li < lines.length; ++li) {
        if (li > 0) out.emit("plain", "\n");
        const line = lines[li];
        const trimmed = line.trimStart();
        const leadLen = line.length - trimmed.length;
        if (leadLen > 0) out.emit("plain", line.slice(0, leadLen));
        if (!trimmed) continue;

        if (trimmed[0] === "#" || trimmed[0] === ";") {
            out.emit("comment", trimmed);
            continue;
        }
        if (trimmed[0] === "[") {
            out.emit("keyword", trimmed);
            continue;
        }
        // key = value o key: value
        const match = /^([A-Za-z0-9_.\-/]+)(\s*[:=])(.*)$/.exec(trimmed);
        if (match) {
            out.emit("property", match[1]);
            out.emit("operator", match[2]);
            const val = match[3];
            let i = 0;
            while (i < val.length) {
                const c = val[i];
                if (c === "#" && (i === 0 || val[i - 1] === " " || val[i - 1] === "\t")) {
                    out.emit("comment", val.slice(i));
                    break;
                }
                if (c === '"' || c === "'") {
                    const end = readQuoted(val, i, c, false);
                    out.emit("string", val.slice(i, end));
                    i = end;
                    continue;
                }
                if (c === "#" && isHex(val[i + 1] || "")) {
                    let j = i + 1;
                    while (j < val.length && isHex(val[j])) ++j;
                    out.emit("number", val.slice(i, j));
                    i = j;
                    continue;
                }
                if (isDigit(c)) {
                    let j = i + 1;
                    while (j < val.length && (isDigit(val[j]) || val[j] === "." || val[j] === "_")) ++j;
                    out.emit("number", val.slice(i, j));
                    i = j;
                    continue;
                }
                if (isIdentStart(c)) {
                    let j = i + 1;
                    while (j < val.length && (isIdentPart(val[j]) || val[j] === "-")) ++j;
                    const word = val.slice(i, j);
                    if (CONSTANTS.has(word) || word === "yes" || word === "no" || word === "on" || word === "off")
                        out.emit("number", word);
                    else out.emit("string", word);
                    i = j;
                    continue;
                }
                out.emit("operator", c);
                i += 1;
            }
            continue;
        }
        out.emit("plain", trimmed);
    }
    return out.finish();
}

function tokenizeCss(text, palette) {
    const out = makeWriter(palette);
    const n = text.length;
    let i = 0;
    while (i < n) {
        const ch = text[i];
        const next = i + 1 < n ? text[i + 1] : "";
        if (ch === " " || ch === "\t" || ch === "\n") {
            let j = i + 1;
            while (j < n && (text[j] === " " || text[j] === "\t" || text[j] === "\n")) ++j;
            out.emit("plain", text.slice(i, j));
            i = j;
            continue;
        }
        if (ch === "/" && next === "*") {
            let j = text.indexOf("*/", i + 2);
            j = j < 0 ? n : j + 2;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }
        if (ch === "/" && next === "/") {
            let j = text.indexOf("\n", i + 2);
            if (j < 0) j = n;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }
        if (ch === "@") {
            let j = i + 1;
            while (j < n && (isIdentPart(text[j]) || text[j] === "-")) ++j;
            out.emit("decorator", text.slice(i, j));
            i = j;
            continue;
        }
        if (ch === '"' || ch === "'") {
            const end = readQuoted(text, i, ch, false);
            out.emit("string", text.slice(i, end));
            i = end;
            continue;
        }
        if (ch === "#" && next && isHex(next)) {
            let j = i + 1;
            while (j < n && isHex(text[j])) ++j;
            out.emit("number", text.slice(i, j));
            i = j;
            continue;
        }
        if (isDigit(ch)) {
            let j = i + 1;
            while (j < n && (isDigit(text[j]) || text[j] === "." || text[j] === "%" || isIdentStart(text[j]))) ++j;
            out.emit("number", text.slice(i, j));
            i = j;
            continue;
        }
        if (isIdentStart(ch) || ch === "." || ch === "-") {
            let j = i + 1;
            while (j < n && (isIdentPart(text[j]) || text[j] === "-")) ++j;
            const word = text.slice(i, j);
            let k = j;
            while (k < n && (text[k] === " " || text[k] === "\t")) ++k;
            const role = text[k] === ":" ? "property" : (ch === "." ? "type" : (text[k] === "(" ? "func" : "plain"));
            out.emit(role, word);
            i = j;
            continue;
        }
        if ("{}[]():;,+*>~".indexOf(ch) >= 0) {
            out.emit("operator", ch);
            i += 1;
            continue;
        }
        out.emit("plain", ch);
        i += 1;
    }
    return out.finish();
}

function tokenizeMarkup(text, palette) {
    const out = makeWriter(palette);
    const n = text.length;
    let i = 0;
    while (i < n) {
        if (text.startsWith("<!--", i)) {
            let j = text.indexOf("-->", i + 4);
            j = j < 0 ? n : j + 3;
            out.emit("comment", text.slice(i, j));
            i = j;
            continue;
        }
        if (text[i] === "<") {
            const next = text[i + 1] || "";
            if (next === "!" || next === "?") {
                let j = text.indexOf(">", i + 2);
                j = j < 0 ? n : j + 1;
                out.emit("decorator", text.slice(i, j));
                i = j;
                continue;
            }
            out.emit("operator", "<");
            i += 1;
            if (i < n && text[i] === "/") {
                out.emit("operator", "/");
                i += 1;
            }
            let j = i;
            while (j < n && (isIdentPart(text[j]) || text[j] === "-" || text[j] === ":")) ++j;
            if (j > i) {
                out.emit("keyword", text.slice(i, j));
                i = j;
            }
            while (i < n && text[i] !== ">") {
                const c = text[i];
                if (c === " " || c === "\t" || c === "\n") {
                    let s = i + 1;
                    while (s < n && (text[s] === " " || text[s] === "\t" || text[s] === "\n")) ++s;
                    out.emit("plain", text.slice(i, s));
                    i = s;
                } else if (c === '"' || c === "'") {
                    const end = readQuoted(text, i, c, true);
                    out.emit("string", text.slice(i, end));
                    i = end;
                } else if (c === "=" || c === "/") {
                    out.emit("operator", c);
                    i += 1;
                } else {
                    let a = i + 1;
                    while (a < n && (isIdentPart(text[a]) || text[a] === "-" || text[a] === ":")) ++a;
                    out.emit("property", text.slice(i, a));
                    i = a;
                }
            }
            if (i < n && text[i] === ">") {
                out.emit("operator", ">");
                i += 1;
            }
            continue;
        }
        if (text[i] === "&") {
            const semi = text.indexOf(";", i + 1);
            if (semi > i + 1 && semi - i <= 10 && /^&[A-Za-z0-9#]+;$/.test(text.slice(i, semi + 1))) {
                out.emit("number", text.slice(i, semi + 1));
                i = semi + 1;
                continue;
            }
        }
        let j = i + 1;
        while (j < n && text[j] !== "<" && text[j] !== "&") ++j;
        out.emit("plain", text.slice(i, j));
        i = j;
    }
    return out.finish();
}

function tokenizeMarkdownInline(line, out) {
    const n = line.length;
    let i = 0;
    while (i < n) {
        const ch = line[i];
        // Código en línea `...`
        if (ch === "`") {
            const end = line.indexOf("`", i + 1);
            if (end > i) {
                out.emit("func", line.slice(i, end + 1));
                i = end + 1;
                continue;
            }
        }
        // Negrita **...**
        if (ch === "*" && line[i + 1] === "*") {
            const end = line.indexOf("**", i + 2);
            if (end > i + 1) {
                out.emit("operator", "**");
                out.emit("type", line.slice(i + 2, end));
                out.emit("operator", "**");
                i = end + 2;
                continue;
            }
        }
        // Enlaces [texto](url)
        if (ch === "[") {
            const close = line.indexOf("]", i + 1);
            if (close > i && line[close + 1] === "(") {
                const parenEnd = line.indexOf(")", close + 2);
                if (parenEnd > close + 1) {
                    out.emit("operator", "[");
                    out.emit("property", line.slice(i + 1, close));
                    out.emit("operator", "](");
                    out.emit("string", line.slice(close + 2, parenEnd));
                    out.emit("operator", ")");
                    i = parenEnd + 1;
                    continue;
                }
            }
        }
        let j = i + 1;
        while (j < n && line[j] !== "`" && line[j] !== "*" && line[j] !== "[") ++j;
        out.emit("plain", line.slice(i, j));
        i = j;
    }
}

function tokenizeMarkdown(text, palette) {
    const lines = text.split("\n");
    const parts = [];
    let inFence = false;
    let fenceLang = "plain";
    let fenceBuf = [];

    for (let li = 0; li < lines.length; ++li) {
        const line = lines[li];
        const fenceMatch = /^(\s*```+)([A-Za-z0-9_+-]*)(.*)$/.exec(line);
        if (fenceMatch) {
            if (inFence) {
                if (fenceBuf.length) {
                    const inner = fenceBuf.join("\n");
                    parts.push("\n");
                    parts.push(fenceLang === "plain"
                        ? '<span style="color:' + palette.string + '">' + escapeHtml(inner) + "</span>"
                        : highlightInner(inner, fenceLang, palette));
                    fenceBuf = [];
                }
                parts.push("\n");
                parts.push('<span style="color:' + palette.comment + '">' + escapeHtml(line) + "</span>");
                inFence = false;
                fenceLang = "plain";
            } else {
                if (li > 0) parts.push("\n");
                parts.push('<span style="color:' + palette.comment + '">' + escapeHtml(fenceMatch[1]) + "</span>");
                if (fenceMatch[2]) {
                    parts.push('<span style="color:' + palette.decorator + '">' + escapeHtml(fenceMatch[2]) + "</span>");
                    fenceLang = detectLanguage("x." + fenceMatch[2]).id;
                } else {
                    fenceLang = "plain";
                }
                if (fenceMatch[3]) parts.push(escapeHtml(fenceMatch[3]));
                inFence = true;
            }
            continue;
        }
        if (inFence) {
            fenceBuf.push(line);
            continue;
        }

        if (li > 0) parts.push("\n");
        const lineOut = makeWriter(palette);
        const heading = /^(\s*#{1,6}\s+)(.*)$/.exec(line);
        if (heading) {
            lineOut.emit("operator", heading[1]);
            lineOut.emit("keyword", heading[2]);
            parts.push(lineOut.finish());
            continue;
        }
        const quote = /^(\s*>\s?)(.*)$/.exec(line);
        if (quote) {
            lineOut.emit("keyword", quote[1]);
            lineOut.emit("comment", quote[2]);
            parts.push(lineOut.finish());
            continue;
        }
        const bullet = /^(\s*(?:[-*+]|\d+\.)\s+)(.*)$/.exec(line);
        if (bullet) {
            lineOut.emit("keyword", bullet[1]);
            tokenizeMarkdownInline(bullet[2], lineOut);
            parts.push(lineOut.finish());
            continue;
        }
        if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
            lineOut.emit("operator", line);
            parts.push(lineOut.finish());
            continue;
        }
        tokenizeMarkdownInline(line, lineOut);
        parts.push(lineOut.finish());
    }
    if (inFence && fenceBuf.length) {
        const inner = fenceBuf.join("\n");
        parts.push("\n");
        parts.push(fenceLang === "plain"
            ? '<span style="color:' + palette.string + '">' + escapeHtml(inner) + "</span>"
            : highlightInner(inner, fenceLang, palette));
    }
    return parts.join("");
}

function highlightInner(text, langId, palette) {
    if (!text) return "";
    if (langId === "json") return tokenizeJson(text, palette);
    if (langId === "config") return tokenizeConfig(text, palette);
    if (langId === "css") return tokenizeCss(text, palette);
    if (langId === "markup") return tokenizeMarkup(text, palette);
    if (langId === "markdown") return tokenizeMarkdown(text, palette);
    if (langId === "plain") return escapeHtml(text);
    return tokenizeCode(text, langId, palette);
}

function highlightToHtml(text, langId, palette) {
    const plainColor = (palette && palette.plain) || "#f3f5f8";
    if (!text) return "";
    const inner = highlightInner(text, langId, palette);
    return '<pre style="margin:0;white-space:pre-wrap;color:' + plainColor + ';">' + inner + "</pre>";
}

// Analiza indentación y bloques de función/ámbito (estilo VS Code) para dibujar guías verticales
// y breadcrumbs sin alterar el documento PlainText.
function detectIndentSize(lines) {
    const counts = { 2: 0, 4: 0 };
    let prev = 0;
    const limit = Math.min(lines.length, 240);
    for (let i = 0; i < limit; ++i) {
        const line = lines[i];
        if (!line || !line.trim()) continue;
        if (line[0] === "\t") return 4;
        let spaces = 0;
        while (spaces < line.length && line[spaces] === " ") spaces++;
        const diff = Math.abs(spaces - prev);
        if (diff === 2) counts[2]++;
        else if (diff === 4) counts[4]++;
        prev = spaces;
    }
    return counts[2] > counts[4] * 1.4 ? 2 : 4;
}

function leadingColumns(line, tabWidth) {
    let col = 0;
    for (let i = 0; i < line.length; ++i) {
        const ch = line[i];
        if (ch === " ") col += 1;
        else if (ch === "\t") col += tabWidth - (col % tabWidth);
        else break;
    }
    return col;
}

function classifyScopeHeader(trimmed, langId) {
    if (!trimmed) return { label: "", kind: "block" };
    // Python / Rust / JS / TS / QML / C-like
    let m = /^(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\(/.exec(trimmed);
    if (m) return { label: m[1] + "()", kind: "func" };
    m = /^(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s+([A-Za-z_$][\w$]*)\s*\(/.exec(trimmed);
    if (m) return { label: m[1] + "()", kind: "func" };
    m = /^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_]\w*)/.exec(trimmed);
    if (m) return { label: m[1] + "()", kind: "func" };
    m = /^(?:export\s+)?(?:abstract\s+)?(?:class|struct|enum|trait|interface|impl)\s+([A-Za-z_$][\w$:<>]*)/.exec(trimmed);
    if (m) return { label: m[1], kind: "type" };
    if (langId === "qml") {
        m = /^(on[A-Z]\w*)\s*:/.exec(trimmed);
        if (m) return { label: m[1], kind: "func" };
        m = /^component\s+([A-Z]\w*)\s*:/.exec(trimmed);
        if (m) return { label: m[1], kind: "type" };
        m = /^(?:(?:readonly|required|default)\s+)*property\s+\S+\s+([A-Za-z_]\w*)\s*:/.exec(trimmed);
        if (m) return { label: m[1], kind: "prop" };
        m = /^([A-Z][A-Za-z0-9_.]*)\s*\{/.exec(trimmed);
        if (m) return { label: m[1], kind: "type" };
    }
    m = /^(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>/.exec(trimmed);
    if (m) return { label: m[1] + "()", kind: "func" };
    m = /^([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{/.exec(trimmed);
    if (m && !NON_FUNC_KEYWORDS.has(m[1])) return { label: m[1] + "()", kind: "func" };
    m = /^(if|else\s+if|else|for|while|switch|try|catch|finally|with|match)\b/.exec(trimmed);
    if (m) return { label: m[1], kind: "control" };
    return { label: "", kind: "block" };
}

function stripStringsAndCommentsForBraces(line, langId, state) {
    const hashComments = langId === "python" || langId === "shell" || langId === "config";
    const slashComments = !hashComments && langId !== "sql";
    let out = "";
    let i = 0;
    const n = line.length;
    while (i < n) {
        const ch = line[i];
        const next = i + 1 < n ? line[i + 1] : "";
        if (state.inBlockComment) {
            if (ch === "*" && next === "/") {
                state.inBlockComment = false;
                i += 2;
            } else {
                i += 1;
            }
            continue;
        }
        if (slashComments && ch === "/" && next === "/") break;
        if (slashComments && ch === "/" && next === "*") {
            state.inBlockComment = true;
            i += 2;
            continue;
        }
        if (hashComments && ch === "#") break;
        if (ch === '"' || ch === "'" || ch === "`") {
            const q = ch;
            i += 1;
            while (i < n) {
                if (line[i] === "\\") { i += 2; continue; }
                if (line[i] === q) { i += 1; break; }
                i += 1;
            }
            continue;
        }
        out += ch;
        i += 1;
    }
    return out;
}

function analyzeCodeStructure(text, langId) {
    if (!text) return { indentSize: 4, indentCols: [], scopes: [] };
    const lines = text.split("\n");
    const n = lines.length;
    const indentSize = detectIndentSize(lines);
    const rawIndent = new Array(n);
    const nonEmpty = new Array(n);

    for (let i = 0; i < n; ++i) {
        const trimmed = lines[i].trim();
        nonEmpty[i] = trimmed.length > 0;
        rawIndent[i] = nonEmpty[i] ? leadingColumns(lines[i], indentSize) : -1;
    }

    // Rellena líneas vacías con la indentación efectiva entre sus vecinas para no cortar guías.
    const indentCols = new Array(n);
    let lastIndent = 0;
    for (let i = 0; i < n; ++i) {
        if (nonEmpty[i]) {
            lastIndent = rawIndent[i];
            indentCols[i] = lastIndent;
        } else {
            indentCols[i] = lastIndent;
        }
    }
    let nextIndent = 0;
    for (let i = n - 1; i >= 0; --i) {
        if (nonEmpty[i]) {
            nextIndent = rawIndent[i];
        } else {
            indentCols[i] = Math.min(indentCols[i], nextIndent);
        }
    }

    const scopes = [];
    const indentBased = langId === "python" || langId === "config";

    if (indentBased) {
        const stack = [];
        for (let i = 0; i < n; ++i) {
            if (!nonEmpty[i]) continue;
            const col = rawIndent[i];
            const trimmed = lines[i].trim();
            while (stack.length > 0 && col <= stack[stack.length - 1].indentCol) {
                const popped = stack.pop();
                let end = i - 1;
                while (end > popped.startLine && !nonEmpty[end]) end--;
                if (end > popped.startLine) {
                    popped.endLine = end;
                    scopes.push(popped);
                }
            }
            if (trimmed.endsWith(":") && !trimmed.startsWith("#")) {
                const info = classifyScopeHeader(trimmed, langId);
                stack.push({
                    startLine: i,
                    endLine: n - 1,
                    indentCol: col,
                    label: info.label,
                    kind: info.kind
                });
            }
        }
        while (stack.length > 0) {
            const popped = stack.pop();
            let end = n - 1;
            while (end > popped.startLine && !nonEmpty[end]) end--;
            if (end > popped.startLine) {
                popped.endLine = end;
                scopes.push(popped);
            }
        }
    } else {
        const stack = [];
        const commentState = { inBlockComment: false };
        for (let i = 0; i < n; ++i) {
            const cleaned = stripStringsAndCommentsForBraces(lines[i], langId, commentState);
            if (!cleaned) continue;
            const trimmed = lines[i].trim();
            const col = nonEmpty[i] ? rawIndent[i] : 0;
            for (let k = 0; k < cleaned.length; ++k) {
                const ch = cleaned[k];
                if (ch === "{") {
                    const info = classifyScopeHeader(trimmed, langId);
                    stack.push({
                        startLine: i,
                        endLine: i,
                        indentCol: col,
                        label: info.label,
                        kind: info.kind
                    });
                } else if (ch === "}" && stack.length > 0) {
                    const popped = stack.pop();
                    if (i > popped.startLine) {
                        popped.endLine = i;
                        scopes.push(popped);
                    }
                }
            }
        }
    }

    scopes.sort(function(a, b) {
        if (a.startLine !== b.startLine) return a.startLine - b.startLine;
        return b.endLine - a.endLine;
    });

    return { indentSize: indentSize, indentCols: indentCols, scopes: scopes };
}

function findActiveScopes(scopes, lineIndex) {
    if (!scopes || !scopes.length || lineIndex < 0) return [];
    const matched = [];
    for (let i = 0; i < scopes.length; ++i) {
        const s = scopes[i];
        if (s.startLine <= lineIndex && lineIndex <= s.endLine)
            matched.push(s);
    }
    return matched;
}
