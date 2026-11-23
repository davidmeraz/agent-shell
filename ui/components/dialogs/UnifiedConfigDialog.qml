import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import "../shared"

// Configuración del modo unificado: cascada de arquitectos, umbral % y obreros dedicados.
GlassDialog {
    id: dialog
    required property AgentBridge bridge
    title: "Modo unificado · Cascada y obreros"
    modal: true

    property int thresholdValue: 35
    property bool parallelValue: true
    property var cascadeDraft: []
    property var workersDraft: []
    property string validationError: ""

    readonly property var providerOptions: [
        { id: "agy", label: "Gemini (agy)" },
        { id: "claude", label: "Claude" },
        { id: "chatgpt", label: "ChatGPT" }
    ]
    readonly property var effortOptions: [
        { id: "", label: "Auto" },
        { id: "low", label: "low" },
        { id: "medium", label: "medium" },
        { id: "high", label: "high" },
        { id: "xhigh", label: "xhigh" },
        { id: "max", label: "max" }
    ]
    readonly property var autoWorkerTiers: [
        { key: "__auto__:balanced", label: "Auto · Balanceado", tier: "balanced" },
        { key: "__auto__:fast", label: "Auto · Rápido", tier: "fast" },
        { key: "__auto__:strong", label: "Auto · Potente", tier: "strong" }
    ]

    function cloneDefaultCascade() {
        return [
            { provider: "agy", model: "gemini-4-neon-xhigh", effort: "xhigh" },
            { provider: "claude", model: "claude-opus", effort: "xhigh" },
            { provider: "chatgpt", model: "gpt-6.2-astra", effort: "high" }
        ];
    }

    function cloneDefaultWorkers() {
        return [
            { slot: "chatgpt", provider: "chatgpt", model: "", effort: "medium", tier: "balanced" },
            { slot: "claude", provider: "claude", model: "", effort: "medium", tier: "balanced" }
        ];
    }

    function loadFromBridge() {
        const cfg = bridge.unifiedConfig || ({});
        thresholdValue = typeof cfg.quota_threshold === "number" ? cfg.quota_threshold : 35;
        thresholdInput.text = String(thresholdValue);
        parallelValue = cfg.parallel_workers !== false;
        const srcCascade = Array.isArray(cfg.architect_cascade) && cfg.architect_cascade.length
            ? cfg.architect_cascade : cloneDefaultCascade();
        cascadeDraft = srcCascade.map(step => ({
            provider: step.provider || "agy",
            model: step.model || "",
            effort: step.effort || ""
        }));
        const srcWorkers = Array.isArray(cfg.workers) && cfg.workers.length
            ? cfg.workers : cloneDefaultWorkers();
        workersDraft = srcWorkers.map(worker => ({
            slot: worker.slot || worker.provider || "chatgpt",
            provider: worker.provider || worker.slot || "chatgpt",
            model: worker.model || "",
            effort: worker.effort || "medium",
            tier: worker.tier || "balanced"
        }));
        validationError = "";
    }

    function catalogFor(provider) {
        const catalogs = bridge.providerCatalogs || ({});
        return Array.isArray(catalogs[provider]) ? catalogs[provider] : [];
    }

    function modelOptionsFor(provider, currentModel, isWorker) {
        const rows = [];
        if (isWorker) {
            for (const preset of autoWorkerTiers)
                rows.push({ value: preset.key, label: preset.label });
        } else {
            rows.push({ value: "", label: "Auto (buque insignia)" });
        }
        const catalog = catalogFor(provider);
        const seen = {};
        for (const item of catalog) {
            seen[item.slug] = true;
            rows.push({ value: item.slug, label: item.display_name || item.slug });
        }
        if (currentModel && !seen[currentModel])
            rows.push({ value: currentModel, label: currentModel });
        return rows;
    }

    function effortFromSlug(slug) {
        const match = /-(low|medium|high|xhigh|max)$/.exec(slug || "");
        return match ? match[1] : "";
    }

    function syncAgySlug(provider, model, effort) {
        if (provider !== "agy" || !model || !effort) return model;
        const base = model.replace(/-(low|medium|high|xhigh|max)$/, "");
        const candidate = base + "-" + effort;
        const catalog = catalogFor("agy");
        return catalog.some(item => item.slug === candidate) ? candidate : model;
    }

    function updateCascadeStep(index, patch) {
        const next = cascadeDraft.map((item, idx) => idx === index ? Object.assign({}, item, patch) : item);
        cascadeDraft = next;
        validationError = "";
    }

    function moveCascadeStep(index, delta) {
        const target = index + delta;
        if (target < 0 || target >= cascadeDraft.length) return;
        const next = cascadeDraft.slice();
        const tmp = next[index];
        next[index] = next[target];
        next[target] = tmp;
        cascadeDraft = next;
    }

    function updateWorkerSlot(index, patch) {
        const next = workersDraft.map((item, idx) => idx === index ? Object.assign({}, item, patch) : item);
        workersDraft = next;
        validationError = "";
    }

    function indexByKey(list, key, value) {
        for (let i = 0; i < list.length; ++i)
            if (list[i][key] === value) return i;
        return 0;
    }

    function submitConfig() {
        const cleaned = thresholdInput.text.trim();
        if (!/^\d+$/.test(cleaned)) {
            validationError = "El umbral de cuota debe ser un entero entre 0 y 95.";
            return false;
        }
        const parsedThreshold = parseInt(cleaned, 10);
        if (isNaN(parsedThreshold) || parsedThreshold < 0 || parsedThreshold > 95) {
            validationError = "El umbral de cuota debe estar entre 0 y 95%.";
            return false;
        }
        const seenSlots = {};
        const cleanWorkers = [];
        for (const worker of workersDraft) {
            const slot = worker.provider;
            if (seenSlots[slot]) {
                validationError = "Cada obrero debe usar un proveedor distinto (ej. ChatGPT y Claude).";
                return false;
            }
            seenSlots[slot] = true;
            cleanWorkers.push({
                slot: slot,
                provider: worker.provider,
                model: worker.model || "",
                effort: worker.effort || "",
                tier: worker.tier || "balanced"
            });
        }
        const cleanCascade = cascadeDraft.map(step => ({
            provider: step.provider,
            model: step.model || "",
            effort: step.effort || ""
        }));
        validationError = "";
        bridge.configureUnified({
            quota_threshold: parsedThreshold,
            parallel_workers: parallelValue,
            architect_cascade: cleanCascade,
            workers: cleanWorkers
        });
        return true;
    }

    onOpened: {
        bridge.prepareUnified();
        loadFromBridge();
    }

    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: "El modo unificado arranca con el 1.° arquitecto y cambia automáticamente al siguiente cuando su cuota restante (ventana 5 h o semanal) baja al umbral."
                color: GemaTheme.subtleColor
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            // Umbral de cuota %
            GlassPanel {
                Layout.fillWidth: true
                implicitHeight: thresholdRow.implicitHeight + 16
                radius: 11
                reflective: false
                topColor: "#14ffffff"
                bottomColor: "#08ffffff"
                edgeColor: "#26ffffff"
                RowLayout {
                    id: thresholdRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Umbral de cambio (% restante)"
                            color: GemaTheme.textColor
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: "Cambia de arquitecto al llegar a ≤ este porcentaje."
                            color: GemaTheme.subtleColor
                            font.pixelSize: 10
                        }
                    }
                    Repeater {
                        model: [20, 35, 50]
                        delegate: ActionButton {
                            required property int modelData
                            text: modelData + "%"
                            font.pixelSize: 11
                            verticalPadding: 4
                            horizontalPadding: 8
                            accent: thresholdInput.text.trim() === String(modelData)
                            onClicked: {
                                thresholdInput.text = String(modelData);
                                dialog.thresholdValue = modelData;
                                dialog.validationError = "";
                            }
                        }
                    }
                    GlassPanel {
                        implicitWidth: 64
                        implicitHeight: 32
                        radius: 8
                        reflective: false
                        highlighted: thresholdInput.activeFocus
                        TextInput {
                            id: thresholdInput
                            objectName: "unifiedThresholdInput"
                            anchors.fill: parent
                            anchors.margins: 6
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#f5f5f5"
                            selectionColor: "#ffffff"
                            selectedTextColor: "#000000"
                            font.pixelSize: 13
                            onTextEdited: dialog.validationError = ""
                        }
                    }
                }
            }

            // Cascada de arquitectos
            Text {
                text: "CASCADA DE ARQUITECTOS (ORDEN DE PRIORIDAD)"
                color: GemaTheme.subtleColor
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }

            Repeater {
                model: dialog.cascadeDraft
                delegate: GlassPanel {
                    id: stepCard
                    required property var modelData
                    required property int index
                    readonly property var modelList: dialog.modelOptionsFor(modelData.provider, modelData.model, false)
                    Layout.fillWidth: true
                    implicitHeight: stepCol.implicitHeight + 16
                    radius: 11
                    reflective: false
                    topColor: "#14ffffff"
                    bottomColor: "#08ffffff"
                    edgeColor: "#26ffffff"
                    ColumnLayout {
                        id: stepCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: (stepCard.index + 1) + ".° Arquitecto"
                                color: GemaTheme.synced ? GemaTheme.accentInk : "#ffffff"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            Item { Layout.fillWidth: true }
                            ActionButton {
                                text: "↑"
                                font.pixelSize: 11
                                verticalPadding: 2
                                horizontalPadding: 7
                                enabled: stepCard.index > 0
                                onClicked: dialog.moveCascadeStep(stepCard.index, -1)
                            }
                            ActionButton {
                                text: "↓"
                                font.pixelSize: 11
                                verticalPadding: 2
                                horizontalPadding: 7
                                enabled: stepCard.index < dialog.cascadeDraft.length - 1
                                onClicked: dialog.moveCascadeStep(stepCard.index, 1)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            GlassComboBox {
                                objectName: "unifiedCascadeProvider_" + stepCard.index
                                Layout.preferredWidth: 128
                                implicitHeight: 34
                                font.pixelSize: 11
                                model: dialog.providerOptions
                                textRole: "label"
                                currentIndex: dialog.indexByKey(dialog.providerOptions, "id", stepCard.modelData.provider)
                                onActivated: idx => {
                                    const nextProv = dialog.providerOptions[idx].id;
                                    dialog.updateCascadeStep(stepCard.index, {
                                        provider: nextProv,
                                        model: "",
                                        effort: nextProv === "chatgpt" ? "high" : "xhigh"
                                    });
                                }
                            }
                            GlassComboBox {
                                objectName: "unifiedCascadeModel_" + stepCard.index
                                Layout.fillWidth: true
                                implicitHeight: 34
                                font.pixelSize: 11
                                model: stepCard.modelList
                                textRole: "label"
                                currentIndex: dialog.indexByKey(stepCard.modelList, "value", stepCard.modelData.model)
                                onActivated: idx => {
                                    const chosen = stepCard.modelList[idx].value;
                                    const inferred = stepCard.modelData.provider === "agy" ? dialog.effortFromSlug(chosen) : "";
                                    dialog.updateCascadeStep(stepCard.index, {
                                        model: chosen,
                                        effort: inferred || stepCard.modelData.effort
                                    });
                                }
                            }
                            GlassComboBox {
                                objectName: "unifiedCascadeEffort_" + stepCard.index
                                Layout.preferredWidth: 92
                                implicitHeight: 34
                                font.pixelSize: 11
                                model: dialog.effortOptions
                                textRole: "label"
                                currentIndex: dialog.indexByKey(dialog.effortOptions, "id", stepCard.modelData.effort)
                                onActivated: idx => {
                                    const nextEffort = dialog.effortOptions[idx].id;
                                    const synced = dialog.syncAgySlug(stepCard.modelData.provider, stepCard.modelData.model, nextEffort);
                                    dialog.updateCascadeStep(stepCard.index, { model: synced, effort: nextEffort });
                                }
                            }
                        }
                    }
                }
            }

            // Obreros dedicados
            Text {
                Layout.topMargin: 4
                text: "OBREROS DEDICADOS (2 PROVEEDORES)"
                color: GemaTheme.subtleColor
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }

            Repeater {
                model: dialog.workersDraft
                delegate: GlassPanel {
                    id: workerCard
                    required property var modelData
                    required property int index
                    readonly property var modelList: dialog.modelOptionsFor(modelData.provider, modelData.model, true)
                    readonly property string selectedValue: modelData.model ? modelData.model : ("__auto__:" + (modelData.tier || "balanced"))
                    Layout.fillWidth: true
                    implicitHeight: workerCol.implicitHeight + 16
                    radius: 11
                    reflective: false
                    topColor: "#14ffffff"
                    bottomColor: "#08ffffff"
                    edgeColor: "#26ffffff"
                    ColumnLayout {
                        id: workerCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        Text {
                            text: "Obrero " + (workerCard.index + 1)
                            color: GemaTheme.textColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            GlassComboBox {
                                objectName: "unifiedWorkerProvider_" + workerCard.index
                                Layout.preferredWidth: 128
                                implicitHeight: 34
                                font.pixelSize: 11
                                model: dialog.providerOptions
                                textRole: "label"
                                currentIndex: dialog.indexByKey(dialog.providerOptions, "id", workerCard.modelData.provider)
                                onActivated: idx => {
                                    const nextProv = dialog.providerOptions[idx].id;
                                    dialog.updateWorkerSlot(workerCard.index, {
                                        slot: nextProv,
                                        provider: nextProv,
                                        model: "",
                                        effort: "medium",
                                        tier: "balanced"
                                    });
                                }
                            }
                            GlassComboBox {
                                objectName: "unifiedWorkerModel_" + workerCard.index
                                Layout.fillWidth: true
                                implicitHeight: 34
                                font.pixelSize: 11
                                model: workerCard.modelList
                                textRole: "label"
                                currentIndex: dialog.indexByKey(workerCard.modelList, "value", workerCard.selectedValue)
                                onActivated: idx => {
                                    const val = workerCard.modelList[idx].value;
                                    if (val.startsWith("__auto__:")) {
                                        dialog.updateWorkerSlot(workerCard.index, {
                                            model: "",
                                            tier: val.slice("__auto__:".length)
                                        });
                                    } else {
                                        const inferred = workerCard.modelData.provider === "agy" ? dialog.effortFromSlug(val) : "";
                                        dialog.updateWorkerSlot(workerCard.index, {
                                            model: val,
                                            effort: inferred || workerCard.modelData.effort
                                        });
                                    }
                                }
                            }
                            GlassComboBox {
                                objectName: "unifiedWorkerEffort_" + workerCard.index
                                Layout.preferredWidth: 92
                                implicitHeight: 34
                                font.pixelSize: 11
                                model: dialog.effortOptions
                                textRole: "label"
                                currentIndex: dialog.indexByKey(dialog.effortOptions, "id", workerCard.modelData.effort)
                                onActivated: idx => {
                                    const nextEffort = dialog.effortOptions[idx].id;
                                    const synced = dialog.syncAgySlug(workerCard.modelData.provider, workerCard.modelData.model, nextEffort);
                                    dialog.updateWorkerSlot(workerCard.index, { model: synced, effort: nextEffort });
                                }
                            }
                        }
                    }
                }
            }

            GlassPanel {
                Layout.fillWidth: true
                implicitHeight: parallelRow.implicitHeight + 14
                radius: 11
                reflective: false
                topColor: "#12ffffff"
                bottomColor: "#06ffffff"
                edgeColor: "#24ffffff"
                RowLayout {
                    id: parallelRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Ejecución en paralelo de obreros"
                            color: GemaTheme.textColor
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Permite que Obrero ChatGPT y Obrero Claude trabajen a la vez en archivos distintos."
                            color: GemaTheme.subtleColor
                            font.pixelSize: 10
                            wrapMode: Text.Wrap
                        }
                    }
                    ActionButton {
                        objectName: "unifiedParallelToggle"
                        text: dialog.parallelValue ? "Activo" : "En serie"
                        accent: dialog.parallelValue
                        font.pixelSize: 11
                        verticalPadding: 5
                        horizontalPadding: 12
                        onClicked: dialog.parallelValue = !dialog.parallelValue
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: dialog.validationError !== "" || dialog.bridge.unifiedConfigError !== ""
                text: dialog.validationError || dialog.bridge.unifiedConfigError
                color: "#ffb3bf"
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }

    footer: DialogButtonBox {
        padding: 16
        spacing: 8
        background: null
        ActionButton {
            objectName: "unifiedResetButton"
            text: "Predeterminado"
            enabled: dialog.bridge.ready && !dialog.bridge.busy
            onClicked: {
                dialog.bridge.resetUnifiedConfig();
                dialog.thresholdValue = 35;
                thresholdInput.text = "35";
                dialog.parallelValue = true;
                dialog.cascadeDraft = dialog.cloneDefaultCascade();
                dialog.workersDraft = dialog.cloneDefaultWorkers();
                dialog.validationError = "";
            }
        }
        ActionButton { text: "Cancelar"; DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
        ActionButton {
            objectName: "unifiedSaveButton"
            text: "Guardar"
            accent: true
            enabled: dialog.bridge.ready && !dialog.bridge.busy
            onClicked: {
                if (dialog.submitConfig()) dialog.accept();
            }
        }
    }
}
