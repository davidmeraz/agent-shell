import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// Ventana independiente: acompaña Chat/Work sin bloquearlos ni desenfocarlos.
FloatingWindow {
    id: usage
    objectName: "accountUsageWindow"
    required property AgentBridge bridge
    property string mainWindowTitle: ""
    title: "Agent Shell · Uso del plan"
    implicitWidth: 320
    implicitHeight: Math.max(140, Math.min(420, stats.implicitHeight + 32))
    // La altura sigue las cuotas incluso si llegan después de abrir en Wayland.
    minimumSize: Qt.size(260, implicitHeight)
    maximumSize: Qt.size(16777215, implicitHeight)
    color: "transparent"
    visible: false
    onClosed: usage.visible = false
    BackgroundEffect.blurRegion: Region { item: matteSurface; radius: matteSurface.radius }
    property double nowMs: Date.now()
    readonly property bool hasData: !!bridge.accountUsage.checked_at

    function open() {
        const alreadyVisible = visible;
        visible = true;
        if (alreadyVisible) bridge.refreshUsage();
        Qt.callLater(function() {
            if (!usage.visible || usage.bridge.activeArea === "work") return;
            content.forceActiveFocus();
            content.Window.window.requestActivate();
        });
    }
    function close() { visible = false; }
    onVisibleChanged: {
        if (visible) { nowMs = Date.now(); bridge.refreshUsage(); }
        schedulePlacement();
        if (!visible) { placementDelay.stop(); placement.running = false; }
    }
    // En Work comparte columna con el chat; en Chat conserva la tarjeta libre.
    function schedulePlacement() {
        if (visible && bridge.activeArea === "work" && mainWindowTitle
            && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen")
            placementDelay.restart();
    }
    onImplicitHeightChanged: schedulePlacement()
    function refreshWhenAvailable() {
        if (visible && bridge.ready && bridge.authenticated && !hasData
            && !bridge.accountBusy && !bridge.loginBusy && !bridge.usageBusy)
            bridge.refreshUsage();
    }
    Connections {
        target: usage.bridge
        function onAreaChanged() { usage.schedulePlacement(); }
        function onReadyChanged() { Qt.callLater(usage.refreshWhenAvailable); }
        function onLoginBusyChanged() { Qt.callLater(usage.refreshWhenAvailable); }
        function onEventReceived(event) {
            if (event.type === "auth.refresh.finished") usage.refreshWhenAvailable();
        }
    }
    Timer {
        id: placementDelay
        interval: 120
        onTriggered: {
            if (!usage.visible || usage.bridge.activeArea !== "work") return;
            placement.running = false;
            placement.command = [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python",
                Quickshell.shellDir + "/scripts/place-text-viewer.py",
                String(Quickshell.processId), usage.title, "4", usage.mainWindowTitle];
            placement.running = true;
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del uso: " + data) }
    }

    Timer {
        objectName: "usageRefreshTimer"
        interval: 60000
        repeat: true
        running: usage.visible
        onTriggered: { usage.nowMs = Date.now(); usage.bridge.refreshUsage(); }
    }
    ViewerMotion {
        anchors.fill: parent
        shown: usage.visible
        MattePanel {
            id: matteSurface
            objectName: "usageMatteSurface"
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#90303030"
            bottomColor: "#a01c1c1c"
            edgeColor: "#50ffffff"
        }
        Item {
            id: content
            objectName: "usageContent"
            anchors.fill: parent
            focus: true
            Shortcut {
                sequence: "Esc"
                context: Qt.WindowShortcut
                enabled: usage.visible
                onActivated: usage.close()
            }
            Shortcut {
                sequence: "F5"
                context: Qt.WindowShortcut
                enabled: usage.visible
                onActivated: { usage.nowMs = Date.now(); usage.bridge.refreshUsage(); }
            }
            // El contenido es informativo; se puede arrastrar la tarjeta sin una cabecera.
            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton
                onActiveChanged: { if (active) usage.startSystemMove(); }
            }
            ScrollView {
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: availableWidth
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    id: stats
                    objectName: "usageStats"
                    width: parent.width
                    spacing: 18
                    Text {
                        objectName: "chatUsageError"
                        Layout.fillWidth: true
                        visible: !!usage.bridge.usageError
                        text: usage.bridge.usageError
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !usage.hasData && !usage.bridge.usageError
                        text: usage.bridge.usageBusy ? "Consultando uso…" : "Sin datos de uso"
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }
                    Repeater {
                        objectName: "chatUsageLimits"
                        model: usage.hasData ? usage.bridge.accountUsage.limits : []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 14
                            Text {
                                Layout.fillWidth: true
                                visible: usage.bridge.accountUsage.limits.length > 1
                                text: modelData.name === "codex" ? "Codex" : modelData.name || "Codex"
                                textFormat: Text.PlainText
                                color: "#aaaaaa"
                                font.pixelSize: 11
                            }
                            UsageLimit {
                                objectName: "usagePrimary_" + modelData.id
                                Layout.fillWidth: true
                                visible: modelData.primary !== null || modelData.secondary === null
                                compact: true
                                windowData: modelData.primary
                                nowMs: usage.nowMs
                                fallbackTitle: "Uso"
                            }
                            UsageLimit {
                                Layout.fillWidth: true
                                visible: modelData.secondary !== null
                                compact: true
                                windowData: modelData.secondary
                                nowMs: usage.nowMs
                                fallbackTitle: "Adicional"
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: usage.hasData && !usage.bridge.accountUsage.limits.length
                        text: "Sin cuotas disponibles"
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
