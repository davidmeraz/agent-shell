import QtQuick
import QtQuick.Layouts

// Pulso discreto sólo durante trabajo visible; no anima en segundo plano.
RowLayout {
    id: note
    required property string text
    required property bool busy
    required property bool windowVisible
    property real pulse: 0.5
    spacing: 7
    Rectangle {
        Layout.preferredWidth: 4
        Layout.preferredHeight: 4
        radius: 2
        color: "white"
        opacity: note.busy ? note.pulse : 0.4
    }
    Text {
        id: label
        Layout.fillWidth: true
        text: note.text
        textFormat: Text.PlainText
        font.pixelSize: 11
        color: "#999999"
        elide: Text.ElideRight
    }
    SequentialAnimation {
        running: note.busy && note.windowVisible
        loops: Animation.Infinite
        NumberAnimation { target: note; property: "pulse"; from: 0.45; to: 0.95; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { target: note; property: "pulse"; from: 0.95; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
    }
}
