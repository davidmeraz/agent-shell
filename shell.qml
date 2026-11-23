import QtQuick
import AgentShell.Native
import "ui"

// Aplicación nativa Qt6/Wayland conectada al backend mediante AgentBridge.
NativeScope {
    id: root
    property bool usageWasVisible: false
    property bool unifiedWasVisible: false

    AgentBridge { id: agent }

    ChatWindow {
        id: chatWindow
        bridge: agent
        onClosed: Qt.quit()
    }

    Connections {
        target: NativeApp
        function onActivateRequested() {
            if (!chatWindow.visible) {
                chatWindow.visible = true;
                if (root.usageWasVisible && !agent.unifiedMode) chatWindow.usageWindow.visible = true;
                if (root.unifiedWasVisible && agent.unifiedMode) chatWindow.unifiedUsage.open();
            }
            chatWindow.focusWindow();
            NativeApp.focusInHyprland(chatWindow.title);
        }
        function onToggleRequested() {
            if (chatWindow.visible && chatWindow.active) {
                root.usageWasVisible = chatWindow.usageWindow.visible;
                root.unifiedWasVisible = chatWindow.unifiedUsage.shown;
                chatWindow.usageWindow.visible = false;
                chatWindow.unifiedUsage.close();
                chatWindow.visible = false;
                return;
            }
            if (!chatWindow.visible) {
                chatWindow.visible = true;
                if (root.usageWasVisible && !agent.unifiedMode) chatWindow.usageWindow.visible = true;
                if (root.unifiedWasVisible && agent.unifiedMode) chatWindow.unifiedUsage.open();
            }
            chatWindow.focusWindow();
            NativeApp.focusInHyprland(chatWindow.title);
        }
        function onQuitRequested() {
            Qt.quit();
        }
    }
}
