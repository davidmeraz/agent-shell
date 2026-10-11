import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtTest
import Quickshell
import "ui"

// Teclado y paneles reales con la cuenta y el servicio HTTP locales de prueba.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property var prompt: null
    property var menu: null
    property var list: null
    property var composer: null
    property var conversation: null
    property var activeModel: null
    property var initialLayout: ({})
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 560; implicitHeight: 560; title: "Agent Shell · Commands Test" }
    TestCase { id: inspector; parent: chat.contentItem; when: false }

    function check(value, message) {
        if (value) return true;
        console.error("COMMANDS_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function typeCommand(text) {
        inspector.wait(180); // Permitir que termine el cierre del panel anterior.
        prompt.forceActiveFocus();
        prompt.text = text;
        prompt.cursorPosition = prompt.length;
        inspector.wait(20);
        inspector.keyClick(Qt.Key_Return);
        inspector.wait(20);
    }
    function checkLayout() {
        const position = composer.mapToItem(chat.contentItem, 0, 0);
        return check(Math.abs(composer.height - initialLayout.height) < 0.5
            && Math.abs(position.y - initialLayout.y) < 0.5
            && Math.abs(conversation.height - initialLayout.conversationHeight) < 0.5,
            "las sugerencias desplazan el editor o la conversación");
    }
    Timer {
        id: steps
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (scenario.stepping) return;
            scenario.stepping = true;
            try {
                if (scenario.stage === 0) {
                    if (!agent.canSend) return;
                    scenario.prompt = inspector.findChild(chat, "chatPrompt");
                    scenario.menu = inspector.findChild(chat, "chatInlineSuggestions");
                    scenario.list = inspector.findChild(chat, "chatCommandList");
                    scenario.composer = inspector.findChild(chat, "chatComposer");
                    scenario.conversation = inspector.findChild(chat, "chatConversation");
                    scenario.activeModel = inspector.findChild(chat, "chatActiveModel");
                    if (!scenario.check(!!scenario.prompt && !!scenario.menu && !!scenario.list, "controles ausentes")) return;
                    if (!scenario.check(!!scenario.activeModel && scenario.activeModel.visible
                        && scenario.activeModel.text === "Modelo de prueba", "modelo activo ausente o incorrecto")) return;
                    if (!scenario.check(!inspector.findChild(chat, "chatModelSelector"), "el editor conserva el selector de modelo")) return;
                    scenario.initialLayout = { height: scenario.composer.height,
                        y: scenario.composer.mapToItem(chat.contentItem, 0, 0).y,
                        conversationHeight: scenario.conversation.height };
                    chat.contentItem.Window.window.requestActivate();
                    scenario.prompt.forceActiveFocus(); scenario.prompt.text = "/";
                    scenario.stage = 1;
                } else if (scenario.stage === 1) {
                    if (!scenario.check(scenario.menu.visible && scenario.menu.height <= 28 && scenario.list.count === 6, "sugerencias no compactas o incompletas")) return;
                    if (!scenario.checkLayout()) return;
                    if (!scenario.check(!scenario.activeModel.visible, "modelo activo se superpone a sugerencias")) return;
                    const actions = inspector.findChild(chat, "chatComposerActions");
                    if (!scenario.check(scenario.menu.mapToItem(actions, 0, 0).y >= 0
                        && scenario.menu.mapToItem(actions, 0, 0).y + scenario.menu.height <= actions.height,
                        "las opciones están fuera de la fila de envío")) return;
                    scenario.list.positionViewAtIndex(3, ListView.Contain);
                    inspector.wait(20);
                    if (!scenario.check(scenario.list.itemAtIndex(3).modelData.label === "/modelos", "nombre de comando incorrecto")) return;
                    inspector.keyClick(Qt.Key_Left);
                    if (!scenario.check(scenario.list.currentIndex === 5, "flecha izquierda no recorre el menú")) return;
                    inspector.keyClick(Qt.Key_Right);
                    if (!scenario.check(scenario.list.currentIndex === 0, "flecha derecha no vuelve al inicio")) return;
                    inspector.keyClick(Qt.Key_Right);
                    inspector.keyClick(Qt.Key_Down);
                    inspector.keyClick(Qt.Key_Up);
                    if (!scenario.check(scenario.list.currentIndex === 1, "arriba o abajo cambian la sugerencia")) return;
                    inspector.keyClick(Qt.Key_Tab);
                    if (!scenario.check(scenario.prompt.text === "/nuevo" && !scenario.menu.visible && !agent.busy && !agent.currentChatId, "flechas o Tab ejecutan indebidamente")) return;
                    scenario.prompt.text = "/";
                    inspector.wait(20); inspector.keyClick(Qt.Key_Escape);
                    if (!scenario.check(!scenario.menu.visible && scenario.prompt.text === "/", "Esc no cierra conservando borrador")) return;
                    inspector.wait(20);
                    if (!scenario.check(scenario.activeModel.visible && scenario.activeModel.text === "Modelo de prueba",
                        "modelo activo no regresa al ocultar sugerencias")) return;
                    if (!scenario.checkLayout()) return;
                    scenario.typeCommand("/ayu");
                    const help = inspector.findChild(chat, "commandHelp");
                    if (!scenario.check(help.visible && scenario.prompt.text === "" && !agent.messages.count && !agent.currentChatId && !agent.performanceHistory.length, "ayuda enviada al modelo o no abierta")) return;
                    help.close();
                    scenario.typeCommand("/desconocido");
                    if (!scenario.check(scenario.prompt.text === "/desconocido" && agent.status.indexOf("desconocido") >= 0 && !agent.messages.count, "comando desconocido perdido o enviado")) return;
                    scenario.typeCommand("/nuevo extra");
                    if (!scenario.check(scenario.prompt.text === "/nuevo extra" && agent.status.indexOf("argumentos") >= 0, "argumentos ignorados")) return;
                    scenario.stage = 2;
                } else if (scenario.stage === 2) {
                    scenario.prompt.forceActiveFocus(); scenario.prompt.text = "/historial";
                    inspector.wait(20);
                    inspector.mouseClick(scenario.list.itemAtIndex(0));
                    inspector.wait(20);
                    const history = inspector.findChild(chat, "chatHistory");
                    if (!scenario.check(history.visible && !agent.busy && !agent.messages.count, "historial no abrió localmente")) return;
                    history.close();
                    scenario.typeCommand("/terminal");
                    const settings = inspector.findChild(chat, "shellSettings");
                    if (!scenario.check(settings.visible && !agent.shellEnabled && !agent.pendingTool.request_id && !agent.busy, "terminal ejecutó o se activó automáticamente")) return;
                    settings.close();
                    inspector.wait(180);
                    scenario.prompt.forceActiveFocus();
                    for (const prefix of ["/m", "/mo", "/mod", "/mode", "/model", "/modelo"]) {
                        scenario.prompt.text = prefix;
                        inspector.wait(20);
                        if (!scenario.check(!scenario.composer.modelMode && scenario.menu.visible && scenario.list.count === 1
                            && scenario.list.itemAtIndex(0).modelData.value === "/modelos" && agent.modelName === "test-model",
                            "los modelos se activan antes de completar /modelos")) return;
                        if (!scenario.checkLayout()) return;
                    }
                    scenario.prompt.cursorPosition = scenario.prompt.length;
                    inspector.keyClick(Qt.Key_S);
                    inspector.wait(20);
                    if (!scenario.check(scenario.prompt.text === "/modelos" && scenario.composer.modelMode
                        && scenario.menu.visible && scenario.list.count === 2,
                        "modelos no aparecen dentro del editor")) return;
                    if (!scenario.checkLayout()) return;
                    scenario.prompt.text = "/modelos other";
                    inspector.wait(20);
                    if (!scenario.check(scenario.list.count === 1 && scenario.list.itemAtIndex(0).modelData.value === "other-model", "filtro de modelos incorrecto")) return;
                    if (!scenario.checkLayout()) return;
                    inspector.keyClick(Qt.Key_Tab);
                    if (!scenario.check(scenario.prompt.text === "/modelos other-model" && agent.modelName === "test-model", "Tab cambia modelo antes de confirmar")) return;
                    inspector.keyClick(Qt.Key_Return);
                    scenario.stage = 3;
                } else if (scenario.stage === 3) {
                    if (agent.modelName !== "other-model") return;
                    if (!scenario.check(scenario.activeModel.visible && scenario.activeModel.text === "Otro modelo",
                        "etiqueta no se actualiza al cambiar modelo")) return;
                    scenario.typeCommand("/modelos inexistente");
                    if (!scenario.check(scenario.prompt.text === "/modelos inexistente" && agent.status.indexOf("disponible") >= 0, "modelo desconocido no conserva borrador")) return;
                    for (const alias of ["/mode", "/model", "/modelo"])
                        if (!scenario.check(!agent.submit(alias + " test-model") && agent.modelName === "other-model",
                            "un nombre incompleto cambia el modelo")) return;
                    if (!scenario.check(agent.submit("/modelos"), "comando modelos rechazado")) return;
                    inspector.wait(20);
                    if (!scenario.check(scenario.prompt.text === "/modelos " && scenario.list.count === 2, "comando no abre opciones en el editor")) return;
                    inspector.keyClick(Qt.Key_Right);
                    if (!scenario.check(scenario.list.currentIndex === 1 && scenario.prompt.text === "/modelos ",
                        "flecha derecha no selecciona modelo o modifica borrador")) return;
                    inspector.keyClick(Qt.Key_Return);
                    if (!scenario.check(!scenario.prompt.text, "Enter no confirma opción de modelo")) return;
                    if (!scenario.check(agent.submit("/modelos"), "comando modelos rechazado")) return;
                    inspector.wait(20);
                    inspector.mouseClick(scenario.list.itemAtIndex(0));
                    if (!scenario.check(!scenario.prompt.text && !scenario.menu.visible, "clic no confirma modelo en el editor")) return;
                    if (!scenario.check(!agent.messages.count && !agent.performanceHistory.length && !agent.currentChatId, "comandos locales crean chat o métricas")) return;
                    agent.submit("cancel");
                    scenario.stage = 4;
                } else if (scenario.stage === 4) {
                    if (!agent.firstReceivedAt) return;
                    if (!scenario.check(!agent.submit("/nuevo") && agent.busy && !agent.submit("/terminal")
                        && !agent.submit("/modelos other-model"), "cambio de chat, terminal o modelo durante turno")) return;
                    scenario.typeCommand("/detener");
                    scenario.stage = 5;
                } else if (scenario.stage === 5) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.latestPerformance.status === "interrupted" && agent.messages.count === 2 && scenario.prompt.text === "", "detener no cancela o añade mensaje")) return;
                    scenario.typeCommand("/nuevo");
                    scenario.stage = 6;
                } else if (scenario.stage === 6) {
                    if (agent.messages.count) return;
                    if (!scenario.check(!agent.currentChatId && !agent.submit("/detener"), "nuevo o detener sin turno incorrectos")) return;
                    agent.authenticated = false;
                    if (!scenario.check(!scenario.activeModel.visible, "etiqueta muestra modelo sin sesión")) return;
                    scenario.typeCommand("/ayuda");
                    const help = inspector.findChild(chat, "commandHelp");
                    if (!scenario.check(help.visible, "ayuda no disponible sin sesión")) return;
                    help.close();
                    scenario.typeCommand("/historial");
                    const history = inspector.findChild(chat, "chatHistory");
                    if (!scenario.check(history.visible, "historial no disponible sin sesión")) return;
                    history.close();
                    scenario.typeCommand("/modelos");
                    if (!scenario.check(scenario.prompt.text === "/modelos" && !agent.messages.count, "modelo sin sesión no bloqueado")) return;
                    scenario.typeCommand("borrador sin sesión");
                    if (!scenario.check(scenario.prompt.text === "borrador sin sesión" && !agent.messages.count, "borrador sin sesión perdido")) return;
                    agent.authenticated = true;
                    inspector.wait(180);
                    scenario.prompt.forceActiveFocus(); scenario.prompt.text = "hola";
                    scenario.prompt.cursorPosition = scenario.prompt.length;
                    inspector.keyClick(Qt.Key_Left);
                    if (!scenario.check(scenario.prompt.cursorPosition === 3, "izquierda no mueve cursor sin sugerencias")) return;
                    inspector.keyClick(Qt.Key_Right);
                    if (!scenario.check(scenario.prompt.cursorPosition === 4, "derecha no mueve cursor sin sugerencias")) return;
                    inspector.keyClick(Qt.Key_Return, Qt.ShiftModifier);
                    if (!scenario.check(scenario.prompt.text === "hola\n" && !agent.busy, "Shift+Enter no conserva salto")) return;
                    inspector.keyClick(Qt.Key_Return);
                    scenario.stage = 7;
                } else if (scenario.stage === 7) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.messages.count === 2 && agent.messages.get(1).body === "Hola desde ChatGPT. 🎵"
                        && agent.performanceHistory.length === 2 && scenario.prompt.text === "", "envío normal o métricas alterados")) return;
                    const account = inspector.findChild(chat, "chatAccount");
                    const picker = inspector.findChild(chat, "chatAccountSelector");
                    const add = inspector.findChild(chat, "chatAddAccount");
                    account.open(); inspector.wait(180);
                    if (!scenario.check(picker.visible && picker.count === 2 && picker.currentIndex === 0
                        && add.visible && add.enabled && account.height < chat.height, "controles de cuenta ausentes o panel demasiado alto")) return;
                    inspector.mouseClick(add);
                    scenario.stage = 8;
                } else if (scenario.stage === 8) {
                    if (agent.loginBusy) return;
                    if (!scenario.check(agent.status === "Cuenta nueva solicitada (prueba)." && !agent.authUrl
                        && agent.canSend && agent.messages.count === 2, "botón no solicita cuenta nueva o altera chat")) return;
                    const picker = inspector.findChild(chat, "chatAccountSelector");
                    picker.popup.open(); inspector.wait(30);
                    inspector.mouseClick(picker.popup.contentItem.itemAtIndex(1));
                    scenario.stage = 9;
                } else if (scenario.stage === 9) {
                    if (agent.accountBusy || agent.activeAccountIndex !== 1) return;
                    if (!scenario.check(agent.canSend && agent.messages.count === 2 && agent.registeredAccounts.count === 2,
                        "selección de cuenta no actualiza modelos o conserva chat")) return;
                    if (!scenario.check(agent.email === "second@example.invalid", "correo no corresponde a cuenta seleccionada")) return;
                    console.log("COMMANDS_OK: sugerencias fijas, activación al completar /modelos, filtro, teclado, seis comandos y borradores");
                    console.log("ACCOUNT_OK: cuenta nueva y selector sin navegador, con chat conservado");
                    steps.stop(); Qt.callLater(Qt.quit);
                }
            } finally { scenario.stepping = false; }
        }
    }
}
