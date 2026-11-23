import QtQuick

// Entrada fluida del contenido: combina opacidad, elevación y sutil escala cristalina sin mover la ventana.
Item {
    id: motion
    objectName: "projectViewerMotion"
    required property bool shown
    property real progress: 0
    opacity: progress
    scale: 0.978 + 0.022 * motion.progress
    transform: Translate { y: 12 * (1 - motion.progress) }
    function reveal() { entrance.restart(); }
    onShownChanged: {
        if (shown) reveal();
        else { entrance.stop(); progress = 0; }
    }
    Component.onCompleted: { if (shown) reveal(); }
    NumberAnimation {
        id: entrance
        target: motion
        property: "progress"
        from: 0
        to: 1
        duration: 300
        easing.type: Easing.OutCubic
    }
}
