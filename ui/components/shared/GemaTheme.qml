pragma Singleton
import QtQuick
import AgentShell.Native
import "../../js/CodeSyntax.js" as CodeSyntax

// Sincronización en vivo con el tema Gema de Hyprland (~/.config/gema/preferences.json).
QtObject {
    id: gemaTheme
    property color accent: "#c4dcff"
    property string accentHex: "#c4dcff"
    property int rounding: 18
    property int borderSize: 2
    property bool blur: true
    property bool shadows: false
    property bool animations: true
    property bool darkText: false
    property int gemShape: 7
    property color wallpaperColor: "#101119"
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
    readonly property string gemSymbol: "◆"

    Behavior on accent { ColorAnimation { duration: gemaTheme.animations ? 260 : 0 } }

    readonly property string preferencesPath: NativeApp.env("GEMA_SETTINGS_PATH")
        || ((NativeApp.env("XDG_CONFIG_HOME") || (NativeApp.env("HOME") + "/.config")) + "/gema/preferences.json")

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
            if (typeof data.borderSize === "number" && isFinite(data.borderSize))
                borderSize = Math.max(0, Math.min(8, Math.round(data.borderSize)));
            if (typeof data.blur === "boolean")
                blur = data.blur;
            if (typeof data.shadows === "boolean")
                shadows = data.shadows;
            if (typeof data.animations === "boolean")
                animations = data.animations;
            if (typeof data.darkText === "boolean")
                darkText = data.darkText;
            if (typeof data.gemShape === "number")
                gemShape = data.gemShape;
            if (typeof data.wallpaperColor === "string" && /^#[0-9a-fA-F]{6}$/.test(data.wallpaperColor))
                wallpaperColor = data.wallpaperColor.toLowerCase();
            synced = true;
        } catch (e) {
            // Si Gema no está instalado o el archivo aún no existe, conserva los valores base.
        }
    }

    readonly property NativeFileView prefsFile: NativeFileView {
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
