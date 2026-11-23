.pragma library
.import "CodeSyntax.js" as CodeSyntax

// Convierte Markdown de las respuestas del asistente en RichText (HTML/CSS compatible con Qt 6)
// con paleta armónica sincronizada al tema Gema, espaciado editorial y bloques de código resaltados.

function escapeHtml(text) {
    if (!text) return "";
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function rgbaFromHex(hex, alpha) {
    const rgb = CodeSyntax.hexToRgb(hex || "#c4dcff");
    const r = Math.round(rgb.r * 255);
    const g = Math.round(rgb.g * 255);
    const b = Math.round(rgb.b * 255);
    return "rgba(" + r + "," + g + "," + b + "," + alpha + ")";
}

function safeUrl(raw) {
    const trimmed = (raw || "").trim();
    if (/^(https?:\/\/|mailto:)/i.test(trimmed))
        return escapeHtml(trimmed);
    return "";
}

function makeTheme(palette, accentHex, darkText) {
    const pal = palette || CodeSyntax.buildPalette(accentHex || "#c4dcff", !!darkText, true);
    const accent = accentHex || pal.accent || "#c4dcff";
    if (darkText) {
        return {
            pal: pal,
            accent: pal.accent || accent,
            h2: pal.accent || accent,
            h3: pal.type || accent,
            h4: pal.func || accent,
            body: "#1b2430",
            strong: "#0d131c",
            italic: pal.property || "#2a384a",
            muted: "#4d5d72",
            inlineCodeFg: pal.func || pal.keyword || "#1a5276",
            inlineCodeBg: rgbaFromHex(accent, 0.14),
            codeHeaderBg: rgbaFromHex(accent, 0.16),
            codeBodyBg: "rgba(18,24,34,0.08)",
            codeBorder: rgbaFromHex(accent, 0.28),
            tableHeaderBg: rgbaFromHex(accent, 0.18),
            tableRowOdd: "rgba(18,24,34,0.03)",
            tableRowEven: "rgba(18,24,34,0.07)",
            tableBorder: "rgba(18,24,34,0.16)",
            quoteBg: rgbaFromHex(accent, 0.10),
            quoteText: "#273547",
            ruleColor: rgbaFromHex(accent, 0.30)
        };
    }
    return {
        pal: pal,
        accent: accent,
        h2: accent,
        h3: pal.type || "#d2c4ff",
        h4: pal.func || "#9ce5d8",
        body: "#e6ecf4",
        strong: "#ffffff",
        italic: pal.property || "#d4e3f8",
        muted: "#a9b7c9",
        inlineCodeFg: pal.func || "#9ee6d4",
        inlineCodeBg: rgbaFromHex(accent, 0.14),
        codeHeaderBg: rgbaFromHex(accent, 0.15),
        codeBodyBg: "rgba(7,11,18,0.56)",
        codeBorder: rgbaFromHex(accent, 0.26),
        tableHeaderBg: rgbaFromHex(accent, 0.18),
        tableRowOdd: "rgba(255,255,255,0.03)",
        tableRowEven: "rgba(255,255,255,0.07)",
        tableBorder: "rgba(255,255,255,0.14)",
        quoteBg: rgbaFromHex(accent, 0.10),
        quoteText: "#d7e3f4",
        ruleColor: rgbaFromHex(accent, 0.28)
    };
}

// Cierra virtualmente marcadores Markdown abiertos durante el streaming para evitar destellos de sintaxis cruda.
function closeOpenMarkdown(partial) {
    if (!partial) return "";
    const text = partial;
    const fenceMatches = text.match(/^```/gm);
    if (fenceMatches && (fenceMatches.length % 2 === 1))
        return text + "\n```";
    const lastNewline = text.lastIndexOf("\n");
    let lastLine = lastNewline >= 0 ? text.slice(lastNewline + 1) : text;
    const prefix = lastNewline >= 0 ? text.slice(0, lastNewline + 1) : "";
    lastLine = lastLine.replace(/(\*\*|\*|`)+$/, function(match) {
        const withoutTrailing = lastLine.slice(0, lastLine.length - match.length);
        const outsideCode = withoutTrailing.replace(/`[^`]*`/g, "");
        const boldBefore = (outsideCode.match(/\*\*/g) || []).length;
        const codeBefore = (withoutTrailing.match(/`/g) || []).length;
        if (match === "`" && (codeBefore % 2 === 1)) return match;
        if (match === "**" && (boldBefore % 2 === 1)) return match;
        if (match === "*" && (boldBefore % 2 === 1)) return "**";
        return "";
    });
    const ticks = (lastLine.match(/`/g) || []).length;
    if (ticks % 2 === 1)
        lastLine += "`";
    const outsideCode = lastLine.replace(/`[^`]*`/g, "");
    const bolds = (outsideCode.match(/\*\*/g) || []).length;
    if (bolds % 2 === 1)
        lastLine += "**";
    return prefix + lastLine;
}

function renderInline(text, theme) {
    if (!text) return "";
    const out = [];
    const n = text.length;
    let i = 0;

    while (i < n) {
        const ch = text[i];

        // Escape con barra invertida (\*, \`, \[, etc.)
        if (ch === "\\" && i + 1 < n && /[*_`[\]()~#\\|>-]/.test(text[i + 1])) {
            out.push(escapeHtml(text[i + 1]));
            i += 2;
            continue;
        }

        // Código en línea `...` o ``...``
        if (ch === "`") {
            let ticks = 1;
            while (i + ticks < n && text[i + ticks] === "`") ticks++;
            const delim = text.slice(i, i + ticks);
            const end = text.indexOf(delim, i + ticks);
            if (end > i + ticks) {
                const code = text.slice(i + ticks, end);
                out.push('<span style="font-family:monospace;font-size:13px;color:' + theme.inlineCodeFg
                    + ";background-color:" + theme.inlineCodeBg + ';">&nbsp;' + escapeHtml(code) + "&nbsp;</span>");
                i = end + ticks;
                continue;
            }
        }

        // Enlaces [etiqueta](url)
        if (ch === "[") {
            const closeBracket = text.indexOf("]", i + 1);
            if (closeBracket > i + 1 && text[closeBracket + 1] === "(") {
                const closeParen = text.indexOf(")", closeBracket + 2);
                if (closeParen > closeBracket + 2) {
                    const label = text.slice(i + 1, closeBracket);
                    const url = safeUrl(text.slice(closeBracket + 2, closeParen));
                    if (url) {
                        out.push('<a href="' + url + '" style="color:' + theme.accent + ';text-decoration:underline;">'
                            + renderInline(label, theme) + "</a>");
                        i = closeParen + 1;
                        continue;
                    }
                }
            }
        }

        // Negrita + cursiva ***...***
        if (ch === "*" && text.startsWith("***", i)) {
            const end = text.indexOf("***", i + 3);
            if (end > i + 3) {
                out.push('<b style="color:' + theme.strong + ';"><i>' + renderInline(text.slice(i + 3, end), theme) + "</i></b>");
                i = end + 3;
                continue;
            }
        }

        // Negrita **...**
        if (ch === "*" && text[i + 1] === "*") {
            const end = text.indexOf("**", i + 2);
            if (end > i + 2) {
                out.push('<b style="color:' + theme.strong + ';">' + renderInline(text.slice(i + 2, end), theme) + "</b>");
                i = end + 2;
                continue;
            }
        }

        // Tachado ~~...~~
        if (ch === "~" && text[i + 1] === "~") {
            const end = text.indexOf("~~", i + 2);
            if (end > i + 2) {
                out.push('<s style="color:' + theme.muted + ';">' + renderInline(text.slice(i + 2, end), theme) + "</s>");
                i = end + 2;
                continue;
            }
        }

        // Cursiva *...*
        if (ch === "*" && text[i + 1] !== " " && text[i + 1] !== "*") {
            const end = text.indexOf("*", i + 1);
            if (end > i + 1 && text[end - 1] !== " ") {
                out.push('<i style="color:' + theme.italic + ';">' + renderInline(text.slice(i + 1, end), theme) + "</i>");
                i = end + 1;
                continue;
            }
        }

        // Avanzar bloque de texto normal de una sola vez
        let j = i + 1;
        while (j < n && text[j] !== "\\" && text[j] !== "`" && text[j] !== "[" && text[j] !== "*" && text[j] !== "~")
            j++;
        out.push(escapeHtml(text.slice(i, j)));
        i = j;
    }

    return out.join("");
}

function splitTableCells(row) {
    const trimmed = row.trim();
    const inner = trimmed.replace(/^\|/, "").replace(/\|$/, "");
    return inner.split("|").map(function(cell) { return cell.trim(); });
}

function parseTableAlign(sepRow) {
    return splitTableCells(sepRow).map(function(cell) {
        const left = cell.startsWith(":");
        const right = cell.endsWith(":");
        if (left && right) return "center";
        if (right) return "right";
        return "left";
    });
}

function normalizeFenceLang(langRaw) {
    const clean = (langRaw || "").trim().toLowerCase();
    const aliases = {
        python: "py", py3: "py",
        javascript: "js", node: "js",
        typescript: "ts",
        rust: "rs",
        bash: "sh", shell: "sh", zsh: "sh", fish: "sh", console: "sh",
        "c++": "cpp", cxx: "cpp", cc: "cpp",
        "c#": "cs", csharp: "cs",
        kotlin: "kt",
        markdown: "md",
        yaml: "yml",
        dockerfile: "sh", makefile: "sh"
    };
    return aliases[clean] || clean;
}

function renderCodeBlock(codeLines, langRaw, theme, isFirst) {
    const langTrim = (langRaw || "").trim();
    const ext = normalizeFenceLang(langTrim);
    const detected = ext ? CodeSyntax.detectLanguage("x." + ext) : { id: "plain", label: "CÓDIGO" };
    const label = langTrim ? langTrim.toUpperCase().slice(0, 16) : "CÓDIGO";
    const rawCode = codeLines.join("\n");
    const highlighted = detected.id === "plain"
        ? escapeHtml(rawCode)
        : CodeSyntax.highlightInner(rawCode, detected.id, theme.pal);
    const mt = isFirst ? 6 : 18;

    return '<table width="100%" cellspacing="0" cellpadding="0" style="margin-top:' + mt + 'px;margin-bottom:18px;">'
        + '<tr><td><table width="100%" cellspacing="0" cellpadding="12" style="border:1px solid ' + theme.codeBorder
        + ";background-color:" + theme.codeBodyBg + ';">'
        + '<tr><td style="border-bottom:1px solid ' + theme.codeBorder + ';">'
        + '<span style="color:' + theme.accent + ';font-size:10px;font-weight:700;">●&nbsp;&nbsp;' + escapeHtml(label) + "</span>"
        + "</td></tr>"
        + '<tr><td>'
        + '<pre style="margin:0;white-space:pre-wrap;font-family:monospace;font-size:13px;line-height:142%;color:'
        + theme.pal.plain + ';">' + highlighted + "</pre>"
        + "</td></tr></table></td></tr></table>";
}

function renderTableBlock(rows, theme, isFirst) {
    if (!rows.length) return "";
    const mt = isFirst ? 6 : 18;
    let hasHeader = false;
    let aligns = [];
    let bodyStart = 0;

    if (rows.length >= 2 && /^\|?[\s:-]+(?:\|[\s:-]+)+\|?$/.test(rows[1].trim())) {
        hasHeader = true;
        aligns = parseTableAlign(rows[1]);
        bodyStart = 2;
    } else if (rows.length === 2 && /^\|[\s|:-]*$/.test(rows[1].trim())) {
        // Separador a medio escribir durante el streaming.
        hasHeader = true;
        bodyStart = 2;
    }

    const html = ['<table width="100%" cellspacing="0" cellpadding="0" style="margin-top:' + mt
        + 'px;margin-bottom:18px;"><tr><td><table width="100%" cellspacing="0" cellpadding="10" style="border:1px solid '
        + theme.tableBorder + ";background-color:" + theme.codeBodyBg + ';">'];

    if (hasHeader) {
        const headers = splitTableCells(rows[0]);
        html.push("<tr>");
        for (let c = 0; c < headers.length; ++c) {
            const align = aligns[c] || "left";
            html.push('<th align="' + align + '" style="color:' + theme.accent
                + ";font-size:13px;font-weight:700;border-bottom:1px solid " + theme.codeBorder + ';">'
                + renderInline(headers[c], theme) + "</th>");
        }
        html.push("</tr>");
    }

    for (let r = bodyStart; r < rows.length; ++r) {
        if (/^\|[\s|:-]*$/.test(rows[r].trim())) continue;
        const cells = splitTableCells(rows[r]);
        html.push("<tr>");
        for (let c = 0; c < cells.length; ++c) {
            const align = aligns[c] || "left";
            html.push('<td align="' + align + '" style="color:' + theme.body
                + ';font-size:14px;line-height:140%;border-top:1px solid ' + theme.tableBorder + ';">'
                + renderInline(cells[c], theme) + "</td>");
        }
        html.push("</tr>");
    }

    html.push("</table></td></tr></table>");
    return html.join("");
}

function renderQuoteBlock(quoteLines, theme, isFirst) {
    const mt = isFirst ? 6 : 16;
    const inner = quoteLines.map(function(l) { return renderInline(l, theme); }).join("<br/>");
    return '<table width="100%" cellspacing="0" cellpadding="0" style="margin-top:' + mt + 'px;margin-bottom:18px;">'
        + '<tr><td><table width="100%" cellspacing="0" cellpadding="12" style="border:1px solid ' + theme.codeBorder
        + ";background-color:" + theme.quoteBg + ';">'
        + '<tr><td style="color:' + theme.quoteText + ';line-height:144%;font-size:14px;">'
        + '<span style="color:' + theme.accent + ';font-weight:700;">▎&nbsp;&nbsp;</span>' + inner + "</td></tr></table></td></tr></table>";
}

function isBlockStart(line) {
    const t = line.trim();
    if (!t) return true;
    if (t.startsWith("```")) return true;
    if (/^#{1,6}\s+/.test(t)) return true;
    if (/^>\s?/.test(t)) return true;
    if (/^([-*_])\1{2,}$/.test(t)) return true;
    if (/^(\s*)(?:[-*+]|\d+\.)\s+/.test(line)) return true;
    if (/^\|.*\|$/.test(t)) return true;
    return false;
}

function toHtml(raw, palette, accentHex, darkText) {
    if (!raw) return "";
    const theme = makeTheme(palette, accentHex, darkText);
    const lines = raw.replace(/\r\n/g, "\n").split("\n");
    const blocks = [];
    let i = 0;

    while (i < lines.length) {
        const line = lines[i];
        const trimmed = line.trim();

        if (!trimmed) {
            i++;
            continue;
        }

        const isFirst = blocks.length === 0;

        // 1. Bloque de código ```lang ... ```
        const fence = /^\s*```+([A-Za-z0-9_+#.-]*)\s*$/.exec(line);
        if (fence) {
            const lang = fence[1] || "";
            const codeLines = [];
            i++;
            while (i < lines.length && !/^\s*```+\s*$/.test(lines[i])) {
                codeLines.push(lines[i]);
                i++;
            }
            if (i < lines.length) i++;
            blocks.push(renderCodeBlock(codeLines, lang, theme, isFirst));
            continue;
        }

        // 2. Separador horizontal --- / *** / ___
        if (/^([-*_])\1{2,}$/.test(trimmed)) {
            blocks.push("<hr/>");
            i++;
            continue;
        }

        // 3. Encabezados # .. ######
        const heading = /^(#{1,6})\s+(.*)$/.exec(trimmed);
        if (heading) {
            const level = heading[1].length;
            const titleHtml = renderInline(heading[2].trim(), theme);
            const sizes = [19, 17, 16, 15, 14, 14];
            const colors = [theme.accent, theme.h2, theme.h3, theme.h4, theme.strong, theme.strong];
            const topMargins = [26, 22, 18, 16, 14, 12];
            const bottomMargins = [12, 10, 8, 6, 6, 6];
            const mt = isFirst ? 2 : topMargins[level - 1];
            const mb = bottomMargins[level - 1];
            blocks.push('<p style="margin-top:' + mt + "px;margin-bottom:" + mb + "px;font-size:"
                + sizes[level - 1] + "px;font-weight:700;line-height:130%;color:" + colors[level - 1] + ';">'
                + titleHtml + "</p>");
            i++;
            continue;
        }

        // 4. Cita / cuadro destacado > ...
        if (/^>\s?/.test(trimmed)) {
            const quoteLines = [];
            while (i < lines.length && /^>\s?/.test(lines[i].trim())) {
                quoteLines.push(lines[i].trim().replace(/^>\s?/, ""));
                i++;
            }
            blocks.push(renderQuoteBlock(quoteLines, theme, isFirst));
            continue;
        }

        // 5. Tabla Markdown | col1 | col2 |
        if (/^\|.*\|$/.test(trimmed)) {
            const tableRows = [];
            while (i < lines.length && lines[i].trim().startsWith("|")) {
                tableRows.push(lines[i]);
                i++;
            }
            blocks.push(renderTableBlock(tableRows, theme, isFirst));
            continue;
        }

        // 6. Listas (-, *, +, 1.) con viñetas acento y aire entre elementos
        const listMatch = /^(\s*)(?:([-*+])|(\d+)\.)\s+(.*)$/.exec(line);
        if (listMatch) {
            const listItems = [];
            while (i < lines.length) {
                const m = /^(\s*)(?:([-*+])|(\d+)\.)\s+(.*)$/.exec(lines[i]);
                if (!m) break;
                const depth = Math.min(3, Math.floor(m[1].length / 2));
                const ordered = !!m[3];
                const marker = ordered ? (m[3] + ".") : (depth > 0 ? "◦" : "•");
                const itemLines = [m[4]];
                i++;
                // Continuación indentada del mismo ítem
                while (i < lines.length && lines[i].trim() !== "" && /^\s{2,}\S/.test(lines[i])
                       && !/^(\s*)(?:[-*+]|\d+\.)\s+/.test(lines[i]) && !isBlockStart(lines[i])) {
                    itemLines.push(lines[i].trim());
                    i++;
                }
                listItems.push({ depth: depth, marker: marker, text: itemLines.join(" ") });
            }
            for (let li = 0; li < listItems.length; ++li) {
                const item = listItems[li];
                const mt = (li === 0) ? (isFirst ? 2 : 12) : 6;
                const mb = (li === listItems.length - 1) ? 14 : 7;
                const ml = 18 + item.depth * 18;
                blocks.push('<p style="margin-top:' + mt + "px;margin-bottom:" + mb + "px;margin-left:" + ml
                    + 'px;text-indent:-14px;line-height:142%;color:' + theme.body + ';">'
                    + '<span style="color:' + theme.accent + ';font-weight:700;">' + item.marker + "&nbsp;&nbsp;</span>"
                    + renderInline(item.text, theme) + "</p>");
            }
            continue;
        }

        // 7. Subtítulo en línea independiente en negrita (**Título:**)
        if (/^\*\*[^*]+\*\*:?$/.test(trimmed)) {
            const mt = isFirst ? 2 : 18;
            blocks.push('<p style="margin-top:' + mt + "px;margin-bottom:8px;font-size:15px;font-weight:700;line-height:138%;color:"
                + theme.h3 + ';">' + renderInline(trimmed.replace(/^\*\*/, "").replace(/\*\*(:?)$/, "$1"), theme) + "</p>");
            i++;
            continue;
        }

        // 8. Párrafo estándar con interlineado cómodo y separación clara
        const paraLines = [trimmed];
        i++;
        while (i < lines.length && !isBlockStart(lines[i])) {
            const prev = paraLines[paraLines.length - 1];
            const nextTrim = lines[i].trim();
            // Si el modelo separa párrafos con un solo salto tras punto/pregunta, les damos aire real.
            if (/[.!?…:]$/.test(prev) && /^[A-ZÁÉÍÓÚÑ¿¡*]/.test(nextTrim))
                break;
            paraLines.push(nextTrim);
            i++;
        }
        const mt = isFirst ? 2 : 12;
        blocks.push('<p style="margin-top:' + mt + "px;margin-bottom:14px;line-height:142%;color:" + theme.body + ';">'
            + paraLines.map(function(l) { return renderInline(l, theme); }).join("<br/>") + "</p>");
    }

    return '<div style="color:' + theme.body + ';line-height:142%;">' + blocks.join("") + "</div>";
}
