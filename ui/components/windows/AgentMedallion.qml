import QtQuick
import QtQuick.Shapes
import "../shared"

// Emblema del subagente: órbita mientras trabaja, anillo cerrado y símbolo de resultado al terminar.
Item {
    id: medallion
    required property string glyph
    property bool working: false
    property string outcome: ""
    property color tint: "#ffffff"
    implicitWidth: 52
    implicitHeight: 52

    Rectangle {
        id: ripple
        anchors.centerIn: parent
        width: 44
        height: 44
        radius: 22
        color: "transparent"
        border.width: 1
        border.color: medallion.tint
        opacity: 0
        ParallelAnimation {
            running: medallion.working && medallion.visible && GemaTheme.animations
            loops: Animation.Infinite
            onRunningChanged: if (!running) ripple.opacity = 0
            NumberAnimation { target: ripple; property: "scale"; from: 0.9; to: 1.32; duration: 1700; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: ripple; property: "opacity"; from: 0; to: 0.5; duration: 260 }
                NumberAnimation { target: ripple; property: "opacity"; to: 0; duration: 1440; easing.type: Easing.OutQuad }
            }
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: 40
        height: 40
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(medallion.tint, 0.26) }
            GradientStop { position: 1; color: Qt.alpha(medallion.tint, 0.06) }
        }
        border.width: 1
        border.color: "#26ffffff"
    }
    Shape {
        id: orbit
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: medallion.tint
            strokeWidth: 2
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                id: arc
                property real sweep: medallion.working ? 100 : 360
                centerX: orbit.width / 2
                centerY: orbit.height / 2
                radiusX: 23
                radiusY: 23
                startAngle: -90
                sweepAngle: sweep
                Behavior on sweep { NumberAnimation { duration: GemaTheme.animations ? 620 : 0; easing.type: Easing.InOutCubic } }
            }
        }
        RotationAnimation on rotation {
            from: 0; to: 360
            duration: 1500
            loops: Animation.Infinite
            running: medallion.working && medallion.visible && GemaTheme.animations
        }
    }
    Text {
        id: symbol
        objectName: "agentMedallionSymbol"
        anchors.centerIn: parent
        text: medallion.outcome || medallion.glyph
        color: medallion.tint
        font.pixelSize: 18
        font.weight: Font.Bold
        style: Text.Raised
        styleColor: GemaTheme.textShadow
        onTextChanged: if (GemaTheme.animations) pop.restart()
        SequentialAnimation {
            id: pop
            NumberAnimation { target: symbol; property: "scale"; from: 0.3; to: 1.22; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: symbol; property: "scale"; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
    }
}
