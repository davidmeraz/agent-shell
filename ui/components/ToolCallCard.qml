import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// El resultado original permanece intacto; sólo se acorta su vista en el chat.
GlassPanel {
    id: card
    objectName: "chatToolCall"
    required property var call
    property bool expanded: false
    readonly property string rawOutput: call.output || ""
    readonly property string displayOutput: rawOutput.replace(/\n$/, "")
    readonly property var outputLines: displayOutput ? displayOutput.split("\n") : []
    readonly property string previewOutput: outputLines.slice(0, 8).join("\n").slice(0, 1600)
    readonly property bool hasMoreOutput: previewOutput.length < displayOutput.length
    readonly property bool running: call.status === "running" || call.status === "pending"
    readonly property string stateLabel: ({ pending: "Preparando", running: "Ejecutando", completed: "Completado",
        error: "Error", timeout: "Tiempo agotado", denied: "Rechazado", interrupted: "Detenido" })[call.status] || "Terminal"
    readonly property string durationLabel: {
        const ms = call.duration_ms;
        if (typeof ms !== "number" || !isFinite(ms) || ms < 0) return "";
        return ms < 1000 ? Math.round(ms) + " ms" : (ms / 1000).toFixed(2) + " s";
    }
    readonly property string directoryLabel: {
        const path = call.workdir || "";
        const parts = path.split("/").filter(part => part.length > 0);
        return parts.length > 2 ? "…/" + parts.slice(-2).join("/") : path;
    }
    readonly property bool needsInteractiveTerminal: call.status === "error"
        && /sudo:.*(?:terminal is required|password is required)/i.test(rawOutput)
    implicitHeight: content.implicitHeight + 24
    radius: 12
    topColor: "#1c3b3b3b"
    bottomColor: "#101b1b1b"
    edgeColor: "#20ffffff"
    reflective: false

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "$"
                color: "#888888"
                font.family: "monospace"
                font.pixelSize: 13
                Layout.alignment: Qt.AlignTop
                topPadding: 2
            }
            ScrollView {
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(command.implicitHeight, 72)
                clip: true
                TextArea {
                    id: command
                    objectName: "chatShellCommand"
                    text: card.call.command || "Comando no ejecutado"
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: "#eeeeee"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    padding: 0
                    leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                    background: null
                }
            }
            BusyIndicator {
                visible: card.running
                running: visible
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignTop
            }
            Text {
                objectName: "chatShellStatus"
                Layout.alignment: Qt.AlignTop
                topPadding: 2
                text: (card.call.status === "completed" ? "✓ " : "") + card.stateLabel
                    + (typeof card.call.exit_code === "number" && card.call.exit_code !== 0 ? " · código " + card.call.exit_code : "")
                    + (card.durationLabel ? " · " + card.durationLabel : "")
                color: card.call.status === "error" || card.call.status === "timeout" ? "#dddddd" : "#999999"
                font.pixelSize: 10
                textFormat: Text.PlainText
                Accessible.name: text
                HoverHandler { id: stateHover }
                ToolTip.visible: stateHover.hovered
                ToolTip.delay: 400
                ToolTip.text: card.stateLabel + (typeof card.call.exit_code === "number" ? "\nCódigo de salida: " + card.call.exit_code : "")
                    + (card.durationLabel ? "\nDuración: " + card.durationLabel : "")
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: "#10ffffff"
            visible: !!card.rawOutput
        }
        TextArea {
            id: output
            objectName: "chatShellOutput"
            Layout.fillWidth: true
            visible: !!card.rawOutput
            text: card.expanded ? card.displayOutput : card.previewOutput
            readOnly: true
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.WrapAnywhere
            font.family: "monospace"
            font.pixelSize: 12
            color: "#cccccc"
            selectionColor: "#ffffff"
            selectedTextColor: "#000000"
            padding: 0
            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
            background: null
        }
        Text {
            Layout.fillWidth: true
            visible: !card.rawOutput
            text: card.running ? "Esperando salida…" : "Sin salida"
            color: "#888888"
            font.pixelSize: 11
        }
        Text {
            objectName: "chatShellInputHint"
            Layout.fillWidth: true
            visible: card.needsInteractiveTerminal
            text: "Este comando necesita una terminal interactiva para pedir la contraseña."
            color: "#aaaaaa"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                objectName: "chatShellDirectory"
                Layout.fillWidth: true
                text: (card.call.source === "local" ? "Local" : "IA") + (card.directoryLabel ? " · " + card.directoryLabel : "")
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: "#888888"
                font.pixelSize: 10
                HoverHandler { id: directoryHover }
                ToolTip.visible: directoryHover.hovered
                ToolTip.delay: 400
                ToolTip.text: card.call.workdir || ""
                Accessible.name: (card.call.source === "local" ? "Terminal local" : "Terminal usada por la IA") + ": " + (card.call.workdir || "")
            }
            Text {
                visible: !!card.call.truncated
                text: "Salida recortada"
                font.pixelSize: 10
                color: "#aaaaaa"
                HoverHandler { id: limitHover }
                ToolTip.visible: limitHover.hovered
                ToolTip.text: "El proceso superó el límite de salida guardada."
            }
            Button {
                id: expandButton
                objectName: "chatShellExpand"
                visible: card.hasMoreOutput
                text: card.expanded ? "Ver menos" : "Ver salida completa"
                hoverEnabled: true
                padding: 4
                Accessible.name: text
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: card.outputLines.length + " líneas guardadas"
                onClicked: card.expanded = !card.expanded
                contentItem: Text {
                    text: expandButton.text
                    color: expandButton.hovered ? "#eeeeee" : "#aaaaaa"
                    font.pixelSize: 10
                }
                background: Rectangle {
                    radius: 6
                    color: expandButton.hovered ? "#12ffffff" : "transparent"
                    border.width: expandButton.visualFocus ? 1 : 0
                    border.color: "#60ffffff"
                }
            }
            MessageCopyButton {
                objectName: "chatCopyShellOutput"
                visible: !!card.rawOutput
                textToCopy: card.rawOutput
                copyLabel: "Copiar salida completa"
                copiedLabel: "Salida copiada"
            }
        }
    }
}
