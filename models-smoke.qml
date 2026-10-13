import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "ui"
import "ui/ChatCommands.js" as ChatCommands

// Familias y esfuerzo con la interfaz y backend reales, catálogo y HTTP locales.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property var prompt
    property var list
    property var composer
    property var menu
    property var layout: ({})
    property string firstChat: ""
    property string secondChat: ""
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 600; implicitHeight: 700 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }

    function check(value, message) {
        if (value) return true;
        console.error("MODELS_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function type(text) {
        prompt.forceActiveFocus(); prompt.text = text; prompt.cursorPosition = prompt.length;
        inspector.wait(30);
    }
    function pick(value, tab) {
        for (let i = 0; i < list.count; ++i) {
            if (composer.completions[i].value === value) {
                list.currentIndex = i;
                inspector.keyClick(tab ? Qt.Key_Tab : Qt.Key_Return);
                inspector.wait(30); return true;
            }
        }
        return check(false, "opción ausente: " + value);
    }
    function stable() {
        return check(Math.abs(composer.height - layout.height) < .5
            && Math.abs(composer.mapToItem(chat.contentItem, 0, 0).y - layout.y) < .5,
            "familia/modelo/esfuerzo desplaza el editor");
    }
    Timer {
        id: steps
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (scenario.stepping) return;
            scenario.stepping = true;
            try {
                if (stage === 0) {
                    if (!agent.canSend) return;
                    scenario.prompt = inspector.findChild(chat, "chatPrompt");
                    scenario.list = inspector.findChild(chat, "chatCommandList");
                    scenario.composer = inspector.findChild(chat, "chatComposer");
                    scenario.menu = inspector.findChild(chat, "chatInlineSuggestions");
                    inspector.findChild(chat, "chatSidebarDrawer").close();
                    inspector.mouseMove(chat.contentItem, chat.width - 20, 100);
                    scenario.layout = { height: composer.height, y: composer.mapToItem(chat.contentItem, 0, 0).y };
                    scenario.type("/modelos");
                    if (!check(list.count === 3 && composer.completions.map(row => row.value).join() === "gpt-6,gpt-5,gpt-4",
                        "familias o orden incorrectos")) return;
                    inspector.keyClick(Qt.Key_Left);
                    if (!check(list.currentIndex === 2, "izquierda no recorre familias")) return;
                    inspector.keyClick(Qt.Key_Right);
                    if (!check(list.currentIndex === 0, "derecha no recorre familias")) return;
                    if (!scenario.pick("gpt-6", true)) return;
                    if (!check(prompt.text === "/modelos gpt-6 " && list.count === 2 && menu.visible
                        && agent.modelName === "gpt-6.1-sol" && !agent.reasoningEffort, "Tab no navega sin aplicar")) return;
                    if (!scenario.stable() || !scenario.pick("gpt-6.1-sol", false)) return;
                    if (!check(prompt.text === "/modelos gpt-6 gpt-6.1-sol " && list.count === 6
                        && !composer.completions.some(row => row.value === "none") && !agent.reasoningEffort,
                        "modelo no abre esfuerzos compatibles")) return;
                    if (!scenario.stable() || !scenario.pick("high", true)) return;
                    if (!check(prompt.text === "/modelos gpt-6 gpt-6.1-sol high" && !menu.visible && !agent.reasoningEffort,
                        "Tab aplica esfuerzo antes de confirmar")) return;
                    inspector.keyClick(Qt.Key_Return);
                    stage = 1;
                } else if (stage === 1) {
                    if (agent.reasoningEffort !== "high") return;
                    if (!check(!prompt.text && !agent.messages.count && !agent.currentChatId && !agent.performanceHistory.length
                        && inspector.findChild(chat, "chatActiveModel").text === "GPT-6.1-Sol · Alto",
                        "selección crea chat o no muestra esfuerzo")) return;
                    scenario.type("/modelos gpt-6 modelos");
                    if (!check(list.count === 2, "listar modelos de la familia con palabra modelos falla")) return;
                    scenario.type("/modelos gpt-6 gpt-6-luna");
                    if (!check(list.count === 3 && composer.completions.map(row => row.value).join() === "auto,low,high",
                        "catálogo no limita esfuerzos")) return;
                    scenario.type("/modelos gpt-6 gpt-6.1-sol none");
                    inspector.keyClick(Qt.Key_Return);
                    if (!check(prompt.text.endsWith(" none") && agent.reasoningEffort === "high"
                        && agent.status.indexOf("esfuerzo") >= 0, "esfuerzo inválido no conserva selección/borrador")) return;
                    scenario.type("/modelos gpt-5");
                    if (!check(list.count === 1 && composer.completions[0].value === "gpt-5.6-sol", "familia mezcla modelos")) return;
                    scenario.type("/modelos gpt-6 gpt-5.6-sol high");
                    inspector.keyClick(Qt.Key_Return);
                    if (!check(agent.modelName === "gpt-6.1-sol" && !!prompt.text, "familia equivocada acepta modelo")) return;
                    scenario.type("Hola"); inspector.keyClick(Qt.Key_Return);
                    stage = 2;
                } else if (stage === 2) {
                    if (agent.busy) return;
                    scenario.firstChat = agent.currentChatId;
                    if (!check(agent.messages.count === 2 && agent.reasoningEffort === "high", "respuesta pierde esfuerzo")) return;
                    agent.newChat(); stage = 3;
                } else if (stage === 3) {
                    if (agent.messages.count) return;
                    scenario.type("/modelos gpt-5 gpt-5.6-sol low");
                    inspector.keyClick(Qt.Key_Return); stage = 4;
                } else if (stage === 4) {
                    if (agent.modelName !== "gpt-5.6-sol" || agent.reasoningEffort !== "low") return;
                    scenario.type("Segunda conversación"); inspector.keyClick(Qt.Key_Return); stage = 5;
                } else if (stage === 5) {
                    if (agent.busy) return;
                    scenario.secondChat = agent.currentChatId;
                    agent.openChat(firstChat); stage = 6;
                } else if (stage === 6) {
                    if (agent.openingChat || agent.currentChatId !== firstChat) return;
                    if (!check(agent.modelName === "gpt-6.1-sol" && agent.reasoningEffort === "high", "reabrir pierde elección propia")) return;
                    scenario.type("/modelos gpt-6 gpt-6.1-sol auto");
                    if (!check(list.count === 1, "Auto no se puede filtrar")) return;
                    inspector.mouseClick(list.itemAtIndex(0)); stage = 7;
                } else if (stage === 7) {
                    if (agent.reasoningEffort) return;
                    if (!check(!prompt.text && inspector.findChild(chat, "chatActiveModel").text === "GPT-6.1-Sol",
                        "Auto no restaura etiqueta discreta")) return;
                    scenario.type("/modelos gpt-4");
                    if (!scenario.pick("gpt-4.1", false)) return;
                    stage = 8;
                } else if (stage === 8) {
                    if (agent.modelName !== "gpt-4.1") return;
                    if (!check(!agent.reasoningEffort && !prompt.text, "modelo sin razonamiento no selecciona directamente")) return;
                    scenario.type("/modelos gpt-6 gpt-6.1-sol");
                    inspector.keyClick(Qt.Key_Escape);
                    if (!check(!menu.visible && prompt.text.endsWith("gpt-6.1-sol"), "Esc pierde borrador")) return;
                    const parsed = ChatCommands.parse("/modelos gpt-6 modelos gpt-6.1-sol max");
                    if (!check(parsed.family === "gpt-6" && parsed.model === "gpt-6.1-sol" && parsed.effort === "max",
                        "comando completo no se interpreta")) return;
                    console.log("MODELS_OK: familias, modelos, esfuerzos compatibles, Auto, teclado/clic, franja fija, borradores, selección local e historial por conversación");
                    steps.stop(); Qt.quit();
                }
            } finally { scenario.stepping = false; }
        }
    }
    Timer { interval: 9000; running: true; onTriggered: scenario.check(false,
        "Tiempo agotado en etapa " + stage + ": " + agent.status) }
}
