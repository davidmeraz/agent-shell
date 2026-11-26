import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import AgentShell.Native
import "../.."
import "../shared"

// Terminal rápida flotante Gema Glassmorphism para navegar directorios e inicializar Work/App al instante.
NativeWindow {
    id: termWin
    objectName: "quickTerminalWindow"
    required property AgentBridge bridge
    property string mainWindowTitle: ""
    property string cwd: ""
    property bool runningCommand: false
    property string pendingRequestId: ""
    property var commandHistory: []
    property int historyCursor: -1

    title: "Agent Shell · Terminal"
    implicitWidth: 680
    implicitHeight: 440
    minimumSize: Qt.size(460, 300)
    color: "transparent"
    visible: false
    onClosed: termWin.visible = false

    ListModel { id: terminalLog }

    function openTerminal() {
        if (!cwd) cwd = bridge.workspace || "";
        if (terminalLog.count === 0) {
            terminalLog.append({
                cwd: cwd,
                command: "",
                output: "Terminal rápida de Agent Shell · Escribe `cd <ruta>`, `init work [nombre]`, `init app [nombre] [rust]`, `ls` o `help`.",
                ok: true
            });
        }
        visible = true;
        scheduleCenter();
        Qt.callLater(function() {
            if (!termWin.visible) return;
            cmdInput.forceActiveFocus();
            if (termWin.contentItem && termWin.contentItem.Window.window)
                termWin.contentItem.Window.window.requestActivate();
        });
    }

    function toggleTerminal() {
        if (visible) visible = false;
        else openTerminal();
    }

    function scheduleCenter() {
        if (visible && NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE") && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen")
            centerDelay.restart();
    }

    function shortCwd(raw) {
        const home = NativeApp.env("HOME") || "";
        if (home && raw && raw.startsWith(home))
            return "~" + raw.slice(home.length);
        return raw || "~";
    }

    function runCommand(rawText) {
        const cmd = (rawText || "").trim();
        if (!cmd || runningCommand) return;
        cmdInput.text = "";
        historyCursor = -1;
        if (!commandHistory.length || commandHistory[commandHistory.length - 1] !== cmd)
            commandHistory = commandHistory.concat([cmd]).slice(-80);
        if (cmd === "clear" || cmd === "cls") {
            terminalLog.clear();
            return;
        }
        runningCommand = true;
        pendingRequestId = bridge.execTerminal(cmd, cwd || bridge.workspace);
    }

    Connections {
        target: termWin.bridge
        function onTerminalResult(data) {
            if (termWin.pendingRequestId && data.request_id && data.request_id !== termWin.pendingRequestId)
                return;
            termWin.runningCommand = false;
            termWin.pendingRequestId = "";
            if (data.cwd) termWin.cwd = data.cwd;
            terminalLog.append({
                cwd: data.cwd || termWin.cwd,
                command: data.command || "",
                output: (data.output || "").replace(/\s+$/, ""),
                ok: data.status === "completed" && (data.exit_code === 0 || data.exit_code === null || data.exit_code === undefined)
            });
            Qt.callLater(() => logList.positionViewAtEnd());
            if (termWin.visible) cmdInput.forceActiveFocus();
        }
    }

    Timer {
        id: centerDelay
        interval: 60
        onTriggered: {
            if (!termWin.visible) return;
            centerProcess.running = false;
            centerProcess.command = [
                NativeApp.pythonExecutable,
                NativeApp.placementScript,
                "--center-window",
                String(NativeApp.processId),
                termWin.title,
                String(termWin.width || termWin.implicitWidth),
                String(termWin.height || termWin.implicitHeight),
                termWin.mainWindowTitle
            ];
            centerProcess.running = true;
        }
    }

    NativeProcess {
        id: centerProcess
        errorOutput: LineParser { onRead: data => console.warn("Terminal rápida: " + data) }
    }

    MattePanel {
        anchors.fill: parent
        anchors.margins: 1
        radius: 18
        topColor: "#58141c26"
        bottomColor: "#6e0c121a"
        edgeColor: "#4cffffff"
    }

    GlassToolTipTheme {}

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Cabecera: icono, ruta actual y botones rápidos para inicializar Work / App aquí
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            GlassPanel {
                implicitWidth: 28
                implicitHeight: 28
                radius: 8
                reflective: false
                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#22ffffff"
                bottomColor: "#0cffffff"
                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.55) : "#44ffffff"
                GemaIcon {
                    anchors.centerIn: parent
                    name: "terminal"
                    size: 14
                    color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                }
            }

            Text {
                Layout.fillWidth: true
                text: termWin.shortCwd(termWin.cwd || termWin.bridge.workspace)
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: GemaTheme.textColor
                font.family: "monospace"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: GemaTheme.textShadow
            }

            ActionButton {
                objectName: "terminalInitWorkBtn"
                text: "+ Work aquí"
                font.pixelSize: 11
                implicitHeight: 28
                horizontalPadding: 10
                verticalPadding: 0
                enabled: !termWin.runningCommand && termWin.bridge.canSelectArea
                ToolTip.visible: hovered
                ToolTip.delay: 350
                ToolTip.text: "Inicializar o abrir la carpeta actual como proyecto en Work"
                onClicked: termWin.runCommand("init work")
            }

            ActionButton {
                objectName: "terminalInitAppBtn"
                text: "+ App aquí"
                accent: true
                font.pixelSize: 11
                implicitHeight: 28
                horizontalPadding: 10
                verticalPadding: 0
                enabled: !termWin.runningCommand && termWin.bridge.canSelectArea
                ToolTip.visible: hovered
                ToolTip.delay: 350
                ToolTip.text: "Inicializar o abrir la carpeta actual como aplicación Gema UI Kit"
                onClicked: termWin.runCommand("init app")
            }

            ActionButton {
                implicitWidth: 28
                implicitHeight: 28
                horizontalPadding: 0
                verticalPadding: 0
                text: "×"
                font.pixelSize: 15
                ToolTip.visible: hovered
                ToolTip.delay: 350
                ToolTip.text: "Cerrar terminal (Esc)"
                onClicked: termWin.visible = false
            }
        }

        // Salida de comandos
        GlassPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            reflective: false
            topColor: "#12080d14"
            bottomColor: "#18060a10"
            edgeColor: "#28ffffff"

            ListView {
                id: logList
                objectName: "quickTerminalLog"
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                spacing: 8
                model: terminalLog
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: ColumnLayout {
                    required property string cwd
                    required property string command
                    required property string output
                    required property bool ok
                    width: logList.width
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        visible: command.length > 0
                        spacing: 6
                        Text {
                            text: "❯"
                            color: ok ? (GemaTheme.synced ? GemaTheme.accent : "#7ef5a8") : "#ff8a80"
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: command
                            textFormat: Text.PlainText
                            color: "#ffffff"
                            font.family: "monospace"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            wrapMode: Text.WrapAnywhere
                        }
                    }

                    TextEdit {
                        Layout.fillWidth: true
                        visible: output.length > 0
                        text: output
                        textFormat: TextEdit.PlainText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        color: ok ? "#cfd8e6" : "#ffb4ab"
                        font.family: "monospace"
                        font.pixelSize: 11
                        selectionColor: "#ffffff"
                        selectedTextColor: "#000000"
                    }
                }
            }
        }

        // Línea de entrada de comandos con historial ↑/↓
        GlassPanel {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 11
            reflective: false
            highlighted: cmdInput.activeFocus
            topColor: cmdInput.activeFocus ? "#22ffffff" : "#14ffffff"
            bottomColor: "#0a060a10"
            edgeColor: cmdInput.activeFocus
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.70) : "#64ffffff")
                : "#2cffffff"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 8

                Text {
                    text: termWin.runningCommand ? "…" : "❯"
                    color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                }

                TextInput {
                    id: cmdInput
                    objectName: "quickTerminalInput"
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: !termWin.runningCommand
                    color: "#f5f5f5"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    font.family: "monospace"
                    font.pixelSize: 12
                    selectByMouse: true
                    clip: true
                    onAccepted: termWin.runCommand(text)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            termWin.visible = false;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            if (termWin.commandHistory.length) {
                                if (termWin.historyCursor < 0) termWin.historyCursor = termWin.commandHistory.length - 1;
                                else if (termWin.historyCursor > 0) termWin.historyCursor--;
                                cmdInput.text = termWin.commandHistory[termWin.historyCursor];
                                cmdInput.cursorPosition = cmdInput.length;
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            if (termWin.historyCursor >= 0) {
                                if (termWin.historyCursor < termWin.commandHistory.length - 1) {
                                    termWin.historyCursor++;
                                    cmdInput.text = termWin.commandHistory[termWin.historyCursor];
                                } else {
                                    termWin.historyCursor = -1;
                                    cmdInput.text = "";
                                }
                                cmdInput.cursorPosition = cmdInput.length;
                            }
                            event.accepted = true;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !cmdInput.text
                        text: "cd ~/Dev/mi-app · init app · init work · ls · help"
                        color: "#768292"
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
