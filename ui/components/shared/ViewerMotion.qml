import QtQuick

// Entrada del contenido: no retrasa el cierre nativo ni mueve la ventana.
Item {
    id: motion
    objectName: "projectViewerMotion"
    required property bool shown
    property real progress: 0
    opacity: progress
    transform: Translate { y: 8 * (1 - motion.progress) }
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
        duration: 240
        easing.type: Easing.OutCubic
    }
}
