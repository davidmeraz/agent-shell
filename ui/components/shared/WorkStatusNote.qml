import QtQuick
import QtQuick.Layouts

// Pulso armonizado con GemaTheme sólo durante trabajo visible; no anima en segundo plano.
RowLayout {
    id: note
    required property string text
    required property bool busy
    required property bool windowVisible
    property real pulse: 0.55
    property real haloScale: 0.8
    property real haloOpacity: 0.0
    spacing: 8
    Item {
        Layout.preferredWidth: 12
        Layout.preferredHeight: 12
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
            anchors.centerIn: parent
            width: 12
            height: 12
            radius: 6
            color: GemaTheme.accent
            visible: note.busy && note.windowVisible
            scale: note.haloScale
            opacity: note.haloOpacity
        }
        Rectangle {
            anchors.centerIn: parent
            width: 6
            height: 6
            radius: 3
            color: note.busy ? GemaTheme.accent : GemaTheme.accentAlpha(0.55)
            opacity: note.busy ? note.pulse : 0.7
            border.width: 1
            border.color: note.busy ? "#66ffffff" : "transparent"
            Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
        }
    }
    Text {
        id: label
        Layout.fillWidth: true
        text: note.text
        textFormat: Text.PlainText
        font.pixelSize: 11
        font.weight: note.busy ? Font.Medium : Font.Normal
        color: note.busy ? GemaTheme.mutedColor : GemaTheme.subtleColor
        style: Text.Raised
        styleColor: GemaTheme.textShadow
        elide: Text.ElideRight
        Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
    }
    ParallelAnimation {
        running: note.busy && note.windowVisible
        loops: Animation.Infinite
        SequentialAnimation {
            NumberAnimation { target: note; property: "pulse"; from: 0.55; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { target: note; property: "pulse"; from: 1.0; to: 0.55; duration: 650; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            ParallelAnimation {
                NumberAnimation { target: note; property: "haloScale"; from: 0.65; to: 1.5; duration: 1150; easing.type: Easing.OutQuad }
                NumberAnimation { target: note; property: "haloOpacity"; from: 0.52; to: 0.0; duration: 1150; easing.type: Easing.OutQuad }
            }
            PauseAnimation { duration: 150 }
        }
    }
}
