import QtQuick
import QtQuick.Controls
import Quickshell

// Copia el texto original, incluido Markdown y código, sin cambiar su selección.
Button {
    id: control
    required property string textToCopy
    property string copyLabel: "Copiar respuesta"
    property string copiedLabel: "Respuesta copiada"
    property bool copied: false
    implicitWidth: 28
    implicitHeight: 28
    padding: 6
    hoverEnabled: true
    enabled: textToCopy.length > 0
    Accessible.name: copied ? copiedLabel : copyLabel
    ToolTip.visible: hovered
    ToolTip.delay: 400
    ToolTip.text: copied ? "Copiado" : copyLabel
    onClicked: {
        Quickshell.clipboardText = textToCopy;
        copied = true;
        feedback.restart();
    }
    Timer { id: feedback; interval: 1600; onTriggered: control.copied = false }
    contentItem: Item {
        Rectangle {
            x: 2; y: 1; width: 9; height: 10; radius: 2
            visible: !control.copied
            color: "transparent"
            border.width: 1
            border.color: control.hovered ? "#eeeeee" : "#999999"
        }
        Rectangle {
            x: 5; y: 4; width: 9; height: 10; radius: 2
            visible: !control.copied
            color: "#252525"
            border.width: 1
            border.color: control.hovered ? "#eeeeee" : "#999999"
        }
        Text {
            anchors.centerIn: parent
            visible: control.copied
            text: "✓"
            color: "#eeeeee"
            font.pixelSize: 14
        }
    }
    background: Rectangle {
        radius: 6
        color: control.down ? "#24ffffff" : control.hovered ? "#12ffffff" : "transparent"
        border.width: control.visualFocus ? 1 : 0
        border.color: "#60ffffff"
    }
}
