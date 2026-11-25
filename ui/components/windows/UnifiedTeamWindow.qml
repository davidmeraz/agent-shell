import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import AgentShell.Native
import "../.."
import "../shared"
import "../work"

// Ventana flotante independiente para el equipo del modo unificado (desactivada por defecto).
NativeWindow {
    id: teamWindow
    objectName: "unifiedTeamWindow"
    required property AgentBridge bridge
    property bool enabledInSettings: false
    signal configureRequested()
    signal closedByUser()

    title: "Agent Shell · Equipo unificado"
    implicitWidth: 640
    implicitHeight: Math.max(124, teamPanel.implicitHeight + 16)
    minimumSize: Qt.size(440, implicitHeight)
    maximumSize: Qt.size(16777215, implicitHeight)
    color: "transparent"
    visible: enabledInSettings && bridge.unifiedMode && bridge.engineReady

    onClosed: {
        if (enabledInSettings && bridge.unifiedMode && bridge.engineReady)
            closedByUser();
    }

    MattePanel {
        id: surface
        anchors.fill: parent
        anchors.margins: 1
        radius: 18
        topColor: "#54141c26"
        bottomColor: "#680c121a"
        edgeColor: "#4cffffff"
    }

    GlassToolTipTheme {}

    UnifiedTeam {
        id: teamPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 7
        bridge: teamWindow.bridge
        topColor: "#00000000"
        bottomColor: "#00000000"
        edgeColor: "#00000000"
        reflective: false
        onConfigureRequested: teamWindow.configureRequested()
    }
}
