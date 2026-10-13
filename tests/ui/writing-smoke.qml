import QtQuick
import QtTest
import Quickshell
import "../../ui"

// Guardado atómico por shell real; después verifica retarget y ciclo del visor.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool sawProgress: false
    property bool sawAfterFinish: false
    property bool sawCursor: false
    property bool pausedReading: false
    property string nextText: ""
    property double startedAt: 0
    readonly property var viewer: chat.explorerWindow.firstFileWindow
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 700; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function source() {
        let text = "// Escritura de prueba 🙂: <texto>\n";
        for (let i = 0; i < 35; ++i) text += "const valor_" + i + " = " + i + ";\n";
        return text;
    }
    function check(value, message) {
        if (value) return true;
        console.error("WRITING_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function validUnicode(text) {
        for (let i = 0; i < text.length; ++i) {
            const value = text.charCodeAt(i);
            if (value >= 0xd800 && value <= 0xdbff) {
                const next = text.charCodeAt(++i);
                if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
            } else if (value >= 0xdc00 && value <= 0xdfff) return false;
        }
        return true;
    }
    Timer {
        id: steps
        interval: 30
        running: true
        repeat: true
        onTriggered: {
            const code = inspector.findChild(scenario.viewer, "projectExplorerPreview");
            if (!scenario.check(scenario.validUnicode(code.text), "Unicode incompleto al revelar texto")) return;
            if (scenario.stage === 0) {
                if (!agent.canSend) return;
                agent.createProject("Escritura animada", agent.workspace);
                scenario.stage = 1;
            } else if (scenario.stage === 1) {
                if (!agent.canSend || !agent.projectId) return;
                agent.submit("shell-write");
                scenario.stage = 2;
            } else if (scenario.stage === 2) {
                if (scenario.viewer.writing && code.text.length > 0 && code.text.length < scenario.viewer.preview.length) {
                    scenario.sawProgress = true;
                    if (!scenario.check(scenario.source().startsWith(code.text), "texto ajeno al archivo guardado")) return;
                    const cursor = inspector.findChild(scenario.viewer, "projectCodeWritingCursor");
                    scenario.sawCursor = cursor.visible && cursor.height > 0;
                }
                if (!agent.busy && scenario.viewer.writing) scenario.sawAfterFinish = true;
                if (agent.busy || scenario.viewer.writing || scenario.viewer.preview !== scenario.source()) return;
                if (!scenario.check(scenario.sawProgress && scenario.sawAfterFinish && scenario.sawCursor
                    && code.text === scenario.source() && code.readOnly && code.textFormat === TextEdit.PlainText,
                    "guardado atómico sin escritura progresiva completa y cursor")) return;
                scenario.nextText = scenario.source().replace("valor_10 = 10", 'valor_10 = "hola 🙂"');
                scenario.viewer.applyPreview({text: scenario.nextText, truncated: false}, true);
                if (!scenario.check(code.text.endsWith("const valor_34 = 34;\n") && scenario.viewer.writing,
                    "la modificación pierde el sufijo intacto")) return;
                scenario.viewer.applyPreview({text: scenario.nextText, truncated: false}, false);
                if (!scenario.check(scenario.viewer.writing, "el sondeo idéntico interrumpe la escritura")) return;
                scenario.stage = 3;
            } else if (scenario.stage === 3) {
                scenario.nextText = scenario.nextText.replace("hola 🙂", "hola 👩‍💻").replace("valor_11 = 11", "valor_11 = 999");
                scenario.viewer.applyPreview({text: scenario.nextText, truncated: false}, true);
                scenario.stage = 4;
            } else if (scenario.stage === 4) {
                if (scenario.viewer.writing) return;
                if (!scenario.check(code.text === scenario.nextText, "la ráfaga no termina en la última versión")) return;
                scenario.viewer.activityState = "running";
                scenario.nextText += "// cancelar " + "x".repeat(500);
                scenario.viewer.applyPreview({text: scenario.nextText, truncated: false}, true);
                scenario.viewer.activityState = "interrupted";
                if (!scenario.check(!scenario.viewer.writing && code.text === scenario.nextText,
                    "cancelar deja un documento visual incompleto")) return;
                scenario.nextText = "const emoji = '🙂';\r\n// siguiente\r\n".repeat(8);
                scenario.viewer.applyPreview({text: scenario.nextText, truncated: false}, true);
                scenario.stage = 8;
            } else if (scenario.stage === 8) {
                if (scenario.viewer.writing) return;
                if (!scenario.check(code.text === scenario.nextText.replace(/\r\n/g, "\n")
                    && scenario.viewer.preview === scenario.nextText,
                    "los saltos CRLF rompen el documento o alteran la instantánea original")) return;
                scenario.nextText = "// " + "z".repeat(128 * 1024 - 4) + "\n";
                scenario.viewer.applyPreview({text: scenario.nextText, truncated: true}, true);
                scenario.startedAt = Date.now();
                scenario.stage = 5;
            } else if (scenario.stage === 5) {
                if (scenario.viewer.writing) {
                    if (!scenario.check(Date.now() - scenario.startedAt < 3500, "la vista grande acumula retraso")) return;
                    if (!scenario.pausedReading && scenario.viewer.scroller.contentY > 0) {
                        scenario.pausedReading = true;
                        scenario.viewer.followWriting = false;
                        scenario.viewer.scroller.contentY = 0;
                    } else if (scenario.pausedReading && !scenario.check(scenario.viewer.scroller.contentY < 1,
                        "la escritura desplaza al usuario que está leyendo: y=" + scenario.viewer.scroller.contentY
                        + ", seguimiento=" + scenario.viewer.followWriting + ", foco=" + code.activeFocus)) return;
                    return;
                }
                if (!scenario.check(code.text === scenario.nextText && scenario.viewer.previewTruncated && scenario.pausedReading,
                    "la vista grande no termina exactamente: longitud=" + code.text.length
                    + ", esperada=" + scenario.nextText.length + ", parcial=" + scenario.viewer.previewTruncated
                    + ", inicio=" + code.text.slice(0, 12) + ", final=" + code.text.slice(-12))) return;
                scenario.viewer.applyPreview({text: "siguiente " + "q".repeat(500), truncated: false}, true);
                scenario.viewer.markDeleted();
                if (!scenario.check(!scenario.viewer.writing && code.text === scenario.viewer.preview
                    && scenario.viewer.deleted, "eliminación durante escritura pierde la última vista")) return;
                scenario.viewer.deleted = false;
                scenario.viewer.activityState = "running";
                scenario.viewer.applyPreview({text: "rotación " + "a".repeat(500), truncated: false}, true);
                if (!scenario.check(scenario.viewer.writing, "falta escritura antes de cerrar")) return;
                scenario.viewer.closed();
                if (!scenario.check(!scenario.viewer.visible && !scenario.viewer.writing, "cierre deja un temporizador activo")) return;
                scenario.viewer.openFile("src/main.js");
                scenario.stage = 6;
            } else if (scenario.stage === 6) {
                if (scenario.viewer.pendingId || scenario.viewer.preview !== scenario.source()) return;
                if (!scenario.check(code.text === scenario.source() && !scenario.viewer.writing,
                    "reapertura manual hereda texto o animación anteriores")) return;
                agent.selectArea("chat");
                scenario.stage = 7;
            } else if (scenario.stage === 7) {
                if (agent.areaBusy || agent.activeArea !== "chat") return;
                if (!scenario.check(!scenario.viewer.writing && scenario.viewer.visible && code.text === scenario.source(),
                    "cambiar a Chat pierde el archivo del proyecto")) return;
                console.log("WRITING_OK: guardado atómico real, escritura progresiva, cursor, Unicode y CRLF, prefijo/sufijo, retarget, sondeo, cancelación, 128 KiB, seguimiento sin interrumpir lectura, eliminación, cierre y reapertura");
                steps.stop(); Qt.callLater(Qt.quit);
            }
        }
    }
}
