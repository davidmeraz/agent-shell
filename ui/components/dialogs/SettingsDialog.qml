import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Centro unificado de ajustes accesibles desde la barra lateral.
GlassDialog {
    id: dialog
    required property AgentBridge bridge
    signal limitsRequested()
    signal shellRequested()
    signal accountRequested()
    signal usageRequested()
    signal commandsRequested()

    title: "Ajustes"
    modal: true
    standardButtons: Dialog.Close

    component SettingsRow: Button {
        id: rowButton
        property string iconText: "⚙"
        property string titleText: ""
        property string subtitleText: ""
        property string badgeText: ""
        Layout.fillWidth: true
        implicitHeight: 50
        padding: 10
        hoverEnabled: true
        scale: down ? 0.985 : (hovered ? 1.008 : 1.0)
        Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 130 : 0; easing.type: Easing.OutCubic } }
        contentItem: RowLayout {
            spacing: 11
            GlassPanel {
                implicitWidth: 30
                implicitHeight: 30
                radius: 9
                reflective: false
                topColor: rowButton.hovered
                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2cffffff")
                    : (GemaTheme.synced ? GemaTheme.accentAlpha(0.14) : "#18ffffff")
                bottomColor: "#0affffff"
                edgeColor: rowButton.hovered
                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.60) : "#58ffffff")
                    : "#2cffffff"
                Text {
                    anchors.centerIn: parent
                    text: rowButton.iconText
                    color: rowButton.hovered ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : GemaTheme.textColor
                    font.pixelSize: 13
                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: rowButton.titleText
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: GemaTheme.textColor
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
                Text {
                    Layout.fillWidth: true
                    text: rowButton.subtitleText
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    color: GemaTheme.subtleColor
                    font.pixelSize: 10
                }
            }
            GlassPanel {
                visible: !!rowButton.badgeText
                implicitWidth: badgeLabel.implicitWidth + 12
                implicitHeight: 20
                radius: 7
                reflective: false
                topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#18ffffff"
                bottomColor: "#08ffffff"
                edgeColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.38) : "#2cffffff"
                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: rowButton.badgeText
                    textFormat: Text.PlainText
                    color: GemaTheme.synced ? GemaTheme.accentInk : GemaTheme.mutedColor
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            Text {
                text: "›"
                color: rowButton.hovered ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : GemaTheme.subtleColor
                font.pixelSize: 18
                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            }
        }
        background: GlassPanel {
            radius: 12
            reflective: false
            highlighted: rowButton.hovered || rowButton.activeFocus
            topColor: rowButton.hovered
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.20) : "#24ffffff")
                : "#14ffffff"
            bottomColor: "#0affffff"
            edgeColor: rowButton.hovered
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.54) : "#50ffffff")
                : "#26ffffff"
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        GlassPanel {
            objectName: "settingsProviderCard"
            Layout.fillWidth: true
            implicitHeight: providerCol.implicitHeight + 20
            radius: 12
            reflective: false
            topColor: "#14ffffff"
            bottomColor: "#0affffff"
            edgeColor: "#26ffffff"
            ColumnLayout {
                id: providerCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "Motor de IA"
                        textFormat: Text.PlainText
                        color: GemaTheme.textColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    Text {
                        text: dialog.bridge.provider === "agy"
                            ? "Gemini · Antigravity (agy)"
                            : dialog.bridge.provider === "claude"
                              ? (dialog.bridge.claudeAuthenticated
                                 ? "Claude Code" + (dialog.bridge.claudePlan ? " · " + dialog.bridge.claudePlan : "")
                                 : "Claude · Sin sesión")
                              : (dialog.bridge.authenticated ? "Plan ChatGPT" : "Sin sesión")
                        textFormat: Text.PlainText
                        color: GemaTheme.subtleColor
                        font.pixelSize: 10
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    readonly property bool canSwitch: dialog.bridge.ready && !dialog.bridge.busy
                        && !dialog.bridge.loginBusy && !dialog.bridge.claudeLoginBusy && !dialog.bridge.accountBusy
                        && !dialog.bridge.providerBusy && !dialog.bridge.projectRunPreparing
                    Button {
                        id: chatgptProviderBtn
                        objectName: "settingsProviderChatgpt"
                        Layout.fillWidth: true
                        implicitHeight: 34
                        hoverEnabled: true
                        enabled: parent.canSwitch
                        readonly property bool active: dialog.bridge.provider === "chatgpt"
                        onClicked: dialog.bridge.selectProvider("chatgpt")
                        contentItem: Text {
                            text: (chatgptProviderBtn.active ? "◎ " : "") + "ChatGPT"
                            textFormat: Text.PlainText
                            color: chatgptProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                                : GemaTheme.mutedColor
                            font.pixelSize: 11
                            font.weight: chatgptProviderBtn.active ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: GlassPanel {
                            radius: 9
                            reflective: false
                            highlighted: chatgptProviderBtn.active || chatgptProviderBtn.hovered
                            topColor: chatgptProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2cffffff")
                                : (chatgptProviderBtn.hovered ? "#1effffff" : "#10ffffff")
                            bottomColor: "#08ffffff"
                            edgeColor: chatgptProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.62) : "#58ffffff")
                                : "#24ffffff"
                        }
                    }
                    Button {
                        id: agyProviderBtn
                        objectName: "settingsProviderAgy"
                        Layout.fillWidth: true
                        implicitHeight: 34
                        hoverEnabled: true
                        enabled: parent.canSwitch && dialog.bridge.agyAvailable
                        readonly property bool active: dialog.bridge.provider === "agy"
                        onClicked: dialog.bridge.selectProvider("agy")
                        ToolTip.visible: hovered && !dialog.bridge.agyAvailable
                        ToolTip.text: "Instala e inicia sesión en Antigravity CLI (`agy`) para habilitar Gemini."
                        contentItem: Text {
                            text: (agyProviderBtn.active ? "✦ " : "")
                                + (dialog.bridge.agyAvailable ? "Gemini" : "Gemini (n/d)")
                            textFormat: Text.PlainText
                            color: !dialog.bridge.agyAvailable ? "#777777"
                                : agyProviderBtn.active
                                  ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                                  : GemaTheme.mutedColor
                            font.pixelSize: 11
                            font.weight: agyProviderBtn.active ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: GlassPanel {
                            radius: 9
                            reflective: false
                            highlighted: agyProviderBtn.active || agyProviderBtn.hovered
                            topColor: agyProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2cffffff")
                                : (agyProviderBtn.hovered ? "#1effffff" : "#10ffffff")
                            bottomColor: "#08ffffff"
                            edgeColor: agyProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.62) : "#58ffffff")
                                : "#24ffffff"
                        }
                    }
                    Button {
                        id: claudeProviderBtn
                        objectName: "settingsProviderClaude"
                        Layout.fillWidth: true
                        implicitHeight: 34
                        hoverEnabled: true
                        enabled: parent.canSwitch && dialog.bridge.claudeAvailable
                        readonly property bool active: dialog.bridge.provider === "claude"
                        onClicked: dialog.bridge.selectProvider("claude")
                        ToolTip.visible: hovered && !dialog.bridge.claudeAvailable
                        ToolTip.text: "Instala Claude Code CLI (`claude`) para habilitar este motor."
                        contentItem: Text {
                            text: (claudeProviderBtn.active ? "◆ " : "")
                                + (dialog.bridge.claudeAvailable ? "Claude" : "Claude (n/d)")
                            textFormat: Text.PlainText
                            color: !dialog.bridge.claudeAvailable ? "#777777"
                                : claudeProviderBtn.active
                                  ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                                  : GemaTheme.mutedColor
                            font.pixelSize: 11
                            font.weight: claudeProviderBtn.active ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: GlassPanel {
                            radius: 9
                            reflective: false
                            highlighted: claudeProviderBtn.active || claudeProviderBtn.hovered
                            topColor: claudeProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.28) : "#2cffffff")
                                : (claudeProviderBtn.hovered ? "#1effffff" : "#10ffffff")
                            bottomColor: "#08ffffff"
                            edgeColor: claudeProviderBtn.active
                                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.62) : "#58ffffff")
                                : "#24ffffff"
                        }
                    }
                }
            }
        }

        SettingsRow {
            objectName: "settingsLimitsRow"
            iconText: "◈"
            titleText: "Límites de tokens y compactación"
            subtitleText: "Compactación: " + (dialog.bridge.compactThresholdTokens > 0
                ? Math.round(dialog.bridge.compactThresholdTokens / 1000) + "k tokens"
                : "desactivada") + " · Máx. pasos: " + dialog.bridge.maxSteps
            badgeText: dialog.bridge.limitsProfile
                ? dialog.bridge.limitsProfile.charAt(0).toUpperCase() + dialog.bridge.limitsProfile.slice(1)
                : ""
            enabled: dialog.bridge.ready && !dialog.bridge.busy && !dialog.bridge.loginBusy
            onClicked: { dialog.close(); dialog.limitsRequested(); }
        }

        SettingsRow {
            objectName: "settingsShellRow"
            iconText: "⌘"
            titleText: "Terminal y carpeta de trabajo"
            subtitleText: dialog.bridge.workspace || "Directorio actual"
            badgeText: dialog.bridge.agentShellTimeout + " s"
            enabled: dialog.bridge.canSelectArea && dialog.bridge.workspaceSelected
            onClicked: { dialog.close(); dialog.shellRequested(); }
        }

        SettingsRow {
            objectName: "settingsProfileRow"
            iconText: "◎"
            titleText: "Perfil y cuenta"
            subtitleText: dialog.bridge.displayName
                ? "Nombre visible: " + dialog.bridge.displayName
                : "Configurar nombre de usuario y sesión de ChatGPT"
            badgeText: dialog.bridge.authenticated ? "Activa" : ""
            onClicked: { dialog.close(); dialog.accountRequested(); }
        }

        SettingsRow {
            objectName: "settingsUsageRow"
            visible: dialog.bridge.engineReady
            iconText: "◔"
            titleText: "Uso del plan"
            subtitleText: dialog.bridge.provider === "agy"
                ? "Cuotas por grupo de modelos en Antigravity (Gemini y Claude)"
                : dialog.bridge.provider === "claude"
                  ? "Sesión actual (5 h) y cuota semanal de Claude"
                  : "Ventana de cuotas 5 h y límite semanal"
            onClicked: { dialog.close(); dialog.usageRequested(); }
        }

        SettingsRow {
            objectName: "settingsCommandsRow"
            iconText: "／"
            titleText: "Comandos y atajos"
            subtitleText: "Ver comandos /modelo, /shell, /compact, /limites y más"
            onClicked: { dialog.close(); dialog.commandsRequested(); }
        }

        GlassPanel {
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: 40
            radius: 11
            reflective: false
            topColor: "#10ffffff"
            bottomColor: "#06ffffff"
            edgeColor: "#22ffffff"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8
                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: GemaTheme.accent
                    border.width: 1
                    border.color: "#55ffffff"
                }
                Text {
                    Layout.fillWidth: true
                    text: GemaTheme.synced
                        ? "Tema Gema · " + GemaTheme.gemName + (GemaTheme.animations ? " · Animaciones" : " · Sin animaciones")
                        : "Tema base · Matte Glassmorphism"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: GemaTheme.subtleColor
                    font.pixelSize: 11
                }
                Text {
                    text: "v" + (dialog.bridge.appVersion || "…")
                    textFormat: Text.PlainText
                    color: GemaTheme.subtleColor
                    font.pixelSize: 10
                }
            }
        }
    }
}
