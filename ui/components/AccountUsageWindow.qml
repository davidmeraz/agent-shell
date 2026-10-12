import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import ".."

// Ventana independiente: acompaña Chat/Work sin bloquearlos ni desenfocarlos.
FloatingWindow {
    id: usage
    objectName: "accountUsageWindow"
    required property AgentBridge bridge
    title: "Agent Shell · Uso del plan"
    implicitWidth: 320
    implicitHeight: Math.max(140, Math.min(420, stats.implicitHeight + 32))
    // La altura sigue las cuotas incluso si llegan después de abrir en Wayland.
    minimumSize: Qt.size(260, implicitHeight)
    maximumSize: Qt.size(1000, implicitHeight)
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
            if (!usage.visible) return;
            content.forceActiveFocus();
            content.Window.window.requestActivate();
        });
    }
    function close() { visible = false; }
    onVisibleChanged: {
        if (visible) { nowMs = Date.now(); bridge.refreshUsage(); }
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
