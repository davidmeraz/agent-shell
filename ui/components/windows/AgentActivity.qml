import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../shared"

// Línea de tiempo en vivo de las acciones de un subagente.
ListView {
    id: timeline
    property var agent: null
    property color tint: "#ffffff"
    property string agentId: ""
    property string lastLines: ""
    readonly property bool working: !!agent && agent.status === "running"
    clip: true
    spacing: 4
    boundsBehavior: Flickable.StopAtBounds
    model: ListModel { id: entries }
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }

    function describe(line) {
        const kinds = [["read_file", "≡", "Leyó"], ["grep_files", "⌕", "Buscó"], ["apply_patch", "±", "Editó"]];
        for (const [prefix, icon, verb] of kinds)
            if (line.startsWith(prefix)) return { icon: icon, verb: verb, target: line.slice(prefix.length).trim() };
        return { icon: "$", verb: "Ejecutó", target: line };
    }
    // Los eventos traen las últimas 40 líneas: se agregan sólo las nuevas para poder animarlas.
    function sync() {
        if (!agent) return;
        const lines = agent.lines;
        const signature = JSON.stringify(lines);
        if (agent.id !== agentId) { entries.clear(); agentId = agent.id; lastLines = ""; }
        if (signature === lastLines) return;
        if (lines.length > entries.count) {
            for (const line of lines.slice(entries.count)) entries.append(describe(line));
        } else {
            entries.remove(0);
            entries.append(describe(lines[lines.length - 1]));
        }
        lastLines = signature;
        Qt.callLater(follow);
    }
    function follow() {
        const end = Math.max(originY, originY + contentHeight - height);
        if (!GemaTheme.animations || moving) { if (!moving) contentY = end; return; }
        scroll.to = end;
        scroll.restart();
    }
    onAgentChanged: sync()
    onHeightChanged: Qt.callLater(follow)
    NumberAnimation { id: scroll; target: timeline; property: "contentY"; duration: 260; easing.type: Easing.OutCubic }

    add: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: GemaTheme.animations ? 300 : 0; easing.type: Easing.OutCubic }
        NumberAnimation { property: "x"; from: -18; to: 0; duration: GemaTheme.animations ? 340 : 0; easing.type: Easing.OutCubic }
    }
    displaced: Transition {
        NumberAnimation { properties: "x,y"; duration: GemaTheme.animations ? 220 : 0; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; to: 1; duration: 0 }
    }

    delegate: RowLayout {
        id: entry
        required property int index
        required property string icon
        required property string verb
        required property string target
        readonly property bool current: timeline.working && index === timeline.count - 1
        width: timeline.width - 8
        height: 24
        spacing: 9
        Rectangle {
            implicitWidth: 22
            implicitHeight: 22
            radius: 7
            color: entry.current ? Qt.alpha(timeline.tint, 0.24) : "#12ffffff"
            border.width: 1
            border.color: entry.current ? Qt.alpha(timeline.tint, 0.6) : "#1affffff"
            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            Text {
                anchors.centerIn: parent
                text: entry.icon
                color: entry.current ? timeline.tint : "#9fb0c2"
                font.pixelSize: 11
                font.weight: Font.Bold
            }
        }
        Text {
            text: entry.verb
            color: entry.current ? "#f2f6fb" : "#b9c6d4"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.preferredWidth: 54
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: entry.target
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            maximumLineCount: 1
            color: entry.current ? "#dbe6f2" : "#8d9cad"
            font.pixelSize: 12
            font.family: "monospace"
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !timeline.count
        text: timeline.working ? "Analizando la tarea…" : "Sin acciones registradas"
        color: "#9fb0c2"
        font.pixelSize: 12
    }
}
