import QtQuick
import AgentShell.Native
import "../.."

// Una ventana flotante por rol: aparece cuando el arquitecto usa ese subagente y se va después del turno.
NativeScope {
    id: group
    required property AgentBridge bridge
    required property NativeWindow mainWindow
    property var dismissed: ({})
    property double nowMs: Date.now()
    readonly property var cards: [explorerCard, builderCard, specialistCard, reviewerCard]
    readonly property bool available: bridge.unifiedMode && mainWindow.visible
    readonly property bool lingering: bridge.busy || linger.running
    // Roles por orden de aparición en el turno: cada uno conserva su lugar.
    readonly property var order: bridge.agents.reduce(
        (roles, agent) => roles.includes(agent.role) ? roles : roles.concat(agent.role), [])

    Connections {
        target: group.bridge
        function onBusyChanged() {
            if (group.bridge.busy) { group.dismissed = ({}); linger.stop(); }
            else if (group.bridge.agents.length) linger.restart();
        }
    }
    Timer { id: linger; interval: 45000 }
    Timer {
        interval: 1000
        repeat: true
        running: !!group.bridge.activeAgent
        onTriggered: group.nowMs = Date.now()
    }
    // Se pide antes de la primera ventana para que ninguna tome el foco al aparecer.
    NativeProcess {
        command: [NativeApp.pythonExecutable, NativeApp.placementScript, "--prepare-agents"]
        running: group.bridge.unifiedMode && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen"
        errorOutput: LineParser { onRead: data => console.warn("Reglas de subagentes: " + data) }
    }

    component Card: AgentWindow {
        id: card
        readonly property var work: group.bridge.agents.filter(item => item.role === role)
        mainWindow: group.mainWindow
        agent: work.length ? work[work.length - 1] : null
        count: work.length
        slot: Math.max(0, group.order.indexOf(role))
        nowMs: group.nowMs
        wanted: group.available && !!agent && !group.dismissed[role] && (group.lingering || pinned || hovered)
        onDismissed: {
            pinned = false;
            group.dismissed = Object.assign({}, group.dismissed, { [role]: true });
        }
    }
    Card { id: explorerCard; role: "explorer"; label: "Explorador"; glyph: "⌕" }
    Card { id: builderCard; role: "builder"; label: "Constructor"; glyph: "⬡" }
    Card { id: specialistCard; role: "specialist"; label: "Especialista"; glyph: "◈" }
    Card { id: reviewerCard; role: "reviewer"; label: "Revisor"; glyph: "⊙" }
}
