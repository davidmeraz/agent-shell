import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import "js/Performance.js" as Performance
import "components/chat"
import "components/dialogs"
import "components/shared"
import "components/windows"
import "components/work"

// Cliente de conversación: cuenta, texto progresivo y controles de turno.
FloatingWindow {
    id: window
    required property AgentBridge bridge
    title: bridge.activeArea === "app"
           ? "Agent Shell · App" + (bridge.projectName ? " · " + bridge.projectName : "")
           : bridge.activeArea === "work"
             ? "Agent Shell · Work" + (bridge.projectName ? " · " + bridge.projectName : "")
             : "Agent Shell · Chat"
    implicitWidth: 600
    implicitHeight: 1000
    minimumSize: Qt.size(560, 560)
    color: "transparent"
    visible: true
    BackgroundEffect.blurRegion: Region { item: glassSurface; radius: glassSurface.radius }
    property var selectedPerformance: ({})
    property var chatToDelete: ({})
    property var projectToDelete: ({})
    property var projectToRename: ({})
    property var accountToRemove: ({})
    readonly property bool dialogVisible: historyPanel.visible || performancePanel.visible
                                           || accountPanel.visible || removeAccountDialog.visible || planWelcome.visible || performanceDetails.visible || deleteDialog.visible
                                           || settingsDialog.visible || shellSettings.visible || limitsDialog.visible
                                           || commandHelp.visible
                                           || projectDialog.visible || deleteProjectDialog.visible || renameProjectDialog.visible
    readonly property bool overlayVisible: narrowSidebar.visible || dialogVisible
    readonly property bool wideLayout: width >= 880
    property bool sidebarKeyboardOpen: false
    readonly property bool accountControlsEnabled: bridge.ready && !bridge.busy && !bridge.loginBusy && !bridge.accountBusy && !bridge.projectRunPreparing
    property string performanceModel: ""
    property double elapsedMs: 0

    readonly property ProjectExplorerWindow explorerWindow: ProjectExplorerWindow {
        bridge: window.bridge
        mainWindowTitle: window.title
    }
    readonly property GitFlowWindow gitFlowWindow: GitFlowWindow {
        bridge: window.bridge
        mainWindowTitle: window.title
        onFileRequested: path => {
            if (!window.bridge.projectId || !path) return;
            window.explorerWindow.secondFileWindow.openFile(path, false);
        }
    }
    readonly property AccountUsageWindow usageWindow: AccountUsageWindow {
        bridge: window.bridge
        mainWindowTitle: window.title
    }
    // Apertura inicial informativa: conserva el foco en el prompt del chat.
    Component.onCompleted: Qt.callLater(function() {
        if (!window.visible) return;
        window.usageWindow.visible = true;
        Qt.callLater(function() {
            const nativeWindow = window.contentItem.Window.window;
            if (window.visible && nativeWindow) nativeWindow.requestActivate();
        });
    })

    Shortcut {
        sequence: "Ctrl+B"
        enabled: !window.dialogVisible
        onActivated: {
            if (narrowSidebar.visible) narrowSidebar.close();
            else {
                window.sidebarKeyboardOpen = true;
                narrowSidebar.open();
                narrowSidebar.contentItem.forceActiveFocus();
            }
        }
    }
    Shortcut {
        sequence: "Esc"
        enabled: narrowSidebar.visible && !window.dialogVisible
        onActivated: narrowSidebar.close()
    }

    function showPerformance(measurement) {
        selectedPerformance = measurement;
        performanceDetails.open();
    }

    function openPerformance() {
        performancePanel.open();
        bridge.refreshPerformance();
    }

    function requestDeleteChat(chatId, title) {
        if (!bridge.canBrowseHistory) return;
        chatToDelete = ({ chat_id: chatId, title: title });
        deleteDialog.open();
    }

    function requestRemoveAccount() {
        if (!accountControlsEnabled || bridge.activeAccountIndex < 0
            || bridge.activeAccountIndex >= bridge.registeredAccounts.count) return;
        const item = bridge.registeredAccounts.get(bridge.activeAccountIndex);
        accountToRemove = ({ accountId: item.accountId, displayName: item.displayName });
        removeAccountDialog.open();
    }

    Timer {
        interval: 250
        repeat: true
        running: window.bridge.busy
        onTriggered: window.elapsedMs = Math.max(0, Date.now() - window.bridge.submittedAt)
    }
    Connections {
        target: window.contentItem.Window.window
        function onFrameSwapped() { window.bridge.confirmPresentation(); }
    }

    MattePanel {
        id: glassSurface
        anchors.fill: parent
        anchors.margins: 1
        radius: 20
        // Vidrio esmerilado translúcido Gema unificado con el sidebar y demás paneles.
        topColor: "#54141c26"
        bottomColor: "#680c121a"
        edgeColor: "#4cffffff"
    }

    RowLayout {
        id: mainLayout
        anchors.fill: parent
        anchors.margins: 16
        spacing: 20
        // El panel se dibuja fuera de esta capa: sólo se desenfoca el chat de detrás.
        layer.enabled: window.overlayVisible && GraphicsInfo.api !== GraphicsInfo.Software
                       && GraphicsInfo.api !== GraphicsInfo.Unknown
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 36
            blur: 1.0
            saturation: -0.35
            brightness: -0.08
            autoPaddingEnabled: false
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 14

            Item {
                id: topHeaderBar
                Layout.fillWidth: true
                implicitHeight: 38

                // Botón superior izquierdo para abrir o cerrar la barra lateral.
                Button {
                    id: sidebarToggleButton
                    objectName: "chatSidebarButton"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 38
                    implicitHeight: 38
                    padding: 0
                    hoverEnabled: true
                    enabled: !window.dialogVisible
                    scale: down ? 0.94 : (hovered ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                    Accessible.name: narrowSidebar.visible ? "Cerrar barra lateral" : "Abrir barra lateral"
                    ToolTip.visible: hovered
                    ToolTip.delay: 420
                    ToolTip.text: narrowSidebar.visible ? "Cerrar barra lateral (Ctrl+B)" : "Abrir barra lateral (Ctrl+B)"
                    onClicked: {
                        if (narrowSidebar.visible) {
                            narrowSidebar.close();
                        } else {
                            window.sidebarKeyboardOpen = true;
                            narrowSidebar.open();
                        }
                    }
                    contentItem: Item {
                        // Ícono vectorial minimalista de barra lateral (marco + panel izquierdo).
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 14
                            radius: 3.5
                            color: "transparent"
                            border.width: 1
                            border.color: (sidebarToggleButton.hovered || narrowSidebar.visible)
                                ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff")
                                : GemaTheme.mutedColor
                            Behavior on border.color { ColorAnimation { duration: GemaTheme.animDuration } }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 2
                                width: 5
                                radius: 1.5
                                color: (sidebarToggleButton.hovered || narrowSidebar.visible)
                                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.78) : "#b8ffffff")
                                    : "#52ffffff"
                                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                            }
                        }
                    }
                    background: GlassPanel {
                        radius: 12
                        reflective: true
                        highlighted: sidebarToggleButton.hovered || sidebarToggleButton.activeFocus || narrowSidebar.visible
                        topColor: (sidebarToggleButton.hovered || narrowSidebar.visible)
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#26ffffff")
                            : "#16ffffff"
                        bottomColor: "#0cffffff"
                        edgeColor: (sidebarToggleButton.hovered || narrowSidebar.visible)
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.60) : "#58ffffff")
                            : "#32ffffff"
                    }
                }

                WorkspaceSwitcher {
                    anchors.centerIn: parent
                    bridge: window.bridge
                }

                // Botón superior derecho con icono de perfil personal (abre Perfil y cuenta).
                Button {
                    id: profileHeaderButton
                    objectName: "chatProfileButton"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 38
                    implicitHeight: 38
                    padding: 0
                    hoverEnabled: true
                    enabled: !window.dialogVisible || accountPanel.visible
                    scale: down ? 0.94 : (hovered ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                    Accessible.name: "Perfil y cuenta: " + headerAvatar.displayName
                    ToolTip.visible: hovered
                    ToolTip.delay: 420
                    ToolTip.text: headerAvatar.displayName + "\nPerfil y cuenta"
                    onClicked: accountPanel.open()
                    contentItem: Item {
                        UserAvatar {
                            id: headerAvatar
                            anchors.centerIn: parent
                            size: 28
                            customName: window.bridge.displayName
                            plan: window.bridge.plan
                            connected: window.bridge.authenticated
                            showStatusDot: true
                        }
                    }
                    background: GlassPanel {
                        radius: 19
                        reflective: true
                        highlighted: profileHeaderButton.hovered || profileHeaderButton.activeFocus || accountPanel.visible
                        topColor: (profileHeaderButton.hovered || accountPanel.visible)
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.26) : "#28ffffff")
                            : "#16ffffff"
                        bottomColor: "#0cffffff"
                        edgeColor: (profileHeaderButton.hovered || accountPanel.visible)
                            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#60ffffff")
                            : "#36ffffff"
                    }
                }
            }

            GlassPanel {
                Layout.fillWidth: true
                implicitHeight: loginRow.implicitHeight + 20
                visible: window.bridge.loginBusy
                edgeColor: "#50cccccc"
                RowLayout {
                    id: loginRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        text: "Continúa en el navegador para conectar tu cuenta."
                        color: "#e4e4e4"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                    ActionButton {
                        text: "Abrir navegador"
                        enabled: window.bridge.authUrl !== ""
                        onClicked: Qt.openUrlExternally(window.bridge.authUrl)
                    }
                    ActionButton { text: "Cancelar"; onClicked: window.bridge.cancelLogin() }
                }
            }

            RowLayout {
                objectName: "workProjectHeader"
                Layout.fillWidth: true
                visible: (window.bridge.activeArea === "work" || window.bridge.activeArea === "app") && !!window.bridge.projectId
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: (window.bridge.activeArea === "app" ? "App · " : "Work · ") + window.bridge.projectName
                            textFormat: Text.PlainText
                            color: "#dddddd"
                            font.pixelSize: 13
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        GlassPanel {
                            visible: window.bridge.activeArea === "app"
                            implicitWidth: gemaBadge.implicitWidth + 14
                            implicitHeight: 20
                            radius: 6
                            topColor: "#1cffffff"
                            bottomColor: "#10ffffff"
                            Text {
                                id: gemaBadge
                                anchors.centerIn: parent
                                text: "Gema UI Kit · Glass · " + (window.bridge.projectEngine === "rust" ? "Rust" : "Python")
                                color: "#dddddd"
                                font.pixelSize: 10
                            }
                        }
                    }
                    Text {
                        objectName: "workRunStatus"
                        Layout.fillWidth: true
                        text: window.bridge.projectRunPending ? "Detectando cómo ejecutar…"
                              : window.bridge.projectRunHere ? window.bridge.projectRunNotice || window.bridge.projectRun.message
                              : window.bridge.projectRunNotice || window.bridge.workspace
                        textFormat: Text.PlainText
                        color: "#888888"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }
                }
                ActionButton {
                    objectName: "workGitButton"
                    text: "⎇ Git"
                    accent: window.gitFlowWindow.visible
                    font.pixelSize: 11
                    verticalPadding: 7
                    enabled: window.bridge.ready && !!window.bridge.projectId
                    Accessible.name: window.gitFlowWindow.visible
                        ? "Cerrar visor de flujo Git"
                        : "Abrir visor de flujo de commits Git"
                    ToolTip.visible: hovered
                    ToolTip.delay: 450
                    ToolTip.text: window.gitFlowWindow.visible
                        ? "Ocultar el visor de flujo de commits Git."
                        : "Ver el flujo de commits y ramas Git de este proyecto a la derecha."
                    onClicked: window.gitFlowWindow.toggleForProject({
                        project_id: window.bridge.projectId,
                        name: window.bridge.projectName,
                        workdir: window.bridge.workspace
                    })
                }
                ActionButton {
                    objectName: "appTestButton"
                    visible: window.bridge.activeArea === "app"
                    text: "Probar"
                    font.pixelSize: 11
                    verticalPadding: 7
                    enabled: window.bridge.canTestApp
                    Accessible.name: "Probar sintaxis QML y motor de la aplicación Gema UI Kit"
                    ToolTip.visible: hovered
                    ToolTip.delay: 450
                    ToolTip.text: "Valida los componentes QML Glassmorphism (qmllint) y la conexión IPC del motor."
                    onClicked: window.bridge.testApp()
                }
                ActionButton {
                    objectName: "workRunButton"
                    text: window.bridge.projectRunHere && window.bridge.projectRunActive
                          ? "Detener"
                          : (window.bridge.activeArea === "app" ? "Iniciar" : "Ejecutar")
                    accent: window.bridge.activeArea === "app" && !(window.bridge.projectRunHere && window.bridge.projectRunActive)
                    font.pixelSize: 11
                    verticalPadding: 7
                    enabled: window.bridge.canRunProject || (window.bridge.projectRunHere && window.bridge.projectRunActive
                             && window.bridge.projectRun.phase !== "stopping")
                    Accessible.name: text === "Detener" ? "Detener programa del proyecto"
                                   : window.bridge.activeArea === "app" ? "Iniciar aplicación Gema UI Kit" : "Detectar y ejecutar proyecto con IA"
                    ToolTip.visible: hovered
                    ToolTip.delay: 450
                    ToolTip.text: window.bridge.projectRunHere
                                  ? [window.bridge.projectRunNotice || window.bridge.projectRun.message,
                                     window.bridge.projectRun.source === "cache" ? "Inicio guardado · sin consulta a la IA" : "",
                                     window.bridge.projectRun.command || "",
                                     window.bridge.projectRun.output ? window.bridge.projectRun.output.slice(-1200) : ""].filter(part => !!part).join("\n")
                                  : window.bridge.projectRunActive ? "Otro proyecto se está ejecutando."
                                  : window.bridge.activeArea === "app"
                                    ? "Inicia la ventana Glassmorphism de tu aplicación Gema UI Kit en Hyprland."
                                  : window.bridge.projectRunCaches[window.bridge.projectId]
                                    ? "Ejecutar el inicio guardado del proyecto."
                                    : "La IA detecta cómo iniciar el proyecto sin añadir mensajes al chat."
                    onClicked: {
                        if (window.bridge.projectRunHere && window.bridge.projectRunActive) window.bridge.stopProject();
                        else window.bridge.runProject();
                    }
                }
                ActionButton {
                    objectName: "workProjectsButton"
                    text: window.bridge.activeArea === "app" ? "Apps" : "Proyectos"
                    font.pixelSize: 11
                    verticalPadding: 7
                    enabled: window.bridge.canSelectArea
                    onClicked: window.bridge.selectArea(window.bridge.activeArea, "")
                }
            }
            WorkProjects {
                objectName: "workProjects"
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !window.bridge.workspaceSelected
                bridge: window.bridge
                onNewProjectRequested: projectDialog.open()
                onRenameProjectRequested: (projectId, name) => {
                    window.projectToRename = ({ project_id: projectId, name: name });
                    renameProjectInput.text = name;
                    renameProjectDialog.open();
                    Qt.callLater(() => {
                        renameProjectInput.forceActiveFocus();
                        renameProjectInput.selectAll();
                    });
                }
                onDeleteProjectRequested: (projectId, name, workdir) => {
                    window.projectToDelete = ({ project_id: projectId, name: name, workdir: workdir });
                    deleteProjectDialog.open();
                }
            }
            ConversationPane {
                objectName: "chatConversation"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 140
                visible: window.bridge.workspaceSelected
                bridge: window.bridge
                onPerformanceRequested: measurement => window.showPerformance(measurement)
                onSuggestionRequested: text => composer.prepare(text)
                onLoginRequested: window.bridge.login()
                onAccountRequested: accountPanel.open()
            }

            ProviderSwitcher {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -6
                Layout.bottomMargin: -4
                visible: window.bridge.workspaceSelected && (window.bridge.agyAvailable || window.bridge.claudeAvailable)
                bridge: window.bridge
            }

            MessageComposer {
                id: composer
                Layout.fillWidth: true
                visible: window.bridge.workspaceSelected
                bridge: window.bridge
                compact: window.height < 680
                statusText: window.bridge.status + (window.bridge.busy ? " · " + Performance.duration(window.elapsedMs) : "")
                onPerformanceRequested: measurement => window.showPerformance(measurement)
            }
        }
    }

    // Zona invisible: el panel se superpone sin cambiar el tamaño del chat.
    Item {
        objectName: "chatSidebarEdge"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 12
        z: 3
        HoverHandler {
            id: edgeHover
            enabled: !window.overlayVisible
            onHoveredChanged: {
                if (hovered) sidebarOpenDelay.restart();
                else sidebarOpenDelay.stop();
            }
        }
    }
    Timer {
        id: sidebarOpenDelay
        interval: 160
        onTriggered: {
            if (edgeHover.hovered && !window.overlayVisible) narrowSidebar.open();
        }
    }
    Timer {
        id: sidebarCloseDelay
        interval: 450
        onTriggered: {
            if (!sidebarHover.hovered && !window.sidebarKeyboardOpen) narrowSidebar.close();
        }
    }

    Connections {
        target: window.bridge
        function onLocalCommandRequested(command) {
            if (command === "/ayuda") commandHelp.open();
            else if (command === "/historial") { historyPanel.open(); window.bridge.refreshHistory(); }
            // Preparar las sugerencias después de procesar Enter.
            else if (command === "/modelos" || command.startsWith("/modelos ")) Qt.callLater(() => composer.openModels(command));
            else if (command === "/terminal") shellSettings.open();
            else if (command === "/limites") limitsDialog.open();
        }
        function onPlanConnected() { accountPanel.close(); planWelcome.open(); }
        function onBusyChanged() { window.elapsedMs = 0; }
        function onEventReceived(event) {
            if (event.type === "chat.loaded" || event.type === "chat.reset") narrowSidebar.close();
            if (event.type === "chat.deleted" && event.data.chat_id === window.selectedPerformance.chat_id) {
                performanceDetails.close();
                window.selectedPerformance = ({});
            }
            if (event.type === "project.deleted"
                && event.data.chat_ids.indexOf(window.selectedPerformance.chat_id) >= 0) {
                performanceDetails.close();
                window.selectedPerformance = ({});
            }
            if (event.type === "performance.updated"
                && event.data.measurement.turn_id === window.selectedPerformance.turn_id)
                window.selectedPerformance = event.data.measurement;
        }
    }
    CommandHelpDialog {
        id: commandHelp
        anchors.centerIn: parent
        width: Math.min(440, window.width - 40)
    }
    ProjectDialog {
        id: projectDialog
        bridge: window.bridge
        anchors.centerIn: parent
        width: Math.min(480, window.width - 40)
    }
    GlassDialog {
        id: deleteProjectDialog
        objectName: "workDeleteProjectDialog"
        title: "Eliminar proyecto"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, window.width - 40)
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                Layout.fillWidth: true
                text: window.projectToDelete.name || "Proyecto"
                textFormat: Text.PlainText
                color: "#f5f5f5"
                font.pixelSize: 15
                font.bold: true
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                text: window.projectToDelete.workdir || ""
                textFormat: Text.PlainText
                color: "#aaaaaa"
                font.pixelSize: 11
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                text: "Se eliminarán el proyecto de Work, sus conversaciones y sus mediciones. La carpeta y sus archivos se conservarán. Esta acción no se puede deshacer."
                color: "#bbbbbb"
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }
        footer: DialogButtonBox {
            padding: 16
            spacing: 8
            background: null
            ActionButton {
                objectName: "workCancelDeleteProject"
                text: "Cancelar"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
            ActionButton {
                objectName: "workConfirmDeleteProject"
                text: "Eliminar"
                enabled: window.bridge.canSelectArea
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            }
        }
        onAccepted: window.bridge.deleteProject(window.projectToDelete.project_id)
    }
    GlassDialog {
        id: renameProjectDialog
        objectName: "workRenameProjectDialog"
        title: window.bridge.activeArea === "app" ? "Renombrar aplicación" : "Renombrar proyecto"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, window.width - 40)
        function submitRename() {
            const cleaned = renameProjectInput.text.trim();
            if (!cleaned || cleaned.length > 80) return;
            window.bridge.renameProject(window.projectToRename.project_id, cleaned);
            renameProjectDialog.close();
        }
        contentItem: ColumnLayout {
            spacing: 10
            Text {
                Layout.fillWidth: true
                text: "Nuevo nombre"
                color: GemaTheme.mutedColor
                font.pixelSize: 12
            }
            GlassPanel {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 10
                highlighted: renameProjectInput.activeFocus
                TextInput {
                    id: renameProjectInput
                    objectName: "workRenameProjectInput"
                    anchors.fill: parent
                    anchors.margins: 10
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 80
                    color: "#f5f5f5"
                    selectionColor: "#ffffff"
                    selectedTextColor: "#000000"
                    font.pixelSize: 13
                    selectByMouse: true
                    onAccepted: renameProjectDialog.submitRename()
                }
            }
        }
        footer: DialogButtonBox {
            padding: 16
            spacing: 8
            background: null
            ActionButton {
                objectName: "workCancelRenameProject"
                text: "Cancelar"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
            ActionButton {
                objectName: "workConfirmRenameProject"
                text: "Guardar"
                accent: true
                enabled: window.bridge.canSelectArea && renameProjectInput.text.trim().length > 0
                         && renameProjectInput.text.trim().length <= 80
                onClicked: renameProjectDialog.submitRename()
            }
        }
    }
    Drawer {
        id: narrowSidebar
        objectName: "chatSidebarDrawer"
        width: Math.min(280, window.width - 40)
        height: window.height
        edge: Qt.LeftEdge
        padding: 0
        modal: false
        dim: false
        focus: window.sidebarKeyboardOpen
        onOpened: {
            if (!sidebarHover.hovered && !window.sidebarKeyboardOpen) sidebarCloseDelay.restart();
        }
        onClosed: {
            sidebarCloseDelay.stop();
            window.sidebarKeyboardOpen = false;
        }
        background: MattePanel { overlay: true; radius: 18 }
        contentItem: Item {
            HoverHandler {
                id: sidebarHover
                onHoveredChanged: {
                    if (hovered) sidebarCloseDelay.stop();
                    else if (narrowSidebar.visible && !window.sidebarKeyboardOpen) sidebarCloseDelay.restart();
                }
            }
            ChatSidebar {
                objectName: "chatSidebar"
                anchors.fill: parent
                anchors.margins: 8
                topColor: "#00000000"
                bottomColor: "#00000000"
                edgeColor: "#00000000"
                waterReflection: false
                bridge: window.bridge
                onHistoryRequested: { narrowSidebar.close(); historyPanel.open(); }
                onPerformanceRequested: { narrowSidebar.close(); window.openPerformance(); }
                onSettingsRequested: { narrowSidebar.close(); settingsDialog.open(); }
                onShellRequested: { narrowSidebar.close(); shellSettings.open(); }
                onProjectRequested: { narrowSidebar.close(); projectDialog.open(); }
                onDeleteRequested: (chatId, title) => {
                    narrowSidebar.close();
                    window.requestDeleteChat(chatId, title);
                }
            }
        }
    }

    GlassDialog {
        id: deleteDialog
        title: "Borrar conversación"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, window.width - 40)
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                Layout.fillWidth: true
                text: window.chatToDelete.title || "Conversación"
                textFormat: Text.PlainText
                color: "#f5f5f5"
                font.pixelSize: 15
                font.bold: true
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                text: "Se borrarán los mensajes y las mediciones de este chat del historial local. Esta acción no se puede deshacer."
                color: "#bbbbbb"
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }
        footer: DialogButtonBox {
            padding: 16
            spacing: 8
            background: null
            ActionButton {
                text: "Cancelar"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
            ActionButton {
                text: "Borrar"
                enabled: window.bridge.canBrowseHistory
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? "#ffffff" : "#777777"
                    font: parent.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        onAccepted: window.bridge.deleteChat(window.chatToDelete.chat_id)
    }

    SettingsDialog {
        id: settingsDialog
        objectName: "chatSettingsDialog"
        bridge: window.bridge
        anchors.centerIn: parent
        width: Math.min(460, window.width - 40)
        onLimitsRequested: limitsDialog.open()
        onShellRequested: shellSettings.open()
        onAccountRequested: accountPanel.open()
        onUsageRequested: window.usageWindow.open()
        onCommandsRequested: commandHelp.open()
    }

    ShellSettingsDialog {
        id: shellSettings
        objectName: "shellSettings"
        bridge: window.bridge
        anchors.centerIn: parent
        width: Math.min(480, window.width - 40)
    }

    TokenLimitsDialog {
        id: limitsDialog
        objectName: "tokenLimitsDialog"
        bridge: window.bridge
        anchors.centerIn: parent
        width: Math.min(480, window.width - 40)
    }

    GlassDialog {
        id: accountPanel
        objectName: "chatAccount"
        title: "Perfil y cuenta"
        modal: true
        anchors.centerIn: parent
        width: Math.min(460, window.width - 40)
        standardButtons: Dialog.Close
        onOpened: profileNameInput.text = window.bridge.displayName
        contentItem: ColumnLayout {
            spacing: 11
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                UserAvatar {
                    id: accountAvatarPreview
                    size: 34
                    customName: profileNameInput.text.trim() || window.bridge.displayName
                    plan: window.bridge.plan
                    connected: window.bridge.authenticated
                    showStatusDot: true
                }
                GlassPanel {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 10
                    highlighted: profileNameInput.activeFocus
                    TextInput {
                        id: profileNameInput
                        objectName: "chatProfileNameInput"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        maximumLength: 40
                        color: "#f5f5f5"
                        selectionColor: "#ffffff"
                        selectedTextColor: "#000000"
                        font.pixelSize: 13
                        selectByMouse: true
                        onAccepted: window.bridge.updateProfile(profileNameInput.text)
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !profileNameInput.text && !profileNameInput.activeFocus
                            text: "Nombre de usuario…"
                            color: "#80ffffff"
                            font.pixelSize: 13
                        }
                    }
                }
                ActionButton {
                    objectName: "chatProfileSaveButton"
                    text: "Guardar"
                    verticalPadding: 7
                    accent: profileNameInput.text.trim() !== window.bridge.displayName
                    enabled: window.bridge.ready && profileNameInput.text.trim() !== window.bridge.displayName
                    onClicked: window.bridge.updateProfile(profileNameInput.text)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !!window.bridge.profileError
                text: window.bridge.profileError
                textFormat: Text.PlainText
                color: "#ff9b9b"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                text: window.bridge.authenticated
                    ? accountAvatarPreview.displayName + " · Cuenta de ChatGPT conectada (usa los límites de tu plan)."
                    : "Inicia sesión en el navegador y autoriza el uso de tu plan de ChatGPT."
                color: "#bbbbbb"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            GlassComboBox {
                objectName: "chatAccountSelector"
                Layout.fillWidth: true
                visible: window.bridge.registeredAccounts.count > 1
                enabled: window.accountControlsEnabled
                model: window.bridge.registeredAccounts
                textRole: "displayName"
                currentIndex: window.bridge.activeAccountIndex
                onActivated: index => window.bridge.selectAccount(window.bridge.registeredAccounts.get(index).accountId)
            }
            RowLayout {
                Layout.fillWidth: true
                ActionButton {
                    Layout.fillWidth: true
                    text: window.bridge.authenticated ? "Actualizar cuenta" : "Continuar con ChatGPT"
                    accent: !window.bridge.authenticated
                    enabled: window.accountControlsEnabled
                    onClicked: window.bridge.authenticated ? window.bridge.refreshAccount() : window.bridge.login()
                }
                ActionButton {
                    text: "Salir"
                    visible: window.bridge.email !== ""
                    enabled: window.accountControlsEnabled
                    onClicked: window.bridge.logout()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: window.bridge.registeredAccounts.count > 0
                ActionButton {
                    objectName: "chatAddAccount"
                    Layout.fillWidth: true
                    text: "Usar otra cuenta"
                    enabled: window.accountControlsEnabled
                    onClicked: window.bridge.login(true)
                }
                ActionButton {
                    objectName: "chatRemoveAccount"
                    text: "Quitar"
                    visible: window.bridge.activeAccountIndex >= 0
                    enabled: window.accountControlsEnabled
                    onClicked: window.requestRemoveAccount()
                }
            }
            ActionButton {
                objectName: "chatUsageButton"
                Layout.fillWidth: true
                visible: window.bridge.engineReady
                text: window.bridge.provider === "agy" ? "Ver uso de Antigravity (agy)"
                    : window.bridge.provider === "claude" ? "Ver uso de Claude"
                    : "Ver uso del plan"
                onClicked: { accountPanel.close(); window.usageWindow.open(); }
            }
            Text {
                Layout.fillWidth: true
                text: window.bridge.status
                textFormat: Text.PlainText
                color: "#bbbbbb"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            RowLayout {
                visible: window.bridge.loginBusy
                ActionButton {
                    text: "Abrir navegador"
                    enabled: window.bridge.authUrl !== ""
                    onClicked: Qt.openUrlExternally(window.bridge.authUrl)
                }
                ActionButton { text: "Cancelar"; onClicked: window.bridge.cancelLogin() }
            }
            Text { text: "Agent Shell · v" + (window.bridge.appVersion || "…"); color: "#aaaaaa"; font.pixelSize: 10 }
        }
    }

    GlassDialog {
        id: removeAccountDialog
        objectName: "chatRemoveAccountDialog"
        title: "Quitar cuenta"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, window.width - 40)
        contentItem: ColumnLayout {
            spacing: 12
            Text {
                Layout.fillWidth: true
                text: window.accountToRemove.displayName || "Cuenta"
                textFormat: Text.PlainText
                color: "#f5f5f5"
                font.pixelSize: 15
                font.bold: true
                wrapMode: Text.WrapAnywhere
            }
            Text {
                Layout.fillWidth: true
                text: "Se eliminará este registro de Agent Shell y se cerrará su sesión local. Tus conversaciones y proyectos se conservan."
                color: "#bbbbbb"
                font.pixelSize: 13
                wrapMode: Text.Wrap
            }
        }
        footer: DialogButtonBox {
            padding: 16
            spacing: 8
            background: null
            ActionButton {
                text: "Cancelar"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            }
            ActionButton {
                objectName: "chatConfirmRemoveAccount"
                text: "Quitar"
                enabled: window.accountControlsEnabled
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? "#ffffff" : "#777777"
                    font: parent.font
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        onAccepted: window.bridge.removeAccount(window.accountToRemove.accountId)
    }

    GlassDialog {
        id: planWelcome
        title: "Tu plan de ChatGPT"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, window.width - 48)
        standardButtons: Dialog.Ok
        contentItem: Text {
            text: "Estás usando tu plan de ChatGPT. Las respuestas de Agent Shell consumen sus límites disponibles. Puedes administrar el uso y desconectar la aplicación en los ajustes de ChatGPT."
            wrapMode: Text.Wrap
            color: "#e4e4e4"
            font.pixelSize: 14
        }
    }

    GlassDialog {
        id: performanceDetails
        objectName: "chatPerformanceDetails"
        title: "Detalles de rendimiento"
        modal: true
        anchors.centerIn: parent
        width: Math.min(580, window.width - 40)
        height: Math.min(650, window.height - 40)
        standardButtons: Dialog.Close
        contentItem: ScrollView {
            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            TextArea {
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                text: Performance.details(window.selectedPerformance)
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: "#e4e4e4"
                font.pixelSize: 13
                background: null
            }
        }
    }

    Drawer {
        id: performancePanel
        width: Math.min(560, window.width - 40)
        height: window.height
        edge: Qt.RightEdge
        background: MattePanel { overlay: true; radius: 18 }
        Overlay.modal: Rectangle { color: "#66000000" }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Rendimiento"; color: "#f5f5f5"; font.pixelSize: 21; font.bold: true }
                ActionButton { text: "Cerrar"; font.pixelSize: 11; verticalPadding: 6; onClicked: performancePanel.close() }
            }
            Text {
                Layout.fillWidth: true
                text: "Últimos 200 turnos guardados. Las medianas y el p95 usan sólo respuestas completadas sin terminal. Los turnos con comandos incluyen esperas y ejecución. Compara mensajes y contextos similares."
                color: "#a0a0a0"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                GlassComboBox {
                    Layout.fillWidth: true
                    model: ["Todos los modelos"].concat(window.bridge.modelPerformance.map(row => row.model))
                    onActivated: window.performanceModel = currentIndex ? currentText : ""
                    onModelChanged: {
                        currentIndex = window.performanceModel ? model.indexOf(window.performanceModel) : 0;
                        if (currentIndex < 0) { window.performanceModel = ""; currentIndex = 0; }
                    }
                }
                ActionButton {
                    text: window.bridge.performanceBusy ? "Cargando…" : "Actualizar"
                    enabled: window.bridge.ready && !window.bridge.performanceBusy
                    onClicked: window.bridge.refreshPerformance()
                }
            }
            ListView {
                id: performanceList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 10
                model: window.bridge.performanceHistory.filter(row => !window.performanceModel || row.model === window.performanceModel)
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                header: Column {
                    width: performanceList.width
                    spacing: 10
                    Repeater {
                        model: window.bridge.modelPerformance.filter(row => !window.performanceModel || row.model === window.performanceModel)
                        delegate: GlassPanel {
                            id: modelCard
                            required property var modelData
                            width: performanceList.width
                            implicitHeight: modelStats.implicitHeight + 24
                            radius: 8
                            Column {
                                id: modelStats
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6
                                Text { text: modelCard.modelData.model; color: "#ffffff"; font.bold: true }
                                Text {
                                    width: parent.width
                                    text: "Primer texto (mediana): " + Performance.duration(modelCard.modelData.firstMedian)
                                          + "\nTotal (mediana): " + Performance.duration(modelCard.modelData.totalMedian)
                                          + "\nTotal p95: " + (modelCard.modelData.totalP95 === null
                                              ? "Disponible desde 20 respuestas completadas" : Performance.duration(modelCard.modelData.totalP95))
                                    color: "#e4e4e4"
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }
                                Text {
                                    width: parent.width
                                    text: modelCard.modelData.completed + " completadas · " + modelCard.modelData.failed
                                          + " fallidas · " + modelCard.modelData.interrupted + " interrumpidas"
                                          + (modelCard.modelData.agentTurns ? "\n" + modelCard.modelData.agentTurns + " turnos con terminal separados" : "")
                                    color: "#a0a0a0"
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: window.bridge.performanceHistory.length ? "Mediciones por respuesta" : "Envía un mensaje para registrar la primera medición. Los chats antiguos no tienen datos de rendimiento."
                        color: "#a0a0a0"
                        wrapMode: Text.Wrap
                    }
                    Item { width: 1; height: 6 }
                }
                delegate: ItemDelegate {
                    id: measurementRow
                    required property var modelData
                    width: performanceList.width
                    onClicked: window.showPerformance(modelData)
                    contentItem: Column {
                        spacing: 6
                        Text {
                            width: parent.width
                            text: measurementRow.modelData.model + " · " + Performance.status(measurementRow.modelData.status)
                            color: "#e4e4e4"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: Performance.summary(measurementRow.modelData)
                            color: "#a0a0a0"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                        Text {
                            text: new Date(measurementRow.modelData.started_at).toLocaleString()
                            color: "#888888"
                            font.pixelSize: 10
                        }
                    }
                    background: GlassPanel {
                        radius: 10
                        highlighted: measurementRow.activeFocus
                        topColor: measurementRow.hovered ? "#22ffffff" : "#12ffffff"
                    }
                }
            }
        }
    }

    Drawer {
        id: historyPanel
        objectName: "chatHistory"
        width: Math.min(360, window.width - 40)
        height: window.height
        edge: Qt.LeftEdge
        background: MattePanel { overlay: true; radius: 18 }
        Overlay.modal: Rectangle { color: "#66000000" }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: window.bridge.activeArea === "app" ? "Historial de la aplicación" : window.bridge.activeArea === "work" ? "Historial del proyecto" : "Historial de Chat"; color: "#f5f5f5"; font.pixelSize: 21; font.bold: true }
                ActionButton { text: "Cerrar"; font.pixelSize: 11; verticalPadding: 6; onClicked: historyPanel.close() }
            }
            Text {
                Layout.fillWidth: true
                visible: window.bridge.conversations.count === 0
                text: "Tus conversaciones aparecerán aquí al enviar el primer mensaje."
                color: "#a0a0a0"
                wrapMode: Text.Wrap
            }
            ListView {
                id: savedChats
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: window.bridge.conversations
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
                delegate: ConversationRow {
                    width: savedChats.width
                    font.pixelSize: 13
                    selected: chatId === window.bridge.currentChatId
                    enabled: window.bridge.canBrowseHistory
                    onClicked: {
                        window.bridge.openChat(chatId);
                        historyPanel.close();
                    }
                    onDeleteRequested: (chatId, title) => window.requestDeleteChat(chatId, title)
                }
            }
            Text { text: "Directorio del historial"; color: "#ffffff"; font.pixelSize: 12 }
            TextArea {
                selectionColor: "#ffffff"
                selectedTextColor: "#000000"
                Layout.fillWidth: true
                text: window.bridge.historyDirectory
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: "#a0a0a0"
                font.pixelSize: 11
                background: null
                padding: 0
            }
            RowLayout {
                Layout.fillWidth: true
                ActionButton {
                    text: "Abrir carpeta"
                    enabled: window.bridge.historyDirectory !== ""
                    onClicked: Qt.openUrlExternally("file://" + window.bridge.historyDirectory)
                }
                ActionButton {
                    text: "Actualizar"
                    enabled: window.bridge.canBrowseHistory
                    onClicked: window.bridge.refreshHistory()
                }
            }
        }
    }

    function sendPrompt() {
        composer.send();
    }
}
