import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Equipo del modo unificado: el arquitecto activo y el subagente que se usaría en cada rol.
GlassPanel {
    id: team
    objectName: "unifiedTeam"
    required property AgentBridge bridge
    property bool compact: false
    readonly property var activeAgent: bridge.activeAgent
    readonly property bool planning: bridge.busy && !activeAgent
    readonly property string delegations: !bridge.agentTurn ? ""
        : bridge.agents.length ? " · " + bridge.agents.length + (bridge.agents.length === 1 ? " DELEGACIÓN" : " DELEGACIONES")
        : bridge.busy ? "" : " · SIN DELEGAR"
    readonly property var architect: bridge.unifiedArchitect
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
        readonly property int uses: team.bridge.agents.filter(agent => agent.role === role).length
        readonly property var options: {
            const row = team.bridge.unifiedTeam.find(entry => entry.role === role);
            return row ? row.workers : [];
        }
        readonly property bool working: !!team.activeAgent && team.activeAgent.role === role
        readonly property var worker: working && team.activeAgent.worker.name ? team.activeAgent.worker : (options.length ? options[0] : null)
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
                text: cell.worker ? team.symbol(cell.worker.provider) + " " + cell.worker.name : "No disponible"
                color: cell.worker ? GemaTheme.textColor : GemaTheme.subtleColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                visible: !team.compact
                text: cell.worker ? team.engine(cell.worker.provider) + " · " + team.quota(cell.worker) : ""
                color: GemaTheme.subtleColor
                font.pixelSize: 10
            }
        }

        HoverHandler { id: cellHover }
        ToolTip.visible: cellHover.hovered && cell.options.length > 0
        ToolTip.delay: 300
        ToolTip.text: "Orden de uso según la cuota\n" + cell.options.map((worker, index) =>
            (index + 1) + ". " + worker.name + (worker.effort ? " (" + worker.effort + ")" : "")
            + " · " + team.engine(worker.provider) + " · " + team.quota(worker)).slice(0, 7).join("\n")
        Accessible.role: Accessible.StaticText
        Accessible.name: "Subagente " + cell.title.toLowerCase() + ": " + (cell.worker ? cell.worker.name : "no disponible")
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 10
        spacing: 8

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
                color: GemaTheme.subtleColor
                font.pixelSize: 10
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: team.width < 600 ? 2 : 4
            columnSpacing: 6
            rowSpacing: 6
            WorkerCell { title: "EXPLORADOR"; role: "explorer" }
            WorkerCell { title: "CONSTRUCTOR"; role: "builder" }
            WorkerCell { title: "ESPECIALISTA"; role: "specialist" }
            WorkerCell { title: "REVISOR"; role: "reviewer" }
        }
    }
}
