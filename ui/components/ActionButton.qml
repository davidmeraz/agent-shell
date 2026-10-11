import QtQuick
import QtQuick.Controls

// Botón compartido para mantener coherentes foco, estado deshabilitado y color.
Button {
    id: control
    property bool accent: false
    horizontalPadding: 14
    verticalPadding: 10
    hoverEnabled: true
    font.pixelSize: 13
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? (control.accent ? "#b3f5df" : "#edf4fa") : "#899aab"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: GlassPanel {
        radius: 10
        topColor: control.down ? "#80365151"
                  : control.accent && control.enabled ? "#70408273"
                  : control.hovered && control.enabled ? "#70445669" : "#44304153"
        bottomColor: control.accent && control.enabled ? "#5030564f" : "#30172334"
        edgeColor: control.accent && control.enabled ? "#7072e5c0" : "#38ffffff"
        highlighted: control.activeFocus
        opacity: control.enabled ? 1 : 0.55
    }
}
