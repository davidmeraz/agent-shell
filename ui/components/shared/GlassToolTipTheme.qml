import QtQuick
import QtQuick.Controls

// Aplica estilo Matte Glassmorphism al ToolTip compartido de toda la ventana (quita el fondo amarillo de Qt).
Item {
    id: themeHook
    width: 0
    height: 0
    visible: false

    Component {
        id: glassBackground
        Rectangle {
            radius: 9
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#ee161f2a" }
                GradientStop { position: 1.0; color: "#f20d131c" }
            }
            border.width: 1
            border.color: GemaTheme.synced ? GemaTheme.accentAlpha(0.45) : "#42ffffff"
        }
    }

    Component {
        id: glassLabel
        Text {
            property var ownerTip: null
            text: ownerTip ? ownerTip.text : ""
            textFormat: Text.PlainText
            color: "#eef4fb"
            font.pixelSize: 11
            wrapMode: Text.Wrap
            maximumLineCount: 8
            elide: Text.ElideRight
            style: Text.Raised
            styleColor: GemaTheme.textShadow
        }
    }

    Component {
        id: enterFade
        Transition {
            NumberAnimation {
                property: "opacity"
                from: 0.0; to: 1.0
                duration: GemaTheme.animations ? 110 : 0
                easing.type: Easing.OutCubic
            }
        }
    }

    Component {
        id: exitFade
        Transition {
            NumberAnimation {
                property: "opacity"
                from: 1.0; to: 0.0
                duration: GemaTheme.animations ? 90 : 0
                easing.type: Easing.InCubic
            }
        }
    }

    function applyTheme() {
        const tip = themeHook.ToolTip.toolTip;
        if (!tip) return;
        if (tip.objectName === "gemaGlassToolTip" && tip.background && tip.contentItem) return;
        const popupHost = (tip.contentItem && tip.contentItem.parent)
            || (tip.background && tip.background.parent)
            || themeHook;
        tip.objectName = "gemaGlassToolTip";
        tip.leftPadding = 10;
        tip.rightPadding = 10;
        tip.topPadding = 6;
        tip.bottomPadding = 6;
        tip.margins = 8;
        tip.palette.toolTipBase = "#eb141c26";
        tip.palette.toolTipText = "#eef4fb";
        tip.background = glassBackground.createObject(popupHost);
        tip.contentItem = glassLabel.createObject(popupHost, { ownerTip: tip });
        tip.enter = enterFade.createObject(tip);
        tip.exit = exitFade.createObject(tip);
    }

    Window.onWindowChanged: Qt.callLater(themeHook.applyTheme)
    Component.onCompleted: Qt.callLater(themeHook.applyTheme)
}
