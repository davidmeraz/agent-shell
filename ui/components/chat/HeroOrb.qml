import QtQuick
import QtQuick.Layouts
import "../.."
import "../shared"

// Orbe cristalino orbital con perspectiva 3D real, reflejos Gema y firma por motor de IA.
Item {
    id: orb
    objectName: "chatHeroOrb"
    required property AgentBridge bridge
    property real orbitAngleA: 0
    property real orbitAngleB: 2.1
    property real orbitAngleC: 4.3
    property real floatPhase: 0
    property bool hovered: hoverHandler.hovered

    readonly property bool animate: visible && GemaTheme.animations
    readonly property string engineSymbol: bridge.provider === "agy" ? "✦"
        : bridge.provider === "claude" ? "◆" : "◎"
    readonly property color accentColor: GemaTheme.synced ? GemaTheme.accent : "#dce9f8"
    readonly property color softGlowColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.32) : "#30dce9f8"
    readonly property real floatY: animate ? Math.sin(floatPhase) * 5.0 : 0.0

    implicitWidth: 224
    implicitHeight: 224

    function triggerPulse() {
        if (!GemaTheme.animations) return;
        pulseAnim.restart();
    }

    Connections {
        target: orb.bridge
        function onProviderChanged() { orb.triggerPulse(); }
        function onActiveAreaChanged() { orb.triggerPulse(); }
    }

    // Ciclos armónicos no repetitivos (7.6s, 11.4s, 16.2s) para movimiento orgánico continuo.
    NumberAnimation on orbitAngleA {
        from: 0; to: Math.PI * 2
        duration: 7600
        loops: Animation.Infinite
        running: orb.animate
    }
    NumberAnimation on orbitAngleB {
        from: 2.1; to: 2.1 + Math.PI * 2
        duration: 11400
        loops: Animation.Infinite
        running: orb.animate
    }
    NumberAnimation on orbitAngleC {
        from: 4.3; to: 4.3 - Math.PI * 2
        duration: 16200
        loops: Animation.Infinite
        running: orb.animate
    }
    NumberAnimation on floatPhase {
        from: 0; to: Math.PI * 2
        duration: 4600
        loops: Animation.Infinite
        running: orb.animate
    }

    // Halo ambiental translúcido que respira suavemente detrás de la gema.
    Rectangle {
        id: ambientHalo
        anchors.centerIn: parent
        width: 176
        height: 176
        radius: 88
        opacity: orb.hovered ? 0.92 : 0.68
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.22) : "#20dce9f8" }
            GradientStop { position: 0.52; color: GemaTheme.synced ? GemaTheme.accentAlpha(0.07) : "#0adce9f8" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
        SequentialAnimation on scale {
            running: orb.animate
            loops: Animation.Infinite
            NumberAnimation { from: 0.93; to: 1.07; duration: 3100; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.07; to: 0.93; duration: 3100; easing.type: Easing.InOutSine }
        }
    }

    // Dos ondas cristalinas expansivas desfasadas (latido zen de vidrio).
    Repeater {
        model: 2
        Rectangle {
            id: zenRipple
            required property int index
            anchors.centerIn: parent
            width: 190
            height: 190
            radius: 95
            color: "transparent"
            border.width: 1
            border.color: GemaTheme.synced ? GemaTheme.accentAlpha(0.42) : "#3adce9f8"
            opacity: 0.0
            scale: 0.42

            SequentialAnimation {
                running: orb.animate
                loops: Animation.Infinite
                PauseAnimation { duration: zenRipple.index * 2600 }
                ParallelAnimation {
                    NumberAnimation {
                        target: zenRipple; property: "scale"
                        from: 0.42; to: 1.06; duration: 5200; easing.type: Easing.OutCubic
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: zenRipple; property: "opacity"
                            from: 0.0; to: 0.34; duration: 900; easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: zenRipple; property: "opacity"
                            from: 0.34; to: 0.0; duration: 4300; easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // Pulso interactivo al cambiar de IA o pulsar el orbe.
    Rectangle {
        id: switchBurst
        anchors.centerIn: parent
        width: 170
        height: 170
        radius: 85
        color: "transparent"
        border.width: 1.5
        border.color: orb.accentColor
        opacity: 0.0
        scale: 0.45
    }

    ParallelAnimation {
        id: pulseAnim
        NumberAnimation { target: switchBurst; property: "scale"; from: 0.45; to: 1.18; duration: 640; easing.type: Easing.OutCubic }
        SequentialAnimation {
            NumberAnimation { target: switchBurst; property: "opacity"; from: 0.0; to: 0.65; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: switchBurst; property: "opacity"; from: 0.65; to: 0.0; duration: 530; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            NumberAnimation { target: coreMedallion; property: "pulseScale"; from: 1.0; to: 0.86; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: coreMedallion; property: "pulseScale"; from: 0.86; to: 1.10; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { target: coreMedallion; property: "pulseScale"; from: 1.10; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
        }
    }

    // Contenedor flotante unificado (órbitas + núcleo cristalino).
    Item {
        id: stage
        anchors.centerIn: parent
        anchors.verticalCenterOffset: orb.floatY
        width: 210
        height: 210
        scale: orb.hovered ? 1.045 : 1.0
        Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 260 : 0; easing.type: Easing.OutCubic } }

        // Tres pistas elípticas finas en perspectiva 3D (pintadas una sola vez: 0% CPU continuo).
        Canvas {
            id: orbitTracks
            anchors.fill: parent
            z: 1
            antialiasing: true
            property color trackAccent: orb.accentColor
            onTrackAccentChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2;
                const cy = height / 2;
                const rings = [
                    { rx: 86, ry: 31, deg: -26, alpha: 0.24 },
                    { rx: 78, ry: 29, deg: 34, alpha: 0.20 },
                    { rx: 64, ry: 23, deg: 86, alpha: 0.14 }
                ];
                for (const r of rings) {
                    ctx.save();
                    ctx.translate(cx, cy);
                    ctx.rotate(r.deg * Math.PI / 180);
                    ctx.beginPath();
                    ctx.ellipse(-r.rx, -r.ry, r.rx * 2, r.ry * 2);
                    ctx.lineWidth = 1.0;
                    ctx.strokeStyle = Qt.rgba(trackAccent.r, trackAccent.g, trackAccent.b, r.alpha);
                    ctx.stroke();
                    ctx.restore();
                }
            }
        }

        // Componente de perla orbital 3D: cruza por delante (z=4) y por detrás (z=0) del núcleo de vidrio.
        component OrbitPearl: Item {
            id: pearl
            required property real rx
            required property real ry
            required property real tiltDeg
            required property real angle
            property real dotSize: 6
            property bool subtle: false
            readonly property real rad: tiltDeg * Math.PI / 180
            readonly property real lx: Math.cos(angle) * rx
            readonly property real ly: Math.sin(angle) * ry
            readonly property real depth: (Math.sin(angle) + 1.0) * 0.5 // 0 atrás, 1 frente
            readonly property real px: stage.width / 2 + lx * Math.cos(rad) - ly * Math.sin(rad)
            readonly property real py: stage.height / 2 + lx * Math.sin(rad) + ly * Math.cos(rad)
            x: px - width / 2
            y: py - height / 2
            width: 20
            height: 20
            z: Math.sin(angle) >= 0 ? 4 : 0
            scale: 0.68 + depth * 0.46
            opacity: (subtle ? 0.45 : 0.72) + depth * (subtle ? 0.40 : 0.28)

            // Halo luminoso suave.
            Rectangle {
                anchors.centerIn: parent
                width: pearl.dotSize * 2.6
                height: width
                radius: width / 2
                color: orb.softGlowColor
                opacity: 0.55 + pearl.depth * 0.45
            }
            // Núcleo nítido de la perla.
            Rectangle {
                anchors.centerIn: parent
                width: pearl.dotSize
                height: width
                radius: width / 2
                color: pearl.subtle ? "#e8f0fa" : orb.accentColor
            }
        }

        // Perlas principales y contrapesos tenues en cada órbita.
        OrbitPearl { rx: 86; ry: 31; tiltDeg: -26; angle: orb.orbitAngleA; dotSize: 6.5 }
        OrbitPearl { rx: 86; ry: 31; tiltDeg: -26; angle: orb.orbitAngleA + Math.PI; dotSize: 3.5; subtle: true }
        OrbitPearl { rx: 78; ry: 29; tiltDeg: 34; angle: orb.orbitAngleB; dotSize: 5.5 }
        OrbitPearl { rx: 78; ry: 29; tiltDeg: 34; angle: orb.orbitAngleB + Math.PI; dotSize: 3.0; subtle: true }
        OrbitPearl { rx: 64; ry: 23; tiltDeg: 86; angle: orb.orbitAngleC; dotSize: 4.5; subtle: true }

        // Núcleo cristalino central de vidrio esmerilado (z=2: entre perlas traseras y frontales).
        GlassPanel {
            id: coreMedallion
            objectName: "chatHeroCore"
            property real pulseScale: 1.0
            anchors.centerIn: parent
            width: 78
            height: 78
            radius: 39
            z: 2
            scale: pulseScale
            reflective: true
            highlighted: orb.hovered
            topColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#24ffffff"
            bottomColor: GemaTheme.synced ? GemaTheme.accentAlpha(0.08) : "#0effffff"
            edgeColor: orb.hovered
                ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.70) : "#66ffffff")
                : (GemaTheme.synced ? GemaTheme.accentAlpha(0.46) : "#42ffffff")

            // Prisma diamante interior rotando con reflejo sutil Gema.
            Rectangle {
                id: innerFacet
                anchors.centerIn: parent
                width: 42
                height: 42
                radius: 10
                color: GemaTheme.synced ? GemaTheme.accentAlpha(0.12) : "#14ffffff"
                border.width: 1
                border.color: GemaTheme.synced ? GemaTheme.accentAlpha(0.40) : "#34ffffff"
                rotation: 45
                RotationAnimation on rotation {
                    from: 45; to: 405
                    duration: 28000
                    loops: Animation.Infinite
                    running: orb.animate
                }
            }

            // Símbolo vivo del motor de IA activo (◎ ChatGPT · ✦ Gemini · ◆ Claude).
            Text {
                id: centerGlyph
                objectName: "chatHeroGlyph"
                anchors.centerIn: parent
                text: orb.engineSymbol
                color: orb.accentColor
                font.pixelSize: 22
                style: Text.Raised
                styleColor: GemaTheme.textShadow

                SequentialAnimation on scale {
                    running: orb.animate
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) centerGlyph.scale = 1.0
                    NumberAnimation { from: 0.94; to: 1.07; duration: 2200; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1.07; to: 0.94; duration: 2200; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    HoverHandler { id: hoverHandler }
    TapHandler { onTapped: orb.triggerPulse() }
}
