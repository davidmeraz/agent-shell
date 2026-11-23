import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Inicio de Work y App: proyectos locales y aplicaciones Gema UI Kit; cada carpeta conserva conversaciones propias.
GlassPanel {
    id: panel
    required property AgentBridge bridge
    readonly property bool isAppArea: bridge.activeArea === "app"
    signal newProjectRequested()
    signal renameProjectRequested(string projectId, string name)
    signal deleteProjectRequested(string projectId, string name, string workdir)
    radius: 16
    topColor: "#00000000"
    bottomColor: "#00000000"
    edgeColor: "#00000000"
    reflective: false
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    spacing: 8
                    Text {
                        text: panel.isAppArea ? GemaTheme.gemSymbol : "❖"
                        color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                        font.pixelSize: 20
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                    Text {
                        Layout.fillWidth: true
                        text: panel.isAppArea ? "App · Gema UI Kit" : "Work · Proyectos"
                        color: GemaTheme.textColor
                        font.pixelSize: 26
                        font.bold: true
                        font.letterSpacing: -0.3
                        style: Text.Raised
                        styleColor: GemaTheme.textShadow
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: panel.isAppArea
                        ? "Crea aplicaciones del día a día con diseño Matte Transparent Glassmorphism (Quickshell + Python/Rust)."
                        : "Un espacio para construir, explorar y ejecutar tus proyectos con la IA."
                    color: GemaTheme.mutedColor
                    font.pixelSize: 13
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                    wrapMode: Text.Wrap
                }
            }
            ActionButton {
                objectName: "workNewProject"
                text: panel.isAppArea ? "+  Nueva App" : "+  Nuevo proyecto"
                accent: panel.isAppArea
                enabled: panel.bridge.canSelectArea
                onClicked: panel.newProjectRequested()
            }
        }
        GlassPanel {
            Layout.fillWidth: true
            visible: panel.isAppArea
            implicitHeight: kitInfo.implicitHeight + 24
            radius: 12
            topColor: "#18ffffff"
            bottomColor: "#0cffffff"
            edgeColor: "#30ffffff"
            ColumnLayout {
                id: kitInfo
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: "Stack Gema UI Kit · Matte Transparent Glassmorphism"
                    color: "#f0f0f0"
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: "Genera automáticamente la ventana de vidrio mate transparente con blur de Hyprland (MattePanel, GlassPanel, WaterReflection, ActionButton), puente IPC JSON-Lines sobre stdio y botones para Probar e Iniciar."
                    color: "#b8b8b8"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }
        Text {
            Layout.fillWidth: true
            visible: !!panel.bridge.areaError
            text: panel.bridge.areaError
            color: "#dddddd"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: !(panel.isAppArea ? panel.bridge.apps.count : panel.bridge.projects.count)
            text: panel.isAppArea
                ? "Crea tu primera aplicación con '+ Nueva App'. Se preparará la estructura Gema UI Kit lista para probar, iniciar y personalizar con la IA."
                : "Vincula una carpeta local para crear, modificar y probar proyectos con la IA. Cada proyecto tiene su propio historial."
            color: "#bbbbbb"
            font.pixelSize: 14
            wrapMode: Text.Wrap
        }
        ListView {
            id: projectList
            objectName: "workProjectList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            topMargin: 4
            bottomMargin: 4
            leftMargin: 6
            rightMargin: 6
            spacing: 10
            model: panel.isAppArea ? panel.bridge.apps : panel.bridge.projects
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
            delegate: ItemDelegate {
                id: projectRow
                required property string projectId
                required property string name
                required property string workdir
                required property string engine
                objectName: "workProjectRow"
                width: projectList.width - projectList.leftMargin - projectList.rightMargin
                padding: 16
                hoverEnabled: true
                enabled: panel.bridge.canSelectArea
                scale: projectRow.down ? 0.988 : (projectRow.hovered ? 1.008 : 1.0)
                Behavior on scale { NumberAnimation { duration: GemaTheme.animations ? 140 : 0; easing.type: Easing.OutCubic } }
                onClicked: panel.bridge.selectArea(panel.isAppArea ? "app" : "work", projectId)
                contentItem: RowLayout {
                    spacing: 14
                    GlassPanel {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: 10
                        topColor: projectRow.hovered
                                  ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.30) : "#28ffffff")
                                  : (GemaTheme.synced ? GemaTheme.accentAlpha(0.16) : "#18ffffff")
                        bottomColor: "#0cffffff"
                        edgeColor: projectRow.hovered
                                   ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#50ffffff")
                                   : "#28ffffff"
                        Text {
                            anchors.centerIn: parent
                            text: panel.isAppArea ? GemaTheme.gemSymbol : "❖"
                            color: GemaTheme.synced ? GemaTheme.accent : "#ffffff"
                            font.pixelSize: 16
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: projectRow.name
                                textFormat: Text.PlainText
                                color: GemaTheme.textColor
                                font.pixelSize: 15
                                font.bold: true
                                style: Text.Raised
                                styleColor: GemaTheme.textShadow
                                elide: Text.ElideRight
                            }
                            GlassPanel {
                                visible: panel.isAppArea
                                implicitWidth: engineTag.implicitWidth + 14
                                implicitHeight: 20
                                radius: 6
                                topColor: "#1cffffff"
                                bottomColor: "#10ffffff"
                                Text {
                                    id: engineTag
                                    anchors.centerIn: parent
                                    text: "Gema UI · " + (projectRow.engine === "rust" ? "Rust" : "Python")
                                    color: GemaTheme.mutedColor
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    style: Text.Raised
                                    styleColor: GemaTheme.textShadow
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: projectRow.workdir
                            textFormat: Text.PlainText
                            color: GemaTheme.subtleColor
                            font.pixelSize: 11
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                            elide: Text.ElideMiddle
                        }
                    }
                    ActionButton {
                        id: renameProjectButton
                        objectName: "workRenameProject"
                        enabled: panel.bridge.canSelectArea
                        implicitWidth: 30
                        implicitHeight: 30
                        horizontalPadding: 7
                        verticalPadding: 7
                        Accessible.name: "Editar nombre: " + projectRow.name
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: "Editar nombre"
                        onClicked: panel.renameProjectRequested(projectRow.projectId, projectRow.name)
                        contentItem: Item {
                            Item {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                rotation: -45
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 3
                                    width: 8
                                    height: 4
                                    radius: 1
                                    color: "transparent"
                                    border.width: 1
                                    border.color: renameProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 0
                                    width: 3
                                    height: 2
                                    radius: 1
                                    color: renameProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                                }
                            }
                        }
                    }
                    ActionButton {
                        id: deleteProjectButton
                        objectName: "workDeleteProject"
                        enabled: !(panel.bridge.projectRunActive && panel.bridge.projectRun.project_id === projectRow.projectId)
                        implicitWidth: 30
                        implicitHeight: 30
                        horizontalPadding: 7
                        verticalPadding: 7
                        Accessible.name: "Eliminar proyecto: " + projectRow.name
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        ToolTip.text: "Eliminar proyecto"
                        onClicked: panel.deleteProjectRequested(projectRow.projectId, projectRow.name, projectRow.workdir)
                        contentItem: Item {
                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 2
                                width: 10; height: 11; radius: 2
                                color: "transparent"
                                border.width: 1
                                border.color: deleteProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height / 2 - 5
                                width: 14; height: 1
                                color: deleteProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height / 2 - 8
                                width: 6; height: 3; radius: 1
                                color: "transparent"
                                border.width: 1
                                border.color: deleteProjectButton.hovered ? "#ffffff" : "#aaaaaa"
                            }
                        }
                    }
                }
                background: GlassPanel {
                    radius: 12
                    highlighted: projectRow.activeFocus || projectRow.hovered
                    topColor: projectRow.hovered
                              ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.24) : "#26ffffff")
                              : "#1cffffff"
                    bottomColor: "#22060a10"
                    edgeColor: projectRow.hovered
                               ? (GemaTheme.synced ? GemaTheme.accentAlpha(0.65) : "#58ffffff")
                               : "#3cffffff"
                }
                ToolTip.visible: hovered
                ToolTip.delay: 650
                ToolTip.text: workdir
                Accessible.name: name + ", " + workdir
            }
        }
        Text {
            Layout.fillWidth: true
            text: "La terminal trabaja en la carpeta del proyecto."
            color: "#888888"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
