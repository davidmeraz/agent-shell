import QtQuick
import QtQuick.Controls
import QtQuick.Window
import AgentShell.Native
import "../.."
import "../shared"

// Visor flotante minimalista sin bordes ni marco: muestra únicamente la imagen centrada y nítida.
NativeWindow {
    id: viewer
    objectName: "imagePreviewWindow"
    property string imageSource: ""
    property string mainWindowTitle: ""
    property real zoomFactor: 1.0
    property real panX: 0
    property real panY: 0

    readonly property int maxAllowedWidth: Math.max(480, Math.round((Screen.width || 1920) * 0.80))
    readonly property int maxAllowedHeight: Math.max(360, Math.round((Screen.height || 1080) * 0.82))
    readonly property real naturalWidth: previewImage.implicitWidth > 0 ? previewImage.implicitWidth : 640
    readonly property real naturalHeight: previewImage.implicitHeight > 0 ? previewImage.implicitHeight : 480
    readonly property real fitScale: {
        const downScale = Math.min(maxAllowedWidth / naturalWidth, maxAllowedHeight / naturalHeight);
        if (downScale > 1.0) return Math.min(downScale, 2.0);
        return downScale;
    }
    readonly property int fittedWidth: Math.max(240, Math.min(maxAllowedWidth, Math.round(naturalWidth * fitScale)))
    readonly property int fittedHeight: Math.max(180, Math.min(maxAllowedHeight, Math.round(naturalHeight * fitScale)))

    title: "Agent Shell · Imagen"
    color: "transparent"
    visible: false
    implicitWidth: fittedWidth
    implicitHeight: fittedHeight
    minimumSize: Qt.size(fittedWidth, fittedHeight)
    maximumSize: Qt.size(fittedWidth, fittedHeight)

    function openImage(url) {
        if (!url) return;
        zoomFactor = 1.0;
        panX = 0;
        panY = 0;
        imageSource = url;
        visible = true;
        scheduleCenter();
        Qt.callLater(function() {
            if (!viewer.visible) return;
            stage.forceActiveFocus();
            if (viewer.contentItem && viewer.contentItem.Window.window)
                viewer.contentItem.Window.window.requestActivate();
        });
    }

    function closeViewer() {
        visible = false;
        zoomFactor = 1.0;
        panX = 0;
        panY = 0;
    }

    function scheduleCenter() {
        if (visible && fittedWidth > 0 && fittedHeight > 0
            && NativeApp.env("HYPRLAND_INSTANCE_SIGNATURE") && NativeApp.env("QT_QPA_PLATFORM") !== "offscreen")
            centerDelay.restart();
    }

    onFittedWidthChanged: if (visible) scheduleCenter()
    onFittedHeightChanged: if (visible) scheduleCenter()
    onClosed: closeViewer()

    Timer {
        id: centerDelay
        interval: 60
        onTriggered: {
            if (!viewer.visible) return;
            centerProcess.running = false;
            centerProcess.command = [
                NativeApp.pythonExecutable,
                NativeApp.placementScript,
                "--center-window",
                String(NativeApp.processId),
                viewer.title,
                String(viewer.fittedWidth),
                String(viewer.fittedHeight),
                viewer.mainWindowTitle
            ];
            centerProcess.running = true;
        }
    }

    NativeProcess {
        id: centerProcess
        errorOutput: LineParser { onRead: data => console.warn("Visor de imagen: " + data) }
    }

    Item {
        id: stage
        anchors.fill: parent
        clip: true
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Space) {
                viewer.closeViewer();
                event.accepted = true;
            } else if (event.key === Qt.Key_0) {
                viewer.zoomFactor = 1.0;
                viewer.panX = 0;
                viewer.panY = 0;
                event.accepted = true;
            }
        }

        Image {
            id: previewImage
            objectName: "imagePreviewFull"
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: viewer.panX
            anchors.verticalCenterOffset: viewer.panY
            width: stage.width * viewer.zoomFactor
            height: stage.height * viewer.zoomFactor
            source: viewer.imageSource
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            cache: false
            asynchronous: false
            onStatusChanged: {
                if (status === Image.Ready && viewer.visible)
                    viewer.scheduleCenter();
            }
        }

        MouseArea {
            id: interactionArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: viewer.zoomFactor > 1.01
                ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                : Qt.PointingHandCursor
            property real pressX: 0
            property real pressY: 0
            property real startPanX: 0
            property real startPanY: 0
            property bool dragged: false

            onPressed: mouse => {
                pressX = mouse.x;
                pressY = mouse.y;
                startPanX = viewer.panX;
                startPanY = viewer.panY;
                dragged = false;
            }
            onPositionChanged: mouse => {
                if (!pressed || viewer.zoomFactor <= 1.01) return;
                const dx = mouse.x - pressX;
                const dy = mouse.y - pressY;
                if (Math.abs(dx) > 3 || Math.abs(dy) > 3) dragged = true;
                const limitX = (stage.width * (viewer.zoomFactor - 1)) / 2;
                const limitY = (stage.height * (viewer.zoomFactor - 1)) / 2;
                viewer.panX = Math.max(-limitX, Math.min(limitX, startPanX + dx));
                viewer.panY = Math.max(-limitY, Math.min(limitY, startPanY + dy));
            }
            onClicked: {
                if (dragged) return;
                if (viewer.zoomFactor > 1.01) {
                    viewer.zoomFactor = 1.0;
                    viewer.panX = 0;
                    viewer.panY = 0;
                } else {
                    viewer.closeViewer();
                }
            }
            onDoubleClicked: {
                if (viewer.zoomFactor > 1.01) {
                    viewer.zoomFactor = 1.0;
                    viewer.panX = 0;
                    viewer.panY = 0;
                } else {
                    viewer.zoomFactor = 2.0;
                }
            }
            onWheel: wheel => {
                const factor = wheel.angleDelta.y > 0 ? 1.15 : (1 / 1.15);
                const next = Math.max(1.0, Math.min(3.5, viewer.zoomFactor * factor));
                viewer.zoomFactor = next;
                if (next <= 1.01) {
                    viewer.panX = 0;
                    viewer.panY = 0;
                } else {
                    const limitX = (stage.width * (next - 1)) / 2;
                    const limitY = (stage.height * (next - 1)) / 2;
                    viewer.panX = Math.max(-limitX, Math.min(limitX, viewer.panX));
                    viewer.panY = Math.max(-limitY, Math.min(limitY, viewer.panY));
                }
            }
        }
    }
}
