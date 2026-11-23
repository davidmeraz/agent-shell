import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AgentShell.Native
import "../shared"

// Ventana flotante de un subagente: tarea, actividad en vivo, informe y totales.
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
    // Al cerrarse conserva lo último que mostró mientras termina la animación.
    property var shown: null
    property bool placed: false
    property real presence: wanted && placed ? 1 : 0
    property bool showReport: false
    readonly property bool hovered: hover.hovered
    readonly property bool working: !!shown && shown.status === "running"
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
    signal dismissed()

    objectName: "agentWindow_" + role
    title: "Agent Shell · Agente · " + label
    implicitWidth: 540
    implicitHeight: 328
    minimumSize: Qt.size(400, 240)
    color: "transparent"
    visible: wanted || presence > 0.01
    onClosed: dismissed()
    onAgentChanged: if (agent) shown = agent
    onVisibleChanged: {
        if (!visible) { placed = false; return; }
        if (!compositor) { placed = true; return; }
        placement.running = false;
        placement.command = [NativeApp.pythonExecutable, NativeApp.placementScript, String(NativeApp.processId),
            title, String(22 + slot), mainWindow.title];
        placement.running = true;
        placementLimit.restart();
    }
    // Aparecer mientras se escribe en el chat no debe sacarlo del editor.
    onWantedChanged: if (wanted && mainWindow.active) Qt.callLater(() => mainWindow.requestActivate())
    onWorkingChanged: showReport = !working
    onOutcomeChanged: if (outcome && visible && GemaTheme.animations) finishGlow.restart()
    Behavior on presence {
        NumberAnimation {
            duration: !GemaTheme.animations ? 0 : card.wanted ? 460 : 240
            easing.type: card.wanted ? Easing.OutCubic : Easing.InCubic
        }
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

    NativeProcess {
        id: placement
        errorOutput: LineParser { onRead: data => console.warn("Posición del subagente: " + data) }
        onExited: card.placed = card.visible
    }
    Timer { id: placementLimit; interval: 700; onTriggered: card.placed = card.visible }

    component IconButton: Button {
        id: iconButton
        property bool accented: false
        implicitWidth: 28
        implicitHeight: 28
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
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
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
        property real amount: 0
        property string suffix: ""
        property string literal: ""
        property string tip: ""
        property real displayed: amount
        Behavior on displayed { NumberAnimation { duration: GemaTheme.animations ? 420 : 0; easing.type: Easing.OutCubic } }
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 44
        radius: 11
        color: "#0effffff"
        border.width: 1
        border.color: "#18ffffff"
        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 6
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            spacing: 0
            Text {
                text: stat.literal || (stat.suffix ? stat.displayed.toFixed(1) + stat.suffix : String(Math.round(stat.displayed)))
                color: "#f2f6fb"
                font.pixelSize: 14
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
            Text {
                text: stat.caption
                color: "#8d9cad"
                font.pixelSize: 10
            }
        }
        HoverHandler { id: statHover }
        ToolTip.visible: statHover.hovered && stat.tip !== ""
        ToolTip.delay: 250
        ToolTip.text: stat.tip
    }

    Item {
        id: surface
        anchors.fill: parent
        opacity: card.presence
        scale: 0.94 + 0.06 * card.presence
        transformOrigin: Item.Right
        transform: Translate { x: 40 * (1 - card.presence) }

        MattePanel {
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#7a141c26"
            bottomColor: "#8c0c121a"
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
            anchors.margins: 18
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 13
                opacity: card.stage(1)
                AgentMedallion {
                    objectName: "agentMedallion_" + card.role
                    glyph: card.glyph
                    working: card.working && card.visible
                    outcome: card.outcome
                    tint: card.stateColor
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    Text {
                        objectName: "agentTitle_" + card.role
                        Layout.fillWidth: true
                        text: card.label + (card.count > 1 ? " ×" + card.count : "")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: "#f5f8fc"
                        font.pixelSize: 17
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
                        font.pixelSize: 12
                    }
                }
                Rectangle {
                    implicitWidth: chip.implicitWidth + 22
                    implicitHeight: 26
                    radius: 13
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
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
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

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 10
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
                    maximumLineCount: card.height > 420 ? 5 : 2
                    elide: Text.ElideRight
                    color: "#dbe4ee"
                    font.pixelSize: 13
                    lineHeight: 1.15
                    HoverHandler { id: taskHover }
                    ToolTip.visible: taskHover.hovered && truncated
                    ToolTip.delay: 500
                    ToolTip.text: text
                }
            }

            RowLayout {
                spacing: 18
                opacity: card.stage(3)
                Tab { report: false; text: "Actividad" }
                Tab { report: true; text: "Informe" }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 3
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
                spacing: 8
                opacity: card.stage(4)
                Stat { caption: "Tiempo"; literal: card.elapsedText }
                Stat { caption: "Acciones"; amount: card.shown ? card.shown.tool_calls : 0 }
                Stat {
                    caption: "Archivos"
                    amount: card.shown ? card.shown.files_changed.length : 0
                    tip: card.shown ? card.shown.files_changed.slice(0, 12).join("\n") : ""
                }
                Stat {
                    caption: "Tokens"
                    amount: card.shown ? card.shown.tokens_used / 1000 : 0
                    suffix: " k"
                    literal: card.working ? "—" : ""
                }
            }
        }

        MouseArea {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 18
            height: 18
            cursorShape: Qt.SizeFDiagCursor
            onPressed: card.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }
}
