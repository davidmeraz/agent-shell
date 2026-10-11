import Quickshell
import "ui"

// Una ventana de conversación; el motor de Codex queda detrás de AgentBridge.
ShellRoot {
    AgentBridge { id: agent }

    ChatWindow {
        bridge: agent
        onClosed: Qt.quit()
    }
}
