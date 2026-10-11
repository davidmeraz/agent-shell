import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import "components"
import "Performance.js" as Performance

// Cliente de conversación: cuenta, texto progresivo y controles de turno.
FloatingWindow {
    id: window
    required property AgentBridge bridge
    title: "Agent Shell · ChatGPT"
    implicitWidth: 820
    implicitHeight: 780
    minimumSize: Qt.size(560, 560)
    color: "#0d1420"
    visible: true
    property var selectedPerformance: ({})
    property string performanceModel: ""
    property double elapsedMs: 0

    function showPerformance(measurement) {
        selectedPerformance = measurement;
        performanceDetails.open();
    }

    function openPerformance() {
        performancePanel.open();
        bridge.refreshPerformance();
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "AGENT SHELL"; color: "#72e5c0"; font.pixelSize: 12; font.letterSpacing: 3 }
                Text { text: "Conversa con ChatGPT"; color: "#edf4fa"; font.pixelSize: 27; font.bold: true }
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: "Rendimiento"
                enabled: window.bridge.historyReady
                onClicked: window.openPerformance()
            }
            ActionButton {
                text: "Historial"
                enabled: window.bridge.historyReady
                onClicked: historyPanel.open()
            }
            ActionButton {
                text: "Nuevo chat"
                enabled: window.bridge.canBrowseHistory
                onClicked: window.bridge.newChat()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: accountRow.implicitHeight + 24
            color: "#172330"
            radius: 10
            border.color: window.bridge.authenticated ? "#2f6156" : "#314155"
            RowLayout {
                id: accountRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: window.bridge.authenticated ? "#72e5c0" : "#f5c478"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: window.bridge.authenticated
                              ? window.bridge.email || "Cuenta de ChatGPT conectada"
                              : "Conecta tu cuenta de ChatGPT"
                        color: "#edf4fa"
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.bridge.authenticated
                              ? "Usando tu plan de ChatGPT"
                              : "Conecta tu cuenta y autoriza el uso de tu plan."
                        color: "#96a9bb"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
                ActionButton {
                    text: window.bridge.authenticated ? "Actualizar" : "Continuar con ChatGPT"
                    accent: !window.bridge.authenticated
                    enabled: window.bridge.ready && !window.bridge.busy && !window.bridge.loginBusy && !window.bridge.accountBusy
                    onClicked: window.bridge.authenticated ? window.bridge.refreshAccount() : window.bridge.login()
                }
                ActionButton {
                    text: "Salir"
                    visible: window.bridge.email !== ""
                    enabled: window.bridge.ready && !window.bridge.busy && !window.bridge.loginBusy && !window.bridge.accountBusy
                    onClicked: window.bridge.logout()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: window.bridge.availableModels.count > 0
            ComboBox {
                Layout.fillWidth: true
                model: window.bridge.availableModels
                textRole: "displayName"
                valueRole: "slug"
                enabled: window.bridge.canSend
                currentIndex: {
                    for (let i = 0; i < window.bridge.availableModels.count; ++i)
                        if (window.bridge.availableModels.get(i).slug === window.bridge.modelName) return i;
                    return -1;
                }
                onActivated: window.bridge.selectModel(currentValue)
            }
            ActionButton {
                text: "Administrar uso"
                onClicked: Qt.openUrlExternally("https://chatgpt.com/#settings/Usage")
            }
        }

        Text {
            Layout.fillWidth: true
            visible: window.bridge.currentTitle !== ""
            text: window.bridge.currentTitle
            color: "#96a9bb"
            font.pixelSize: 12
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        RowLayout {
            visible: window.bridge.loginBusy
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "Continúa en el navegador para conectar tu cuenta."
                color: "#96a9bb"
                wrapMode: Text.Wrap
            }
            ActionButton {
                text: "Abrir navegador"
                enabled: window.bridge.authUrl !== ""
                onClicked: Qt.openUrlExternally(window.bridge.authUrl)
            }
            ActionButton { text: "Cancelar"; onClicked: window.bridge.cancelLogin() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#111d2a"
            radius: 12
            border.color: "#243347"
            Text {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: window.bridge.messages.count === 0
                text: "¿Qué tienes en mente?\n\nPregunta, comparte una idea o pide ayuda con código."
                color: "#96a9bb"
                font.pixelSize: 16
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
            ListView {
                id: conversation
                anchors.fill: parent
                anchors.margins: 18
                clip: true
                spacing: 20
                model: window.bridge.messages
                ScrollBar.vertical: ScrollBar {}
                onContentHeightChanged: {
                    if (!moving) Qt.callLater(() => conversation.positionViewAtEnd());
                }
                delegate: Column {
                    required property string author
                    required property string body
                    required property string performanceJson
                    readonly property var measurement: performanceJson ? JSON.parse(performanceJson) : ({})
                    width: conversation.width - 16
                    spacing: 6
                    Text {
                        text: parent.author
                        color: parent.author === "SISTEMA" ? "#f5c478" : "#72e5c0"
                        font.pixelSize: 11
                        font.bold: true
                    }
                    TextArea {
                        text: parent.body
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        color: "#d8e5ee"
                        font.pixelSize: 14
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        padding: 0
                        background: null
                    }
                    RowLayout {
                        width: parent.width
                        visible: !!parent.measurement.turn_id
                        Text {
                            Layout.fillWidth: true
                            text: Performance.summary(parent.parent.measurement)
                            color: "#96a9bb"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                        ActionButton {
                            text: "Detalles"
                            onClicked: window.showPerformance(parent.parent.measurement)
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: window.bridge.status
            color: window.bridge.busy || window.bridge.loginBusy ? "#f5c478" : "#96a9bb"
            font.pixelSize: 12
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }

        Text {
            Layout.fillWidth: true
            visible: window.bridge.busy
            text: (window.bridge.latestPerformance.first_text_ms === null
                   || window.bridge.latestPerformance.first_text_ms === undefined
                   ? "Esperando el primer texto" : "Recibiendo respuesta")
                  + " · " + Performance.duration(window.elapsedMs)
            color: "#72e5c0"
            font.pixelSize: 11
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 95
            TextArea {
                id: prompt
                placeholderText: window.bridge.authenticated ? "Escribe un mensaje…" : "Inicia sesión para conversar…"
                placeholderTextColor: "#788da2"
                color: "#edf4fa"
                font.pixelSize: 14
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                enabled: window.bridge.canSend
                background: Rectangle { color: "#192535"; radius: 8; border.color: "#314155" }
                // Enter envía; Shift+Enter conserva el salto de línea.
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && !(event.modifiers & Qt.ShiftModifier)) {
                        window.sendPrompt();
                        event.accepted = true;
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "v" + (window.bridge.appVersion || "…")
                      + (window.bridge.modelName ? " · " + window.bridge.modelName : " · ChatGPT")
                color: "#788da2"
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            ActionButton { text: "Detener"; enabled: window.bridge.busy; onClicked: window.bridge.cancel() }
            ActionButton {
                text: "Enviar"
                accent: true
                enabled: window.bridge.canSend && prompt.text.trim().length > 0 && prompt.text.length <= 16000
                onClicked: window.sendPrompt()
            }
        }
    }

    Connections {
        target: window.bridge
        function onPlanConnected() { planWelcome.open(); }
        function onBusyChanged() { window.elapsedMs = 0; }
        function onEventReceived(event) {
            if (event.type === "performance.updated"
                && event.data.measurement.turn_id === window.selectedPerformance.turn_id)
                window.selectedPerformance = event.data.measurement;
        }
    }
    Dialog {
        id: planWelcome
        title: "Tu plan de ChatGPT"
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, window.width - 48)
        standardButtons: Dialog.Ok
        contentItem: Text {
            text: "Estás usando tu plan de ChatGPT. Las respuestas de Agent Shell consumen sus límites disponibles. Puedes administrar el uso y desconectar la aplicación en los ajustes de ChatGPT."
            wrapMode: Text.Wrap
        }
    }

    Dialog {
        id: performanceDetails
        title: "Detalles de rendimiento"
        modal: true
        anchors.centerIn: parent
        width: Math.min(580, window.width - 40)
        height: Math.min(650, window.height - 40)
        standardButtons: Dialog.Close
        contentItem: ScrollView {
            TextArea {
                text: Performance.details(window.selectedPerformance)
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
            }
        }
    }

    Drawer {
        id: performancePanel
        width: Math.min(560, window.width - 40)
        height: window.height
        edge: Qt.RightEdge
        background: Rectangle { color: "#111d2a"; border.color: "#314155" }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            Text { text: "Rendimiento"; color: "#edf4fa"; font.pixelSize: 21; font.bold: true }
            Text {
                Layout.fillWidth: true
                text: "Últimos 200 turnos guardados. Las medianas y el p95 usan sólo respuestas completadas y tiempos del backend. Compara mensajes y contextos similares."
                color: "#96a9bb"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                ComboBox {
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
                        delegate: Rectangle {
                            id: modelCard
                            required property var modelData
                            width: performanceList.width
                            implicitHeight: modelStats.implicitHeight + 24
                            radius: 8
                            color: "#192535"
                            Column {
                                id: modelStats
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6
                                Text { text: modelCard.modelData.model; color: "#72e5c0"; font.bold: true }
                                Text {
                                    width: parent.width
                                    text: "Primer texto (mediana): " + Performance.duration(modelCard.modelData.firstMedian)
                                          + "\nTotal (mediana): " + Performance.duration(modelCard.modelData.totalMedian)
                                          + "\nTotal p95: " + (modelCard.modelData.totalP95 === null
                                              ? "Disponible desde 20 respuestas completadas" : Performance.duration(modelCard.modelData.totalP95))
                                    color: "#d8e5ee"
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }
                                Text {
                                    width: parent.width
                                    text: modelCard.modelData.completed + " completadas · " + modelCard.modelData.failed
                                          + " fallidas · " + modelCard.modelData.interrupted + " interrumpidas"
                                    color: "#96a9bb"
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: window.bridge.performanceHistory.length ? "Mediciones por respuesta" : "Envía un mensaje para registrar la primera medición. Los chats antiguos no tienen datos de rendimiento."
                        color: "#96a9bb"
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
                            color: "#d8e5ee"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: Performance.summary(measurementRow.modelData)
                            color: "#96a9bb"
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                        Text {
                            text: new Date(measurementRow.modelData.started_at).toLocaleString()
                            color: "#788da2"
                            font.pixelSize: 10
                        }
                    }
                    background: Rectangle { radius: 8; color: "#192535" }
                }
            }
        }
    }

    Drawer {
        id: historyPanel
        width: Math.min(360, window.width - 40)
        height: window.height
        edge: Qt.LeftEdge
        background: Rectangle { color: "#111d2a"; border.color: "#314155" }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14
            Text { text: "Historial de chats"; color: "#edf4fa"; font.pixelSize: 21; font.bold: true }
            Text {
                Layout.fillWidth: true
                visible: window.bridge.conversations.count === 0
                text: "Tus conversaciones aparecerán aquí al enviar el primer mensaje."
                color: "#96a9bb"
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
                delegate: ItemDelegate {
                    id: savedChat
                    required property string chatId
                    required property string title
                    required property string updatedAt
                    width: savedChats.width
                    enabled: window.bridge.canBrowseHistory
                    onClicked: {
                        window.bridge.openChat(chatId);
                        historyPanel.close();
                    }
                    contentItem: Column {
                        spacing: 6
                        Text {
                            width: parent.width
                            text: savedChat.title
                            color: "#d8e5ee"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Text {
                            text: new Date(savedChat.updatedAt).toLocaleString()
                            color: "#96a9bb"
                            font.pixelSize: 10
                        }
                    }
                    background: Rectangle {
                        radius: 8
                        color: savedChat.chatId === window.bridge.currentChatId ? "#263e44" : "#192535"
                    }
                }
            }
            Text { text: "Directorio del historial"; color: "#72e5c0"; font.pixelSize: 12 }
            TextArea {
                Layout.fillWidth: true
                text: window.bridge.historyDirectory
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: "#96a9bb"
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
        if (!bridge.canSend || !prompt.text.trim() || prompt.text.length > 16000) return;
        bridge.submit(prompt.text);
        prompt.clear();
    }
}
