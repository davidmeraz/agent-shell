import QtQuick
import QtQuick.Controls

// Botón compartido para mantener coherentes foco, estado deshabilitado y color.
Button {
    id: control
    property bool accent: false
    padding: 12
    font.pixelSize: 13
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? (control.accent ? "#09211e" : "#d8e5ee") : "#697a8b"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 8
        color: control.enabled && control.accent ? "#72e5c0"
               : control.hovered ? "#263547" : "#192535"
        border.color: control.activeFocus ? "#72e5c0" : "#314155"
        opacity: control.enabled ? 1 : 0.5
    }
}
