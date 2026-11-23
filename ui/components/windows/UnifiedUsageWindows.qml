import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// Tres tarjetas de uso, una por proveedor, en fila sobre el chat mientras dura el modo unificado.
Scope {
    id: group
    required property AgentBridge bridge
    property string mainWindowTitle: ""
    property var dismissed: ({})
    property bool shown: false
    property double nowMs: Date.now()
    readonly property var cards: [chatgptCard, agyCard, claudeCard]
    readonly property int rowHeight: cards.reduce(
        (height, card) => card.visible ? Math.max(height, card.naturalHeight) : height, 120)

    function open() {
        dismissed = ({});
        shown = true;
        refresh();
    }
    function close() { shown = false; }
    function refresh() {
        nowMs = Date.now();
        bridge.refreshTeamUsage();
    }
    function dismiss(providerId) {
        dismissed = Object.assign({}, dismissed, { [providerId]: true });
        if (cards.every(card => !card.visible)) shown = false;
    }
    function schedulePlacement() {
        if (shown && mainWindowTitle
            && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen")
            placementDelay.restart();
    }
    onShownChanged: {
        if (!shown) { placementDelay.stop(); placement.running = false; }
        schedulePlacement();
    }
    onRowHeightChanged: schedulePlacement()
    onMainWindowTitleChanged: schedulePlacement()
    Connections {
        target: group.bridge
        function onAreaChanged() { group.schedulePlacement(); }
    }

    component Card: ProviderUsageWindow {
        bridge: group.bridge
        rowHeight: group.rowHeight
        nowMs: group.nowMs
        onBackingWindowVisibleChanged: group.schedulePlacement()
        onDismissed: group.dismiss(providerId)
        onRefreshRequested: group.refresh()
    }
    Card {
        id: chatgptCard
        providerId: "chatgpt"; label: "ChatGPT"; symbol: "◎"
        visible: group.shown && !group.dismissed.chatgpt
    }
    Card {
        id: agyCard
        providerId: "agy"; label: "Gemini"; symbol: "✦"
        visible: group.shown && group.bridge.agyAvailable && !group.dismissed.agy
    }
    Card {
        id: claudeCard
        providerId: "claude"; label: "Claude"; symbol: "◆"
        visible: group.shown && group.bridge.claudeAvailable && !group.dismissed.claude
    }

    Timer {
        interval: 60000
        repeat: true
        running: group.shown
        onTriggered: group.refresh()
    }
    Timer {
        id: placementDelay
        interval: 160
        onTriggered: {
            const card = group.cards.find(item => item.visible);
            if (!card || !group.mainWindowTitle) return;
            placement.running = false;
            placement.command = [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python",
                Quickshell.shellDir + "/scripts/place-text-viewer.py",
                String(Quickshell.processId), card.title, "21", group.mainWindowTitle];
            placement.running = true;
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del uso: " + data) }
    }
}
