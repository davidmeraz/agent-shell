import QtQuick
import "../../js/FileChanges.js" as FileChanges

// Presentación local de texto ya recibido: ritmo suave a 60 fps con curva orgánica, sin cola de versiones.
QtObject {
    id: reveal
    required property TextEdit editor
    property string targetText: ""
    property int start: 0
    property int end: 0
    property int position: 0
    property double startedAt: 0
    property int duration: 480
    property real progress: 1
    readonly property bool running: ticker.running
    signal advanced()

    function reset(text) {
        text = FileChanges.visibleText(text);
        ticker.stop();
        targetText = text;
        editor.text = text;
        start = 0; end = text.length; position = end;
        progress = 1;
    }
    function finish() {
        ticker.stop();
        if (editor.text !== targetText) editor.text = targetText;
        position = end;
        progress = 1;
        advanced();
    }
    function apply(text, animated) {
        text = FileChanges.visibleText(text);
        if (text === targetText) return;
        ticker.stop();
        targetText = text;
        if (!animated) { reset(text); return; }
        const changed = FileChanges.span(editor.text, text);
        start = changed.start; end = changed.newEnd; position = start;
        // El prefijo y sufijo intactos permanecen; sólo se escribe la parte nueva.
        editor.remove(start, changed.oldEnd);
        if (start === end) { finish(); return; }
        const spanLen = end - start;
        // Duración sublineal: pausada y apreciable en código normal, acotada en bloques enormes.
        if (spanLen <= 4000) {
            duration = Math.round(Math.min(2650, Math.max(460, 260 + Math.pow(spanLen, 0.64) * 28)));
        } else {
            duration = Math.round(Math.min(2650, 2200 + Math.min(450, (spanLen - 4000) * 0.005)));
        }
        progress = 0;
        startedAt = Date.now();
        ticker.start();
        advanced();
    }
    function advance() {
        const raw = Math.min(1, (Date.now() - startedAt) / duration);
        // Curva en S combinada con flujo lineal: entrada suave, ritmo constante y cierre elegante.
        const eased = raw >= 1 ? 1 : (0.35 * raw + 0.65 * (0.5 - 0.5 * Math.cos(Math.PI * raw)));
        progress = eased;
        const next = FileChanges.nextBoundary(targetText,
            Math.max(position, start + Math.floor((end - start) * eased)), end);
        if (next > position) {
            editor.insert(position, targetText.slice(position, next));
            position = next;
            advanced();
        }
        if (position >= end || raw >= 1) {
            if (position < end) {
                editor.insert(position, targetText.slice(position, end));
                position = end;
                advanced();
            }
            progress = 1;
            ticker.stop();
        }
    }
    readonly property Timer ticker: Timer {
        interval: 16
        repeat: true
        onTriggered: reveal.advance()
    }
}
