import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    property bool opensAbove: false
    implicitHeight: 40
    hoverEnabled: true
    font.pixelSize: 13
    leftPadding: 14
    rightPadding: 36
    topPadding: 10
    bottomPadding: 10

    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled ? "#edf4fa" : "#899aab"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 14
        y: (control.height - height) / 2
        text: control.opensAbove ? "⌃" : "⌄"
        font.pixelSize: 18
        color: control.enabled ? "#b3f5df" : "#899aab"
    }
    background: GlassPanel {
        implicitWidth: 180
        implicitHeight: 40
        radius: 10
        highlighted: control.activeFocus || control.popup.visible
        topColor: control.hovered ? "#70445669" : "#44304153"
        bottomColor: "#30172334"
        opacity: control.enabled ? 1 : 0.55
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        width: control.width - 12
        highlighted: control.highlightedIndex === index
        hoverEnabled: true
        contentItem: Text {
            text: control.textAt(option.index)
            font: control.font
            color: "#edf4fa"
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: GlassPanel {
            radius: 8
            visible: option.highlighted || option.hovered
            topColor: "#70408273"
            bottomColor: "#3030564f"
            edgeColor: "#5072e5c0"
        }
    }
    popup: Popup {
        y: control.opensAbove ? -implicitHeight - 6 : control.height + 6
        width: control.width
        padding: 6
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(contentHeight, 280)
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: GlassPanel {
            topColor: "#f02a3a4b"
            bottomColor: "#f0172433"
        }
    }
}
