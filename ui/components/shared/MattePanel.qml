import QtQuick

// Vidrio esmerilado translúcido unificado: deja ver el blur del fondo y hace brillar el texto y los botones en toda la app.
GlassPanel {
    id: matte
    property bool overlay: false
    property bool waterReflection: true
    reflective: true
    topColor: "#54141c26"
    bottomColor: "#680c121a"
    edgeColor: overlay ? "#58ffffff" : "#4cffffff"
    radius: 16
    WaterReflection {
        anchors.fill: parent
        visible: matte.waterReflection
        cornerRadius: matte.radius
        strength: 0.85
    }
}
