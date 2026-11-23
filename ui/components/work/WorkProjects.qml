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
    signal deleteProjectRequested(string projectId, string name, string workdir)
    radius: 16
    topColor: "#14292929"
    bottomColor: "#24171717"
    edgeColor: "#20ffffff"
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Text {
                    Layout.fillWidth: true
                    text: panel.isAppArea ? "App · Gema UI Kit" : "Work"
                    color: "#f5f5f5"
                    font.pixelSize: 26
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: panel.isAppArea
                        ? "Crea aplicaciones del día a día con diseño Glassmorphism (Quickshell + Python/Rust)."
                        : "Un espacio para construir."
                    color: "#aaaaaa"
                    font.pixelSize: 13
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
            topColor: "#1e3d3d3d"
            bottomColor: "#181e1e1e"
            edgeColor: "#30ffffff"
            ColumnLayout {
                id: kitInfo
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: "Stack Gema UI Kit · Dark Glassmorphism"
                    color: "#f0f0f0"
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: "Genera automáticamente la ventana translúcida con blur de Hyprland (MattePanel, GlassPanel, WaterReflection, ActionButton), puente IPC JSON-Lines sobre stdio y botones para Probar e Iniciar."
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
                width: projectList.width
                padding: 16
                enabled: panel.bridge.canSelectArea
                onClicked: panel.bridge.selectArea(panel.isAppArea ? "app" : "work", projectId)
                contentItem: RowLayout {
                    spacing: 12
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
                                color: "#f5f5f5"
                                font.pixelSize: 15
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            GlassPanel {
                                visible: panel.isAppArea
                                implicitWidth: engineTag.implicitWidth + 14
                                implicitHeight: 20
                                radius: 6
                                topColor: "#28505050"
                                bottomColor: "#1c262626"
                                Text {
                                    id: engineTag
                                    anchors.centerIn: parent
                                    text: "Gema UI · " + (projectRow.engine === "rust" ? "Rust" : "Python")
                                    color: "#dddddd"
                                    font.pixelSize: 10
                                }
                            }
                        }
                        Text { Layout.fillWidth: true; text: projectRow.workdir; textFormat: Text.PlainText; color: "#aaaaaa"; font.pixelSize: 11; elide: Text.ElideMiddle }
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
                    highlighted: projectRow.activeFocus
                    topColor: projectRow.hovered ? "#30555555" : "#183b3b3b"
                    edgeColor: "#24ffffff"
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
