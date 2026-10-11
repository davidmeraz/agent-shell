import QtQuick

// Vidrio esmerilado más denso, con reflejos de agua compartidos por los paneles.
GlassPanel {
    id: matte
    property bool overlay: false
    property bool waterReflection: true
    reflective: false
    topColor: overlay ? "#943a3a3a" : "#50414141"
    bottomColor: overlay ? "#a0303030" : "#60303030"
    edgeColor: "#34ffffff"
    radius: 16
    WaterReflection {
        anchors.fill: parent
        visible: matte.waterReflection
        cornerRadius: matte.radius
        strength: matte.overlay ? 1 : 0.65
    }
}
