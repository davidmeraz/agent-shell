import QtQuick
import QtQuick.Controls
import "../.."
import "../shared"

ActionButton {
    id: control

    enum Glyph { Files, Git, Play, Stop, Projects }
    property int glyph: ProjectActionButton.Files
    readonly property color iconColor: !enabled ? "#888888"
                                       : accent ? (GemaTheme.synced ? GemaTheme.accentInk : "#ffffff")
                                       : GemaTheme.textColor

    implicitWidth: 32
    implicitHeight: 32
    padding: 0
    Accessible.name: text
    ToolTip.text: text
    ToolTip.delay: 450
    ToolTip.visible: text.length > 0 && (hovered || visualFocus)

    onGlyphChanged: icon.requestPaint()
    onIconColorChanged: icon.requestPaint()

    contentItem: Item {
        Canvas {
            id: icon
            anchors.centerIn: parent
            width: 18
            height: 18
            renderTarget: Canvas.Image

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = control.iconColor;
                ctx.fillStyle = control.iconColor;
                ctx.lineWidth = 1.5;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.beginPath();
                switch (control.glyph) {
                case ProjectActionButton.Files:
                    ctx.moveTo(2.5, 5.5);
                    ctx.lineTo(2.5, 3.5);
                    ctx.lineTo(7, 3.5);
                    ctx.lineTo(8.5, 5.5);
                    ctx.lineTo(15.5, 5.5);
                    ctx.lineTo(15.5, 14.5);
                    ctx.lineTo(2.5, 14.5);
                    ctx.closePath();
                    ctx.stroke();
                    break;
                case ProjectActionButton.Git:
                    ctx.moveTo(5, 5);
                    ctx.lineTo(5, 13);
                    ctx.moveTo(5, 10);
                    ctx.bezierCurveTo(5, 7, 13, 9, 13, 5);
                    ctx.stroke();
                    for (const point of [[5, 4], [5, 14], [13, 4]]) {
                        ctx.beginPath();
                        ctx.arc(point[0], point[1], 1.5, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                    break;
                case ProjectActionButton.Play:
                    ctx.moveTo(5, 2.5);
                    ctx.lineTo(15, 9);
                    ctx.lineTo(5, 15.5);
                    ctx.closePath();
                    ctx.fill();
                    break;
                case ProjectActionButton.Stop:
                    ctx.fillRect(4, 4, 10, 10);
                    break;
                case ProjectActionButton.Projects:
                    ctx.strokeRect(2.5, 2.5, 5, 5);
                    ctx.strokeRect(10.5, 2.5, 5, 5);
                    ctx.strokeRect(2.5, 10.5, 5, 5);
                    ctx.strokeRect(10.5, 10.5, 5, 5);
                    break;
                }
            }
        }
    }
}
