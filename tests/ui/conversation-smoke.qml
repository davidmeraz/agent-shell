import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "../../ui"
import "../../ui/js/Performance.js" as Performance

// Interacción con mensajes de prueba; nunca envía solicitudes a un modelo real.
ShellRoot {
    id: scenario
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 560; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function check(value, message) {
        if (value) return true;
        console.error("CONVERSATION_FAILED: " + message);
        Qt.callLater(Qt.quit);
        return false;
    }
    function append(author, body, turn, measurement) {
        agent.messages.append({ author: author, body: body, turnId: turn,
            performanceJson: measurement ? JSON.stringify(measurement) : "", toolJson: "" });
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (!agent.canSend) return;
            stop();
            agent.messages.clear();
            const markdown = "**Hola**.\n\n- Una idea\n- Otro paso\n\n```sh\npwd\n```";
            scenario.append("TÚ", "que puedes hacer", "fixture-turn", null);
            scenario.append("CHATGPT", markdown, "fixture-turn", {
                turn_id: "fixture-turn", model: "test-model", status: "completed",
                total_ms: 2300, first_text_ms: 1900, characters_per_second: 139,
                context_tokens: 12400, tokens_per_second: 45.5, model_request_ms: 2000,
                usage: { input_tokens: 22000, output_tokens: 91, reasoning_tokens: 30, cached_tokens: 4000 }
            });
            agent.currentChatId = "fixture-chat";
            agent.latestPerformance = Object.assign({}, JSON.parse(agent.messages.get(1).performanceJson), { chat_id: "fixture-chat" });
            inspector.wait(150);
            const list = inspector.findChild(chat, "chatMessageList");
            if (!scenario.check(list.ScrollBar.vertical.policy === ScrollBar.AlwaysOff,
                "la barra de desplazamiento sigue visible")) return;
            const user = inspector.findChild(list.itemAtIndex(0), "chatUserMessage");
            const userProfile = inspector.findChild(list.itemAtIndex(0), "chatUserProfile");
            const userProfileName = inspector.findChild(list.itemAtIndex(0), "chatUserProfileName");
            const assistant = inspector.findChild(list.itemAtIndex(1), "chatAssistantMessage");
            const copy = inspector.findChild(list.itemAtIndex(1), "chatCopyResponse");
            const metrics = inspector.findChild(list.itemAtIndex(1), "chatResponseMetrics");
            if (!scenario.check(!!user && !!userProfile && userProfile.visible && !!userProfileName
                && !userProfileName.text.includes("@") && !!assistant && !!copy && !!metrics,
                "controles o perfil de usuario ausentes o exponiendo correo")) return;
            agent.updateProfile("Dav3e Pro");
            inspector.wait(120);
            if (!scenario.check(agent.displayName === "Dav3e Pro" && userProfileName.text === "Dav3e Pro",
                "nombre de usuario personalizado no se guarda ni actualiza en el chat")) return;
            if (!scenario.check(user.parent.width < list.width / 2 && user.lineCount === 1
                && user.textFormat === TextEdit.PlainText,
                "burbuja corta demasiado ancha, con salto innecesario o interpretada como Markdown")) return;
            if (!scenario.check(assistant.textFormat === TextEdit.RichText
                && assistant.getText(0, assistant.length).includes("pwd")
                && !assistant.getText(0, assistant.length).includes("**Hola**"), "Markdown y código no renderizados")) return;
            assistant.select(0, 4);
            const selection = assistant.selectedText;
            inspector.mouseClick(copy);
            if (!scenario.check(Quickshell.clipboardText === markdown && copy.copied && assistant.selectedText === selection,
                "copiar pierde formato original, selección o confirmación")) return;
            if (!scenario.check(metrics.text === "2.30 s · Media: 45.5 tok/s",
                "resumen duplica contexto o pierde velocidad")) return;
            const context = inspector.findChild(chat, "chatComposerContext");
            const send = inspector.findChild(chat, "chatSendButton");
            const composer = inspector.findChild(chat, "chatComposer");
            const actions = inspector.findChild(chat, "chatComposerActions");
            const contextPosition = context.mapToItem(actions, 0, 0);
            const sendPosition = send.mapToItem(actions, 0, 0);
            if (!scenario.check(context.visible && context.text === "Contexto: 12.4k tokens"
                && contextPosition.x + context.width <= sendPosition.x
                && Math.abs(contextPosition.y + context.height / 2 - sendPosition.y - send.height / 2) < 1,
                "contexto no está junto a Enviar en la misma fila")) return;
            const composerHeight = composer.height;
            inspector.mouseClick(context); inspector.wait(50);
            const contextDetails = inspector.findChild(chat, "chatPerformanceDetails");
            if (!scenario.check(contextDetails.visible && chat.selectedPerformance.context_tokens === 12400,
                "contexto no abre su desglose")) return;
            contextDetails.close(); inspector.wait(200);
            const measured = agent.latestPerformance;
            agent.latestPerformance = Object.assign({}, measured, { context_tokens: null });
            inspector.wait(20);
            if (!scenario.check(!context.visible && Math.abs(composer.height - composerHeight) < 1,
                "contexto desconocido aparece o cambia altura del editor")) return;
            agent.latestPerformance = Object.assign({}, measured, { chat_id: "other-chat" });
            if (!scenario.check(!context.visible, "contexto muestra datos de otra conversación")) return;
            agent.latestPerformance = measured;
            const info = Performance.details(JSON.parse(agent.messages.get(1).performanceJson));
            if (!scenario.check(info.includes("Contexto de la última llamada: 12400 tokens")
                && info.includes("Consumo acumulado reportado del turno:") && info.includes("Tokens de entrada: 22000")
                && Performance.compactSummary({ turn_id: "zero", status: "completed", context_tokens: 0, tokens_per_second: 0 })
                    === "Media: 0.0 tok/s"
                && !Performance.compactSummary({ turn_id: "unknown", status: "completed", total_ms: 2000 })
                    .includes("tok/s"), "detalles confunden consumo con contexto o inventan datos")) return;
            inspector.mouseClick(metrics); inspector.wait(100);
            const details = inspector.findChild(chat, "chatPerformanceDetails");
            if (!scenario.check(details.visible && chat.selectedPerformance.turn_id === "fixture-turn",
                "métricas no abren los detalles de la respuesta")) return;
            details.close(); inspector.wait(200);
            for (let i = 0; i < 12; ++i)
                scenario.append("CHATGPT", "Respuesta " + i + "\n\n" + "Texto para leer.\n".repeat(6), "long-" + i, null);
            inspector.wait(150);
            if (!scenario.check(list.atYEnd, "no sigue las respuestas nuevas inicialmente")) return;
            inspector.mouseWheel(list, list.width / 2, list.height / 2, 0, 240);
            inspector.wait(250);
            if (!scenario.check(!list.followLatest && !list.atYEnd, "leer mensajes anteriores no detiene el seguimiento")) return;
            const previousY = list.contentY;
            agent.messages.setProperty(agent.messages.count - 1, "body", "Más texto.\n".repeat(30));
            scenario.append("CHATGPT", "Otro fragmento recibido.", "new-turn", null);
            inspector.wait(100);
            if (!scenario.check(Math.abs(list.contentY - previousY) < 1 && !list.atYEnd,
                "recibir texto desplaza la lectura al final")) return;
            const jump = inspector.findChild(chat, "chatJumpToLatest");
            if (!scenario.check(jump.visible, "acceso al último mensaje ausente")) return;
            inspector.mouseClick(jump); inspector.wait(100);
            if (!scenario.check(list.followLatest && list.atYEnd, "no vuelve al último mensaje")) return;
            agent.messages.clear();
            agent.activeTurnId = "pending-turn";
            scenario.append("TÚ", "Nueva pregunta", "pending-turn", null);
            agent.busy = true;
            inspector.wait(100);
            const thinking = inspector.findChild(chat, "chatThinkingIndicator");
            if (!scenario.check(thinking.visible, "espera de la IA sin indicación")) return;
            if (!scenario.check(send.text.startsWith("Detener") && send.enabled,
                "el botón no cambia a Detener durante respuesta de IA")) return;
            scenario.append("CHATGPT", "Empiezo a responder…", "pending-turn", null);
            inspector.wait(100);
            if (!scenario.check(!thinking.visible, "indicador de espera sigue después del primer texto")) return;
            agent.busy = false;
            if (!scenario.check(send.text.startsWith("Enviar"), "el botón no recupera Enviar al terminar la IA")) return;

            const nativeWindow = chat.contentItem.Window.window;
            nativeWindow.width = 826;
            nativeWindow.height = 1208;
            agent.createProject("Proyecto de prueba", agent.workspace);
            inspector.tryCompare(agent, "areaBusy", false, 1500);
            if (!scenario.check(agent.activeArea === "work" && !!agent.projectId,
                "no se abrió el proyecto para probar su historial")) return;
            inspector.mouseClick(inspector.findChild(chat, "chatSidebarButton"));
            if (!scenario.check(chat.overlayVisible, "el panel lateral no se abrió")) return;
            const toolCalls = Array.from({ length: 273 }, (_, i) => ({
                id: "tool-" + i,
                message_index: i < 263 ? 1 : i < 270 ? 2 : 3,
                command: "git status",
                output: "Salida de prueba.",
                status: "completed"
            }));
            agent.receive(JSON.stringify({ version: 2, type: "chat.loaded", data: { chat: {
                chat_id: "long-work-history",
                title: "Historial del proyecto",
                messages: [
                    { role: "user", text: "Revisa el estado del proyecto." },
                    { role: "user", text: "Revisión detallada del estado del proyecto. ".repeat(8) },
                    { role: "assistant", id: "last-response", text: "La revisión está completa. ".repeat(10) }
                ],
                tool_calls: toolCalls
            } } }));
            inspector.wait(250);
            if (!scenario.check(list.count === 276 && list.atYEnd && !!list.itemAtIndex(275),
                "el historial largo del proyecto no llega al final")) return;
            console.log("CONVERSATION_OK: burbujas compactas, Markdown, código, copia original, métricas, espera y reapertura de historial largo");
            Qt.callLater(Qt.quit);
        }
    }
}
