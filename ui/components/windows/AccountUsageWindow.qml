import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../shared"

// Ventana independiente: acompaña Chat/Work sin bloquearlos ni desenfocarlos.
FloatingWindow {
    id: usage
    objectName: "accountUsageWindow"
    required property AgentBridge bridge
    property string mainWindowTitle: ""
    title: "Agent Shell · Uso del plan"
    implicitWidth: 320
    implicitHeight: Math.max(140, Math.min(560, stats.implicitHeight + 32))
    // La altura sigue las cuotas incluso si llegan después de abrir en Wayland.
    minimumSize: Qt.size(260, implicitHeight)
    maximumSize: Qt.size(16777215, implicitHeight)
    color: "transparent"
    visible: false
    onClosed: usage.visible = false
    BackgroundEffect.blurRegion: Region { item: matteSurface; radius: matteSurface.radius }
    property double nowMs: Date.now()
    property bool geminiOnly: false
    readonly property bool hasData: !!bridge.accountUsage.checked_at
    readonly property bool isAgyUsage: hasData && bridge.accountUsage.source === "agy"
    readonly property var visibleLimits: {
        if (!hasData) return [];
        const raw = bridge.accountUsage.limits || [];
        if (!isAgyUsage) return raw;
        return raw.filter(item => {
            const id = (item.id || "").toLowerCase();
            const name = (item.name || "").toLowerCase();
            if (id.indexOf("argon") >= 0 || name.indexOf("argon") >= 0) return false;
            if (!geminiOnly) return true;
            return id.indexOf("gemini") >= 0 || name.indexOf("gemini") >= 0;
        });
    }

    function groupTitle(item) {
        const name = (item && item.name) ? item.name : "Codex";
        if (!isAgyUsage) return name === "codex" ? "Codex" : name;
        const lower = name.toLowerCase();
        if (lower.indexOf("gemini") >= 0) return "Gemini";
        if (lower.indexOf("claude") >= 0) return "Claude · GPT";
        return name;
    }

    function open() {
        const alreadyVisible = visible;
        visible = true;
        if (alreadyVisible) bridge.refreshUsage();
        Qt.callLater(function() {
            if (!usage.visible || usage.bridge.activeArea === "work" || usage.bridge.activeArea === "app") return;
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
    // Comparte columna con el chat desde el arranque, tanto en Chat como en Work.
    function schedulePlacement() {
        if (visible && mainWindowTitle
            && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen")
            placementDelay.restart();
    }
    onImplicitHeightChanged: schedulePlacement()
    onMainWindowTitleChanged: schedulePlacement()
    function refreshWhenAvailable() {
        if (visible && bridge.ready && bridge.engineReady && !hasData
            && !bridge.accountBusy && !bridge.loginBusy && !bridge.providerBusy && !bridge.usageBusy)
            bridge.refreshUsage();
    }
    Connections {
        target: usage.bridge
        function onAreaChanged() { usage.schedulePlacement(); }
        function onReadyChanged() { Qt.callLater(usage.refreshWhenAvailable); }
        function onLoginBusyChanged() { Qt.callLater(usage.refreshWhenAvailable); }
        function onProviderChanged() {
            usage.nowMs = Date.now();
            Qt.callLater(usage.refreshWhenAvailable);
        }
        function onEventReceived(event) {
            if (event.type === "auth.refresh.finished" || event.type === "provider.refresh.finished")
                usage.refreshWhenAvailable();
        }
    }
    Timer {
        id: placementDelay
        interval: 120
        onTriggered: {
            if (!usage.visible || !usage.mainWindowTitle) return;
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
            topColor: "#54141c26"
            bottomColor: "#680c121a"
            edgeColor: "#4cffffff"
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
            // El contenido es informativo; se puede arrastrar la tarjeta sin una cabecera pesada.
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
                    spacing: 12
                    RowLayout {
                        objectName: "usageHeaderRow"
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            objectName: "usageHeaderTitle"
                            Layout.fillWidth: true
                            text: usage.bridge.provider === "agy"
                                ? (usage.geminiOnly ? "Uso · Gemini" : "Uso · Antigravity")
                                : "Uso · ChatGPT"
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: "#cfd8e3"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Button {
                            id: geminiFilterButton
                            objectName: "usageGeminiOnlyButton"
                            visible: usage.isAgyUsage
                            implicitHeight: 20
                            leftPadding: 8
                            rightPadding: 8
                            topPadding: 0
                            bottomPadding: 0
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            scale: down ? 0.95 : (hovered ? 1.03 : 1.0)
                            Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 120 : 0; easing.type: Easing.OutCubic } }
                            onClicked: usage.geminiOnly = !usage.geminiOnly
                            Accessible.name: usage.geminiOnly
                                ? "Mostrando solo modelos Gemini. Pulsar para ver Gemini y Claude"
                                : "Filtrar para mostrar solo el uso de los modelos Gemini"
                            ToolTip.visible: hovered
                            ToolTip.delay: 350
                            ToolTip.text: usage.geminiOnly
                                ? "Mostrando solo Gemini · Clic para ver todos"
                                : "Mostrar solo el uso de Gemini"
                            contentItem: Text {
                                text: usage.geminiOnly ? "✦ Gemini" : "Solo Gemini"
                                textFormat: Text.PlainText
                                color: usage.geminiOnly
                                    ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                                    : (geminiFilterButton.hovered ? "#ffffff" : "#b8c4d2")
                                font.pixelSize: 10
                                font.weight: usage.geminiOnly ? Font.DemiBold : Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: GlassPanel {
                                radius: 6
                                reflective: false
                                highlighted: usage.geminiOnly || geminiFilterButton.hovered
                                topColor: usage.geminiOnly
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2cffffff")
                                    : (geminiFilterButton.hovered ? "#22ffffff" : "#14ffffff")
                                bottomColor: "#08ffffff"
                                edgeColor: usage.geminiOnly
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.58) : "#58ffffff")
                                    : (geminiFilterButton.hovered ? "#44ffffff" : "#28ffffff")
                            }
                        }
                    }
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
                        model: usage.visibleLimits
                        delegate: ColumnLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                visible: index > 0 && usage.isAgyUsage
                                color: "#1affffff"
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: usage.visibleLimits.length > 1
                                text: usage.groupTitle(modelData)
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: "#aaaaaa"
                                font.pixelSize: 11
                                HoverHandler { id: groupTitleHover }
                                ToolTip.visible: visible && groupTitleHover.hovered && !!modelData.description
                                ToolTip.delay: 350
                                ToolTip.text: modelData.description || ""
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
                        visible: usage.hasData && !usage.visibleLimits.length
                        text: usage.geminiOnly && usage.isAgyUsage
                            ? "Sin cuotas de Gemini disponibles"
                            : "Sin cuotas disponibles"
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
