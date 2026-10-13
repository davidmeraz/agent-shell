import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "../../ui"
import "../../ui/js/ChatCommands.js" as ChatCommands

// Comandos reales en el workspace temporal; cuenta y servicio HTTP de prueba.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property var prompt: null
    property string savedChatId: ""
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 560; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function check(value, message) {
        if (value) return true;
        console.error("SHELL_COMMAND_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function submit(text) {
        prompt.forceActiveFocus(); prompt.text = text; prompt.cursorPosition = prompt.length;
        inspector.wait(20); inspector.keyClick(Qt.Key_Return);
    }
    function call(index) { return JSON.parse(agent.messages.get(index).toolJson); }
    Timer {
        id: steps
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (scenario.stepping) return;
            scenario.stepping = true;
            try {
                if (scenario.stage === 0) {
                    if (!agent.canRunShell) return;
                    agent.authenticated = false;
                    agent.availableModels.clear();
                    scenario.prompt = inspector.findChild(chat, "chatPrompt");
                    chat.contentItem.Window.window.requestActivate();
                    scenario.prompt.forceActiveFocus(); scenario.prompt.text = "/sh";
                    inspector.wait(50); inspector.keyClick(Qt.Key_Tab); inspector.wait(50);
                    if (!scenario.check(scenario.prompt.text === "/shell " && !agent.busy && !agent.messages.count,
                        "completar /shell no prepara el argumento o ejecuta un proceso")) return;
                    inspector.keyClick(Qt.Key_Return);
                    if (!scenario.check(scenario.prompt.text === "/shell " && !agent.busy && !agent.currentChatId,
                        "comando sin argumento se envía o borra el borrador")) return;
                    const raw = "printf '%s' 'a b' | tr a-z A-Z\nprintf done ";
                    if (!scenario.check(ChatCommands.parse("/shell " + raw).command === raw
                        && !!ChatCommands.parse("/shell pwd\0").error
                        && !!ChatCommands.parse("/shell " + "x".repeat(8001)).error,
                        "parser altera el comando o admite NUL/longitud inválida")) return;
                    scenario.submit("/shell pwd");
                    inspector.wait(10);
                    if (!scenario.check(scenario.prompt.text === "" && !inspector.findChild(chat, "chatInlineSuggestions").visible,
                        "envío conserva borrador o menú")) return;
                    scenario.stage = 1;
                } else if (scenario.stage === 1) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.messages.count === 1 && scenario.call(0).source === "local"
                        && scenario.call(0).output.trim() === agent.workspace && scenario.call(0).exit_code === 0
                        && !agent.performanceHistory.length && agent.canRunShell && !agent.canSend,
                        "pwd local sin sesión no muestra salida o crea métricas de IA")) return;
                    const list = inspector.findChild(chat, "chatMessageList");
                    inspector.wait(100);
                    const card = inspector.findChild(list.itemAtIndex(0), "chatToolCall");
                    if (!scenario.check(!!card && inspector.findChild(card, "chatShellOutput").text.trim() === agent.workspace,
                        "salida no renderizada en tarjeta")) return;
                    const state = inspector.findChild(card, "chatShellStatus");
                    if (!scenario.check(state.text.includes("Completado") && !!card.durationLabel
                        && inspector.findChild(card, "chatShellDirectory").text.startsWith("Local"),
                        "estado, duración o procedencia ausentes")) return;
                    scenario.savedChatId = agent.currentChatId;
                    scenario.submit("/shell printf '%s' 'a b' | tr a-z A-Z; printf 'err' >&2; exit 7 ");
                    scenario.stage = 2;
                } else if (scenario.stage === 2) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.messages.count === 2 && scenario.call(1).output === "A Berr"
                        && scenario.call(1).exit_code === 7 && scenario.call(1).status === "error"
                        && scenario.call(1).command.endsWith(" "), "comillas, tuberías, stderr o código de salida incorrectos")) return;
                    scenario.submit("/shell printf ready; sleep 30");
                    scenario.stage = 3;
                } else if (scenario.stage === 3) {
                    if (agent.messages.count < 3 || scenario.call(2).output !== "ready") return;
                    if (!scenario.check(agent.busy && agent.shellRunning
                        && !inspector.findChild(chat, "chatThinkingIndicator").visible
                        && !inspector.findChild(chat, "chatActiveModel").visible
                        && !agent.submit("/shell pwd"), "ejecución simultánea o indicador de IA en comando local")) return;
                    const stop = inspector.findChild(chat, "chatSendButton");
                    if (!scenario.check(stop.text.startsWith("Detener") && stop.enabled && scenario.prompt.text === "",
                        "el botón no permite detener con editor vacío y sin sesión")) return;
                    scenario.prompt.text = "Borrador para después";
                    inspector.mouseClick(stop);
                    scenario.stage = 4;
                } else if (scenario.stage === 4) {
                    if (agent.busy) return;
                    if (!scenario.check(!agent.shellRunning && scenario.call(2).status === "interrupted"
                        && scenario.call(2).output === "ready" && !agent.performanceHistory.length,
                        "detener pierde salida o conserva ejecución activa")) return;
                    const send = inspector.findChild(chat, "chatSendButton");
                    if (!scenario.check(send.text.startsWith("Enviar") && !send.enabled
                        && scenario.prompt.text === "Borrador para después",
                        "detener no recupera Enviar o elimina el borrador")) return;
                    scenario.prompt.clear();
                    agent.newChat();
                    scenario.stage = 5;
                } else if (scenario.stage === 5) {
                    if (agent.messages.count) return;
                    agent.openChat(scenario.savedChatId);
                    scenario.stage = 6;
                } else if (scenario.stage === 6) {
                    if (agent.openingChat) return;
                    if (!scenario.check(agent.messages.count === 3 && scenario.call(0).source === "local"
                        && scenario.call(2).status === "interrupted" && !agent.shellRunning && !agent.busy,
                        "historial no recupera las tarjetas o vuelve a ejecutar")) return;
                    scenario.submit("/shell i=1; while [ $i -le 18 ]; do printf 'line %s\\n' $i; i=$((i+1)); done");
                    scenario.stage = 7;
                } else if (scenario.stage === 7) {
                    if (agent.busy) return;
                    const list = inspector.findChild(chat, "chatMessageList");
                    list.positionViewAtEnd(); inspector.wait(100);
                    const card = inspector.findChild(list.itemAtIndex(3), "chatToolCall");
                    const output = inspector.findChild(card, "chatShellOutput");
                    const expand = inspector.findChild(card, "chatShellExpand");
                    const copy = inspector.findChild(card, "chatCopyShellOutput");
                    const original = scenario.call(3).output;
                    if (!scenario.check(card.hasMoreOutput && !card.expanded && expand.visible
                        && output.text.split("\n").length === 8 && !output.text.includes("line 18"),
                        "salida larga sin vista compacta o botón de ampliación")) return;
                    const height = card.height;
                    output.select(0, 6); const selection = output.selectedText;
                    inspector.mouseClick(copy);
                    if (!scenario.check(Quickshell.clipboardText === original && copy.copied
                        && output.selectedText === selection, "copiar pierde salida original o selección")) return;
                    inspector.mouseClick(expand); inspector.wait(80);
                    if (!scenario.check(card.expanded && output.text.includes("line 18") && card.height > height,
                        "ampliar no muestra la salida completa")) return;
                    list.positionViewAtEnd(); inspector.wait(50);
                    inspector.mouseClick(expand); inspector.wait(80);
                    if (!scenario.check(!card.expanded && Math.abs(card.height - height) < 1,
                        "colapsar no recupera el tamaño compacto")) return;
                    console.log("SHELL_COMMAND_OK: /shell, tarjetas compactas, duración, salida completa, copia, errores, cancelación e historial sin IA");
                    steps.stop(); Qt.callLater(Qt.quit);
                }
            } finally { scenario.stepping = false; }
        }
    }
}
