import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Selector global de motor de IA (ChatGPT / Gemini / Claude) centrado bajo WorkspaceSwitcher.
GlassPanel {
    id: switcher
    objectName: "providerSwitcher"
    required property AgentBridge bridge
    readonly property int tabCount: 1 + (bridge.agyAvailable ? 1 : 0) + (bridge.claudeAvailable ? 1 : 0)
    implicitWidth: tabCount >= 3 ? 276 : 204
    implicitHeight: 28
    radius: 10
    reflective: true
    topColor: "#14ffffff"
    bottomColor: "#0affffff"
    edgeColor: "#2effffff"

    readonly property bool canSwitch: bridge.ready && !bridge.busy && !bridge.loginBusy
                                      && !bridge.claudeLoginBusy && !bridge.accountBusy
                                      && !bridge.providerBusy && !bridge.projectRunPreparing

    component EngineTab: Button {
        id: tab
        required property AgentBridge bridge
        required property string providerId
        required property string iconSymbol
        required property string tipText
        readonly property bool selected: bridge.provider === providerId
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 0
        hoverEnabled: true
        enabled: switcher.canSwitch
                 && (providerId !== "agy" || bridge.agyAvailable)
                 && (providerId !== "claude" || bridge.claudeAvailable)
        scale: tab.down ? 0.96 : (tab.hovered && !tab.selected ? 1.03 : 1.0)
        Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
        onClicked: {
            if (!selected) bridge.selectProvider(providerId);
        }
        ToolTip.visible: hovered
        ToolTip.delay: 420
        ToolTip.text: tipText
        contentItem: RowLayout {
            spacing: 5
            Item { Layout.fillWidth: true }
            Text {
                text: tab.iconSymbol
                color: tab.selected ? (GemaTheme.synced ? GemaTheme.accent : "#ffffff") : (tab.hovered ? "#e0e6f0" : "#9aa4b4")
                font.pixelSize: 10
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            }
            Text {
                text: tab.text
                textFormat: Text.PlainText
                color: tab.selected ? GemaTheme.textColor : (tab.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                font.pixelSize: 11
                font.weight: tab.selected ? Font.Bold : Font.Medium
                style: Text.Raised
                styleColor: GemaTheme.textShadow
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            }
            Item { Layout.fillWidth: true }
        }
        background: Rectangle {
            radius: 7.5
            color: tab.selected ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#24ffffff")
                   : tab.hovered ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.10) : "#12ffffff") : "transparent"
            border.width: tab.selected || tab.activeFocus || tab.hovered ? 1 : 0
            border.color: tab.activeFocus ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.75) : "#70ffffff")
                          : tab.selected ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.52) : "#40ffffff")
                          : (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#18ffffff")
            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
            Behavior on border.color { ColorAnimation { duration: GemaTheme.animDuration } }
        }
        Accessible.name: text
        Accessible.description: tipText
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 3
        EngineTab {
            objectName: "providerChatgptButton"
            text: "ChatGPT"
            providerId: "chatgpt"
            iconSymbol: "◎"
            tipText: switcher.bridge.authenticated
                ? "Usar ChatGPT (sesión activa)"
                : "Cambiar a ChatGPT"
            bridge: switcher.bridge
        }
        EngineTab {
            objectName: "providerGeminiButton"
            visible: switcher.bridge.agyAvailable
            text: "Gemini"
            providerId: "agy"
            iconSymbol: "✦"
            tipText: "Usar Gemini y modelos de Antigravity (agy)"
            bridge: switcher.bridge
        }
        EngineTab {
            objectName: "providerClaudeButton"
            visible: switcher.bridge.claudeAvailable
            text: "Claude"
            providerId: "claude"
            iconSymbol: "◆"
            tipText: switcher.bridge.claudeAuthenticated
                ? "Usar Claude Code" + (switcher.bridge.claudePlan ? " (" + switcher.bridge.claudePlan + ")" : "")
                : "Usar Claude Code (requiere iniciar sesión)"
            bridge: switcher.bridge
        }
    }
}
