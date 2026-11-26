import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import AgentShell.Native
import "../.."
import "../shared"

// Terminal estilo Linux integrada en Gema Glassmorphism: prompt en línea, foco automático y colocación simétrica inferior izquierda.
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
    readonly property string userName: NativeApp.env("USER") || "user"

    title: "Agent Shell · Terminal"
    implicitWidth: 640
    implicitHeight: 500
    minimumSize: Qt.size(440, 320)
    color: "transparent"
    visible: false
    onClosed: termWin.visible = false

    ListModel { id: terminalLog }

    function focusPrompt() {
        if (!termWin.visible) return;
        if (termWin.contentItem && termWin.contentItem.Window.window)
            termWin.contentItem.Window.window.requestActivate();
        if (logList.footerItem && logList.footerItem.focusInput)
            logList.footerItem.focusInput();
    }

    function openTerminal() {
        if (!cwd) cwd = bridge.workspace || "";
        visible = true;
        schedulePlacement();
        Qt.callLater(focusPrompt);
        focusRetry.restart();
    }

    function toggleTerminal() {
        if (visible) visible = false;
        else openTerminal();
    }

    function schedulePlacement() {
        if (visible && mainWindowTitle
            && NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE") && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen")
            placementDelay.restart();
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(focusPrompt);
            focusRetry.restart();
        } else {
            placementDelay.stop();
            focusRetry.stop();
            placementProcess.running = false;
        }
    }

    onActiveChanged: {
        if (active && visible) Qt.callLater(focusPrompt);
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
        historyCursor = -1;
        if (!commandHistory.length || commandHistory[commandHistory.length - 1] !== cmd)
            commandHistory = commandHistory.concat([cmd]).slice(-80);
        if (cmd === "clear" || cmd === "cls") {
            terminalLog.clear();
            Qt.callLater(focusPrompt);
            return;
        }
        if (cmd === "exit" || cmd === "quit") {
            termWin.visible = false;
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
            const prevCwd = termWin.cwd || termWin.bridge.workspace;
            termWin.runningCommand = false;
            termWin.pendingRequestId = "";
            if (data.cwd) termWin.cwd = data.cwd;
            terminalLog.append({
                promptCwd: prevCwd,
                command: data.command || "",
                output: (data.output || "").replace(/\s+$/, ""),
                ok: data.status === "completed" && (data.exit_code === 0 || data.exit_code === null || data.exit_code === undefined)
            });
            Qt.callLater(function() {
                logList.positionViewAtEnd();
                termWin.focusPrompt();
            });
        }
    }

    Timer {
        id: focusRetry
        interval: 160
        onTriggered: termWin.focusPrompt()
    }

    // Coloca la terminal en la columna inferior izquierda (rol 2), simétrica con el chat central.
    Timer {
        id: placementDelay
        interval: 70
        onTriggered: {
            if (!termWin.visible || !termWin.mainWindowTitle) return;
            placementProcess.running = false;
            placementProcess.command = [
                NativeApp.pythonExecutable,
                NativeApp.placementScript,
                String(NativeApp.processId),
                termWin.title,
                "2",
                termWin.mainWindowTitle
            ];
            placementProcess.running = true;
        }
    }

    NativeProcess {
        id: placementProcess
        errorOutput: LineParser { onRead: data => console.warn("Terminal rápida: " + data) }
        onExited: if (termWin.visible) focusRetry.restart()
    }

    MattePanel {
        anchors.fill: parent
        anchors.margins: 1
        radius: 18
        topColor: "#5c121922"
        bottomColor: "#740a1018"
        edgeColor: "#4cffffff"
    }

    GlassToolTipTheme {}

    // Clic en cualquier zona vacía enfoca inmediatamente el prompt de la terminal
    MouseArea {
        anchors.fill: parent
        onClicked: termWin.focusPrompt()
    }

    // Flujo continuo estilo terminal Linux real
    ListView {
        id: logList
        objectName: "quickTerminalLog"
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 16
        anchors.bottomMargin: 16
        clip: true
        spacing: 10
        model: terminalLog
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: ColumnLayout {
            required property string promptCwd
            required property string command
            required property string output
            required property bool ok
            width: logList.width
            spacing: 4

            // Prompt histórico estilo Starship
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "◆"
                    color: GemaTheme.synced ? GemaTheme.accent : "#a8d4ff"
                    font.family: "monospace"
                    font.pixelSize: 11
                }
                Text {
                    text: termWin.userName
                    color: GemaTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: termWin.shortCwd(promptCwd)
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: GemaTheme.synced ? GemaTheme.accentAlpha(0.85) : "#96c2f0"
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7
                Text {
                    text: "❯"
                    color: ok ? "#68f098" : "#ff8a80"
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: command
                    textFormat: Text.PlainText
                    color: "#f5f7fa"
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                }
            }

            TextEdit {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                visible: output.length > 0
                text: output
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: ok ? "#cfd8e6" : "#ffb4ab"
                font.family: "monospace"
                font.pixelSize: 12
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
            }
        }

        // Prompt activo en línea directamente en el flujo de la terminal
        footer: ColumnLayout {
            id: livePrompt
            width: logList.width
            spacing: 4

            function focusInput() {
                cmdInput.forceActiveFocus();
                cmdInput.cursorPosition = cmdInput.length;
            }

            Item { implicitHeight: logList.count > 0 ? 4 : 0 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "◆"
                    color: GemaTheme.synced ? GemaTheme.accent : "#a8d4ff"
                    font.family: "monospace"
                    font.pixelSize: 11
                }
                Text {
                    text: termWin.userName
                    color: GemaTheme.textColor
                    font.family: "monospace"
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: termWin.shortCwd(termWin.cwd || termWin.bridge.workspace)
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: GemaTheme.synced ? GemaTheme.accentAlpha(0.88) : "#96c2f0"
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                Text {
                    text: termWin.runningCommand ? "…" : "❯"
                    color: termWin.runningCommand
                           ? (GemaTheme.synced ? GemaTheme.accent : "#ffd080")
                           : "#68f098"
                    font.family: "monospace"
                    font.pixelSize: 13
                    font.bold: true
                }

                TextInput {
                    id: cmdInput
                    objectName: "quickTerminalInput"
                    Layout.fillWidth: true
                    enabled: !termWin.runningCommand
                    color: "#ffffff"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    font.family: "monospace"
                    font.pixelSize: 12
                    selectByMouse: true
                    clip: true
                    cursorDelegate: Rectangle {
                        width: 7
                        height: cmdInput.cursorRectangle.height > 0 ? cmdInput.cursorRectangle.height : 15
                        radius: 1.5
                        color: GemaTheme.synced ? GemaTheme.accent : "#a8d8ff"
                        opacity: cmdInput.activeFocus ? 0.9 : 0.0
                        SequentialAnimation on opacity {
                            running: cmdInput.activeFocus && GemaTheme.animations
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.9; to: 0.25; duration: 500; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.25; to: 0.9; duration: 500; easing.type: Easing.InOutSine }
                        }
                    }
                    onAccepted: {
                        const value = text;
                        text = "";
                        termWin.runCommand(value);
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            termWin.visible = false;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                            terminalLog.clear();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                            cmdInput.text = "";
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
                        visible: !cmdInput.text && logList.count === 0
                        text: "cd ~/Dev/mi-app · init work · init app · ls · help"
                        color: "#607084"
                        font.family: "monospace"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // Acciones discretas flotantes en la esquina superior derecha (+ Work, + App, ×)
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 12
        spacing: 5
        z: 5

        ActionButton {
            objectName: "terminalInitWorkBtn"
            text: "+ Work"
            font.pixelSize: 10
            implicitHeight: 24
            horizontalPadding: 8
            verticalPadding: 0
            enabled: !termWin.runningCommand && termWin.bridge.canSelectArea
            ToolTip.visible: hovered
            ToolTip.delay: 350
            ToolTip.text: "Inicializar o abrir esta carpeta en Work"
            onClicked: termWin.runCommand("init work")
        }

        ActionButton {
            objectName: "terminalInitAppBtn"
            text: "+ App"
            accent: true
            font.pixelSize: 10
            implicitHeight: 24
            horizontalPadding: 8
            verticalPadding: 0
            enabled: !termWin.runningCommand && termWin.bridge.canSelectArea
            ToolTip.visible: hovered
            ToolTip.delay: 350
            ToolTip.text: "Inicializar o abrir esta carpeta en App (Gema UI Kit)"
            onClicked: termWin.runCommand("init app")
        }

        ActionButton {
            implicitWidth: 24
            implicitHeight: 24
            horizontalPadding: 0
            verticalPadding: 0
            text: "×"
            font.pixelSize: 13
            ToolTip.visible: hovered
            ToolTip.delay: 350
            ToolTip.text: "Cerrar terminal (Esc)"
            onClicked: termWin.visible = false
        }
    }
}
