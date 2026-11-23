import QtQuick
import QtQuick.Controls

// Botón Glassmorphism interactivo con relieve de texto y micro-animaciones estilo Gema.
Button {
    id: control
    property bool accent: false
    horizontalPadding: 14
    verticalPadding: 10
    hoverEnabled: true
    font.pixelSize: 13
    scale: control.down ? 0.97 : (control.hovered && control.enabled ? 1.015 : 1.0)
    Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
    contentItem: Text {
        text: control.text
        font.family: control.font.family
        font.pixelSize: control.font.pixelSize
        font.weight: control.accent || control.hovered ? Font.DemiBold : Font.Medium
        color: !control.enabled ? "#888888"
               : control.accent ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
               : GemaTheme.textColor
        style: Text.Raised
        styleColor: GemaTheme.textShadow
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
    }
    background: GlassPanel {
        radius: 10
        topColor: control.down ? "#36ffffff"
                  : control.accent && control.enabled ? (GemaTheme.synced ? GemaTheme.accentAlpha(control.hovered ? 0.42 : 0.30) : "#30ffffff")
                  : control.hovered && control.enabled ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#28ffffff") : "#1cffffff"
        bottomColor: control.accent && control.enabled
                     ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.18) : "#1cffffff")
                     : "#22060a10"
        edgeColor: control.accent && control.enabled ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.85) : "#80ffffff")
                   : control.hovered && control.enabled ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.68) : "#68ffffff") : "#48ffffff"
        highlighted: control.activeFocus || (control.hovered && control.accent)
        opacity: control.enabled ? 1 : 0.55
    }
}
