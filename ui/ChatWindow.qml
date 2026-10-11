import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import "components"
import "Performance.js" as Performance

// Cliente de conversación: cuenta, texto progresivo y controles de turno.
FloatingWindow {
    id: window
    required property AgentBridge bridge
    title: "Agent Shell · ChatGPT"
    implicitWidth: 1040
    implicitHeight: 800
    minimumSize: Qt.size(560, 560)
    color: "transparent"
    visible: true
    BackgroundEffect.blurRegion: Region { item: glassSurface; radius: glassSurface.radius }
    property var selectedPerformance: ({})
    property var chatToDelete: ({})
    readonly property bool overlayVisible: narrowSidebar.visible || historyPanel.visible || performancePanel.visible
                                           || accountPanel.visible || planWelcome.visible || performanceDetails.visible || deleteDialog.visible
    readonly property bool wideLayout: width >= 880
    property bool sidebarExpanded: true
    readonly property bool sidebarVisible: wideLayout && sidebarExpanded
    readonly property bool accountControlsEnabled: bridge.ready && !bridge.busy && !bridge.loginBusy && !bridge.accountBusy
    property string performanceModel: ""
    property double elapsedMs: 0

    function toggleSidebar() {
        if (wideLayout) sidebarExpanded = !sidebarExpanded;
        else if (narrowSidebar.visible) narrowSidebar.close();
        else narrowSidebar.open();
    }
    onWideLayoutChanged: {
        if (narrowSidebar) narrowSidebar.close();
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
        // Mate más marcado (44–48 % de opacidad), conservando la transparencia.
        topColor: "#701c1c1c"
        bottomColor: "#7a101010"
        edgeColor: "#50ffffff"
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 20
        // El panel se dibuja fuera de esta capa: sólo se desenfoca el chat de detrás.
        layer.enabled: window.overlayVisible && GraphicsInfo.api !== GraphicsInfo.Software
                       && GraphicsInfo.api !== GraphicsInfo.Unknown
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: 1.0
            saturation: -1.0
            autoPaddingEnabled: false
        }

        ChatSidebar {
            Layout.preferredWidth: 232
            Layout.fillHeight: true
            visible: window.sidebarVisible
            bridge: window.bridge
            onHistoryRequested: historyPanel.open()
            onPerformanceRequested: window.openPerformance()
            onAccountRequested: accountPanel.open()
            onDeleteRequested: (chatId, title) => window.requestDeleteChat(chatId, title)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                SidebarToggle {
                    expanded: window.sidebarVisible || narrowSidebar.visible
                    onClicked: window.toggleSidebar()
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 5
                    Text {
                        text: "CONVERSACIÓN"
                        color: "#aaaaaa"
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.bridge.currentTitle || "Nueva conversación"
                        color: "#f5f5f5"
                        font.pixelSize: window.wideLayout ? 24 : 21
                        font.bold: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
                RowLayout {
                    spacing: 7
                    Rectangle {
                        implicitWidth: 6; implicitHeight: 6; radius: 3
                        color: window.bridge.ready && window.bridge.authenticated ? "#ffffff" : "#777777"
                    }
                    Text {
                        text: !window.bridge.ready ? "Conectando…" : window.bridge.authenticated ? "ChatGPT conectado" : "Sin sesión"
                        color: "#bbbbbb"
                        font.pixelSize: 11
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

            ConversationPane {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 140
                bridge: window.bridge
                onPerformanceRequested: measurement => window.showPerformance(measurement)
                onSuggestionRequested: text => composer.prepare(text)
                onLoginRequested: window.bridge.login()
            }

            MessageComposer {
                id: composer
                Layout.fillWidth: true
                bridge: window.bridge
                compact: window.height < 680
                onSubmitted: text => window.bridge.submit(text)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: window.bridge.status + (window.bridge.busy ? " · " + Performance.duration(window.elapsedMs) : "")
                    color: window.bridge.busy || window.bridge.loginBusy ? "#cccccc" : "#bbbbbb"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    ToolTip.visible: statusHover.hovered
                    ToolTip.text: text
                    HoverHandler { id: statusHover }
                }
                Text {
                    text: window.wideLayout ? "Enter envía · Shift+Enter salto de línea" : "Enter · Shift+Enter"
                    color: "#aaaaaa"
                    font.pixelSize: 10
                }
            }
        }
    }

    Connections {
        target: window.bridge
        function onPlanConnected() { accountPanel.close(); planWelcome.open(); }
        function onBusyChanged() { window.elapsedMs = 0; }
        function onEventReceived(event) {
            if (event.type === "chat.loaded" || event.type === "chat.reset") narrowSidebar.close();
            if (event.type === "chat.deleted" && event.data.chat_id === window.selectedPerformance.chat_id) {
                performanceDetails.close();
                window.selectedPerformance = ({});
            }
            if (event.type === "performance.updated"
                && event.data.measurement.turn_id === window.selectedPerformance.turn_id)
                window.selectedPerformance = event.data.measurement;
        }
    }
    Drawer {
        id: narrowSidebar
        width: Math.min(280, window.width - 40)
        height: window.height
        edge: Qt.LeftEdge
        padding: 0
        background: MattePanel { overlay: true; radius: 18 }
        Overlay.modal: Rectangle { color: "#66000000" }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "Navegación"; color: "#bbbbbb"; font.pixelSize: 12 }
                ActionButton { text: "Cerrar"; font.pixelSize: 11; verticalPadding: 6; onClicked: narrowSidebar.close() }
            }
            ChatSidebar {
                Layout.fillWidth: true
                Layout.fillHeight: true
                topColor: "#18333333"
                bottomColor: "#20292929"
                waterReflection: false
                bridge: window.bridge
                onHistoryRequested: { narrowSidebar.close(); historyPanel.open(); }
                onPerformanceRequested: { narrowSidebar.close(); window.openPerformance(); }
                onAccountRequested: { narrowSidebar.close(); accountPanel.open(); }
                onDeleteRequested: (chatId, title) => window.requestDeleteChat(chatId, title)
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

    GlassDialog {
        id: accountPanel
        title: "Cuenta de ChatGPT"
        modal: true
        anchors.centerIn: parent
        width: Math.min(460, window.width - 40)
        standardButtons: Dialog.Close
        contentItem: ColumnLayout {
            spacing: 16
            Text {
                Layout.fillWidth: true
                text: window.bridge.authenticated ? window.bridge.email || "Cuenta conectada" : "Conecta tu cuenta"
                color: "#f5f5f5"
                font.pixelSize: 16
                font.bold: true
                wrapMode: Text.WrapAnywhere
                textFormat: Text.PlainText
            }
            Text {
                Layout.fillWidth: true
                text: window.bridge.authenticated ? "Las respuestas usan los límites disponibles de tu plan de ChatGPT."
                                                     : "Inicia sesión en el navegador y autoriza el uso de tu plan de ChatGPT."
                color: "#bbbbbb"
                font.pixelSize: 13
                wrapMode: Text.Wrap
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
            ActionButton {
                Layout.fillWidth: true
                visible: window.bridge.authenticated
                text: "Administrar uso del plan"
                onClicked: Qt.openUrlExternally("https://chatgpt.com/#settings/Usage")
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
        title: "Detalles de rendimiento"
        modal: true
        anchors.centerIn: parent
        width: Math.min(580, window.width - 40)
        height: Math.min(650, window.height - 40)
        standardButtons: Dialog.Close
        contentItem: ScrollView {
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
                text: "Últimos 200 turnos guardados. Las medianas y el p95 usan sólo respuestas completadas y tiempos del backend. Compara mensajes y contextos similares."
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
                ScrollBar.vertical: ScrollBar {}
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
                        topColor: measurementRow.hovered ? "#70555555" : "#443c3c3c"
                    }
                }
            }
        }
    }

    Drawer {
        id: historyPanel
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
                Text { Layout.fillWidth: true; text: "Historial de chats"; color: "#f5f5f5"; font.pixelSize: 21; font.bold: true }
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
                ScrollBar.vertical: ScrollBar {}
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
