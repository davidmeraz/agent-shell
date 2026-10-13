import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "../../ui"

// Teclado real y PNG de prueba; HTTP/SSE local sin portapapeles ni cuenta del usuario.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property var prompt: null
    property var composer: null
    property string image: ""
    property string chatId: ""
    property string stalePasteId: ""
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 560; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function check(value, message) {
        if (value) return true;
        console.error("IMAGES_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function paste() {
        prompt.forceActiveFocus();
        inspector.keyClick(Qt.Key_V, Qt.ControlModifier);
    }
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
                    if (!agent.canSend) return;
                    inspector.mouseMove(chat.contentItem, chat.width - 24, 100);
                    inspector.findChild(chat, "chatSidebarDrawer").close(); inspector.wait(200);
                    scenario.prompt = inspector.findChild(chat, "chatPrompt");
                    scenario.composer = inspector.findChild(chat, "chatComposer");
                    Quickshell.clipboardText = "texto nativo";
                    scenario.prompt.text = "Antes: "; scenario.prompt.cursorPosition = scenario.prompt.length;
                    inspector.wait(30); scenario.paste(); inspector.wait(30);
                    if (!scenario.check(scenario.prompt.text === "Antes: texto nativo" && !scenario.composer.pendingPasteId
                        && !scenario.composer.attachedImage, "Ctrl+V de texto dejó de ser nativo")) return;
                    Quickshell.clipboardText = "";
                    scenario.prompt.text = "Descripción";
                    inspector.wait(20); scenario.paste();
                    scenario.stage = 1;
                } else if (scenario.stage === 1) {
                    if (!scenario.composer.attachedImage || scenario.composer.pendingPasteId) return;
                    scenario.image = scenario.composer.attachedImage;
                    const thumbnail = inspector.findChild(chat, "chatAttachmentThumbnail");
                    inspector.tryCompare(thumbnail, "status", Image.Ready, 500);
                    if (!scenario.check(thumbnail.status === Image.Ready && inspector.findChild(chat, "chatAttachmentPreview").visible
                        && scenario.prompt.text === "Descripción", "imagen no aparece o reemplaza el texto")) return;
                    inspector.mouseClick(inspector.findChild(chat, "chatRemoveAttachment"));
                    if (!scenario.check(!scenario.composer.attachedImage && scenario.prompt.text === "Descripción",
                        "quitar adjunto borra el texto")) return;
                    scenario.prompt.text = "";
                    scenario.paste(); scenario.stage = 2;
                } else if (scenario.stage === 2) {
                    if (!scenario.composer.attachedImage || scenario.composer.pendingPasteId) return;
                    const send = inspector.findChild(chat, "chatSendButton");
                    if (!scenario.check(send.enabled && !scenario.prompt.text, "no admite enviar sólo una imagen")) return;
                    inspector.mouseClick(send);
                    if (!scenario.check(!scenario.composer.attachedImage && agent.busy, "enviar no consume el adjunto")) return;
                    scenario.stage = 3;
                } else if (scenario.stage === 3) {
                    if (agent.busy) return;
                    scenario.chatId = agent.currentChatId;
                    const list = inspector.findChild(chat, "chatMessageList");
                    inspector.wait(60);
                    const image = inspector.findChild(list.itemAtIndex(0), "chatMessageImage");
                    inspector.tryCompare(image, "status", Image.Ready, 500);
                    if (!scenario.check(agent.messages.count === 2 && agent.messages.get(0).imageUrl === scenario.image
                        && !agent.messages.get(0).body && image.status === Image.Ready && image.height > 0,
                        "imagen enviada ausente en la conversación")) return;
                    agent.newChat(); scenario.stage = 4;
                } else if (scenario.stage === 4) {
                    if (agent.currentChatId) return;
                    agent.openChat(scenario.chatId); scenario.stage = 5;
                } else if (scenario.stage === 5) {
                    if (agent.openingChat || agent.currentChatId !== scenario.chatId) return;
                    if (!scenario.check(agent.messages.get(0).imageUrl === scenario.image, "historial no restaura imagen")) return;
                    scenario.prompt.text = "Borrador con imagen";
                    scenario.paste(); scenario.stage = 6;
                } else if (scenario.stage === 6) {
                    if (!scenario.composer.attachedImage || scenario.composer.pendingPasteId) return;
                    scenario.composer.pasteImage();
                    scenario.stalePasteId = scenario.composer.pendingPasteId;
                    agent.selectArea("work", ""); scenario.stage = 7;
                } else if (scenario.stage === 7) {
                    if (agent.areaBusy || agent.activeArea !== "work") return;
                    agent.receive(JSON.stringify({ version: 2, type: "clipboard.result", data: {
                        request_id: scenario.stalePasteId, image: scenario.image } }));
                    if (!scenario.check(!scenario.composer.attachedImage && !scenario.composer.pendingPasteId,
                        "respuesta tardía adjunta imagen en otro espacio")) return;
                    agent.selectArea("chat"); scenario.stage = 8;
                } else if (scenario.stage === 8) {
                    if (agent.areaBusy || agent.activeArea !== "chat") return;
                    if (!scenario.check(scenario.composer.attachedImage === scenario.image
                        && scenario.prompt.text === "Borrador con imagen", "cambiar de área pierde el adjunto o borrador")) return;
                    scenario.composer.pasteImage();
                    const requestId = scenario.composer.pendingPasteId;
                    agent.receive(JSON.stringify({ version: 2, type: "clipboard.result", data: {
                        request_id: requestId, image: "", message: "Error de imagen de prueba" } }));
                    if (!scenario.check(scenario.composer.attachedImage === scenario.image
                        && !scenario.composer.pendingPasteId && agent.status === "Error de imagen de prueba",
                        "error de portapapeles borra el adjunto anterior o deja bloqueo")) return;
                    scenario.composer.prepare("/modelos " + agent.availableModels.get(1).slug);
                    inspector.wait(20); scenario.composer.send(); scenario.stage = 9;
                } else if (scenario.stage === 9) {
                    if (agent.modelName !== agent.availableModels.get(1).slug) return;
                    if (!scenario.check(scenario.composer.attachedImage === scenario.image && !scenario.prompt.text,
                        "cambiar modelo consume la imagen")) return;
                    scenario.prompt.text = "Analiza esta imagen";
                    scenario.composer.send(); scenario.stage = 10;
                } else if (scenario.stage === 10) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.messages.count === 4 && agent.messages.get(2).imageUrl === scenario.image
                        && agent.messages.get(2).body === "Analiza esta imagen", "mensaje con texto e imagen no llegó completo")) return;
                    scenario.composer.pasteImage();
                    scenario.stalePasteId = scenario.composer.pendingPasteId;
                    agent.newChat(); scenario.stage = 11;
                } else if (scenario.stage === 11) {
                    if (agent.currentChatId) return;
                    agent.receive(JSON.stringify({ version: 2, type: "clipboard.result", data: {
                        request_id: scenario.stalePasteId, image: scenario.image } }));
                    if (!scenario.check(!scenario.composer.attachedImage && !scenario.composer.pendingPasteId,
                        "nuevo chat acepta un adjunto tardío")) return;
                    console.log("IMAGES_OK: Ctrl+V, texto nativo, miniatura, quitar, imagen sola, texto e imagen, historial y borradores sin respuestas tardías");
                    steps.stop(); Qt.callLater(Qt.quit);
                }
            } catch (error) {
                scenario.check(false, "etapa " + scenario.stage + ": " + error.message);
            } finally { scenario.stepping = false; }
        }
    }
}
