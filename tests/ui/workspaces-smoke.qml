import QtQuick
import QtQuick.Controls
import QtTest
import AgentShell.Native
import "../../ui"

// Áreas y dos carpetas temporales con backend real y servicio local de prueba.
NativeScope {
    id: scenario
    property int stage: 0
    property bool stepping: false
    property var prompt: null
    property string root: ""
    readonly property string secondFolder: "segundo proyecto con una ruta lo bastante larga para probar la elisión en la cabecera"
    property string chatId: ""
    property string workId: ""
    property string firstProject: ""
    property string secondProject: ""
    AgentBridge { id: agent }
    ChatWindow { id: chat; bridge: agent; implicitWidth: 560; implicitHeight: 680 }
    TestCase { id: inspector; parent: chat.contentItem; when: false }
    function check(value, message) {
        if (value) return true;
        console.error("WORKSPACES_FAILED: " + message);
        steps.stop(); Qt.callLater(Qt.quit); return false;
    }
    function click(name) {
        const item = inspector.findChild(chat, name);
        if (!check(!!item && item.visible && item.enabled, "control ausente o deshabilitado: " + name
            + " · presente=" + !!item + " · visible=" + (item ? item.visible : "—")
            + " · enabled=" + (item ? item.enabled : "—") + " · canSelectArea=" + agent.canSelectArea)) return false;
        inspector.mouseClick(item);
        return true;
    }
    function fillProject(name, workdir) {
        inspector.findChild(chat, "workProjectName").text = name;
        inspector.findChild(chat, "workProjectDirectory").text = workdir;
        return click("workCreateProject");
    }
    function checkProjectLayout() {
        const switcher = inspector.findChild(chat, "workspaceSwitcher");
        const position = switcher.mapToItem(chat.contentItem, 0, 0);
        if (!check(agent.workspace === root + "/" + secondFolder && switcher.visible
            && Math.abs(position.x + switcher.width / 2 - chat.width / 2) < 1,
            "la ruta larga desplaza el selector de espacios")) return false;
        const actions = inspector.findChild(chat, "workProjectActions");
        const conversation = inspector.findChild(chat, "chatConversation");
        const railPosition = actions.mapToItem(chat.contentItem, 0, 0);
        const conversationPosition = conversation.mapToItem(chat.contentItem, 0, 0);
        if (!check(actions.visible && conversation.visible
            && railPosition.x >= conversationPosition.x + conversation.width,
            "la barra de acciones no está a la derecha de la conversación")) return false;
        let previousX = -1;
        let previousY = -1;
        for (const name of ["workExplorerButton", "workGitButton", "workRunButton", "workProjectsButton"]) {
            const button = inspector.findChild(actions, name);
            if (!check(button && button.visible && button.width === 32 && button.height === 32,
                "el grupo no contiene el botón compacto " + name)) return false;
            const buttonPosition = button.mapToItem(chat.contentItem, 0, 0);
            if (!check(previousX < 0 || (Math.abs(buttonPosition.x - previousX) < 1 && buttonPosition.y > previousY),
                "las acciones no forman una columna: " + name)) return false;
            previousX = buttonPosition.x;
            previousY = buttonPosition.y;
        }
        return true;
    }
    function requestRename(projectId, newName) {
        const list = inspector.findChild(chat, "workProjectList");
        for (let index = 0; index < list.count; ++index) {
            const row = list.itemAtIndex(index);
            if (row && row.projectId === projectId) {
                const button = inspector.findChild(row, "workRenameProject");
                if (!check(!!button && button.enabled, "botón renombrar proyecto ausente")) return false;
                inspector.mouseClick(button);
                inspector.wait(160);
                const dialog = inspector.findChild(chat, "workRenameProjectDialog");
                const input = inspector.findChild(chat, "workRenameProjectInput");
                if (!check(!!dialog && dialog.visible && !!input && !agent.projectId,
                             "el botón renombrar abre el proyecto o no muestra el diálogo")) return false;
                input.text = newName;
                return click("workConfirmRenameProject");
            }
        }
        return check(false, "fila del proyecto para renombrar no encontrada");
    }
    function requestDelete(projectId) {
        const list = inspector.findChild(chat, "workProjectList");
        for (let index = 0; index < list.count; ++index) {
            const row = list.itemAtIndex(index);
            if (row && row.projectId === projectId) {
                const button = inspector.findChild(row, "workDeleteProject");
                if (!check(!!button && button.enabled, "papelera del proyecto ausente")) return false;
                inspector.mouseClick(button);
                inspector.wait(160);
                return check(inspector.findChild(chat, "workDeleteProjectDialog").visible && !agent.projectId,
                             "la papelera abre el proyecto o no pide confirmación");
            }
        }
        return check(false, "fila del proyecto no encontrada");
    }
    Timer {
        id: steps
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (scenario.stepping) return;
            scenario.stepping = true;
            try {
                if (scenario.stage === 0) {
                    if (!agent.canSend) return;
                    inspector.mouseMove(chat.contentItem, chat.width - 24, 100);
                    inspector.findChild(chat, "chatSidebarDrawer").close();
                    inspector.wait(200);
                    scenario.root = agent.workspace;
                    scenario.prompt = inspector.findChild(chat, "chatPrompt");
                    const switcher = inspector.findChild(chat, "workspaceSwitcher");
                    const position = switcher.mapToItem(chat.contentItem, 0, 0);
                    if (!scenario.check(agent.activeArea === "chat" && switcher.visible
                        && Math.abs(position.x + switcher.width / 2 - chat.width / 2) < 1 && position.y < 30,
                        "Chat y Work no están centrados arriba")) return;
                    scenario.prompt.text = "Borrador de Chat";
                    agent.submit("Conversación de Chat");
                    scenario.stage = 1;
                } else if (scenario.stage === 1) {
                    if (agent.busy) return;
                    scenario.chatId = agent.currentChatId;
                    if (!scenario.check(agent.messages.count === 2, "chat inicial incompleto")) return;
                    if (!scenario.click("workAreaButton")) return;
                    scenario.stage = 2;
                } else if (scenario.stage === 2) {
                    if (agent.areaBusy || agent.activeArea !== "work") return;
                    if (!scenario.check(!agent.workspaceSelected && !inspector.findChild(chat, "chatComposer").visible
                        && inspector.findChild(chat, "workProjects").visible && !agent.messages.count,
                        "Work no abre su pantalla de proyectos o mezcla mensajes")) return;
                    if (!scenario.click("workNewProject")) return;
                    inspector.wait(160);
                    if (!scenario.fillProject("Proyecto A", scenario.root + "/no-existe")) return;
                    scenario.stage = 3;
                } else if (scenario.stage === 3) {
                    if (agent.areaBusy) return;
                    const dialog = inspector.findChild(chat, "workProjectDialog");
                    if (!scenario.check(dialog.visible && !!agent.areaError && !agent.projectId,
                        "carpeta inválida cierra el diálogo o crea un proyecto")) return;
                    if (!scenario.fillProject("Proyecto A", scenario.root)) return;
                    scenario.stage = 4;
                } else if (scenario.stage === 4) {
                    if (agent.areaBusy || !agent.projectId) return;
                    inspector.wait(200);
                    if (!scenario.check(!inspector.findChild(chat, "workProjectDialog").visible
                        && inspector.findChild(chat, "workProjectActions").visible && agent.projectName === "Proyecto A"
                        && scenario.prompt.text === "" && agent.canSend, "proyecto no abrió limpio")) return;
                    const gitBtn = inspector.findChild(chat, "workGitButton");
                    if (!scenario.check(!!gitBtn && gitBtn.visible && gitBtn.enabled, "botón Git ausente en Work")) return;
                    inspector.mouseClick(gitBtn); inspector.wait(220);
                    if (!scenario.check(chat.gitFlowWindow.visible && chat.gitFlowWindow.projectId === agent.projectId,
                        "botón Git no abre el visor de flujo Git para el proyecto")) return;
                    inspector.mouseClick(gitBtn); inspector.wait(180);
                    if (!scenario.check(!chat.gitFlowWindow.visible, "segundo clic en Git no cierra el visor")) return;
                    scenario.firstProject = agent.projectId;
                    scenario.prompt.text = "Borrador del proyecto A";
                    agent.submit("/shell mkdir -p '" + scenario.secondFolder + "'; pwd");
                    scenario.stage = 5;
                } else if (scenario.stage === 5) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.messages.count === 1 && !!agent.messages.get(0).toolJson
                        && JSON.parse(agent.messages.get(0).toolJson).output.trim() === scenario.root,
                        "shell no usa la carpeta del proyecto")) return;
                    agent.submit("Analiza el proyecto A");
                    scenario.stage = 6;
                } else if (scenario.stage === 6) {
                    if (agent.busy) return;
                    scenario.workId = agent.currentChatId;
                    if (!scenario.check(agent.messages.count === 3 && agent.currentChatId !== scenario.chatId,
                        "Work comparte la conversación de Chat")) return;
                    if (!scenario.click("chatAreaButton")) return;
                    scenario.stage = 7;
                } else if (scenario.stage === 7) {
                    if (agent.areaBusy || agent.activeArea !== "chat") return;
                    if (!scenario.check(agent.currentChatId === scenario.chatId && agent.messages.count === 2
                        && scenario.prompt.text === "Borrador de Chat" && agent.workspace === scenario.root
                        && agent.conversations.count === 1 && !inspector.findChild(chat, "workProjectActions").visible,
                        "Chat no recupera mensajes, borrador e historial propios")) return;
                    if (!scenario.click("workAreaButton")) return;
                    scenario.stage = 8;
                } else if (scenario.stage === 8) {
                    if (agent.areaBusy || agent.activeArea !== "work") return;
                    if (!scenario.check(agent.currentChatId === scenario.workId && agent.messages.count === 3
                        && scenario.prompt.text === "Borrador del proyecto A" && agent.projectId === scenario.firstProject,
                        "Work no conserva su contexto y borrador")) return;
                    if (!scenario.click("workProjectsButton")) return;
                    scenario.stage = 9;
                } else if (scenario.stage === 9) {
                    if (agent.areaBusy || agent.projectId) return;
                    if (!scenario.check(inspector.findChild(chat, "workProjectList").count === 1, "lista de proyectos vacía")) return;
                    if (!scenario.click("workNewProject")) return;
                    inspector.wait(160);
                    if (!scenario.fillProject("Proyecto B", scenario.root + "/" + scenario.secondFolder)) return;
                    scenario.stage = 10;
                } else if (scenario.stage === 10) {
                    if (agent.areaBusy || !agent.projectId) return;
                    if (!scenario.check(agent.projectName === "Proyecto B" && agent.projectId !== scenario.firstProject
                        && !agent.messages.count && scenario.prompt.text === "" && !agent.conversations.count,
                        "el segundo proyecto comparte mensajes o borradores")) return;
                    if (!scenario.checkProjectLayout()) return;
                    scenario.secondProject = agent.projectId;
                    agent.submit("/shell pwd");
                    scenario.stage = 11;
                } else if (scenario.stage === 11) {
                    if (agent.busy) return;
                    if (!scenario.check(agent.messages.count === 1
                        && JSON.parse(agent.messages.get(0).toolJson).output.trim() === scenario.root + "/" + scenario.secondFolder,
                        "el segundo proyecto ejecuta comandos en la carpeta anterior")) return;
                    agent.selectArea("work", scenario.firstProject);
                    scenario.stage = 12;
                } else if (scenario.stage === 12) {
                    if (agent.areaBusy || agent.projectId !== scenario.firstProject) return;
                    if (!scenario.check(agent.currentChatId === scenario.workId && scenario.prompt.text === "Borrador del proyecto A"
                        && agent.messages.count === 3 && agent.conversations.count === 1,
                        "volver al proyecto A altera historial o borrador")) return;
                    if (!scenario.click("workProjectsButton")) return;
                    scenario.stage = 13;
                } else if (scenario.stage === 13) {
                    if (agent.areaBusy || agent.projectId) return;
                    inspector.wait(160);
                    if (!scenario.requestRename(scenario.secondProject, "Proyecto B Renombrado")) return;
                    inspector.tryCompare(agent, "areaBusy", false, 1000);
                    inspector.wait(60);
                    if (!scenario.check(agent.projects.get(0).name === "Proyecto B Renombrado"
                        || agent.projects.get(1).name === "Proyecto B Renombrado",
                        "el proyecto no actualizó su nombre en la lista")) return;
                    if (!scenario.requestDelete(scenario.secondProject)) return;
                    if (!scenario.click("workCancelDeleteProject")) return;
                    scenario.stage = 14;
                } else if (scenario.stage === 14) {
                    if (inspector.findChild(chat, "workDeleteProjectDialog").visible) return;
                    if (!scenario.check(agent.projects.count === 2, "cancelar elimina el proyecto")) return;
                    if (!scenario.requestDelete(scenario.secondProject)) return;
                    if (!scenario.click("workConfirmDeleteProject")) return;
                    scenario.stage = 15;
                } else if (scenario.stage === 15) {
                    if (agent.areaBusy || agent.projects.count !== 1) return;
                    if (!scenario.check(agent.projects.get(0).projectId === scenario.firstProject,
                                        "se eliminó el proyecto incorrecto")) return;
                    agent.selectArea("work", scenario.firstProject);
                    scenario.stage = 16;
                } else if (scenario.stage === 16) {
                    if (agent.areaBusy || agent.projectId !== scenario.firstProject) return;
                    if (!scenario.check(agent.currentChatId === scenario.workId && agent.messages.count === 3
                        && scenario.prompt.text === "Borrador del proyecto A", "eliminar B altera el proyecto A")) return;
                    if (!scenario.click("workProjectsButton")) return;
                    scenario.stage = 17;
                } else if (scenario.stage === 17) {
                    if (agent.areaBusy || agent.projectId) return;
                    inspector.wait(160);
                    if (!scenario.requestDelete(scenario.firstProject)) return;
                    if (!scenario.click("workConfirmDeleteProject")) return;
                    scenario.stage = 18;
                } else if (scenario.stage === 18) {
                    if (agent.areaBusy || agent.projects.count) return;
                    const composer = inspector.findChild(chat, "chatComposer");
                    if (!scenario.check(!agent.messages.count && !agent.conversations.count
                        && composer.drafts["work:" + scenario.firstProject] === undefined
                        && composer.imageDrafts["work:" + scenario.firstProject] === undefined
                        && !agent.performanceHistory.some(row => row.chat_id === scenario.workId),
                        "el proyecto eliminado conserva contexto, borradores o métricas")) return;
                    if (!scenario.click("chatAreaButton")) return;
                    scenario.stage = 19;
                } else if (scenario.stage === 19) {
                    if (agent.areaBusy || agent.activeArea !== "chat") return;
                    if (!scenario.check(agent.currentChatId === scenario.chatId && agent.messages.count === 2
                        && scenario.prompt.text === "Borrador de Chat", "eliminar proyectos afecta Chat")) return;
                    console.log("WORKSPACES_OK: selector, cabecera compacta con ruta larga, proyectos, shell, historiales y borradores aislados, cancelación y eliminación");
                    steps.stop(); Qt.callLater(Qt.quit);
                }
            } catch (error) {
                scenario.check(false, "etapa " + scenario.stage + ": " + error.message);
            } finally { scenario.stepping = false; }
        }
    }
}
