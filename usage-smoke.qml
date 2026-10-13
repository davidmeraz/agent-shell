import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtTest
import Quickshell
import "ui"
import "ui/components"

// El adaptador real conversa con un proceso RPC de prueba, nunca con una cuenta.
ShellRoot {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property var panel: null
    property string previousUpdate: ""
    property string savedChatId: ""
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitHeight: 560 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    TestCase { id: usageInspector; parent: chat.usageWindow.contentItem; when: false }
    Component { id: limitExample; UsageLimit { windowData: null; width: 360; visible: false } }

    function check(value, message) {
        if (value) return true;
        console.error("USAGE_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    Timer {
        id: steps
        interval: 80
        repeat: true
        running: true
        onTriggered: {
            if (scenario.stepping) return;
            scenario.stepping = true;
            try {
            if (scenario.stage === 0) {
                if (!agent.canSend) return;
                if (!scenario.check(chat.usageWindow.visible, "el uso no abre al iniciar")) return;
                if (agent.usageBusy || !agent.accountUsage.checked_at) return;
                const account = inspector.findChild(chat, "chatAccount");
                account.open(); inspector.wait(180);
                const button = inspector.findChild(chat, "chatUsageButton");
                if (!scenario.check(button.visible && button.enabled, "acceso al uso ausente")) return;
                scenario.panel = chat.usageWindow;
                inspector.mouseClick(button); inspector.wait(180);
                if (!scenario.check(panel.visible && panel.contentItem.Window.window !== chat.contentItem.Window.window,
                    "el uso no abre una ventana independiente")) return;
                const surface = inspector.findChild(panel, "usageMatteSurface");
                if (!scenario.check(surface && surface.waterReflection && surface.topColor.a < 1 && panel.color.a === 0,
                    "ventana de uso sin vidrio mate")) return;
                scenario.stage = 1;
            } else if (scenario.stage === 1) {
                if (!scenario.check(!agent.usageError, agent.usageError)) return;
                if (agent.usageBusy || !agent.accountUsage.checked_at) return;
                // Apartar el puntero del borde evita abrir la navegación por hover en offscreen.
                chat.contentItem.Window.window.requestActivate();
                const chatPrompt = inspector.findChild(chat, "chatPrompt");
                inspector.mouseMove(chatPrompt, chatPrompt.width - 12, 12);
                inspector.findChild(chat, "chatSidebarDrawer").close();
                inspector.wait(180);
                if (!scenario.check(!chat.dialogVisible && !chat.overlayVisible,
                    "el uso bloquea el chat: diálogo=" + chat.dialogVisible + ", overlay=" + chat.overlayVisible)) return;
                if (!scenario.check(agent.accountUsage.limits.length === 2
                    && agent.accountUsage.limits[0].primary.used_percent === 25
                    && agent.accountUsage.limits[1].primary === null
                    && agent.accountUsage.account.email === agent.email
                    && !agent.usageError && agent.canSend && !agent.messages.count,
                    "cuotas, cuenta o independencia del chat incorrectas")) return;
                inspector.wait(30);
                const limits = inspector.findChild(panel, "chatUsageLimits");
                const stats = inspector.findChild(panel, "usageStats");
                inspector.wait(100);
                if (!scenario.check(panel.height >= stats.implicitHeight + 32,
                    "la altura nativa recorta las cuotas recibidas después de abrir")) return;
                const primary = limits && limits.count ? inspector.findChild(limits.itemAt(0), "usagePrimary_codex") : null;
                const remaining = primary ? inspector.findChild(primary, "usageRemaining") : null;
                if (!scenario.check(remaining && remaining.text === "75% restante" && remaining.width > 0,
                    "la ventana no muestra el porcentaje restante")) return;
                if (!scenario.check(primary.compact && panel.implicitWidth === 320 && panel.implicitHeight <= 300
                    && !inspector.findChild(panel, "usageLifetimeTokens") && !inspector.findChild(panel, "chatUsageUpdated")
                    && !inspector.findChild(panel, "chatUsageRefresh") && !inspector.findChild(panel, "usageClose")
                    && inspector.findChild(primary, "usageDescription").text.indexOf("usado") < 0,
                    "la tarjeta conserva controles o información secundaria")) return;
                // Pares de la captura: consumo y saldo deben sumar 100, incluso en los extremos.
                const now = 1800000000000;
                const example = limitExample.createObject(chat.contentItem, { nowMs: now,
                    windowData: { used_percent: 35, window_minutes: 300, resets_at: now / 1000 + 10920 } });
                inspector.wait(250);
                const percent = inspector.findChild(example, "usageRemaining");
                const bar = inspector.findChild(example, "usageRemainingBar");
                const description = inspector.findChild(example, "usageDescription");
                if (!scenario.check(percent.text === "65% restante"
                    && Math.abs(bar.width / bar.parent.width - .65) < .001
                    && description.text === "35% usado · Se restablece en 3 h y 2 min",
                    "35% consumido no corresponde a 65% restante o renovación incorrecta")) return;
                example.nowMs += 60000;
                if (!scenario.check(description.text === "35% usado · Se restablece en 3 h y 1 min", "la cuenta atrás no avanza")) return;
                example.windowData = { used_percent: 30, window_minutes: 10080, resets_at: null };
                if (!scenario.check(percent.text === "70% restante" && example.period(10080) === "Límite semanal"
                    && description.text === "30% usado · Renovación no informada", "límite semanal o renovación desconocida incorrectos")) return;
                example.windowData = { used_percent: 0 };
                if (!scenario.check(percent.text === "100% restante", "cero usado tratado como desconocido")) return;
                example.windowData = { used_percent: 100 };
                if (!scenario.check(percent.text === "0% restante", "cuota agotada invertida")) return;
                example.windowData = null;
                inspector.wait(250);
                if (!scenario.check(percent.text === "Sin datos" && bar.width === 0, "cuota desconocida se muestra como disponible")) return;
                example.compact = true;
                example.windowData = { used_percent: 35, window_minutes: 300, resets_at: now / 1000 + 10920 };
                example.nowMs = now;
                inspector.wait(20);
                if (!scenario.check(example.period(300) === "5 h" && example.period(10080) === "Semanal"
                    && description.text === "Se restablece en 3 h y 2 min" && percent.text === "65% restante"
                    && bar.height === 3, "la versión compacta cambia las cuotas o conserva texto redundante")) return;
                example.destroy();
                const prompt = inspector.findChild(chat, "chatPrompt");
                chat.contentItem.Window.window.requestActivate();
                prompt.forceActiveFocus(); prompt.text = "hola";
                inspector.keyClick(Qt.Key_Return);
                if (!scenario.check(agent.busy && panel.visible && !chat.dialogVisible, "no se puede enviar un mensaje con el uso abierto")) return;
                const usageContent = inspector.findChild(panel, "usageContent");
                usageContent.forceActiveFocus(); usageContent.Window.window.requestActivate(); inspector.wait(80);
                previousUpdate = agent.accountUsage.checked_at;
                usageInspector.keyClick(Qt.Key_F5);
                scenario.stage = 2;
            } else if (scenario.stage === 2) {
                if (agent.busy || agent.usageBusy || agent.accountUsage.checked_at === previousUpdate) return;
                if (!scenario.check(agent.messages.count === 2 && panel.visible && agent.currentChatId,
                    "el chat no responde mientras la ventana está abierta")) return;
                savedChatId = agent.currentChatId;
                panel.close(); inspector.wait(180);
                const refreshTimer = inspector.findChild(panel, "usageRefreshTimer");
                if (!scenario.check(!panel.visible && !refreshTimer.running && chat.visible, "cerrar el uso afecta al chat o conserva el sondeo")) return;
                panel.open(); inspector.wait(180);
                panel.closed();
                if (!scenario.check(!panel.visible && !refreshTimer.running, "cierre nativo conserva intención de visibilidad")) return;
                panel.open(); inspector.wait(180);
                const content = inspector.findChild(panel, "usageContent");
                content.forceActiveFocus(); content.Window.window.requestActivate(); inspector.wait(180);
                usageInspector.keyClick(Qt.Key_Escape);
                inspector.wait(30);
                if (!scenario.check(!panel.visible && chat.visible && agent.currentChatId === savedChatId,
                    "Esc no cierra únicamente la ventana de uso: uso=" + panel.visible + ", chat=" + chat.visible
                    + ", contexto=" + (agent.currentChatId === savedChatId) + ", foco=" + content.activeFocus
                    + ", ventanaActiva=" + (content.Window.window && content.Window.window.active))) return;
                panel.open(); inspector.wait(180);
                if (!scenario.check(chat.usageWindow === panel && !chat.dialogVisible, "reabrir crea otra ventana o bloquea el chat")) return;
                scenario.stage = 3;
            } else if (scenario.stage === 3) {
                if (agent.usageBusy) return;
                if (!scenario.check(panel.visible && !agent.usageError, "la ventana no se puede reabrir")) return;
                agent.selectAccount("fixture-second");
                scenario.stage = 4;
            } else if (scenario.stage === 4) {
                if (agent.accountBusy || agent.email !== "second@example.invalid") return;
                if (agent.usageBusy) return;
                if (!scenario.check(!agent.accountUsage.checked_at && !agent.usageBusy, "consumo anterior conservado al cambiar cuenta")) return;
                agent.refreshUsage();
                scenario.stage = 5;
            } else if (scenario.stage === 5) {
                if (agent.usageBusy || !agent.usageError) return;
                if (!scenario.check(!agent.accountUsage.checked_at && agent.usageError.indexOf("otra cuenta") >= 0
                    && agent.messages.count === 2 && agent.canSend, "mezcla de cuentas o error añadido al chat")) return;
                agent.selectAccount("fixture-account");
                scenario.stage = 6;
            } else if (scenario.stage === 6) {
                if (agent.accountBusy || agent.email !== "fixture@example.invalid") return;
                agent.refreshUsage();
                scenario.stage = 7;
            } else if (scenario.stage === 7) {
                if (agent.usageBusy || !agent.accountUsage.checked_at) return;
                if (!scenario.check(!agent.usageError && agent.accountUsage.limits[0].primary.used_percent === 25,
                    "la consulta no se recupera después de corregir la cuenta")) return;
                agent.selectArea("work", "");
                scenario.stage = 8;
            } else if (scenario.stage === 8) {
                if (agent.areaBusy || agent.activeArea !== "work") return;
                if (!scenario.check(panel.visible && !chat.dialogVisible && agent.accountUsage.checked_at
                    && panel.mainWindowTitle === chat.title,
                    "cambiar a Work cierra el uso o borra la consulta")) return;
                agent.selectArea("chat");
                scenario.stage = 9;
            } else if (scenario.stage === 9) {
                if (agent.areaBusy || agent.activeArea !== "chat") return;
                if (!scenario.check(panel.visible && agent.currentChatId === savedChatId && agent.messages.count === 2,
                    "volver a Chat no conserva la ventana y la conversación")) return;
                console.log("USAGE_OK: tarjeta flotante compacta sin cabecera/botones/datos secundarios, cuotas y barras finas, F5, chat simultáneo, Chat/Work, Esc/compositor, reapertura, sondeo visible e aislamiento de cuentas");
                steps.stop(); Qt.quit();
            }
            } finally { scenario.stepping = false; }
        }
    }
    Timer {
        interval: 8000
        running: true
        onTriggered: scenario.check(false, "Tiempo agotado en etapa " + scenario.stage + ": " + agent.usageError)
    }
}
