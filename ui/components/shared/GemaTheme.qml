pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../js/CodeSyntax.js" as CodeSyntax

// Sincronización en vivo con el tema Gema de Hyprland (~/.config/gema/preferences.json).
QtObject {
    id: gemaTheme
    property color accent: "#c4dcff"
    property string accentHex: "#c4dcff"
    property int rounding: 18
    property bool blur: true
    property bool animations: true
    property bool darkText: false
    property int gemShape: 7
    property bool synced: false

    readonly property color textColor: darkText ? "#17202b" : "#f3f5f8"
    readonly property color mutedColor: darkText ? "#354252" : "#dce2eb"
    readonly property color subtleColor: darkText ? "#4b5a6e" : "#b8c4d4"
    readonly property color textShadow: darkText ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(0, 0, 0, 0.72)
    readonly property color accentInk: darkText ? Qt.darker(accent, 1.8) : accent
    readonly property int animDuration: animations ? 180 : 0
    // Paleta armónica de código y explorador derivada del acento Gema activo.
    readonly property var codePalette: CodeSyntax.buildPalette(accentHex, darkText, synced)
    readonly property string gemName: {
        const names = [
            "Rubí Birmano", "Esmeralda de Muzo", "Amatista Siberiana", "Zafiro Padparadscha",
            "Zafiro de Cachemira", "Turmalina Paraíba", "Topacio Imperial", "Diamante Golconda"
        ];
        return names[gemShape] || "Gema";
    }
    readonly property string gemSymbol: {
        const syms = ["❖", "▭", "◆", "◊", "◈", "▲", "💧", "⬢"];
        return syms[gemShape] || "◆";
    }

    Behavior on accent { ColorAnimation { duration: gemaTheme.animations ? 260 : 0 } }

    readonly property string preferencesPath: Quickshell.env("GEMA_SETTINGS_PATH")
        || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/gema/preferences.json")

    // Tintes derivados del acento de la gema activa para bordes, reflejos y controles.
    function tintColor(baseColor, alphaMix) {
        const c = Qt.color(baseColor);
        const a = Qt.color(accent);
        return Qt.rgba(
            c.r * (1 - alphaMix) + a.r * alphaMix,
            c.g * (1 - alphaMix) + a.g * alphaMix,
            c.b * (1 - alphaMix) + a.b * alphaMix,
            c.a
        );
    }

    function accentAlpha(alpha) {
        const a = Qt.color(accent);
        return Qt.rgba(a.r, a.g, a.b, alpha);
    }

    function load() {
        try {
            const raw = prefsFile.text();
            if (!raw) return;
            const data = JSON.parse(raw);
            if (typeof data.accent === "string" && /^#[0-9a-fA-F]{6}$/.test(data.accent)) {
                accentHex = data.accent.toLowerCase();
                accent = accentHex;
            }
            if (typeof data.rounding === "number" && isFinite(data.rounding))
                rounding = Math.max(8, Math.min(28, Math.round(data.rounding)));
            if (typeof data.blur === "boolean")
                blur = data.blur;
            if (typeof data.animations === "boolean")
                animations = data.animations;
            if (typeof data.darkText === "boolean")
                darkText = data.darkText;
            if (typeof data.gemShape === "number")
                gemShape = data.gemShape;
            synced = true;
        } catch (e) {
            // Si Gema no está instalado o el archivo aún no existe, conserva los valores base.
        }
    }

    readonly property FileView prefsFile: FileView {
        path: gemaTheme.preferencesPath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onLoaded: gemaTheme.load()
        onFileChanged: {
            reload();
            gemaTheme.load();
        }
    }

    Component.onCompleted: load()
}
