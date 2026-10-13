import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: limit
    required property var windowData
    property string fallbackTitle: "Límite"
    property bool compact: false
    property double nowMs: Date.now()
    readonly property var used: windowData ? windowData.used_percent : null
    readonly property bool known: used !== null && used !== undefined
    readonly property double remaining: known ? Math.max(0, 100 - used) : 0
    spacing: compact ? 6 : 9

    function period(minutes) {
        if (!minutes) return fallbackTitle;
        if (compact) {
            if (minutes === 10080) return "Semanal";
            if (minutes % 1440 === 0) return (minutes / 1440) + (minutes === 1440 ? " día" : " días");
            if (minutes % 60 === 0) return (minutes / 60) + " h";
            return minutes + " min";
        }
        if (minutes === 10080) return "Límite semanal";
        if (minutes % 1440 === 0) return "Límite de " + (minutes / 1440) + (minutes === 1440 ? " día" : " días");
        if (minutes % 60 === 0) return "Límite de " + (minutes / 60) + (minutes === 60 ? " hora" : " horas");
        return "Límite de " + minutes + " minutos";
    }

    function renewal() {
        const reset = windowData ? windowData.resets_at : null;
        if (reset === null || reset === undefined) return "Renovación no informada";
        const minutes = Math.ceil((reset * 1000 - nowMs) / 60000);
        if (minutes <= 0) return "Renovación pendiente de actualizar";
        const days = Math.floor(minutes / 1440);
        const hours = Math.floor(minutes % 1440 / 60);
        const rest = minutes % 60;
        const parts = [];
        if (days) parts.push(days + " d");
        if (hours) parts.push(hours + " h");
        if (rest) parts.push(rest + " min");
        return "Se restablece en " + parts.slice(0, 2).join(" y ");
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: limit.period(limit.windowData ? limit.windowData.window_minutes : null)
            color: "#eeeeee"
            font.pixelSize: limit.compact ? 12 : 13
        }
        Text {
            objectName: "usageRemaining"
            text: limit.known ? Number(limit.remaining.toFixed(1)) + "% restante" : "Sin datos"
            color: "#bbbbbb"
            font.pixelSize: 12
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: limit.compact ? 3 : 5
        radius: 3
        color: "#24ffffff"
        Rectangle {
            objectName: "usageRemainingBar"
            width: parent.width * Math.min(100, limit.remaining) / 100
            height: parent.height
            radius: parent.radius
            color: "#dddddd"
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
    }
    Text {
        objectName: "usageDescription"
        Layout.fillWidth: true
        text: limit.compact ? limit.renewal()
              : (limit.known ? Number(limit.used.toFixed(1)) + "% usado" : "Consumo no informado") + " · " + limit.renewal()
        color: "#999999"
        font.pixelSize: limit.compact ? 10 : 11
        wrapMode: Text.Wrap
        HoverHandler { id: resetHover }
        ToolTip.visible: resetHover.hovered && !!limit.windowData
                         && limit.windowData.resets_at !== null && limit.windowData.resets_at !== undefined
        ToolTip.text: limit.windowData && limit.windowData.resets_at !== null && limit.windowData.resets_at !== undefined
                      ? (limit.known ? Number(limit.used.toFixed(1)) + "% usado · " : "")
                        + "Renovación: " + new Date(limit.windowData.resets_at * 1000).toLocaleString(Qt.locale("es_MX"), "d MMM yyyy · HH:mm")
                      : ""
    }
}
