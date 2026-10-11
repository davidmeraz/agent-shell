import QtQuick
import QtQuick.Controls

ActionButton {
    id: control
    property bool expanded: false
    readonly property string description: expanded ? "Ocultar barra lateral" : "Mostrar barra lateral"
    horizontalPadding: 10
    verticalPadding: 10
    Accessible.name: description
    ToolTip.visible: hovered
    ToolTip.text: description
    ToolTip.delay: 500

    contentItem: Item {
        implicitWidth: 18
        implicitHeight: 18
        Rectangle {
            anchors.centerIn: parent
            width: 18
            height: 16
            radius: 3
            color: "transparent"
            border.width: 1
            border.color: control.expanded ? "#b3f5df" : "#d8e5ee"
            Rectangle {
                x: 2; y: 2; width: 4; height: 12; radius: 1
                color: control.expanded ? "#5072e5c0" : "#18ffffff"
            }
            Rectangle { x: 7; y: 1; width: 1; height: 14; color: "#8096a9bb" }
        }
    }
}
