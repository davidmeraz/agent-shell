import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

GlassDialog {
    id: dialog
    required property AgentBridge bridge
    title: "Límites de tokens"
    modal: true
    property string selectedPreset: ""
    property string validationError: ""

    function loadFromBridge() {
        selectedPreset = bridge.limitsProfile;
        thresholdInput.text = String(bridge.compactThresholdTokens);
        compactionsInput.text = String(bridge.maxCompactions);
        billableInput.text = String(bridge.maxTurnBillableTokens);
        stepsInput.text = String(bridge.maxSteps);
        outputCharsInput.text = String(bridge.contextOutputChars);
        validationError = "";
    }

    function applyPresetValues(name) {
        selectedPreset = name;
        validationError = "";
        if (name === "ahorro") {
            thresholdInput.text = "40000";
            compactionsInput.text = "3";
            billableInput.text = "200000";
            stepsInput.text = "24";
            outputCharsInput.text = "4000";
        } else if (name === "equilibrado") {
            thresholdInput.text = "60000";
            compactionsInput.text = "3";
            billableInput.text = "0";
            stepsInput.text = "32";
            outputCharsInput.text = "6000";
        } else if (name === "grande") {
            thresholdInput.text = "80000";
            compactionsInput.text = "3";
            billableInput.text = "0";
            stepsInput.text = "48";
            outputCharsInput.text = "8000";
        }
    }

    function parseInteger(text) {
        const cleaned = text.trim();
        if (!/^\d+$/.test(cleaned)) return NaN;
        return parseInt(cleaned, 10);
    }

    function submitLimits() {
        const threshold = parseInteger(thresholdInput.text);
        const maxComp = parseInteger(compactionsInput.text);
        const billable = parseInteger(billableInput.text);
        const steps = parseInteger(stepsInput.text);
        const outChars = parseInteger(outputCharsInput.text);
        if (isNaN(threshold) || (threshold !== 0 && (threshold < 8000 || threshold > 500000))) {
            validationError = "Umbral de compactación: 0 (apagado) o entre 8000 y 500000.";
            return false;
        }
        if (isNaN(maxComp) || maxComp < 1 || maxComp > 20) {
            validationError = "Compactaciones antes de relevo: entre 1 y 20.";
            return false;
        }
        if (isNaN(billable) || (billable !== 0 && (billable < 4000 || billable > 10000000))) {
            validationError = "Fusible facturable: 0 (apagado) o entre 4000 y 10000000.";
            return false;
        }
        if (isNaN(steps) || steps < 1 || steps > 256) {
            validationError = "Pasos máximos por turno: entre 1 y 256.";
            return false;
        }
        if (isNaN(outChars) || outChars < 256 || outChars > 16000) {
            validationError = "Recorte de salida para IA: entre 256 y 16000 caracteres.";
            return false;
        }
        validationError = "";
        const payload = {
            compact_threshold_tokens: threshold,
            max_compactions: maxComp,
            max_turn_billable_tokens: billable,
            max_steps: steps,
            max_tool_calls: Math.min(1024, Math.max(steps * 2, 16)),
            context_output_chars: outChars
        };
        if (selectedPreset === "ahorro" || selectedPreset === "equilibrado" || selectedPreset === "grande")
            payload.preset = selectedPreset;
        bridge.configureLimits(payload);
        return true;
    }

    onOpened: loadFromBridge()

    contentItem: ColumnLayout {
        spacing: 12
        Text {
            Layout.fillWidth: true
            text: "Perfil actual: " + dialog.bridge.limitsProfile
                  + (dialog.bridge.currentChatId ? " · Compactaciones en este chat: "
                     + dialog.bridge.chatCompactionCount + "/" + dialog.bridge.maxCompactions : "")
            color: "#cccccc"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            ActionButton {
                objectName: "limitsPresetAhorro"
                Layout.fillWidth: true
                text: "Ahorro (40k)"
                accent: dialog.selectedPreset === "ahorro"
                onClicked: dialog.applyPresetValues("ahorro")
            }
            ActionButton {
                objectName: "limitsPresetEquilibrado"
                Layout.fillWidth: true
                text: "Equilibrado (60k)"
                accent: dialog.selectedPreset === "equilibrado"
                onClicked: dialog.applyPresetValues("equilibrado")
            }
            ActionButton {
                objectName: "limitsPresetGrande"
                Layout.fillWidth: true
                text: "Grande (80k)"
                accent: dialog.selectedPreset === "grande"
                onClicked: dialog.applyPresetValues("grande")
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 8

            Text { text: "Umbral auto-compactación (0 = off)"; color: "#dddddd"; font.pixelSize: 12; Layout.fillWidth: true }
            GlassPanel {
                implicitWidth: 128; implicitHeight: 34; radius: 8; highlighted: thresholdInput.activeFocus
                TextInput {
                    id: thresholdInput; objectName: "limitsThresholdInput"
                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                    color: "#f5f5f5"; selectionColor: "#ffffff"; selectedTextColor: "#000000"; font.pixelSize: 13
                    onTextEdited: dialog.selectedPreset = "personalizado"
                }
            }

            Text { text: "Compactaciones antes de relevo"; color: "#dddddd"; font.pixelSize: 12; Layout.fillWidth: true }
            GlassPanel {
                implicitWidth: 128; implicitHeight: 34; radius: 8; highlighted: compactionsInput.activeFocus
                TextInput {
                    id: compactionsInput; objectName: "limitsCompactionsInput"
                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                    color: "#f5f5f5"; selectionColor: "#ffffff"; selectedTextColor: "#000000"; font.pixelSize: 13
                    onTextEdited: dialog.selectedPreset = "personalizado"
                }
            }

            Text { text: "Fusible facturable / turno (0 = off)"; color: "#dddddd"; font.pixelSize: 12; Layout.fillWidth: true }
            GlassPanel {
                implicitWidth: 128; implicitHeight: 34; radius: 8; highlighted: billableInput.activeFocus
                TextInput {
                    id: billableInput; objectName: "limitsBillableInput"
                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                    color: "#f5f5f5"; selectionColor: "#ffffff"; selectedTextColor: "#000000"; font.pixelSize: 13
                    onTextEdited: dialog.selectedPreset = "personalizado"
                }
            }

            Text { text: "Pasos máximos por turno"; color: "#dddddd"; font.pixelSize: 12; Layout.fillWidth: true }
            GlassPanel {
                implicitWidth: 128; implicitHeight: 34; radius: 8; highlighted: stepsInput.activeFocus
                TextInput {
                    id: stepsInput; objectName: "limitsStepsInput"
                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                    color: "#f5f5f5"; selectionColor: "#ffffff"; selectedTextColor: "#000000"; font.pixelSize: 13
                    onTextEdited: dialog.selectedPreset = "personalizado"
                }
            }

            Text { text: "Recorte de salida para IA (chars)"; color: "#dddddd"; font.pixelSize: 12; Layout.fillWidth: true }
            GlassPanel {
                implicitWidth: 128; implicitHeight: 34; radius: 8; highlighted: outputCharsInput.activeFocus
                TextInput {
                    id: outputCharsInput; objectName: "limitsOutputCharsInput"
                    anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                    color: "#f5f5f5"; selectionColor: "#ffffff"; selectedTextColor: "#000000"; font.pixelSize: 13
                    onTextEdited: dialog.selectedPreset = "personalizado"
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: "El fusible facturable cuenta sólo entrada sin caché + salida (no penaliza caché). "
                  + "Al alcanzar el límite de compactaciones se abre un chat nuevo con el relevo esencial y el historial Git."
            color: "#aaaaaa"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: dialog.validationError !== "" || dialog.bridge.limitsError !== ""
            text: dialog.validationError || dialog.bridge.limitsError
            color: "#f5f5f5"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
    footer: DialogButtonBox {
        padding: 16
        background: null
        ActionButton { text: "Cancelar"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        ActionButton {
            objectName: "limitsApplyButton"
            text: "Aplicar"
            accent: true
            enabled: dialog.bridge.ready && !dialog.bridge.busy && !dialog.bridge.loginBusy
            onClicked: {
                if (dialog.submitLimits()) dialog.accept();
            }
        }
    }
}
