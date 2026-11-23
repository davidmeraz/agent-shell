import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import AgentShell.Native
import "../.."
import "../shared"

// Ventana independiente: acompaña Chat/Work sin bloquearlos ni desenfocarlos.
NativeWindow {
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
    property double nowMs: Date.now()
    property bool geminiOnly: true
    readonly property bool hasData: !!bridge.accountUsage.checked_at
    readonly property bool isAgyUsage: hasData && bridge.accountUsage.source === "agy"
    readonly property bool isLoading: !hasData && !bridge.usageError
        && (bridge.usageBusy || bridge.backendUsageBusy || bridge.usageRetryPending
            || bridge.accountBusy || bridge.providerBusy || !bridge.ready)
    readonly property string engineSymbol: bridge.provider === "agy" ? "✦"
        : bridge.provider === "claude" ? "◆" : "◎"
    readonly property color accentGlow: GemaTheme.synced ? GemaTheme.accent : "#dce8f7"
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
            && NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE") && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen")
            placementDelay.restart();
    }
    onImplicitHeightChanged: schedulePlacement()
    onMainWindowTitleChanged: schedulePlacement()
    function refreshWhenAvailable() {
        if (visible && bridge.ready && bridge.engineReady && !hasData
            && !bridge.accountBusy && !bridge.loginBusy && !bridge.claudeLoginBusy && !bridge.providerBusy)
            bridge.refreshUsage();
    }
    Connections {
        target: usage.bridge
        function onAreaChanged() { usage.schedulePlacement(); }
        function onReadyChanged() { Qt.callLater(usage.refreshWhenAvailable); }
        function onLoginBusyChanged() { Qt.callLater(usage.refreshWhenAvailable); }
        function onClaudeAuthenticatedChanged() { Qt.callLater(usage.refreshWhenAvailable); }
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
            placement.command = [NativeApp.pythonExecutable,
                NativeApp.placementScript,
                String(NativeApp.processId), usage.title, "4", usage.mainWindowTitle];
            placement.running = true;
        }
    }
    NativeProcess {
        id: placement
        errorOutput: LineParser { onRead: data => console.warn("Posición del uso: " + data) }
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
            GlassToolTipTheme {}
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
                                : usage.bridge.provider === "claude"
                                  ? "Uso · Claude"
                                  : "Uso · ChatGPT"
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: "#cfd8e3"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        // Indicador discreto cuando se actualiza en segundo plano (F5 / 60s) con datos ya visibles.
                        Item {
                            id: liveRefreshSpinner
                            objectName: "usageRefreshingDot"
                            visible: usage.hasData && usage.bridge.usageBusy
                            implicitWidth: 14
                            implicitHeight: 14
                            Rectangle {
                                anchors.fill: parent
                                radius: 7
                                color: "transparent"
                                border.width: 1
                                border.color: "#28ffffff"
                            }
                            Item {
                                anchors.fill: parent
                                RotationAnimation on rotation {
                                    from: 0; to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                    running: liveRefreshSpinner.visible && GemaTheme.animations
                                }
                                Rectangle {
                                    width: 4; height: 4; radius: 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: -1.5
                                    color: usage.accentGlow
                                }
                            }
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
                                ? "Mostrando solo modelos Gemini. Pulsar para expandir y ver también Claude y GPT"
                                : "Mostrando todos los modelos de Antigravity. Pulsar para contraer a solo Gemini"
                            ToolTip.visible: hovered
                            ToolTip.delay: 350
                            ToolTip.text: usage.geminiOnly
                                ? "Expandir para ver también Claude · GPT"
                                : "Contraer para mostrar solo Gemini"
                            contentItem: Text {
                                text: usage.geminiOnly ? "Todos ▾" : "Solo Gemini ▴"
                                textFormat: Text.PlainText
                                color: !usage.geminiOnly
                                    ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                                    : (geminiFilterButton.hovered ? "#ffffff" : "#b8c4d2")
                                font.pixelSize: 10
                                font.weight: !usage.geminiOnly ? Font.DemiBold : Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: GlassPanel {
                                radius: 6
                                reflective: false
                                highlighted: !usage.geminiOnly || geminiFilterButton.hovered
                                topColor: !usage.geminiOnly
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2cffffff")
                                    : (geminiFilterButton.hovered ? "#22ffffff" : "#14ffffff")
                                bottomColor: "#08ffffff"
                                edgeColor: !usage.geminiOnly
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
                        horizontalAlignment: Text.AlignHCenter
                        color: "#bbbbbb"
                        font.pixelSize: 12
                    }
                    // Estado de carga centrado con órbita de vidrio, onda radial y riel luminoso.
                    Item {
                        id: loadingState
                        objectName: "usageLoadingState"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 94
                        visible: usage.isLoading

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 9

                            Item {
                                id: orbitalMedallion
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 42
                                implicitHeight: 42

                                // Onda radial expansiva suave.
                                Rectangle {
                                    id: pulseRipple
                                    anchors.centerIn: parent
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: "transparent"
                                    border.width: 1
                                    border.color: GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#55dce8f7"
                                    opacity: 0.0
                                    scale: 0.85

                                    ParallelAnimation {
                                        running: loadingState.visible && GemaTheme.animations
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            target: pulseRipple
                                            property: "scale"
                                            from: 0.88; to: 1.48
                                            duration: 1500
                                            easing.type: Easing.OutCubic
                                        }
                                        SequentialAnimation {
                                            NumberAnimation {
                                                target: pulseRipple
                                                property: "opacity"
                                                from: 0.0; to: 0.55
                                                duration: 280
                                                easing.type: Easing.OutQuad
                                            }
                                            NumberAnimation {
                                                target: pulseRipple
                                                property: "opacity"
                                                from: 0.55; to: 0.0
                                                duration: 1220
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }

                                // Anillo orbital base.
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: "transparent"
                                    border.width: 1
                                    border.color: "#24ffffff"
                                }

                                // Medallón central de vidrio con el símbolo del motor activo.
                                GlassPanel {
                                    id: centerBadge
                                    anchors.centerIn: parent
                                    width: 28
                                    height: 28
                                    radius: 14
                                    reflective: false
                                    topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.20) : "#20ffffff"
                                    bottomColor: "#0affffff"
                                    edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.42) : "#36ffffff"

                                    Text {
                                        id: engineGlyph
                                        anchors.centerIn: parent
                                        text: usage.engineSymbol
                                        color: usage.accentGlow
                                        font.pixelSize: 12
                                        style: Text.Raised
                                        styleColor: GemaTheme.textShadow

                                        SequentialAnimation on scale {
                                            running: loadingState.visible && GemaTheme.animations
                                            loops: Animation.Infinite
                                            onRunningChanged: if (!running) engineGlyph.scale = 1.0
                                            NumberAnimation { from: 0.92; to: 1.10; duration: 750; easing.type: Easing.InOutSine }
                                            NumberAnimation { from: 1.10; to: 0.92; duration: 750; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }

                                // Perlas luminosas orbitando suavemente alrededor del medallón.
                                Item {
                                    id: orbitCarrier
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    RotationAnimation on rotation {
                                        from: 0; to: 360
                                        duration: 1350
                                        loops: Animation.Infinite
                                        running: loadingState.visible && GemaTheme.animations
                                    }
                                    Rectangle {
                                        width: 11; height: 11; radius: 5.5
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: -5.5
                                        color: GemaTheme.synced ? GemaTheme.accentAlpha(0.32) : "#38dce8f7"
                                    }
                                    Rectangle {
                                        width: 5; height: 5; radius: 2.5
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: -2.5
                                        color: usage.accentGlow
                                    }
                                    Rectangle {
                                        width: 3; height: 3; radius: 1.5
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -1.5
                                        color: "#66ffffff"
                                    }
                                }
                            }

                            Text {
                                objectName: "usageLoadingLabel"
                                Layout.alignment: Qt.AlignHCenter
                                text: usage.bridge.providerBusy
                                    ? "Sincronizando cuotas…"
                                    : "Consultando uso…"
                                textFormat: Text.PlainText
                                horizontalAlignment: Text.AlignHCenter
                                color: "#c8d4e2"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                            }

                            // Riel luminoso fluido centrado bajo el texto.
                            Rectangle {
                                id: shimmerTrack
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 118
                                implicitHeight: 2.5
                                radius: 1.5
                                color: "#1cffffff"
                                clip: true

                                Rectangle {
                                    id: shimmerComet
                                    width: 46
                                    height: parent.height
                                    radius: parent.radius
                                    x: -width
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "#00ffffff" }
                                        GradientStop { position: 0.5; color: usage.accentGlow }
                                        GradientStop { position: 1.0; color: "#00ffffff" }
                                    }
                                    SequentialAnimation on x {
                                        running: loadingState.visible && GemaTheme.animations
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            from: -shimmerComet.width
                                            to: shimmerTrack.implicitWidth
                                            duration: 1150
                                            easing.type: Easing.InOutSine
                                        }
                                        NumberAnimation {
                                            from: shimmerTrack.implicitWidth
                                            to: -shimmerComet.width
                                            duration: 1150
                                            easing.type: Easing.InOutSine
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 72
                        visible: !usage.hasData && !usage.bridge.usageError && !usage.isLoading
                        Text {
                            anchors.centerIn: parent
                            text: "Sin datos de uso"
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            color: "#9aa6b4"
                            font.pixelSize: 11
                        }
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
