import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import "../shared"

// Tarjeta minimalista de comando/herramienta: vidrio neutro puro, pulso radiactivo del tema y diseño espaciado.
GlassPanel {
    id: card
    objectName: "chatToolCall"
    required property var call
    property bool expanded: false
    property bool minimized: true
    property int entranceDelay: 0
    property double startedAtMs: Date.now()
    property double runningElapsedMs: 0
    readonly property string rawOutput: call.output || ""
    readonly property string displayOutput: rawOutput.replace(/\n$/, "")
    readonly property var outputLines: displayOutput ? displayOutput.split("\n") : []
    readonly property bool running: call.status === "running" || call.status === "pending"
    readonly property string previewOutput: {
        const slice = running && outputLines.length > 8 ? outputLines.slice(-8) : outputLines.slice(0, 8);
        return slice.join("\n").slice(0, 1600);
    }
    readonly property bool hasMoreOutput: previewOutput.length < displayOutput.length
    readonly property bool showOutputArea: !minimized && (!!rawOutput || running || needsInteractiveTerminal)
    readonly property string stateLabel: ({ pending: "Preparando", running: "Ejecutando", completed: "Completado",
        error: "Error", timeout: "Tiempo agotado", denied: "Rechazado", interrupted: "Detenido" })[call.status] || "Terminal"

    // Color radiactivo derivado dinámicamente del color de acento del tema Gema activo.
    readonly property color themeRadioactiveColor: {
        const base = Qt.color(GemaTheme.accent);
        if (base.hslHue >= 0 && base.hslSaturation > 0.05)
            return Qt.hsla(base.hslHue, 1.0, 0.58, 1.0);
        return "#38f2ff";
    }
    readonly property color statusColor: {
        if (call.status === "error" || call.status === "timeout" || call.status === "denied") return "#ff4d6a";
        if (call.status === "interrupted") return "#ffc44d";
        return themeRadioactiveColor;
    }
    readonly property string toolSymbol: {
        const cmd = (call.command || "").trim();
        if (cmd.startsWith("apply_patch")) return "±";
        if (cmd.startsWith("read_file")) return "≡";
        if (cmd.startsWith("grep_files")) return "⌕";
        if (cmd.startsWith("delegate")) return "⬡";
        return "$";
    }
    readonly property string durationLabel: {
        const ms = call.duration_ms;
        if (typeof ms !== "number" || !isFinite(ms) || ms < 0) return "";
        return ms < 1000 ? Math.round(ms) + " ms" : (ms / 1000).toFixed(2) + " s";
    }
    readonly property string liveDurationLabel: {
        if (durationLabel) return durationLabel;
        if (!running || runningElapsedMs < 100) return "";
        return (runningElapsedMs / 1000).toFixed(1) + " s";
    }
    readonly property string directoryLabel: {
        const path = call.workdir || "";
        const parts = path.split("/").filter(part => part.length > 0);
        return parts.length > 2 ? "…/" + parts.slice(-2).join("/") : path;
    }
    readonly property bool needsInteractiveTerminal: call.status === "error"
        && /sudo:.*(?:terminal is required|password is required)/i.test(rawOutput)

    implicitHeight: content.implicitHeight + 20
    radius: 12
    // Vidrio neutro y limpio (sin teñir de colores toda la tarjeta).
    topColor: running ? "#1cffffff" : "#13ffffff"
    bottomColor: running ? "#0effffff" : "#07ffffff"
    edgeColor: running
               ? Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.52)
               : "#2cffffff"
    highlighted: running
    reflective: true

    // Aparición progresiva con cascada, deslizamiento vertical y despliegue suave de escala.
    opacity: 0.0
    transform: [
        Scale {
            id: entranceScale
            origin.x: card.width / 2
            origin.y: card.height / 2
            xScale: 0.94
            yScale: 0.86
        },
        Translate {
            id: entranceShift
            y: 14
        }
    ]
    Component.onCompleted: {
        if (!GemaTheme.animations) {
            card.opacity = 1.0;
            entranceScale.xScale = 1.0;
            entranceScale.yScale = 1.0;
            entranceShift.y = 0;
        } else {
            entranceAnim.start();
        }
    }
    SequentialAnimation {
        id: entranceAnim
        PauseAnimation { duration: Math.max(0, card.entranceDelay) }
        ParallelAnimation {
            NumberAnimation {
                target: card
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: 320
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: entranceShift
                property: "y"
                from: 14
                to: 0
                duration: 360
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: entranceScale
                property: "xScale"
                from: 0.94
                to: 1.0
                duration: 360
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
            NumberAnimation {
                target: entranceScale
                property: "yScale"
                from: 0.86
                to: 1.0
                duration: 360
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }
    }

    Behavior on implicitHeight {
        NumberAnimation { duration: GemaTheme.animations ? 50 : 0; easing.type: Easing.OutQuad }
    }

    onRunningChanged: {
        if (running) {
            startedAtMs = Date.now();
            runningElapsedMs = 0;
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: card.running
        onTriggered: card.runningElapsedMs = Math.max(0, Date.now() - card.startedAtMs)
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 10

        // Barra superior con rejilla de 5 columnas fijas para alineación vertical exacta entre tarjetas.
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 22
            spacing: 10

            // Columna 1 (fija 22 px): botón plegar/desplegar.
            Button {
                id: minimizeButton
                objectName: "chatShellMinimize"
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22
                implicitHeight: 22
                padding: 0
                hoverEnabled: true
                Accessible.name: card.minimized ? "Mostrar salida del comando" : "Minimizar comando"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: card.minimized
                    ? "Mostrar salida" + (card.outputLines.length ? " (" + card.outputLines.length + " líneas)" : "")
                    : "Minimizar comando"
                onClicked: card.minimized = !card.minimized
                contentItem: Text {
                    text: card.minimized ? "▸" : "▾"
                    color: minimizeButton.hovered ? "#ffffff" : "#d0dae6"
                    font.pixelSize: 12
                    font.bold: true
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 6
                    color: minimizeButton.hovered ? "#22ffffff" : "transparent"
                    border.width: minimizeButton.hovered ? 1 : 0
                    border.color: "#44ffffff"
                }
            }

            // Columna 2 (fija 18 px): símbolo de herramienta centrado para que todos los comandos empiecen en el mismo X.
            Text {
                objectName: "chatShellToolSymbol"
                Layout.preferredWidth: 18
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: card.toolSymbol
                color: card.statusColor
                font.family: "monospace"
                font.pixelSize: 13
                font.bold: true
                style: Text.Raised
                styleColor: GemaTheme.textShadow
            }

            // Columna 3 (elástica): comando alineado al mismo margen izquierdo con separación limpia a la derecha.
            ScrollView {
                ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Layout.fillWidth: true
                Layout.minimumWidth: 60
                Layout.preferredHeight: card.minimized ? 18 : Math.min(command.implicitHeight, 44)
                Layout.alignment: Qt.AlignVCenter
                clip: true
                TextArea {
                    id: command
                    objectName: "chatShellCommand"
                    text: card.call.command || "Comando no ejecutado"
                    readOnly: true
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: card.minimized ? TextEdit.NoWrap : TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: "#f4f7fb"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    padding: 0
                    leftPadding: 0; rightPadding: 8; topPadding: 0; bottomPadding: 0
                    background: null
                }
            }

            Text {
                objectName: "chatShellDirectory"
                visible: !card.minimized
                Layout.alignment: Qt.AlignVCenter
                text: (card.call.source === "local" ? "Local" : "IA") + (card.directoryLabel ? " · " + card.directoryLabel : "")
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                Layout.maximumWidth: 140
                color: "#c2cedb"
                font.pixelSize: 10
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                HoverHandler { id: directoryHover }
                ToolTip.visible: directoryHover.hovered
                ToolTip.delay: 400
                ToolTip.text: card.call.workdir || ""
                Accessible.name: (card.call.source === "local" ? "Terminal local" : "Terminal usada por la IA") + ": " + (card.call.workdir || "")
            }

            // Columna 4: tiempo/estado alineado a la derecha, justo antes del punto fijo.
            Text {
                objectName: "chatShellStatus"
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignRight
                visible: text !== ""
                text: {
                    const parts = [];
                    if (card.call.status !== "completed")
                        parts.push(card.stateLabel);
                    if (typeof card.call.exit_code === "number" && card.call.exit_code !== 0)
                        parts.push("código " + card.call.exit_code);
                    if (card.liveDurationLabel)
                        parts.push(card.liveDurationLabel);
                    return parts.join(" · ");
                }
                color: card.running ? (GemaTheme.synced ? GemaTheme.accent : "#eef4fa")
                     : (card.call.status === "error" || card.call.status === "timeout" ? "#ffd0d6" : "#b8c4d2")
                font.pixelSize: 11
                font.weight: card.running ? Font.DemiBold : Font.Normal
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                textFormat: Text.PlainText
                Accessible.name: text || card.stateLabel
                HoverHandler { id: stateHover }
                ToolTip.visible: stateHover.hovered
                ToolTip.delay: 400
                ToolTip.text: card.stateLabel
                    + (typeof card.call.exit_code === "number" ? "\nCódigo de salida: " + card.call.exit_code : "")
                    + (card.liveDurationLabel ? "\nDuración: " + card.liveDurationLabel : "")
                    + (card.outputLines.length ? "\nLíneas de salida: " + card.outputLines.length : "")
            }

            // Columna 5 (fija 16x16 px al extremo derecho): todos los puntos quedan en la misma línea vertical exacta.
            Item {
                id: pulseIndicator
                objectName: "chatShellPulseIndicator"
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter
                readonly property bool pulsing: card.running

                // Halo suave sólo mientras el comando está en ejecución.
                Rectangle {
                    id: pulseHalo
                    anchors.centerIn: parent
                    width: 14
                    height: 14
                    radius: 7
                    visible: card.running
                    color: Qt.rgba(card.statusColor.r, card.statusColor.g, card.statusColor.b, 0.32)

                    SequentialAnimation on scale {
                        running: card.running && GemaTheme.animations
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.75; to: 1.35; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.35; to: 0.75; duration: 900; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on opacity {
                        running: card.running && GemaTheme.animations
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.85; to: 0.20; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.20; to: 0.85; duration: 900; easing.type: Easing.InOutSine }
                    }
                }

                // Punto normal fijo al terminar; respira suavemente sólo mientras corre.
                Rectangle {
                    id: pulseCore
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: card.running
                           ? (GemaTheme.synced ? GemaTheme.accent : "#f0f4f8")
                           : (card.call.status === "completed"
                              ? (GemaTheme.synced ? GemaTheme.accent : "#a8b8c8")
                              : card.statusColor)
                    opacity: card.running ? 1.0 : 0.85

                    SequentialAnimation on opacity {
                        running: card.running && GemaTheme.animations
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.35; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
            }
        }

        // Cuerpo colapsable con mayor respiro visual cuando el usuario lo despliega.
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.showOutputArea
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#20ffffff"
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
                font.pixelSize: 11
                color: "#eef3f8"
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                padding: 0
                leftPadding: 2; rightPadding: 2; topPadding: 4; bottomPadding: 4
                background: null
            }

            Text {
                Layout.fillWidth: true
                visible: !card.rawOutput && card.running
                text: "Esperando salida…"
                color: "#dce6f2"
                font.pixelSize: 11
                style: Text.Raised
                styleColor: GemaTheme.textShadow
            }

            Text {
                objectName: "chatShellInputHint"
                Layout.fillWidth: true
                visible: card.needsInteractiveTerminal
                text: "Este comando necesita una terminal interactiva para pedir la contraseña."
                color: "#eef4fa"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !!card.rawOutput || !!card.call.truncated
                spacing: 10
                Item { Layout.fillWidth: true }
                Text {
                    visible: !!card.call.truncated
                    text: "Salida recortada"
                    font.pixelSize: 10
                    color: "#d4e0ec"
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                    HoverHandler { id: limitHover }
                    ToolTip.visible: limitHover.hovered
                    ToolTip.text: "El proceso superó el límite de salida guardada."
                }
                Button {
                    id: expandButton
                    objectName: "chatShellExpand"
                    visible: card.hasMoreOutput
                    text: card.expanded ? "Ver menos" : "Ver salida completa (" + card.outputLines.length + ")"
                    hoverEnabled: true
                    padding: 4
                    Accessible.name: text
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    ToolTip.text: card.outputLines.length + " líneas guardadas"
                    onClicked: card.expanded = !card.expanded
                    contentItem: Text {
                        text: expandButton.text
                        color: expandButton.hovered ? "#ffffff" : "#e2ecf5"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    background: Rectangle {
                        radius: 6
                        color: expandButton.hovered ? "#22ffffff" : "#10ffffff"
                        border.width: 1
                        border.color: expandButton.hovered ? "#60ffffff" : "#28ffffff"
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
}
