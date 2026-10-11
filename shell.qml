import Quickshell
import "ui"

// Una ventana de conversación conectada al backend mediante AgentBridge.
ShellRoot {
    AgentBridge { id: agent }

    ChatWindow {
        bridge: agent
        onClosed: Qt.quit()
    }
}
