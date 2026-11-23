import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../js/CodeSyntax.js" as CodeSyntax
import "../../js/FileChanges.js" as FileChanges
import "../shared"

// Visor independiente: sólo lee el archivo abierto y descarta respuestas tardías.
FloatingWindow {
    id: viewer
    required property AgentBridge bridge
    required property int viewerId
    property bool floatingMode: false
    property string mainWindowTitle: ""
    property string projectId: ""
    property string projectName: ""
    objectName: "projectFileWindow"
    title: (floatingMode ? "Flotante " + viewerId : "Visor " + viewerId) + " · " + (filePath || projectName)
    implicitWidth: floatingMode ? 740 : 820
    implicitHeight: floatingMode ? 620 : (viewerId === 1 ? 1330 : 655)
    minimumSize: Qt.size(420, 320)
    color: "transparent"
    visible: false
    // Permite reabrir tras cerrar con el atajo del compositor o la decoración.
    onClosed: viewer.visible = false
    BackgroundEffect.blurRegion: Region { item: matteSurface; radius: matteSurface.radius }
    property string filePath: ""
    property string preview: ""
    property bool previewTruncated: false
    property int previewLines: -1
    property string pendingId: ""
    property int serial: 0
    property string activityState: ""
    property bool deleted: false
    property real changeGlow: 0
    property int changeStart: 0
    property int changeEnd: 0
    property real changeTop: 0
    property real changeHeight: 0
    property int changeRevision: 0
    property real contentProgress: 1
    readonly property bool writing: writeReveal.running
    readonly property string displayedPreview: code.text
    property bool followWriting: true
    readonly property var scroller: codeScroll.contentItem
    readonly property var syntaxPalette: GemaTheme.codePalette
    readonly property var languageInfo: CodeSyntax.detectLanguage(filePath)
    readonly property color languageColor: CodeSyntax.roleColor(syntaxPalette, languageInfo.role)
    readonly property string dirPrefix: {
        const slash = filePath.lastIndexOf("/");
        return slash >= 0 ? filePath.slice(0, slash + 1) : "";
    }
    readonly property string fileName: {
        const slash = filePath.lastIndexOf("/");
        return slash >= 0 ? filePath.slice(slash + 1) : filePath;
    }
    property var lineOffsets: [0]
    property string highlightedHtml: ""
    property int writingLineIndex: -1
    property int changeStartLine: -1
    property int changeEndLine: -1
    property bool wordWrap: false
    property int indentSize: 4
    property var indentCols: []
    property var codeScopes: []
    property int cursorLineIndex: 0
    property int cursorColumnIndex: 1
    property int hoveredLineIndex: -1
    property bool hasClickedLine: false
    property bool copiedNotice: false
    readonly property int effectiveLineIndex: writing && writingLineIndex >= 0
        ? writingLineIndex
        : (hasClickedLine ? cursorLineIndex : (hoveredLineIndex >= 0 ? hoveredLineIndex : cursorLineIndex))
    readonly property var activeScopeChain: CodeSyntax.findActiveScopes(codeScopes, effectiveLineIndex)
    readonly property var activeBreadcrumbs: activeScopeChain.filter(s => !!s.label)
    readonly property var activeScope: activeScopeChain.length > 0 ? activeScopeChain[activeScopeChain.length - 1] : null
    readonly property var primaryScope: {
        if (!codeScopes || !codeScopes.length) return null;
        const mainFn = codeScopes.find(s => s.kind === "func" && /^main\b/i.test(s.label || ""));
        if (mainFn) return mainFn;
        const named = codeScopes.filter(s => !!s.label && (s.kind === "func" || s.kind === "type"));
        if (named.length > 0) {
            let best = named[0];
            for (let i = 1; i < named.length; ++i) {
                if (named[i].indentCol < best.indentCol) best = named[i];
            }
            return best;
        }
        return codeScopes.find(s => !!s.label) || null;
    }
    readonly property var displayedBreadcrumbs: {
        if (activeBreadcrumbs.length > 0) return activeBreadcrumbs.slice(-4);
        if (primaryScope) return [primaryScope];
        if (fileName) return [{ label: fileName, kind: "file", startLine: 0, endLine: Math.max(0, liveLineCount - 1) }];
        return [];
    }
    readonly property var displayedScopeRange: activeScope || primaryScope
    readonly property var activeFunctionScope: {
        for (let i = activeScopeChain.length - 1; i >= 0; --i) {
            if (activeScopeChain[i].kind === "func" || activeScopeChain[i].kind === "type")
                return activeScopeChain[i];
        }
        return null;
    }
    readonly property real charWidth: {
        const text = code.text;
        const offsets = lineOffsets;
        if (text && offsets && offsets.length > 0) {
            for (let i = 0; i < Math.min(offsets.length, 120); ++i) {
                const start = offsets[i];
                let spaces = 0;
                while (start + spaces < text.length && text[start + spaces] === " " && spaces < 16)
                    spaces++;
                if (spaces >= 2) {
                    const x0 = code.positionToRectangle(start).x;
                    const xN = code.positionToRectangle(start + spaces).x;
                    if (xN > x0) return (xN - x0) / spaces;
                }
            }
        }
        return Math.max(5, codeMetrics.advanceWidth("        ") / 8.0);
    }
    readonly property int liveLineCount: Math.max(1, lineOffsets.length - (code.text.endsWith("\n") ? 1 : 0))
    readonly property int gutterDigits: Math.max(2, String(Math.max(liveLineCount, previewLines, 1)).length)
    readonly property int gutterWidth: gutterDigits * 8 + 20
    readonly property bool highlightActive: languageInfo.id !== "plain" && code.text.length > 0
                                            && code.text.length <= (writing ? 28000 : 64000)

    FontMetrics {
        id: codeMetrics
        font: code.font
    }

    Timer {
        id: copiedResetTimer
        interval: 1400
        repeat: false
        onTriggered: viewer.copiedNotice = false
    }

    onActivityStateChanged: {
        if (["interrupted", "failed", "error", "timeout"].includes(activityState)) writeReveal.finish();
    }
    onFilePathChanged: syncSyntax()
    onSyntaxPaletteChanged: syncSyntax()
    onHighlightActiveChanged: syncSyntax()
    onWordWrapChanged: {
        syncSyntax();
        Qt.callLater(viewer.updateChangeGeometry);
        Qt.callLater(viewer.repaintCodeOverlays);
    }
    onEffectiveLineIndexChanged: repaintCodeOverlays()
    onHoveredLineIndexChanged: repaintCodeOverlays()
    onWritingChanged: {
        syncSyntax();
        repaintCodeOverlays();
    }
    onChangeGlowChanged: repaintCodeOverlays()

    function repaintCodeOverlays() {
        codeGutter.requestPaint();
        codeGuidesCanvas.requestPaint();
    }

    function updateCursorLocation(markClicked) {
        const pos = Math.min(code.cursorPosition, code.text.length);
        const lineIdx = findLineIndex(pos);
        const lineStart = lineOffsets[lineIdx] || 0;
        cursorLineIndex = lineIdx;
        cursorColumnIndex = Math.max(1, pos - lineStart + 1);
        if (markClicked) hasClickedLine = true;
        repaintCodeOverlays();
    }

    function jumpToLine(lineIndex) {
        if (lineIndex < 0 || lineIndex >= lineOffsets.length) return;
        const pos = Math.min(lineOffsets[lineIndex], code.text.length);
        const rect = code.positionToRectangle(pos);
        if (scroller) {
            scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, rect.y - 24));
        }
        code.cursorPosition = pos;
        updateCursorLocation(true);
    }

    function findLineIndex(pos) {
        const offsets = lineOffsets;
        let lo = 0;
        let hi = offsets.length - 1;
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1;
            if (offsets[mid] <= pos) lo = mid;
            else hi = mid - 1;
        }
        return lo;
    }

    function syncSyntax() {
        const current = code.text;
        lineOffsets = CodeSyntax.computeLineOffsets(current);
        writingLineIndex = writing ? findLineIndex(Math.min(writeReveal.position, current.length)) : -1;
        if (changeHeight > 0 && changeGlow > 0) {
            changeStartLine = findLineIndex(Math.min(changeStart, current.length));
            changeEndLine = findLineIndex(Math.min(changeEnd, current.length));
        } else {
            changeStartLine = -1;
            changeEndLine = -1;
        }
        const canHighlight = languageInfo.id !== "plain" && current.length > 0
            && current.length <= (writing ? 28000 : 64000);
        highlightedHtml = canHighlight ? CodeSyntax.highlightToHtml(current, languageInfo.id, syntaxPalette, wordWrap) : "";
        if (current.length > 0 && current.length <= (writing ? 20000 : 64000)) {
            const structure = CodeSyntax.analyzeCodeStructure(current, languageInfo.id);
            indentSize = structure.indentSize;
            indentCols = structure.indentCols;
            codeScopes = structure.scopes;
        } else {
            indentCols = [];
            codeScopes = [];
        }
        updateCursorLocation(false);
    }

    FileWriteReveal {
        id: writeReveal
        editor: code
        onAdvanced: {
            viewer.writingLineIndex = viewer.findLineIndex(Math.min(writeReveal.position, code.length));
            viewer.repaintCodeOverlays();
            Qt.callLater(viewer.followWritingCursor);
        }
    }
    function followWritingCursor() {
        if (!visible || !writing || !followWriting || scroller.moving || code.selectedText) return;
        const cursor = code.positionToRectangle(Math.min(writeReveal.position, code.length));
        if (cursor.y < scroller.contentY) scroller.contentY = Math.max(0, cursor.y - 16);
        else if (cursor.y + cursor.height > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height),
                cursor.y + cursor.height - scroller.height + 24);
    }
    Connections {
        target: viewer.scroller
        function onMovementStarted() { viewer.followWriting = false; }
        function onMovementEnded() { viewer.followWriting = viewer.scroller.atYEnd; }
        function onContentXChanged() { viewer.repaintCodeOverlays(); }
        function onContentYChanged() { viewer.repaintCodeOverlays(); }
        function onHeightChanged() { viewer.repaintCodeOverlays(); }
    }

    function updateChangeGeometry() {
        const first = code.positionToRectangle(Math.min(changeStart, code.length));
        const last = code.positionToRectangle(Math.min(changeEnd, code.length));
        changeTop = first.y;
        changeHeight = Math.max(first.height, last.y + last.height - first.y);
        if (changeGlow > 0) {
            changeStartLine = findLineIndex(Math.min(changeStart, code.length));
            changeEndLine = findLineIndex(Math.min(changeEnd, code.length));
        }
        codeGutter.requestPaint();
    }

    function applyPreview(data, animated) {
        const changed = preview !== data.text;
        const text = FileChanges.visibleText(data.text);
        const range = changed ? FileChanges.range(previewLines < 0 ? "" : FileChanges.visibleText(preview), text) : null;
        preview = data.text;
        previewTruncated = data.truncated;
        previewLines = text ? text.split("\n").length - (text.endsWith("\n") ? 1 : 0) : 0;
        writeReveal.apply(data.text, animated && visible && !deleted);
        if (changed) {
            changeStart = range.start;
            changeEnd = range.end;
            const revision = ++changeRevision;
            Qt.callLater(function() {
                if (!viewer.visible || viewer.changeRevision !== revision) return;
                viewer.updateChangeGeometry();
                if (animated) highlight.restart();
            });
        }
    }
    function followChange(data) {
        if (!visible || filePath !== data.path) openFile(data.path, true);
        // La instantánea del disco invalida cualquier lectura periódica anterior.
        pendingId = "";
        deleted = false;
        activityState = "running";
        applyPreview(data.preview, true);
    }
    function markDeleted() {
        writeReveal.finish();
        pendingId = "";
        deleted = true;
        activityState = "deleted";
    }
    SequentialAnimation {
        id: highlight
        NumberAnimation { target: viewer; property: "changeGlow"; to: 0.085; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: viewer; property: "changeGlow"; to: 0; duration: 1250; easing.type: Easing.OutCubic }
    }
    NumberAnimation {
        id: fileTransition
        target: viewer
        property: "contentProgress"
        from: 0.65; to: 1; duration: 280
        easing.type: Easing.OutCubic
    }

    function clear() {
        visible = false;
        pendingId = "";
        filePath = "";
        preview = "";
        writeReveal.reset("");
        previewTruncated = false;
        previewLines = -1;
        activityState = ""; deleted = false;
        highlight.stop(); changeGlow = 0;
        ++changeRevision; changeStart = 0; changeEnd = 0; changeHeight = 0;
        changeStartLine = -1; changeEndLine = -1; writingLineIndex = -1;
    }
    function openFile(path, following = false) {
        const wasVisible = visible;
        const switching = wasVisible && filePath !== path;
        highlight.stop(); changeGlow = 0; ++changeRevision; changeHeight = 0;
        changeStartLine = -1; changeEndLine = -1;
        pendingId = "";
        filePath = path;
        hasClickedLine = false;
        hoveredLineIndex = -1;
        cursorLineIndex = 0;
        cursorColumnIndex = 1;
        preview = following ? "" : "Cargando…";
        writeReveal.reset(preview);
        followWriting = true;
        previewTruncated = false;
        previewLines = -1;
        activityState = ""; deleted = false;
        visible = true;
        if (!following) refresh();
        if (switching) fileTransition.restart();
        // Wayland delega la posición al compositor; sólo se aplica al abrir.
        if (!wasVisible && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") {
            const roleId = floatingMode ? Math.min(20, 4 + Math.max(1, viewerId - 2)) : viewerId;
            placement.command = [Quickshell.env("AGENT_SHELL_PYTHON") || Quickshell.shellDir + "/.venv/bin/python",
                Quickshell.shellDir + "/scripts/place-text-viewer.py",
                String(Quickshell.processId), title, String(roleId), mainWindowTitle];
            placement.running = true;
        }
    }
    function refresh() {
        if (!visible || !filePath || pendingId || deleted || writing || !bridge.ready
            || !projectId) return;
        pendingId = "file-viewer-" + viewerId + "-" + (++serial);
        bridge.sendCommand({ type: "explorer.read", project_id: projectId,
                             request_id: pendingId, path: filePath });
    }
    onVisibleChanged: {
        if (!visible) {
            pendingId = "";
            writeReveal.finish();
            placement.running = false;
            highlight.stop(); changeGlow = 0;
            fileTransition.stop(); contentProgress = 1;
            ++changeRevision;
        } else {
            Qt.callLater(viewer.repaintCodeOverlays);
        }
    }
    Process {
        id: placement
        stderr: SplitParser { onRead: data => console.warn("Posición del visor: " + data) }
    }
    Connections {
        target: viewer.bridge
        function onReadyChanged() { viewer.clear(); }
        function onEventReceived(event) {
            const data = event.data;
            if (!viewer.visible || !viewer.pendingId || data.project_id !== viewer.projectId
                || data.request_id !== viewer.pendingId) return;
            if (event.type === "explorer.file" && data.path === viewer.filePath) {
                viewer.pendingId = "";
                viewer.applyPreview(data, viewer.activityState === "running");
            } else if (event.type === "explorer.error") {
                viewer.pendingId = "";
                viewer.preview = data.message;
                writeReveal.reset(data.message);
                viewer.previewTruncated = false;
                viewer.previewLines = -1;
            }
        }
    }
    Timer { interval: 1500; repeat: true; running: viewer.visible && viewer.bridge.ready; onTriggered: viewer.refresh() }
    ViewerMotion {
        id: windowMotion
        anchors.fill: parent
        shown: viewer.visible
        MattePanel {
            id: matteSurface
            objectName: "projectFileMatteSurface"
            anchors.fill: parent
            anchors.margins: 1
            radius: 20
            topColor: "#54141c26"
            bottomColor: "#680c121a"
            edgeColor: "#4cffffff"
            highlighted: viewer.writing
            Rectangle {
                anchors.fill: parent
                radius: 20
                color: GemaTheme.accent
                opacity: viewer.changeGlow * 0.72
            }
        }
        ColumnLayout {
            focus: true
            Keys.onEscapePressed: event => { viewer.visible = false; event.accepted = true; }
            Shortcut {
                sequence: "Alt+Z"
                context: Qt.WindowShortcut
                enabled: viewer.visible
                onActivated: viewer.wordWrap = !viewer.wordWrap
            }
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            // Barra superior arrastrable: lenguaje, ruta destacada y estado de escritura en vivo.
            Item {
                Layout.fillWidth: true
                implicitHeight: 26
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    Rectangle {
                        visible: !!viewer.filePath
                        implicitWidth: langTag.implicitWidth + 12
                        implicitHeight: 20
                        radius: 6
                        color: Qt.rgba(viewer.languageColor.r, viewer.languageColor.g, viewer.languageColor.b, 0.16)
                        border.width: 1
                        border.color: Qt.rgba(viewer.languageColor.r, viewer.languageColor.g, viewer.languageColor.b, 0.48)
                        Text {
                            id: langTag
                            anchors.centerIn: parent
                            text: viewer.languageInfo.label
                            textFormat: Text.PlainText
                            color: viewer.languageColor
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 0
                        Text {
                            visible: !!viewer.dirPrefix
                            text: viewer.dirPrefix
                            textFormat: Text.PlainText
                            color: GemaTheme.subtleColor
                            font.pixelSize: 12
                            elide: Text.ElideLeft
                            Layout.maximumWidth: Math.max(40, parent.width * 0.55)
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: viewer.fileName || viewer.projectName
                            textFormat: Text.PlainText
                            color: GemaTheme.textColor
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            style: Text.Raised
                            styleColor: GemaTheme.textShadow
                        }
                        HoverHandler { id: pathHover }
                        ToolTip {
                            id: pathTip
                            visible: pathHover.hovered
                            text: viewer.bridge.workspace + "/" + viewer.filePath
                            contentItem: Text { text: pathTip.text; textFormat: Text.PlainText; color: pathTip.palette.toolTipText; font: pathTip.font }
                            delay: 500
                        }
                    }
                    Rectangle {
                        visible: viewer.writing
                        implicitWidth: writingBadgeRow.implicitWidth + 12
                        implicitHeight: 20
                        radius: 6
                        color: GemaTheme.accentAlpha(0.18)
                        border.width: 1
                        border.color: GemaTheme.accentAlpha(0.55)
                        RowLayout {
                            id: writingBadgeRow
                            anchors.centerIn: parent
                            spacing: 5
                            Rectangle {
                                width: 5; height: 5; radius: 2.5
                                color: GemaTheme.accent
                                SequentialAnimation on opacity {
                                    running: viewer.writing && viewer.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.35; duration: 480; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.35; to: 1.0; duration: 480; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                text: "GENERANDO"
                                color: GemaTheme.accentInk
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 0.7
                            }
                        }
                    }
                    Button {
                        id: copyFileBtn
                        visible: code.text.length > 0
                        implicitWidth: copyFileLabel.implicitWidth + 14
                        implicitHeight: 20
                        padding: 0
                        hoverEnabled: true
                        z: 2
                        onClicked: {
                            Quickshell.clipboardText = viewer.preview || code.text;
                            viewer.copiedNotice = true;
                            copiedResetTimer.restart();
                        }
                        contentItem: Text {
                            id: copyFileLabel
                            text: viewer.copiedNotice ? "✓ Copiado" : "Copiar"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: viewer.copiedNotice ? GemaTheme.accent : (copyFileBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                        background: Rectangle {
                            radius: 6
                            color: copyFileBtn.hovered ? GemaTheme.accentAlpha(0.18) : "#12ffffff"
                            border.width: 1
                            border.color: viewer.copiedNotice || copyFileBtn.hovered ? GemaTheme.accentAlpha(0.45) : "#24ffffff"
                        }
                    }
                    Rectangle {
                        implicitWidth: viewerTag.implicitWidth + 10
                        implicitHeight: 19
                        radius: 6
                        color: "#12ffffff"
                        border.width: 1
                        border.color: GemaTheme.accentAlpha(0.24)
                        Text {
                            id: viewerTag
                            anchors.centerIn: parent
                            text: (viewer.floatingMode ? "◈ #" : "#") + viewer.viewerId
                            color: GemaTheme.subtleColor
                            font.family: "monospace"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onPressed: viewer.startSystemMove()
                }
            }
            // Barra fija de ámbito estilo VS Code: siempre muestra la función/ámbito principal sin saltos de diseño.
            RowLayout {
                objectName: "projectCodeBreadcrumbs"
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.minimumHeight: 22
                Layout.maximumHeight: 22
                visible: code.text.length > 0
                spacing: 4
                Text {
                    text: "ƒ"
                    color: viewer.activeBreadcrumbs.length > 0 ? GemaTheme.accent : GemaTheme.subtleColor
                    font.family: "monospace"
                    font.pixelSize: 11
                    font.bold: true
                    Layout.leftMargin: 2
                    Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                }
                Repeater {
                    model: viewer.displayedBreadcrumbs
                    delegate: RowLayout {
                        id: crumbEntry
                        required property var modelData
                        required property int index
                        spacing: 4
                        opacity: 1.0
                        transform: Translate { id: crumbSlide; x: 0 }
                        Component.onCompleted: {
                            if (GemaTheme.animations && index > 0) {
                                crumbEntry.opacity = 0.0;
                                crumbSlide.x = -5;
                                crumbFadeIn.start();
                            }
                        }
                        ParallelAnimation {
                            id: crumbFadeIn
                            NumberAnimation { target: crumbEntry; property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                            NumberAnimation { target: crumbSlide; property: "x"; from: -5; to: 0; duration: 180; easing.type: Easing.OutCubic }
                        }
                        Text {
                            visible: crumbEntry.index > 0
                            text: "›"
                            color: GemaTheme.subtleColor
                            font.pixelSize: 11
                        }
                        Button {
                            id: scopeChip
                            implicitWidth: scopeChipLabel.implicitWidth + 10
                            implicitHeight: 19
                            padding: 0
                            hoverEnabled: true
                            onClicked: viewer.jumpToLine(crumbEntry.modelData.startLine)
                            contentItem: Text {
                                id: scopeChipLabel
                                text: crumbEntry.modelData.label
                                textFormat: Text.PlainText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: scopeChip.hovered
                                    ? GemaTheme.accent
                                    : (crumbEntry.modelData.kind === "func" ? viewer.syntaxPalette.func
                                       : crumbEntry.modelData.kind === "type" ? viewer.syntaxPalette.type : GemaTheme.mutedColor)
                                font.family: "monospace"
                                font.pixelSize: 10
                                font.weight: crumbEntry.modelData.kind === "func" || crumbEntry.modelData.kind === "type" ? Font.DemiBold : Font.Normal
                                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                            }
                            background: Rectangle {
                                radius: 5
                                color: scopeChip.hovered ? GemaTheme.accentAlpha(0.16) : "#0effffff"
                                border.width: scopeChip.hovered ? 1 : 0
                                border.color: GemaTheme.accentAlpha(0.40)
                                Behavior on color { ColorAnimation { duration: GemaTheme.animDuration } }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !!viewer.displayedScopeRange
                    text: viewer.displayedScopeRange
                        ? ("L" + (viewer.displayedScopeRange.startLine + 1) + "–" + (viewer.displayedScopeRange.endLine + 1))
                        : ""
                    color: GemaTheme.subtleColor
                    font.family: "monospace"
                    font.pixelSize: 10
                }
            }
            // Separador especular + barra de progreso luminosa durante la escritura animada.
            Item {
                Layout.fillWidth: true
                implicitHeight: 2
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00ffffff" }
                        GradientStop { position: 0.22; color: GemaTheme.accentAlpha(0.45) }
                        GradientStop { position: 0.72; color: "#28ffffff" }
                        GradientStop { position: 1.0; color: "#00ffffff" }
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: 2
                    radius: 1
                    width: parent.width * writeReveal.progress
                    opacity: viewer.writing ? 0.95 : 0
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: GemaTheme.accentAlpha(0.22) }
                        GradientStop { position: 0.85; color: GemaTheme.accent }
                        GradientStop { position: 1.0; color: "#f5ffffff" }
                    }
                }
            }
            // Superficie principal de código: numeración + guías de indentación/ámbito VS Code + sintaxis Gema.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                opacity: viewer.contentProgress
                transform: Translate { x: 8 * (1 - viewer.contentProgress) }
                clip: true

                // Guías verticales de indentación, línea de ámbito de función activa y resaltado de línea actual.
                Canvas {
                    id: codeGuidesCanvas
                    objectName: "projectCodeIndentGuides"
                    z: 0
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: viewer.gutterWidth
                    enabled: false
                    contextType: "2d"
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        if (!viewer.visible || width <= 2 || height <= 2) return;
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);

                        const offsets = viewer.lineOffsets;
                        const totalText = code.text;
                        if (!offsets || !offsets.length || !totalText.length) return;
                        const totalLines = (!viewer.writing && totalText.endsWith("\n"))
                            ? Math.max(1, offsets.length - 1) : offsets.length;
                        const scrollX = viewer.scroller ? (viewer.scroller.contentX - viewer.scroller.originX) : 0;
                        const scrollY = viewer.scroller ? (viewer.scroller.contentY - viewer.scroller.originY) : 0;
                        const viewBottom = scrollY + height + 24;
                        const padLeft = code.leftPadding;
                        const cw = viewer.charWidth;
                        const step = Math.max(2, viewer.indentSize);
                        const accent = Qt.color(GemaTheme.accent);
                        const aR = Math.round(accent.r * 255);
                        const aG = Math.round(accent.g * 255);
                        const aB = Math.round(accent.b * 255);

                        // Regla vertical discreta en columna 100 (solo sin ajuste de línea).
                        if (!viewer.wordWrap) {
                            const rulerX = Math.floor(padLeft + 100 * cw - scrollX) + 0.5;
                            if (rulerX > 0 && rulerX < width) {
                                ctx.strokeStyle = "rgba(255,255,255,0.055)";
                                ctx.lineWidth = 1;
                                ctx.beginPath();
                                ctx.moveTo(rulerX, 0);
                                ctx.lineTo(rulerX, height);
                                ctx.stroke();
                            }
                        }

                        // Búsqueda binaria de la primera línea visible.
                        let lo = 0;
                        let hi = totalLines - 1;
                        while (lo < hi) {
                            const mid = (lo + hi) >> 1;
                            const r = code.positionToRectangle(Math.min(offsets[mid], totalText.length));
                            if (r.y + r.height < scrollY - 24) lo = mid + 1;
                            else hi = mid;
                        }

                        const activeLine = viewer.effectiveLineIndex;
                        const hoveredLine = viewer.hoveredLineIndex;
                        const indents = viewer.indentCols;
                        const innerScope = viewer.activeScope;
                        const fnScope = viewer.activeFunctionScope;

                        // 1a. Banda muy suave bajo el puntero cuando apunta a otra línea.
                        if (!viewer.writing && hoveredLine >= lo && hoveredLine < totalLines && hoveredLine !== activeLine) {
                            const hr = code.positionToRectangle(Math.min(offsets[hoveredLine], totalText.length));
                            const hy = hr.y - scrollY;
                            if (hy + hr.height >= 0 && hy <= height) {
                                ctx.fillStyle = "rgba(" + aR + "," + aG + "," + aB + ",0.045)";
                                ctx.fillRect(2, hy, Math.max(0, width - 4), Math.max(16, hr.height));
                            }
                        }

                        // 1b. Banda de la línea activa / seleccionada (estilo VS Code).
                        if (!viewer.writing && activeLine >= lo && activeLine < totalLines) {
                            const ar = code.positionToRectangle(Math.min(offsets[activeLine], totalText.length));
                            const ay = ar.y - scrollY;
                            if (ay + ar.height >= 0 && ay <= height) {
                                ctx.fillStyle = "rgba(" + aR + "," + aG + "," + aB + ",0.095)";
                                ctx.fillRect(2, ay, Math.max(0, width - 4), Math.max(16, ar.height));
                            }
                        }

                        // 2. Guías verticales de sangría para todas las líneas visibles.
                        if (indents && indents.length) {
                            ctx.lineWidth = 1;
                            ctx.strokeStyle = "rgba(" + aR + "," + aG + "," + aB + ",0.16)";
                            for (let i = lo; i < totalLines; ++i) {
                                const rect = code.positionToRectangle(Math.min(offsets[i], totalText.length));
                                if (rect.y > viewBottom) break;
                                const drawY = rect.y - scrollY;
                                if (drawY + rect.height < -8) continue;
                                const colCount = indents[i] || 0;
                                const nextRect = (i + 1 < totalLines)
                                    ? code.positionToRectangle(Math.min(offsets[i + 1], totalText.length))
                                    : null;
                                const rowBottom = nextRect ? Math.min(height, nextRect.y - scrollY) : (drawY + rect.height);
                                const segH = Math.max(rect.height, rowBottom - drawY);

                                for (let c = step; c <= colCount; c += step) {
                                    const gx = Math.floor(padLeft + (c - step) * cw - scrollX) + 0.5;
                                    if (gx < 2 || gx > width) continue;
                                    ctx.beginPath();
                                    ctx.moveTo(gx, drawY);
                                    ctx.lineTo(gx, drawY + segH);
                                    ctx.stroke();
                                }
                            }
                        }

                        // 3. Guías iluminadas del ámbito de función y del bloque activo (estilo VS Code).
                        function drawScopeRail(scope, alpha, lineW, drawGlow) {
                            if (!scope || scope.endLine <= scope.startLine) return;
                            const firstLine = Math.min(totalLines - 1, scope.startLine + 1);
                            const lastLine = Math.min(totalLines - 1, scope.endLine);
                            const rStart = code.positionToRectangle(Math.min(offsets[firstLine], totalText.length));
                            const rEnd = code.positionToRectangle(Math.min(offsets[lastLine], totalText.length));
                            const y1 = Math.max(0, rStart.y - scrollY);
                            const y2 = Math.min(height, rEnd.y + rEnd.height - scrollY);
                            if (y2 <= 0 || y1 >= height || y2 <= y1) return;
                            const rx = Math.floor(padLeft + scope.indentCol * cw - scrollX) + 0.5;
                            if (rx < 2 || rx > width) return;

                            if (drawGlow) {
                                ctx.strokeStyle = "rgba(" + aR + "," + aG + "," + aB + ",0.20)";
                                ctx.lineWidth = 4;
                                ctx.beginPath();
                                ctx.moveTo(rx, y1);
                                ctx.lineTo(rx, y2);
                                ctx.stroke();
                            }

                            ctx.strokeStyle = "rgba(" + aR + "," + aG + "," + aB + "," + alpha + ")";
                            ctx.lineWidth = lineW;
                            ctx.beginPath();
                            ctx.moveTo(rx, y1);
                            ctx.lineTo(rx, y2);
                            ctx.stroke();

                            // Remate discreto en el cierre del bloque si el cierre está visible.
                            const exactEndY = rEnd.y + rEnd.height * 0.5 - scrollY;
                            if (exactEndY >= 0 && exactEndY <= height) {
                                ctx.beginPath();
                                ctx.moveTo(rx, exactEndY);
                                ctx.lineTo(rx + 4, exactEndY);
                                ctx.stroke();
                            }
                        }

                        if (fnScope && fnScope !== innerScope)
                            drawScopeRail(fnScope, 0.44, 1.25, false);
                        if (innerScope)
                            drawScopeRail(innerScope, 0.82, 1.5, true);
                    }
                }

                ScrollView {
                    id: codeScroll
                    objectName: "projectCodeScroll"
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: viewer.gutterWidth
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    // TextEdit conserva el control del desplazamiento y el contrato PlainText en el visor.
                    TextEdit {
                        id: code
                        objectName: "projectExplorerPreview"
                        text: ""
                        width: viewer.wordWrap
                            ? codeScroll.availableWidth
                            : Math.max(codeScroll.availableWidth, Math.ceil(implicitWidth) + 28)
                        textFormat: TextEdit.PlainText
                        readOnly: true
                        selectByMouse: true
                        wrapMode: viewer.wordWrap ? TextEdit.Wrap : TextEdit.NoWrap
                        font.family: "monospace"
                        font.pixelSize: 13
                        tabStopDistance: viewer.charWidth * viewer.indentSize
                        color: viewer.highlightActive && viewer.highlightedHtml.length > 0
                               ? "transparent" : viewer.syntaxPalette.plain
                        selectionColor: viewer.syntaxPalette.selectionBg
                        selectedTextColor: viewer.syntaxPalette.selectionFg
                        padding: 0
                        topPadding: 6
                        bottomPadding: 14
                        rightPadding: 14
                        leftPadding: 14
                        onCursorPositionChanged: viewer.updateCursorLocation(code.activeFocus || code.selectedText.length > 0)
                        onSelectionStartChanged: viewer.updateCursorLocation(true)
                        onSelectionEndChanged: viewer.updateCursorLocation(true)
                        onTextChanged: {
                            viewer.syncSyntax();
                            Qt.callLater(viewer.updateChangeGeometry);
                        }
                        onWidthChanged: {
                            Qt.callLater(viewer.updateChangeGeometry);
                            Qt.callLater(viewer.repaintCodeOverlays);
                        }

                        // HoverHandler directamente sobre TextEdit: coordenadas locales exactas sin sumar scroll dos veces.
                        HoverHandler {
                            onPointChanged: {
                                if (code.text.length <= 0) return;
                                const pos = code.positionAt(point.position.x, point.position.y);
                                if (pos >= 0)
                                    viewer.hoveredLineIndex = viewer.findLineIndex(Math.min(pos, code.text.length));
                            }
                            onHoveredChanged: {
                                if (!hovered) viewer.hoveredLineIndex = -1;
                            }
                        }

                        // Banda de líneas recién modificadas, teñida con el acento del tema.
                        Rectangle {
                            objectName: "projectCodeChangeBand"
                            z: -3
                            x: 4
                            y: viewer.changeTop
                            width: Math.max(0, code.width - 8)
                            height: viewer.changeHeight
                            radius: 5
                            opacity: viewer.changeGlow * 2.4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: GemaTheme.accentAlpha(0.95) }
                                GradientStop { position: 0.55; color: GemaTheme.accentAlpha(0.38) }
                                GradientStop { position: 1.0; color: GemaTheme.accentAlpha(0.06) }
                            }
                        }

                        // Haz de luz horizontal que acompaña suavemente la línea que se está escribiendo.
                        Rectangle {
                            id: writingLineSpotlight
                            objectName: "projectCodeWritingLineGlow"
                            z: -2
                            readonly property rect lineRect: {
                                const currentText = code.text;
                                return code.positionToRectangle(Math.min(writeReveal.position, currentText.length));
                            }
                            x: 4
                            y: lineRect.y
                            width: Math.max(0, code.width - 8)
                            height: Math.max(16, lineRect.height)
                            radius: 5
                            opacity: viewer.writing ? 1.0 : 0.0
                            visible: opacity > 0.01
                            Behavior on y {
                                enabled: viewer.writing
                                NumberAnimation { duration: 42; easing.type: Easing.OutQuad }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                            }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: GemaTheme.accentAlpha(0.22) }
                                GradientStop { position: 0.45; color: GemaTheme.accentAlpha(0.09) }
                                GradientStop { position: 1.0; color: GemaTheme.accentAlpha(0.0) }
                            }
                            Rectangle {
                                x: 0
                                y: 2
                                width: 2.5
                                height: Math.max(2, parent.height - 4)
                                radius: 1.25
                                color: GemaTheme.accent
                            }
                        }

                        // Capa visual de sintaxis armonizada (0 px de desfase con TextEdit.PlainText).
                        TextEdit {
                            id: syntaxDisplay
                            objectName: "projectCodeSyntaxLayer"
                            z: -1
                            anchors.fill: parent
                            visible: viewer.highlightActive
                            enabled: false
                            focus: false
                            activeFocusOnPress: false
                            readOnly: true
                            selectByMouse: false
                            textFormat: TextEdit.RichText
                            text: viewer.highlightedHtml
                            wrapMode: code.wrapMode
                            font: code.font
                            tabStopDistance: code.tabStopDistance
                            padding: code.padding
                            topPadding: code.topPadding
                            bottomPadding: code.bottomPadding
                            leftPadding: code.leftPadding
                            rightPadding: code.rightPadding
                            color: viewer.syntaxPalette.plain
                        }

                        // Indicador lateral del bloque modificado.
                        Rectangle {
                            objectName: "projectCodeChangeMarker"
                            z: 1
                            x: 4
                            y: viewer.changeTop
                            width: 2.5
                            height: viewer.changeHeight
                            radius: 1.25
                            color: GemaTheme.accent
                            opacity: Math.min(1, viewer.changeGlow * 14)
                        }

                        // Estela luminosa que sigue al cursor sobre los caracteres recién escritos.
                        Rectangle {
                            id: cursorTrail
                            z: -1
                            visible: viewer.writing && width > 2
                            readonly property real codeLeft: code.leftPadding
                            readonly property real trailWidth: Math.min(96, Math.max(0, writingCursor.x - codeLeft))
                            x: writingCursor.x - trailWidth
                            y: writingCursor.y - 1
                            width: trailWidth
                            height: writingCursor.height + 2
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: GemaTheme.accentAlpha(0.0) }
                                GradientStop { position: 0.65; color: GemaTheme.accentAlpha(0.16) }
                                GradientStop { position: 1.0; color: GemaTheme.accentAlpha(0.36) }
                            }
                        }

                        // Cursor luminoso con halo de energía en el acento del tema Gema.
                        Item {
                            id: writingCursor
                            objectName: "projectCodeWritingCursor"
                            z: 2
                            readonly property rect location: {
                                const currentText = code.text;
                                return code.positionToRectangle(Math.min(writeReveal.position, currentText.length));
                            }
                            x: location.x
                            y: location.y + 1
                            width: 2.5
                            height: Math.max(1, location.height - 2)
                            visible: viewer.writing
                            Rectangle {
                                anchors.centerIn: parent
                                width: 16
                                height: parent.height + 8
                                radius: 8
                                color: GemaTheme.accent
                                opacity: 0.34
                                SequentialAnimation on opacity {
                                    running: viewer.writing && viewer.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0.24; to: 0.48; duration: 420; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 0.48; to: 0.24; duration: 420; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 1.25
                                color: GemaTheme.accent
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 1
                                    height: Math.max(1, parent.height - 2)
                                    radius: 0.5
                                    color: "#f2ffffff"
                                }
                            }
                        }
                    }
                }

                // Canal de numeración de líneas anclado al viewport (nunca se superpone con el código al desplazar horizontalmente).
                Canvas {
                    id: codeGutter
                    objectName: "projectCodeGutter"
                    z: 2
                    x: 0
                    y: 0
                    width: viewer.gutterWidth
                    height: codeScroll.height
                    enabled: false
                    contextType: "2d"
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        if (!viewer.visible || width <= 2 || height <= 2) return;
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);

                        // Separador vertical discreto tintado con el acento.
                        const accent = Qt.color(GemaTheme.accent);
                        ctx.fillStyle = "rgba(" + Math.round(accent.r * 255) + ","
                            + Math.round(accent.g * 255) + "," + Math.round(accent.b * 255) + ",0.18)";
                        ctx.fillRect(width - 1, 2, 1, Math.max(0, height - 4));

                        const offsets = viewer.lineOffsets;
                        const totalText = code.text;
                        if (!offsets || !offsets.length || !totalText.length) return;
                        const totalLines = (!viewer.writing && totalText.endsWith("\n"))
                            ? Math.max(1, offsets.length - 1) : offsets.length;
                        const scrollY = viewer.scroller ? (viewer.scroller.contentY - viewer.scroller.originY) : 0;
                        const viewBottom = scrollY + height + 24;

                        // Búsqueda binaria de la primera línea visible para soportar archivos grandes.
                        let lo = 0;
                        let hi = totalLines - 1;
                        while (lo < hi) {
                            const mid = (lo + hi) >> 1;
                            const r = code.positionToRectangle(Math.min(offsets[mid], totalText.length));
                            if (r.y + r.height < scrollY - 24) lo = mid + 1;
                            else hi = mid;
                        }

                        ctx.textAlign = "right";
                        ctx.textBaseline = "middle";
                        const pal = viewer.syntaxPalette;
                        const activeIdx = viewer.effectiveLineIndex;
                        const chStart = viewer.changeStartLine;
                        const chEnd = viewer.changeEndLine;
                        const scope = viewer.activeScope;

                        for (let i = lo; i < totalLines; ++i) {
                            const rect = code.positionToRectangle(Math.min(offsets[i], totalText.length));
                            if (rect.y > viewBottom) break;
                            const drawY = rect.y - scrollY;
                            if (drawY + rect.height < -8) continue;
                            const isActiveLine = i === activeIdx;
                            const isInActiveScope = !!scope && i >= scope.startLine && i <= scope.endLine;
                            const isChangedLine = viewer.changeGlow > 0.005 && chStart >= 0 && i >= chStart && i <= chEnd;

                            if (isActiveLine) {
                                ctx.font = "bold 11px monospace";
                                ctx.globalAlpha = 1.0;
                                ctx.fillStyle = pal.lineNumberActive;
                            } else if (isChangedLine) {
                                ctx.font = "11px monospace";
                                ctx.globalAlpha = 0.92;
                                ctx.fillStyle = pal.lineNumberActive;
                            } else if (isInActiveScope) {
                                ctx.font = "11px monospace";
                                ctx.globalAlpha = 0.85;
                                ctx.fillStyle = pal.lineNumber;
                            } else {
                                ctx.font = "11px monospace";
                                ctx.globalAlpha = 0.56;
                                ctx.fillStyle = pal.lineNumber;
                            }
                            ctx.fillText(String(i + 1), width - 9, drawY + rect.height * 0.5);
                        }
                    }
                }
            }
            // Barra de estado inferior estilo VS Code (posición Ln/Col, indentación, ajuste de línea y total).
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                WorkStatusNote {
                    Layout.fillWidth: true
                    busy: (viewer.writing || viewer.activityState === "running") && !viewer.deleted
                    windowVisible: viewer.visible
                    text: viewer.deleted ? "Archivo eliminado · última vista"
                          : viewer.writing ? "Mostrando cambios"
                          : viewer.activityState === "running" ? "IA · cambios en vivo"
                          : viewer.activityState === "completed" ? "Actualizado · solo lectura"
                          : viewer.activityState === "interrupted" ? "Detenido · solo lectura"
                          : "Solo lectura"
                    HoverHandler { id: statusHover }
                    ToolTip {
                        visible: statusHover.hovered
                        text: "La escritura animada muestra texto ya recibido del archivo. Alt+Z alterna ajuste de línea · Esc para cerrar."
                        delay: 500
                    }
                }
                Text {
                    visible: code.text.length > 0
                    text: "Ln " + (viewer.effectiveLineIndex + 1) + ", Col " + viewer.cursorColumnIndex
                    color: GemaTheme.subtleColor
                    font.family: "monospace"
                    font.pixelSize: 10
                }
                Text {
                    visible: code.text.length > 0
                    text: "Esp: " + viewer.indentSize
                    color: GemaTheme.subtleColor
                    font.family: "monospace"
                    font.pixelSize: 10
                }
                Button {
                    id: wrapToggleBtn
                    objectName: "projectCodeWrapToggle"
                    implicitWidth: wrapToggleLabel.implicitWidth + 12
                    implicitHeight: 20
                    padding: 0
                    hoverEnabled: true
                    onClicked: viewer.wordWrap = !viewer.wordWrap
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    ToolTip.text: viewer.wordWrap
                        ? "Desactivar ajuste de línea (Alt+Z)"
                        : "Activar ajuste de línea (Alt+Z)"
                    contentItem: Text {
                        id: wrapToggleLabel
                        text: viewer.wordWrap ? "↩ Ajuste: Sí" : "→ Sin ajuste"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: viewer.wordWrap ? GemaTheme.accent : (wrapToggleBtn.hovered ? GemaTheme.textColor : GemaTheme.subtleColor)
                        font.pixelSize: 10
                        font.weight: viewer.wordWrap ? Font.DemiBold : Font.Normal
                    }
                    background: Rectangle {
                        radius: 6
                        color: viewer.wordWrap ? GemaTheme.accentAlpha(0.18)
                               : (wrapToggleBtn.hovered ? "#18ffffff" : "#10ffffff")
                        border.width: 1
                        border.color: viewer.wordWrap ? GemaTheme.accentAlpha(0.50) : "#22ffffff"
                    }
                }
                Text {
                    visible: viewer.previewLines >= 0
                    text: viewer.previewLines + (viewer.previewLines === 1 ? " línea" : " líneas")
                          + (viewer.previewTruncated ? " · vista parcial (128 KiB)" : "")
                    color: GemaTheme.subtleColor
                    font.pixelSize: 10
                    style: Text.Raised
                    styleColor: GemaTheme.textShadow
                }
            }
        }
    }
}
