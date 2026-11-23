import QtQuick
import AgentShell.Native

// Medallón de perfil personal sincronizado con el tema Gema y el nombre de usuario elegido.
Item {
    id: avatar
    property string customName: ""
    property string plan: ""
    property int size: 26
    property bool connected: true
    property bool showStatusDot: false

    readonly property string rawHandle: {
        const custom = (customName || "").trim();
        if (custom)
            return custom;
        const sysUser = NativeApp.env("USER") || "";
        if (sysUser)
            return sysUser;
        return "Tú";
    }

    readonly property string displayName: {
        const custom = (customName || "").trim();
        if (custom)
            return custom;
        const cleaned = rawHandle.replace(/[._-]+/g, " ").trim();
        if (!cleaned) return "Tú";
        return cleaned.split(/\s+/).map(part => {
            if (!part) return "";
            return part.charAt(0).toUpperCase() + part.slice(1);
        }).join(" ");
    }

    readonly property string initials: {
        const parts = displayName.split(/\s+/).filter(p => p.length > 0);
        if (parts.length >= 2)
            return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase();
        return displayName.slice(0, 1).toUpperCase() || "T";
    }

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        border.width: 1
        border.color: avatar.connected
            ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.70) : "#68ffffff")
            : "#38ffffff"
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: avatar.connected
                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.42) : "#38c4dcff")
                    : "#24ffffff"
            }
            GradientStop {
                position: 1.0
                color: avatar.connected
                    ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#16c4dcff")
                    : "#10ffffff"
            }
        }

        // Reflejo superior sutil estilo vidrio esmerilado.
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 2
            width: parent.width * 0.54
            height: Math.max(3, parent.height * 0.22)
            radius: height / 2
            color: "#30ffffff"
        }

        Text {
            anchors.centerIn: parent
            text: avatar.initials
            color: GemaTheme.darkText ? GemaTheme.textColor : "#ffffff"
            font.pixelSize: Math.max(10, Math.round(avatar.size * (avatar.initials.length > 1 ? 0.39 : 0.46)))
            font.weight: Font.Bold
            style: Text.Raised
            styleColor: GemaTheme.textShadow
        }
    }

    Rectangle {
        visible: avatar.showStatusDot
        width: 8
        height: 8
        radius: 4
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        color: avatar.connected ? (GemaTheme.synced ? GemaTheme.accent : "#8be9fd") : "#777777"
        border.width: 1.5
        border.color: "#cc101620"
    }
}
