import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../../js/Performance.js" as Performance
import "../shared"

// Dock inferior sobre el editor: cuota gastada por IA en este chat + selector de motor.
ColumnLayout {
    id: dock
    objectName: "providerSwitcher"
    required property AgentBridge bridge
    readonly property int tabCount: 1 + (bridge.agyAvailable ? 1 : 0) + (bridge.claudeAvailable ? 1 : 0)
    readonly property int barWidth: tabCount >= 3 ? 276 : 204
    readonly property bool hasAnyQuota: {
        const q = bridge.chatQuota;
        if (!q) return false;
        for (const key of ["chatgpt", "agy", "claude"]) {
            const entry = q[key];
            if (entry && (entry.turns > 0 || entry.session_pct > 0 || entry.weekly_pct > 0))
                return true;
        }
        return false;
    }
    readonly property bool showQuotaRow: !!bridge.currentChatId || hasAnyQuota
    readonly property bool canSwitch: bridge.ready && !bridge.busy && !bridge.loginBusy
                                      && !bridge.claudeLoginBusy && !bridge.accountBusy
                                      && !bridge.providerBusy && !bridge.projectRunPreparing
    implicitWidth: barWidth
    spacing: 4

    function quotaEntry(providerId) {
        const q = bridge.chatQuota;
        if (q && q[providerId]) return q[providerId];
        return { session_pct: 0, weekly_pct: 0, turns: 0, tokens: 0 };
    }

    function formatPct(value) {
        const num = typeof value === "number" && isFinite(value) && value > 0 ? value : 0;
        if (num === 0) return "0%";
        if (num < 10) return Number(num.toFixed(1)) + "%";
        return Math.round(num) + "%";
    }

    function badgeText(entry) {
        if (!entry || entry.turns <= 0) return "0%";
        if (entry.session_pct > 0) return formatPct(entry.session_pct);
        if (entry.weekly_pct > 0) return formatPct(entry.weekly_pct) + " sem";
        return "0%";
    }

    function quotaTooltip(label, entry) {
        if (!entry || entry.turns <= 0)
            return label + " · Sin consumo en este chat";
        const parts = [
            "Gastado en este chat · " + label,
            "Sesión (5 h): " + formatPct(entry.session_pct) + " · Semanal: " + formatPct(entry.weekly_pct),
            "Turnos: " + entry.turns + (entry.tokens > 0 ? " · Tokens: " + Performance.tokens(entry.tokens) : "")
        ];
        return parts.join("\n");
    }

    component QuotaSlot: Item {
        id: slot
        required property string providerId
        required property string engineLabel
        readonly property var entry: dock.quotaEntry(providerId)
        readonly property bool used: entry.turns > 0 || entry.session_pct > 0 || entry.weekly_pct > 0
        readonly property bool activeEngine: dock.bridge.provider === providerId
        readonly property bool measuring: activeEngine && dock.bridge.chatQuotaMeasuring
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 19

        GlassPanel {
            id: pill
            anchors.centerIn: parent
            implicitWidth: Math.min(parent.width - 4, Math.max(36, badgeLabel.implicitWidth + 14))
            implicitHeight: 18
            radius: 6
            reflective: false
            visible: slot.used || slot.activeEngine
            topColor: slot.used && slot.activeEngine
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#22ffffff")
                : slot.used ? "#16ffffff" : "#0cffffff"
            bottomColor: "#06ffffff"
            edgeColor: slot.used && slot.activeEngine
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.48) : "#48ffffff")
                : slot.used ? "#2cffffff" : "#1cffffff"

            SequentialAnimation on opacity {
                running: slot.measuring && GemaTheme.animations
                loops: Animation.Infinite
                onRunningChanged: if (!running) pill.opacity = 1.0
                NumberAnimation { from: 1.0; to: 0.45; duration: 480; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1.0; duration: 480; easing.type: Easing.InOutSine }
            }

            Text {
                id: badgeLabel
                objectName: "chatQuotaBadge_" + slot.providerId
                anchors.centerIn: parent
                text: dock.badgeText(slot.entry)
                textFormat: Text.PlainText
                color: slot.used && slot.activeEngine
                    ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                    : slot.used ? "#dce4ee" : "#8e9aa8"
                font.pixelSize: 10
                font.weight: slot.used ? Font.DemiBold : Font.Normal
                style: Text.Raised
                styleColor: GemaTheme.textShadow
            }
        }

        Text {
            objectName: "chatQuotaIdle_" + slot.providerId
            anchors.centerIn: parent
            visible: !slot.used && !slot.activeEngine
            text: "0%"
            textFormat: Text.PlainText
            color: "#60a8b6c6"
            font.pixelSize: 10
        }

        HoverHandler { id: slotHover }
        ToolTip.visible: slotHover.hovered
        ToolTip.delay: 300
        ToolTip.text: dock.quotaTooltip(slot.engineLabel, slot.entry)
    }

    component EngineTab: Button {
        id: tab
        required property AgentBridge bridge
        required property string providerId
        required property string iconSymbol
        required property string tipText
        readonly property bool selected: bridge.provider === providerId
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        padding: 0
        hoverEnabled: true
        enabled: dock.canSwitch
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

    // Fila superior de cuotas gastadas en este chat, alineada columna por columna sobre cada motor.
    RowLayout {
        objectName: "chatQuotaStrip"
        Layout.minimumWidth: dock.barWidth - 4
        Layout.maximumWidth: dock.barWidth - 4
        Layout.preferredWidth: dock.barWidth - 4
        Layout.alignment: Qt.AlignHCenter
        visible: dock.showQuotaRow
        spacing: 3
        QuotaSlot {
            providerId: "chatgpt"
            engineLabel: "ChatGPT"
        }
        QuotaSlot {
            visible: dock.bridge.agyAvailable
            providerId: "agy"
            engineLabel: "Gemini (agy)"
        }
        QuotaSlot {
            visible: dock.bridge.claudeAvailable
            providerId: "claude"
            engineLabel: "Claude Code"
        }
    }

    // Cápsula inferior para cambiar entre ChatGPT, Gemini y Claude.
    GlassPanel {
        id: switcherBar
        objectName: "providerSwitcherBar"
        Layout.minimumWidth: dock.barWidth
        Layout.maximumWidth: dock.barWidth
        Layout.preferredWidth: dock.barWidth
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: dock.barWidth
        implicitHeight: 28
        radius: 10
        reflective: true
        topColor: "#14ffffff"
        bottomColor: "#0affffff"
        edgeColor: "#2effffff"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 3
            EngineTab {
                objectName: "providerChatgptButton"
                text: "ChatGPT"
                providerId: "chatgpt"
                iconSymbol: "◎"
                tipText: dock.bridge.authenticated
                    ? "Usar ChatGPT (sesión activa)"
                    : "Cambiar a ChatGPT"
                bridge: dock.bridge
            }
            EngineTab {
                objectName: "providerGeminiButton"
                visible: dock.bridge.agyAvailable
                text: "Gemini"
                providerId: "agy"
                iconSymbol: "✦"
                tipText: "Usar Gemini y modelos de Antigravity (agy)"
                bridge: dock.bridge
            }
            EngineTab {
                objectName: "providerClaudeButton"
                visible: dock.bridge.claudeAvailable
                text: "Claude"
                providerId: "claude"
                iconSymbol: "◆"
                tipText: dock.bridge.claudeAuthenticated
                    ? "Usar Claude Code" + (dock.bridge.claudePlan ? " (" + dock.bridge.claudePlan + ")" : "")
                    : "Usar Claude Code (requiere iniciar sesión)"
                bridge: dock.bridge
            }
        }
    }
}
