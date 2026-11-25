import QtQuick

// Iconos vectoriales propios y constantes de Agent Shell (no cambian de forma al cambiar de tema).
Item {
    id: root
    property string name: "brand"
    property color color: "#ffffff"
    property real size: 16

    implicitWidth: size
    implicitHeight: size

    onNameChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width <= 0 || height <= 0) return;

            const s = Math.min(width, height) / 24.0;
            ctx.save();
            ctx.translate((width - 24.0 * s) / 2.0, (height - 24.0 * s) / 2.0);
            ctx.scale(s, s);
            ctx.strokeStyle = root.color;
            ctx.fillStyle = root.color;
            ctx.lineWidth = 1.75;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            function roundedRectPath(x, y, w, h, r) {
                ctx.beginPath();
                ctx.moveTo(x + r, y);
                ctx.lineTo(x + w - r, y);
                ctx.quadraticCurveTo(x + w, y, x + w, y + r);
                ctx.lineTo(x + w, y + h - r);
                ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
                ctx.lineTo(x + r, y + h);
                ctx.quadraticCurveTo(x, y + h, x, y + h - r);
                ctx.lineTo(x, y + r);
                ctx.quadraticCurveTo(x, y, x + r, y);
                ctx.closePath();
            }

            if (root.name === "brand") {
                // Diamante cristalino facetado de Agent Shell
                ctx.beginPath();
                ctx.moveTo(12, 2.5);
                ctx.lineTo(20.8, 12);
                ctx.lineTo(12, 21.5);
                ctx.lineTo(3.2, 12);
                ctx.closePath();
                ctx.save();
                ctx.globalAlpha = 0.16;
                ctx.fill();
                ctx.restore();
                ctx.stroke();

                // Destello interior de 4 puntas
                ctx.beginPath();
                ctx.moveTo(12, 6.8);
                ctx.quadraticCurveTo(12.7, 11.3, 16.8, 12);
                ctx.quadraticCurveTo(12.7, 12.7, 12, 17.2);
                ctx.quadraticCurveTo(11.3, 12.7, 7.2, 12);
                ctx.quadraticCurveTo(11.3, 11.3, 12, 6.8);
                ctx.closePath();
                ctx.save();
                ctx.globalAlpha = 0.85;
                ctx.fill();
                ctx.restore();
            } else if (root.name === "chat") {
                // Burbuja minimalista de conversación
                ctx.beginPath();
                ctx.moveTo(6.5, 4.5);
                ctx.lineTo(17.5, 4.5);
                ctx.quadraticCurveTo(20.5, 4.5, 20.5, 7.5);
                ctx.lineTo(20.5, 14.5);
                ctx.quadraticCurveTo(20.5, 17.5, 17.5, 17.5);
                ctx.lineTo(10.2, 17.5);
                ctx.lineTo(6.2, 20.4);
                ctx.lineTo(6.8, 17.5);
                ctx.lineTo(6.5, 17.5);
                ctx.quadraticCurveTo(3.5, 17.5, 3.5, 14.5);
                ctx.lineTo(3.5, 7.5);
                ctx.quadraticCurveTo(3.5, 4.5, 6.5, 4.5);
                ctx.closePath();
                ctx.save();
                ctx.globalAlpha = 0.14;
                ctx.fill();
                ctx.restore();
                ctx.stroke();

                ctx.beginPath();
                ctx.moveTo(8, 9.6);
                ctx.lineTo(16, 9.6);
                ctx.moveTo(8, 13.0);
                ctx.lineTo(13.2, 13.0);
                ctx.stroke();
            } else if (root.name === "work") {
                // Carpeta / espacio de proyecto geométrico
                ctx.beginPath();
                ctx.moveTo(3.5, 7.5);
                ctx.quadraticCurveTo(3.5, 5.2, 5.8, 5.2);
                ctx.lineTo(9.4, 5.2);
                ctx.lineTo(11.4, 7.4);
                ctx.lineTo(18.2, 7.4);
                ctx.quadraticCurveTo(20.5, 7.4, 20.5, 9.7);
                ctx.lineTo(20.5, 17.0);
                ctx.quadraticCurveTo(20.5, 19.2, 18.2, 19.2);
                ctx.lineTo(5.8, 19.2);
                ctx.quadraticCurveTo(3.5, 19.2, 3.5, 17.0);
                ctx.closePath();
                ctx.save();
                ctx.globalAlpha = 0.14;
                ctx.fill();
                ctx.restore();
                ctx.stroke();
            } else if (root.name === "app") {
                // Ventana de aplicación nativa translúcida
                roundedRectPath(3.2, 4.4, 17.6, 15.2, 3.6);
                ctx.save();
                ctx.globalAlpha = 0.14;
                ctx.fill();
                ctx.restore();
                ctx.stroke();

                ctx.beginPath();
                ctx.moveTo(3.8, 9.2);
                ctx.lineTo(20.2, 9.2);
                ctx.stroke();

                for (const cx of [6.6, 9.4, 12.2]) {
                    ctx.beginPath();
                    ctx.arc(cx, 6.8, 0.9, 0, Math.PI * 2);
                    ctx.fill();
                }
            } else if (root.name === "settings") {
                // Controles deslizantes minimalistas
                const rows = [
                    { y: 6.5, knob: 15.5 },
                    { y: 12.0, knob: 9.0 },
                    { y: 17.5, knob: 14.5 }
                ];
                for (const row of rows) {
                    ctx.beginPath();
                    ctx.moveTo(4.0, row.y);
                    ctx.lineTo(row.knob - 2.3, row.y);
                    ctx.moveTo(row.knob + 2.3, row.y);
                    ctx.lineTo(20.0, row.y);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.arc(row.knob, row.y, 2.1, 0, Math.PI * 2);
                    ctx.save();
                    ctx.globalAlpha = 0.22;
                    ctx.fill();
                    ctx.restore();
                    ctx.stroke();
                }
            } else if (root.name === "system") {
                // Nodo de sistema minimalista
                ctx.beginPath();
                ctx.arc(12, 12, 7.5, 0, Math.PI * 2);
                ctx.save();
                ctx.globalAlpha = 0.14;
                ctx.fill();
                ctx.restore();
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(12, 12, 2.4, 0, Math.PI * 2);
                ctx.fill();
            }

            ctx.restore();
        }
    }
}
