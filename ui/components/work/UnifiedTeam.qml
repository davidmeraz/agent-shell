import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Equipo del modo unificado: el arquitecto activo y el obrero que se usaría en cada nivel.
GlassPanel {
    id: team
    objectName: "unifiedTeam"
    required property AgentBridge bridge
    property bool compact: false
    readonly property var activeWorker: bridge.activeWorker
    readonly property bool planning: bridge.busy && !activeWorker
    readonly property string architectName: {
        const resolved = bridge.resolvedModels[bridge.modelName];
        if (bridge.provider === "claude" && resolved) return resolved;
        for (let i = 0; i < bridge.availableModels.count; ++i) {
            const model = bridge.availableModels.get(i);
            if (model.slug === bridge.modelName) return model.displayName;
        }
        return bridge.modelName || "Sin modelo";
    }
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
        required property string level
        readonly property var options: {
            const row = team.bridge.unifiedTeam.find(entry => entry.level === level);
            return row ? row.workers : [];
        }
        readonly property bool working: !!team.activeWorker && team.activeWorker.level === level
        readonly property var worker: working ? team.activeWorker.worker : (options.length ? options[0] : null)
        objectName: "unifiedWorker_" + level
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
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
                text: !cell.working ? cell.title : cell.width < 180 ? "● " + cell.title : cell.title + " · TRABAJANDO"
                color: cell.working ? team.accentColor : GemaTheme.subtleColor
                Pulse { subject: cellCaption; running: cell.working && GemaTheme.animations }
            }
            Label {
                objectName: "unifiedWorkerName_" + cell.level
                Layout.fillWidth: true
                text: cell.worker ? team.symbol(cell.worker.provider) + " " + cell.worker.name : "Sin obrero disponible"
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
        Accessible.name: "Obrero " + cell.title.toLowerCase() + ": " + (cell.worker ? cell.worker.name : "no disponible")
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
                text: team.planning ? "ARQUITECTO · PENSANDO" : "ARQUITECTO"
                color: team.planning ? team.accentColor : GemaTheme.subtleColor
                Pulse { subject: architectCaption; running: team.planning && GemaTheme.animations }
            }
            Label {
                objectName: "unifiedArchitect"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                horizontalAlignment: Text.AlignRight
                text: team.symbol(team.bridge.provider) + " " + team.architectName
                font.pixelSize: 13
                font.weight: Font.Bold
                color: team.accentColor
            }
            Label {
                text: team.engine(team.bridge.provider)
                      + (team.bridge.reasoningEffort ? " · " + team.bridge.reasoningEffort : "")
                color: GemaTheme.subtleColor
                font.pixelSize: 10
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            WorkerCell { title: "SIMPLE"; level: "simple" }
            WorkerCell { title: "NORMAL"; level: "standard" }
            WorkerCell { title: "DIFÍCIL"; level: "hard" }
        }
    }
}
