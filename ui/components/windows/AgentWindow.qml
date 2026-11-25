import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AgentShell.Native
import "../shared"

// Ventana flotante de un subagente: tarea, actividad en vivo, informe, métricas y modo compacto.
NativeWindow {
    id: card
    required property NativeWindow mainWindow
    required property string role
    required property string label
    required property string glyph
    // Último trabajo de este rol en el turno y cuántos lleva.
    property var agent: null
    property int count: 0
    property int slot: 0
    property bool wanted: false
    property bool pinned: false
    property double nowMs: Date.now()
    property string side: "right"
    property bool anotherRunning: false
    property int visiblePeers: 1
    // Al cerrarse conserva lo último que mostró mientras termina la animación.
    property var shown: null
    property bool placed: !compositor
    property real presence: wanted && placed ? 1 : 0
    property bool showReport: false
    property bool autoCompact: false
    property bool manualMode: false
    property bool manualCompact: false
    readonly property int compactHeight: 126
    readonly property int expandedHeight: 420
    readonly property bool hovered: hover.hovered
    readonly property bool working: !!shown && shown.status === "running"
    readonly property bool compact: manualMode ? manualCompact : (!working && !pinned && autoCompact)
    readonly property bool compositor: !!NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE")
                                       && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen"
    readonly property color accentColor: GemaTheme.synced ? GemaTheme.accent : "#dce8f7"
    readonly property color stateColor: !shown || working ? accentColor
        : shown.status === "completed" ? "#7fe0a7" : shown.status === "interrupted" ? "#ffc44d" : "#ff6d84"
    readonly property string outcome: !shown || working ? "" : shown.status === "completed" ? "✓"
        : shown.status === "interrupted" ? "■" : "!"
    readonly property string stateName: !shown ? "" : ({ running: "Trabajando", completed: "Listo", interrupted: "Detenido",
        quota_exhausted: "Sin cuota", incomplete: "Incompleto" })[shown.status] || "Falló"
    readonly property string elapsedText: !shown ? "" : elapsed(working
        ? Math.max(0, nowMs - shown.started_at * 1000) : shown.duration_ms)
    readonly property string compactSummary: {
        if (!shown) return "";
        const raw = shown.error || shown.summary || shown.task || "";
        return raw.replace(/\s+/g, " ").trim();
    }
    signal dismissed()

    objectName: "agentWindow_" + role
    title: "Agent Shell · Agente · " + label
    minimumSize: compact ? Qt.size(360, compactHeight) : Qt.size(360, 260)
    maximumSize: compact ? Qt.size(640, compactHeight) : Qt.size(16777215, 16777215)
    implicitWidth: 480
    implicitHeight: compact ? compactHeight : expandedHeight
    color: "transparent"
    visible: wanted || presence > 0.01
    onClosed: dismissed()
    onAgentChanged: {
        if (!agent) return;
        const fresh = !shown || shown.id !== agent.id;
        shown = agent;
        if (fresh && agent.status === "running") {
            resetCompactState();
        } else if (visible && !working && !pinned && !manualMode && (anotherRunning || visiblePeers > 1)) {
            autoCompact = true;
            finishCompactTimer.stop();
        }
    }
    onVisibleChanged: if (!visible) placed = !compositor
    onMaximumSizeChanged: {
        if (!compact && maximumSize.height >= expandedHeight && height < expandedHeight)
            height = expandedHeight;
    }
    // Aparecer mientras se escribe en el chat no debe sacarlo del editor.
    onWantedChanged: if (wanted && mainWindow.active) Qt.callLater(() => mainWindow.requestActivate())
    onWorkingChanged: {
        showReport = !working;
        if (working) {
            resetCompactState();
        } else if (visible && !pinned && !manualMode) {
            if (anotherRunning || visiblePeers > 1) {
                autoCompact = true;
                finishCompactTimer.stop();
            } else {
                finishCompactTimer.restart();
            }
        }
    }
    onAnotherRunningChanged: {
        if (shown && visible && anotherRunning && !working && !pinned && !manualMode) {
            autoCompact = true;
            finishCompactTimer.stop();
        }
    }
    onVisiblePeersChanged: {
        if (shown && visible && visiblePeers > 1 && !working && !pinned && !manualMode) {
            autoCompact = true;
            finishCompactTimer.stop();
        }
    }
    onHoveredChanged: {
        if (!hovered && !working && !pinned && !manualMode && !autoCompact && visible)
            finishCompactTimer.restart();
    }
    onOutcomeChanged: if (outcome && visible && GemaTheme.animations) finishGlow.restart()
    Behavior on presence {
        NumberAnimation {
            duration: !GemaTheme.animations ? 0 : card.wanted ? 460 : 240
            easing.type: card.wanted ? Easing.OutCubic : Easing.InCubic
        }
    }

    function toggleCompact() {
        const nextCompact = !compact;
        manualMode = true;
        manualCompact = nextCompact;
        finishCompactTimer.stop();
        if (!nextCompact) showReport = !working;
    }
    function expand() {
        manualMode = true;
        manualCompact = false;
        finishCompactTimer.stop();
        showReport = !working;
    }
    function resetCompactState() {
        autoCompact = false;
        manualMode = false;
        manualCompact = false;
        finishCompactTimer.stop();
    }
    function elapsed(ms) {
        const seconds = Math.floor(ms / 1000);
        return seconds < 60 ? seconds + " s" : Math.floor(seconds / 60) + " min " + (seconds % 60) + " s";
    }
    function engine(provider) {
        return provider === "agy" ? "Antigravity" : provider === "claude" ? "Claude Code" : "ChatGPT";
    }
    function symbol(provider) {
        return provider === "agy" ? "✦" : provider === "claude" ? "◆" : "◎";
    }
    // Entrada escalonada de cada franja del contenido.
    function stage(step) {
        return Math.max(0, Math.min(1, (presence - 0.14 * step) / (1 - 0.14 * step)));
    }

    Timer {
        id: finishCompactTimer
        interval: 3500
        onTriggered: {
            if (!card.working && !card.pinned && !card.hovered && !card.manualMode)
                card.autoCompact = true;
        }
    }

    component IconButton: Button {
        id: iconButton
        property bool accented: false
        implicitWidth: 26
        implicitHeight: 26
        padding: 0
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        scale: down ? 0.9 : hovered ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 120 : 0; easing.type: Easing.OutCubic } }
        ToolTip.visible: hovered
        ToolTip.delay: 400
        ToolTip.text: Accessible.name
        contentItem: Text {
            text: iconButton.text
            color: iconButton.accented ? card.accentColor : iconButton.hovered ? "#ffffff" : "#9fb0c2"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: iconButton.accented ? Qt.alpha(card.accentColor, 0.2) : iconButton.hovered ? "#24ffffff" : "#10ffffff"
            border.width: 1
            border.color: iconButton.accented ? Qt.alpha(card.accentColor, 0.5) : "#1cffffff"
            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
        }
    }

    component Tab: Text {
        id: tab
        required property bool report
        readonly property bool selected: card.showReport === report
        color: selected ? "#f2f6fb" : tabHover.hovered ? "#d4dde8" : "#8d9cad"
        font.pixelSize: 12
        font.weight: selected ? Font.DemiBold : Font.Medium
        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
        HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: card.showReport = tab.report }
        Rectangle {
            anchors.top: parent.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            width: tab.selected ? parent.width : 0
            height: 2
            radius: 1
            color: card.stateColor
            Behavior on width { NumberAnimation { duration: GemaTheme.animations ? 240 : 0; easing.type: Easing.OutCubic } }
        }
    }

    component Stat: Rectangle {
        id: stat
        required property string caption
        required property string shortCaption
        property real amount: 0
        property string suffix: ""
        property string literal: ""
        property string tip: ""
        property real displayed: amount
        readonly property string formatted: stat.literal
            || (stat.suffix ? stat.displayed.toFixed(1) + stat.suffix : String(Math.round(stat.displayed)))
        Behavior on displayed { NumberAnimation { duration: GemaTheme.animations ? 420 : 0; easing.type: Easing.OutCubic } }
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: card.compact ? 26 : 28
        radius: 9
        color: "#0effffff"
        border.width: 1
        border.color: "#18ffffff"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 5
            Text {
                text: stat.formatted
                color: "#f2f6fb"
                font.pixelSize: 12
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: stat.shortCaption !== ""
                text: stat.shortCaption
                color: "#8d9cad"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }
        HoverHandler { id: statHover }
        ToolTip.visible: statHover.hovered
        ToolTip.delay: 250
        ToolTip.text: stat.tip ? stat.caption + ": " + stat.formatted + "\n" + stat.tip
                               : stat.caption + ": " + stat.formatted
    }

    Item {
        id: surface
        anchors.fill: parent
        opacity: card.presence
        scale: 0.94 + 0.06 * card.presence
        transformOrigin: card.side === "left" ? Item.Right : Item.Left
        transform: Translate { x: (card.side === "left" ? 40 : -40) * (1 - card.presence) }

        MattePanel {
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#54141c26"
            bottomColor: "#680c121a"
            edgeColor: card.working ? Qt.alpha(card.accentColor, 0.7) : "#4cffffff"
        }
        // Destello único del borde al terminar, con el color del resultado.
        Rectangle {
            id: glow
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            color: Qt.alpha(card.stateColor, 0.10)
            border.width: 2
            border.color: card.stateColor
            opacity: 0
            SequentialAnimation {
                id: finishGlow
                NumberAnimation { target: glow; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InOutSine }
            }
        }
        HoverHandler { id: hover }
        DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) card.startSystemMove()
        }
        GlassToolTipTheme {}

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: card.compact ? 12 : 14
            spacing: card.compact ? 6 : 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: card.stage(1)
                AgentMedallion {
                    objectName: "agentMedallion_" + card.role
                    size: card.compact ? 36 : 42
                    glyph: card.glyph
                    working: card.working && card.visible
                    outcome: card.outcome
                    tint: card.stateColor
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 1
                    Text {
                        objectName: "agentTitle_" + card.role
                        Layout.fillWidth: true
                        text: card.label + (card.count > 1 ? " ×" + card.count : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: "#f5f8fc"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    Text {
                        objectName: "agentModel_" + card.role
                        Layout.fillWidth: true
                        text: card.shown && card.shown.worker.name
                            ? card.symbol(card.shown.worker.provider) + " " + card.shown.worker.name + " · "
                              + card.engine(card.shown.worker.provider)
                              + (card.shown.worker.effort ? " · " + card.shown.worker.effort : "")
                            : "Eligiendo modelo…"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: "#a9b8c8"
                        font.pixelSize: 11
                    }
                }
                Rectangle {
                    implicitWidth: chip.implicitWidth + 18
                    implicitHeight: 24
                    radius: 12
                    color: Qt.alpha(card.stateColor, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(card.stateColor, 0.5)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Text {
                        id: chip
                        objectName: "agentState_" + card.role
                        anchors.centerIn: parent
                        text: card.stateName
                        color: card.stateColor
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                }
                IconButton {
                    objectName: "agentToggle_" + card.role
                    text: card.compact ? "▾" : "▴"
                    Accessible.name: card.compact ? "Expandir tarjeta" : "Compactar tarjeta"
                    onClicked: card.toggleCompact()
                }
                IconButton {
                    objectName: "agentPin_" + card.role
                    text: card.pinned ? "◉" : "○"
                    accented: card.pinned
                    Accessible.name: card.pinned ? "Dejar de fijar" : "Mantener abierta al terminar el turno"
                    onClicked: card.pinned = !card.pinned
                }
                IconButton {
                    text: "✕"
                    Accessible.name: "Cerrar"
                    onClicked: card.dismissed()
                }
            }

            // Riel de progreso: un cometa recorre la ventana mientras el subagente trabaja.
            Rectangle {
                id: rail
                Layout.fillWidth: true
                implicitHeight: 2
                radius: 1
                color: "#18ffffff"
                clip: true
                Rectangle {
                    id: comet
                    width: rail.width * 0.32
                    height: parent.height
                    radius: 1
                    opacity: card.working ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#00ffffff" }
                        GradientStop { position: 0.7; color: card.accentColor }
                        GradientStop { position: 1; color: "#00ffffff" }
                    }
                    NumberAnimation on x {
                        from: -comet.width
                        to: rail.width
                        duration: 1500
                        loops: Animation.Infinite
                        easing.type: Easing.InOutSine
                        running: card.working && card.visible && GemaTheme.animations
                    }
                }
                Rectangle {
                    height: parent.height
                    width: card.working ? 0 : rail.width
                    radius: 1
                    color: card.stateColor
                    opacity: card.working ? 0 : 0.8
                    Behavior on width { NumberAnimation { duration: GemaTheme.animations ? 620 : 0; easing.type: Easing.OutCubic } }
                }
            }

            // Resumen clicable de 1 línea en modo compacto para abrir el informe al instante.
            Item {
                visible: card.compact
                Layout.fillWidth: true
                implicitHeight: 20
                opacity: card.stage(2)
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: 3
                        radius: 1.5
                        color: Qt.alpha(card.stateColor, 0.8)
                    }
                    Text {
                        objectName: "agentSummary_" + card.role
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: card.compactSummary
                        textFormat: Text.PlainText
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        color: card.shown && card.shown.error ? "#ffb3bf" : "#d4dfe9"
                        font.pixelSize: 12
                    }
                    Text {
                        text: "Ver informe"
                        color: summaryHover.hovered ? "#f2f6fb" : "#8d9cad"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                    }
                }
                HoverHandler { id: summaryHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: card.expand() }
                ToolTip.visible: summaryHover.hovered
                ToolTip.delay: 350
                ToolTip.text: "Clic para expandir y ver el informe completo"
            }

            RowLayout {
                visible: !card.compact
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 8
                opacity: card.stage(2)
                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 3
                    radius: 1.5
                    color: Qt.alpha(card.stateColor, 0.8)
                }
                Text {
                    objectName: "agentTask_" + card.role
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: card.shown ? card.shown.task : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: card.height > 440 ? 4 : 2
                    elide: Text.ElideRight
                    color: "#dbe4ee"
                    font.pixelSize: 12
                    lineHeight: 1.15
                    HoverHandler { id: taskHover }
                    ToolTip.visible: taskHover.hovered && truncated
                    ToolTip.delay: 500
                    ToolTip.text: text
                }
            }

            RowLayout {
                visible: !card.compact
                spacing: 18
                opacity: card.stage(3)
                Tab { report: false; text: "Actividad" }
                Tab { report: true; text: "Informe" }
            }

            Item {
                visible: !card.compact
                Layout.fillWidth: true
                Layout.fillHeight: !card.compact
                Layout.topMargin: 2
                opacity: card.stage(3)
                AgentActivity {
                    objectName: "agentActivity_" + card.role
                    anchors.fill: parent
                    agent: card.shown
                    tint: card.stateColor
                    opacity: card.showReport ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: GemaTheme.animations ? 240 : 0; easing.type: Easing.InOutSine } }
                }
                Flickable {
                    id: reportView
                    anchors.fill: parent
                    contentHeight: report.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    opacity: card.showReport ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: GemaTheme.animations ? 240 : 0; easing.type: Easing.InOutSine } }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
                    Text {
                        id: report
                        objectName: "agentReport_" + card.role
                        width: reportView.width - 10
                        // Texto plano: el informe es dato del modelo y no debe cargar enlaces ni imágenes.
                        textFormat: Text.PlainText
                        text: !card.shown ? "" : card.working ? "El informe aparecerá al terminar."
                              : card.shown.error || card.shown.summary || "Sin informe"
                        wrapMode: Text.Wrap
                        color: card.shown && card.shown.error ? "#ffb3bf" : "#cbd6e2"
                        font.pixelSize: 12
                        lineHeight: 1.2
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                opacity: card.stage(4)
                Stat { caption: "Tiempo"; shortCaption: ""; literal: card.elapsedText }
                Stat { caption: "Acciones"; shortCaption: "acc."; amount: card.shown ? card.shown.tool_calls : 0 }
                Stat {
                    caption: "Archivos"
                    shortCaption: "arch."
                    amount: card.shown ? card.shown.files_changed.length : 0
                    tip: card.shown ? card.shown.files_changed.slice(0, 12).join("\n") : ""
                }
                Stat {
                    caption: "Tokens"
                    shortCaption: card.working ? "" : "tok"
                    amount: card.shown ? card.shown.tokens_used / 1000 : 0
                    suffix: " k"
                    literal: card.working ? "—" : ""
                }
            }
        }

        MouseArea {
            visible: !card.compact
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 18
            height: 18
            cursorShape: Qt.SizeFDiagCursor
            onPressed: card.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }
}
