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
        color: control.enabled ? (control.accent ? "#ffffff" : "#f5f5f5") : "#888888"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: GlassPanel {
        radius: 10
        topColor: control.down ? "#80555555"
                  : control.accent && control.enabled ? "#70707070"
                  : control.hovered && control.enabled ? "#70555555" : "#443c3c3c"
        bottomColor: control.accent && control.enabled ? "#504d4d4d" : "#30202020"
        edgeColor: control.accent && control.enabled ? "#70ffffff" : "#38ffffff"
        highlighted: control.activeFocus
        opacity: control.enabled ? 1 : 0.55
    }
}
