import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."
import "../shared"

// Tarjeta de uso de un proveedor en modo unificado; UnifiedUsageWindows la alinea con las demás.
FloatingWindow {
    id: card
    required property AgentBridge bridge
    required property string providerId
    required property string label
    required property string symbol
    // Altura común de la fila para que las tarjetas queden alineadas.
    property int rowHeight: naturalHeight
    property bool geminiOnly: true
    property double nowMs: Date.now()
    readonly property int naturalHeight: Math.max(120, Math.min(420, stats.implicitHeight + 28))
    readonly property var usage: bridge.providerUsage[providerId] || null
    readonly property bool hasData: !!usage && !!usage.checked_at
    readonly property bool architect: bridge.provider === providerId
    readonly property bool working: !!bridge.activeWorker && bridge.activeWorker.worker.provider === providerId
    readonly property var limits: {
        const rows = hasData ? usage.limits || [] : [];
        if (providerId !== "agy") return rows;
        return rows.filter(row => {
            const id = ((row.id || "") + " " + (row.name || "")).toLowerCase();
            return id.indexOf("argon") < 0 && (!geminiOnly || id.indexOf("gemini") >= 0);
        });
    }
    signal dismissed()
    signal refreshRequested()

    objectName: "providerUsage_" + providerId
    title: "Agent Shell · Uso · " + label
    implicitWidth: 260
    implicitHeight: rowHeight
    minimumSize: Qt.size(150, rowHeight)
    maximumSize: Qt.size(16777215, rowHeight)
    color: "transparent"
    visible: false
    onClosed: dismissed()
    BackgroundEffect.blurRegion: Region { item: surface; radius: surface.radius }

    function groupTitle(row) {
        const name = row.name || "";
        if (name.toLowerCase().indexOf("gemini") >= 0) return "Gemini";
        return name.toLowerCase().indexOf("claude") >= 0 ? "Claude · GPT" : name;
    }

    ViewerMotion {
        anchors.fill: parent
        shown: card.visible
        MattePanel {
            id: surface
            anchors.fill: parent
            anchors.margins: 1
            radius: 18
            topColor: "#54141c26"
            bottomColor: "#680c121a"
            edgeColor: card.working && GemaTheme.synced ? GemaTheme.accentAlpha(0.80)
                       : card.working ? "#a8ffffff" : "#4cffffff"
        }
        Item {
            anchors.fill: parent
            focus: true
            Shortcut {
                sequence: "Esc"
                context: Qt.WindowShortcut
                enabled: card.visible
                onActivated: card.dismissed()
            }
            Shortcut {
                sequence: "F5"
                context: Qt.WindowShortcut
                enabled: card.visible
                onActivated: card.refreshRequested()
            }
            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton
                onActiveChanged: if (active) card.startSystemMove()
            }
            ScrollView {
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: availableWidth
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    id: stats
                    width: parent.width
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            objectName: "providerUsageTitle_" + card.providerId
                            Layout.fillWidth: true
                            text: card.symbol + " " + card.label
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: "#e6edf6"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            objectName: "providerUsageRole_" + card.providerId
                            visible: text !== ""
                            text: card.working ? "Trabajando" : card.architect ? "Arquitecto" : ""
                            color: GemaTheme.synced ? GemaTheme.accentInk : "#ffffff"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        Button {
                            id: expand
                            objectName: "providerUsageExpand_" + card.providerId
                            visible: card.providerId === "agy" && card.hasData
                            implicitWidth: 18
                            implicitHeight: 18
                            padding: 0
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            onClicked: card.geminiOnly = !card.geminiOnly
                            Accessible.name: card.geminiOnly ? "Ver también Claude y GPT" : "Mostrar solo Gemini"
                            ToolTip.visible: hovered
                            ToolTip.delay: 350
                            ToolTip.text: Accessible.name
                            contentItem: Text {
                                text: card.geminiOnly ? "▾" : "▴"
                                color: expand.hovered ? "#ffffff" : "#b8c4d2"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 6
                                color: expand.hovered ? "#22ffffff" : "#12ffffff"
                            }
                        }
                    }
                    Text {
                        objectName: "providerUsageNotice_" + card.providerId
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.usage && card.usage.error ? card.usage.error
                              : !card.hasData ? "Consultando uso…" : !card.limits.length ? "Sin cuotas disponibles" : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: "#b4c0ce"
                        font.pixelSize: 11
                    }
                    Repeater {
                        objectName: "providerUsageLimits_" + card.providerId
                        model: card.limits
                        delegate: ColumnLayout {
                            id: group
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                visible: card.limits.length > 1
                                text: card.groupTitle(group.modelData)
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: "#aaaaaa"
                                font.pixelSize: 10
                            }
                            UsageLimit {
                                Layout.fillWidth: true
                                visible: group.modelData.primary !== null
                                compact: true
                                windowData: group.modelData.primary
                                nowMs: card.nowMs
                                fallbackTitle: "Uso"
                            }
                            UsageLimit {
                                Layout.fillWidth: true
                                visible: group.modelData.secondary !== null
                                compact: true
                                windowData: group.modelData.secondary
                                nowMs: card.nowMs
                                fallbackTitle: "Adicional"
                            }
                        }
                    }
                }
            }
        }
    }
}
