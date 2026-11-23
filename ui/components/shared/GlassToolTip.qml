import QtQuick
import QtQuick.Controls

// Tooltip translúcido Gema (sin el fondo amarillo nativo de Qt).
ToolTip {
    id: tip
    leftPadding: 10
    rightPadding: 10
    topPadding: 6
    bottomPadding: 6
    margins: 8
    palette.toolTipBase: "#eb141c26"
    palette.toolTipText: "#eef4fb"

    contentItem: Text {
        text: tip.text
        textFormat: Text.PlainText
        color: "#eef4fb"
        font.pixelSize: 11
        wrapMode: Text.Wrap
        maximumLineCount: 8
        elide: Text.ElideRight
        style: Text.Raised
        styleColor: GemaTheme.textShadow
    }

    background: Rectangle {
        radius: 9
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ee161f2a" }
            GradientStop { position: 1.0; color: "#f20d131c" }
        }
        border.width: 1
        border.color: GemaTheme.synced ? GemaTheme.accentAlpha(0.45) : "#42ffffff"
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0; to: 1.0
            duration: GemaTheme.animations ? 110 : 0
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0; to: 0.0
            duration: GemaTheme.animations ? 90 : 0
            easing.type: Easing.InCubic
        }
    }
}
