import QtQuick
import "../../js/FileChanges.js" as FileChanges

// Presentación local de texto ya recibido: un solo destino, sin cola de versiones.
QtObject {
    id: reveal
    required property TextEdit editor
    property string targetText: ""
    property int start: 0
    property int end: 0
    property int position: 0
    property double startedAt: 0
    property int duration: 180
    readonly property bool running: ticker.running
    signal advanced()

    function reset(text) {
        text = FileChanges.visibleText(text);
        ticker.stop();
        targetText = text;
        editor.text = text;
        start = 0; end = text.length; position = end;
    }
    function finish() {
        ticker.stop();
        if (editor.text !== targetText) editor.text = targetText;
        position = end;
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
        duration = Math.min(1600, Math.max(180, (end - start) * 2));
        startedAt = Date.now();
        ticker.start();
        advanced();
    }
    function advance() {
        const progress = Math.min(1, (Date.now() - startedAt) / duration);
        const next = FileChanges.nextBoundary(targetText,
            Math.max(position, start + Math.floor((end - start) * progress)), end);
        if (next > position) {
            editor.insert(position, targetText.slice(position, next));
            position = next;
            advanced();
        }
        if (position >= end) ticker.stop();
    }
    readonly property Timer ticker: Timer {
        interval: 24
        repeat: true
        onTriggered: reveal.advance()
    }
}
