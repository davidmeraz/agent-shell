import QtQuick

// Luz sobre agua: velos y ondas suaves. Se dibuja al cambiar el tamaño,
// sin animaciones continuas ni eventos de ratón sobre los controles.
Canvas {
    id: reflection
    property real cornerRadius: 16
    property real strength: 1
    contextType: "2d"
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onCornerRadiusChanged: requestPaint()
    onStrengthChanged: requestPaint()
    onPaint: {
        if (width <= 2 || height <= 2) return;
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        ctx.beginPath();
        const radius = Math.min(cornerRadius, (width - 2) / 2, (height - 2) / 2);
        ctx.roundedRect(1, 1, width - 2, height - 2, radius, radius);
        ctx.clip();
        ctx.globalAlpha = strength;

        // Un reflejo ancho se desvanece hacia el centro del panel.
        const sheen = ctx.createRadialGradient(width * 0.16, 0, 0,
                                               width * 0.16, 0, width * 0.85);
        sheen.addColorStop(0, "#16ffffff");
        sheen.addColorStop(0.45, "#07ffffff");
        sheen.addColorStop(1, "#00ffffff");
        ctx.fillStyle = sheen;
        ctx.fillRect(0, 0, width, height);

        const light = ctx.createLinearGradient(0, 0, width, 0);
        light.addColorStop(0, "#00ffffff");
        light.addColorStop(0.18, "#24ffffff");
        light.addColorStop(0.5, "#08ffffff");
        light.addColorStop(0.8, "#1cffffff");
        light.addColorStop(1, "#00ffffff");
        ctx.strokeStyle = light;
        const band = Math.min(height * 0.14, 65);
        for (let i = 0; i < 3; ++i) {
            const offset = i * 8;
            ctx.beginPath();
            ctx.moveTo(-width * 0.08, band * 0.45 + offset);
            ctx.bezierCurveTo(width * 0.18, -band * 0.2 + offset,
                              width * 0.31, band * 1.25 + offset,
                              width * 0.57, band * 0.6 + offset);
            ctx.bezierCurveTo(width * 0.78, -band * 0.15 + offset,
                              width * 0.95, band * 0.8 + offset,
                              width * 1.08, band * 0.3 + offset);
            // Halo ancho y trazo fino forman la luz reflejada, sin aristas duras.
            ctx.globalAlpha = strength * 0.18;
            ctx.lineWidth = 9 - i * 2;
            ctx.stroke();
            ctx.globalAlpha = strength * (0.85 - i * 0.2);
            ctx.lineWidth = 1.1;
            ctx.stroke();
        }

        // Segundo destello, más tenue, junto al borde inferior.
        ctx.beginPath();
        ctx.moveTo(width * 0.2, height - 16);
        ctx.bezierCurveTo(width * 0.47, height - 44,
                          width * 0.64, height + 5,
                          width * 1.06, height - 26);
        ctx.globalAlpha = strength * 0.4;
        ctx.lineWidth = 1.2;
        ctx.stroke();
    }
}
