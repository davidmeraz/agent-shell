import QtQuick
import AgentShell.Native
import "../.."

// Una ventana flotante por rol: aparece cuando el arquitecto usa ese subagente y se apila junta en el lateral.
NativeScope {
    id: group
    required property AgentBridge bridge
    required property NativeWindow mainWindow
    property var dismissed: ({})
    property double nowMs: Date.now()
    property string side: "right"
    readonly property var cards: [chatgptCard, claudeCard, agyCard]
    readonly property bool available: bridge.unifiedMode && mainWindow.visible
    readonly property bool lingering: bridge.busy || linger.running
    readonly property bool compositor: !!NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE")
                                       && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen"
    readonly property int visibleCount: cards.filter(card => card.visible).length
    // Obreros por orden de aparición en el turno: cada uno conserva su lugar.
    readonly property var order: bridge.agents.reduce(
        (roles, agent) => roles.includes(agent.role) ? roles : roles.concat(agent.role), [])

    function markPlaced() {
        for (const card of cards) {
            if (card.visible) card.placed = true;
        }
    }
    function schedulePlacement() {
        const visibleCards = cards.filter(card => card.visible);
        if (!visibleCards.length) {
            placementDelay.stop();
            placementLimit.stop();
            placement.running = false;
            return;
        }
        if (!compositor || !mainWindow.title) {
            markPlaced();
            return;
        }
        placementDelay.restart();
        placementLimit.restart();
    }
    onOrderChanged: schedulePlacement()

    Connections {
        target: group.mainWindow
        function onTitleChanged() { group.schedulePlacement(); }
    }
    Connections {
        target: group.bridge
        function onBusyChanged() {
            if (group.bridge.busy) {
                group.dismissed = ({});
                linger.stop();
                for (const card of group.cards) card.resetCompactState();
            } else if (group.bridge.agents.length) {
                linger.restart();
            }
        }
    }
    Timer { id: linger; interval: 45000 }
    Timer {
        interval: 1000
        repeat: true
        running: group.bridge.activeAgents.length > 0
        onTriggered: group.nowMs = Date.now()
    }
    Timer {
        id: placementDelay
        interval: 90
        onTriggered: {
            const ordered = [];
            for (const role of group.order) {
                const card = group.cards.find(item => item.role === role && item.visible);
                if (card) ordered.push({ title: card.title, compact: card.compact });
            }
            for (const card of group.cards) {
                if (card.visible && !ordered.some(spec => spec.title === card.title))
                    ordered.push({ title: card.title, compact: card.compact });
            }
            if (!ordered.length || !group.mainWindow.title) return;
            placement.running = false;
            placement.command = [
                NativeApp.pythonExecutable,
                NativeApp.placementScript,
                "--place-agents",
                String(NativeApp.processId),
                group.mainWindow.title,
                JSON.stringify(ordered),
            ];
            placement.running = true;
        }
    }
    Timer {
        id: placementLimit
        interval: 700
        onTriggered: group.markPlaced()
    }
    NativeProcess {
        id: placement
        output: LineParser {
            onRead: data => {
                const trimmed = data.trim();
                if (trimmed === "left" || trimmed === "right") group.side = trimmed;
            }
        }
        errorOutput: LineParser { onRead: data => console.warn("Posición de subagentes: " + data) }
        onExited: {
            placementLimit.stop();
            group.markPlaced();
        }
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
        side: group.side
        anotherRunning: group.bridge.activeAgents.some(item => item.role !== role)
        visiblePeers: group.visibleCount
        wanted: group.available && !!agent && !group.dismissed[role] && (group.lingering || pinned || hovered)
        onVisibleChanged: group.schedulePlacement()
        onCompactChanged: group.schedulePlacement()
        onDismissed: {
            pinned = false;
            group.dismissed = Object.assign({}, group.dismissed, { [role]: true });
        }
    }
    Card { id: chatgptCard; role: "chatgpt"; label: "Obrero ChatGPT"; glyph: "◎" }
    Card { id: claudeCard; role: "claude"; label: "Obrero Claude"; glyph: "◆" }
    Card { id: agyCard; role: "agy"; label: "Obrero Gemini"; glyph: "✦" }
}
