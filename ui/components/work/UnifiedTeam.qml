import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Equipo del modo unificado: cascada de arquitectos con umbral de cuota y 2 obreros dedicados.
GlassPanel {
    id: team
    objectName: "unifiedTeam"
    required property AgentBridge bridge
    property bool compact: false
    signal configureRequested()
    readonly property var activeAgents: bridge.activeAgents
    readonly property bool planning: bridge.busy && activeAgents.length === 0
    readonly property string delegations: !bridge.agentTurn ? ""
        : bridge.agents.length ? " · " + bridge.agents.length + (bridge.agents.length === 1 ? " DELEGACIÓN" : " DELEGACIONES")
        : bridge.busy ? "" : " · SIN DELEGAR"
    readonly property var architect: bridge.unifiedArchitect
    readonly property var cascade: bridge.unifiedCascade || []
    readonly property int threshold: typeof bridge.unifiedConfig.quota_threshold === "number"
        ? bridge.unifiedConfig.quota_threshold : 35
    readonly property bool parallelWorkers: bridge.unifiedConfig.parallel_workers !== false
    readonly property var workerSlots: bridge.unifiedTeam.length
        ? bridge.unifiedTeam
        : [{ role: "chatgpt", provider: "chatgpt", workers: [] }, { role: "claude", provider: "claude", workers: [] }]
    readonly property color accentColor: GemaTheme.synced ? GemaTheme.accentInk : "#ffffff"
    implicitHeight: content.implicitHeight + 20
    radius: 14
    topColor: "#16ffffff"
    bottomColor: "#0affffff"
    edgeColor: "#32ffffff"

    function symbol(provider) {
        return provider === "agy" ? "✦" : provider === "claude" ? "◆" : "◎";
    }
    function engine(provider) {
        return provider === "agy" ? "Antigravity" : provider === "claude" ? "Claude Code" : "ChatGPT";
    }
    function slotTitle(slot) {
        return slot === "chatgpt" ? "OBRERO CHATGPT" : slot === "claude" ? "OBRERO CLAUDE" : "OBRERO GEMINI";
    }
    function quota(worker) {
        return typeof worker.remaining === "number" ? worker.remaining + "% restante" : "cuota sin medir";
    }

    component Label: Text {
        textFormat: Text.PlainText
        color: GemaTheme.textColor
        elide: Text.ElideRight
        style: Text.Raised
        styleColor: GemaTheme.textShadow
    }

    component Caption: Label {
        color: GemaTheme.subtleColor
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }

    component Pulse: SequentialAnimation {
        id: pulse
        required property Item subject
        loops: Animation.Infinite
        onRunningChanged: if (!running) subject.opacity = 1
        NumberAnimation { target: pulse.subject; property: "opacity"; to: 0.4; duration: 520; easing.type: Easing.InOutSine }
        NumberAnimation { target: pulse.subject; property: "opacity"; to: 1; duration: 520; easing.type: Easing.InOutSine }
    }

    component WorkerCell: Rectangle {
        id: cell
        required property string title
        required property string role
        required property var options
        readonly property int uses: team.bridge.agents.filter(agent => agent.role === role).length
        readonly property var runningAgent: team.activeAgents.find(agent => agent.role === role) || null
        readonly property bool working: !!runningAgent
        readonly property var worker: working && runningAgent.worker && runningAgent.worker.name
            ? runningAgent.worker : (options.length ? options[0] : null)
        objectName: "unifiedWorker_" + role
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        Layout.fillHeight: true
        implicitHeight: cellContent.implicitHeight + 14
        radius: 10
        color: working ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#24ffffff") : "#0cffffff"
        border.width: 1
        border.color: working ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.70) : "#70ffffff") : "#1cffffff"
        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
        Behavior on border.color { ColorAnimation { duration: GemaTheme.animDuration } }

        ColumnLayout {
            id: cellContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 9
            spacing: 2
            Caption {
                id: cellCaption
                Layout.fillWidth: true
                text: (cell.working ? "● " : "") + cell.title + (cell.uses ? " ×" + cell.uses : "")
                color: cell.working ? team.accentColor : GemaTheme.subtleColor
                Pulse { subject: cellCaption; running: cell.working && GemaTheme.animations }
            }
            Label {
                objectName: "unifiedWorkerName_" + cell.role
                Layout.fillWidth: true
                text: cell.worker
                    ? team.symbol(cell.worker.provider) + " " + cell.worker.name
                      + (cell.worker.effort ? " (" + cell.worker.effort + ")" : "")
                    : "No disponible"
                color: cell.worker ? GemaTheme.textColor : GemaTheme.subtleColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                visible: !team.compact
                text: cell.worker ? team.engine(cell.worker.provider) + " · " + team.quota(cell.worker) : "Conecta este proveedor"
                color: GemaTheme.subtleColor
                font.pixelSize: 10
            }
        }

        HoverHandler { id: cellHover }
        ToolTip.visible: cellHover.hovered
        ToolTip.delay: 300
        ToolTip.text: cell.worker
            ? cell.title + "\n" + cell.worker.name + (cell.worker.effort ? " (" + cell.worker.effort + ")" : "")
              + " · " + team.engine(cell.worker.provider) + " · " + team.quota(cell.worker)
              + (team.parallelWorkers ? "\nPuede trabajar en paralelo con el otro obrero en archivos distintos." : "")
            : cell.title + ": proveedor no conectado o sin cuota."
        Accessible.role: Accessible.StaticText
        Accessible.name: cell.title.toLowerCase() + ": " + (cell.worker ? cell.worker.name : "no disponible")
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 10
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            spacing: 8
            Caption {
                id: architectCaption
                objectName: "unifiedArchitectState"
                text: "ARQUITECTO" + (team.planning ? " · PENSANDO" : "") + team.delegations
                color: team.planning ? team.accentColor : GemaTheme.subtleColor
                Pulse { subject: architectCaption; running: team.planning && GemaTheme.animations }
            }
            Label {
                objectName: "unifiedArchitect"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                text: team.architect.name ? team.symbol(team.architect.provider) + " " + team.architect.name : "Sin modelo"
                font.pixelSize: 13
                font.weight: Font.Bold
                color: team.accentColor
            }
            Label {
                visible: !!team.architect.model
                text: team.engine(team.architect.provider)
                      + (team.architect.effort ? " · " + team.architect.effort : "")
                      + (typeof team.architect.remaining === "number" ? " · " + team.architect.remaining + "%" : "")
                color: GemaTheme.subtleColor
                font.pixelSize: 10
            }
            Button {
                id: configButton
                objectName: "unifiedConfigButton"
                implicitWidth: 24
                implicitHeight: 24
                padding: 0
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                enabled: team.bridge.ready && !team.bridge.busy
                onClicked: team.configureRequested()
                Accessible.name: "Configurar cascada y obreros del modo unificado"
                ToolTip.visible: hovered
                ToolTip.delay: 300
                ToolTip.text: "Configurar cascada de arquitectos, umbral (≤ " + team.threshold + "%) y obreros"
                contentItem: Text {
                    text: "⚙"
                    color: configButton.hovered ? team.accentColor : GemaTheme.subtleColor
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 7
                    color: configButton.hovered ? "#24ffffff" : "#10ffffff"
                    border.width: 1
                    border.color: configButton.hovered ? "#48ffffff" : "#1effffff"
                }
            }
        }

        // Vista compacta de la cascada de relevos por cuota (ej. Neon -> Opus -> Astra · <=35%).
        RowLayout {
            objectName: "unifiedCascadeRow"
            Layout.fillWidth: true
            Layout.leftMargin: 2
            visible: !team.compact && team.cascade.length > 0
            spacing: 4
            Repeater {
                model: team.cascade
                delegate: RowLayout {
                    id: stepItem
                    required property var modelData
                    required property int index
                    spacing: 4
                    Text {
                        visible: stepItem.index > 0
                        text: "›"
                        color: "#667788"
                        font.pixelSize: 11
                    }
                    Rectangle {
                        implicitWidth: stepLabel.implicitWidth + 10
                        implicitHeight: 19
                        radius: 6
                        color: stepItem.modelData.active
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#22ffffff")
                            : "#0cffffff"
                        border.width: 1
                        border.color: stepItem.modelData.active
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#58ffffff")
                            : "#1cffffff"
                        opacity: !stepItem.modelData.available ? 0.45
                            : stepItem.modelData.below_threshold && !stepItem.modelData.active ? 0.55 : 1.0
                        Text {
                            id: stepLabel
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: (stepItem.index + 1) + ". " + team.symbol(stepItem.modelData.provider) + " "
                                + stepItem.modelData.name
                                + (stepItem.modelData.effort ? " " + stepItem.modelData.effort : "")
                                + (typeof stepItem.modelData.remaining === "number" ? " · " + stepItem.modelData.remaining + "%" : "")
                            color: stepItem.modelData.active ? team.accentColor : GemaTheme.subtleColor
                            font.pixelSize: 10
                            font.weight: stepItem.modelData.active ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Label {
                objectName: "unifiedThresholdBadge"
                text: "≤" + team.threshold + "%" + (team.parallelWorkers ? " · ∥" : "")
                color: GemaTheme.subtleColor
                font.pixelSize: 10
                HoverHandler { id: badgeHover }
                ToolTip.visible: badgeHover.hovered
                ToolTip.delay: 250
                ToolTip.text: "Cambia al siguiente arquitecto al llegar a ≤ " + team.threshold + "% restante"
                    + (team.parallelWorkers ? "\nObreros en paralelo habilitados en archivos distintos" : "\nObreros en secuencia")
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1, Math.min(team.workerSlots.length, team.width < 460 ? 1 : 2))
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: team.workerSlots
                delegate: WorkerCell {
                    required property var modelData
                    title: team.slotTitle(modelData.role)
                    role: modelData.role
                    options: modelData.workers || []
                }
            }
        }
    }
}
