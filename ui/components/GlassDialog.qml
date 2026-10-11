import QtQuick
import QtQuick.Controls

Dialog {
    id: control
    padding: 20
    background: GlassPanel {
        radius: 16
        topColor: "#f02a3a4b"
        bottomColor: "#f0172433"
    }
    header: Label {
        text: control.title
        color: "#edf4fa"
        font.pixelSize: 20
        font.bold: true
        padding: 20
        bottomPadding: 4
        elide: Text.ElideRight
    }
    footer: DialogButtonBox {
        standardButtons: control.standardButtons
        padding: 16
        spacing: 8
        background: null
        delegate: ActionButton {}
    }
    Overlay.modal: Rectangle { color: "#80080e18" }
}
