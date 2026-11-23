"""Generación de aplicaciones con el diseño Glassmorphism de Gema UI Kit (Quickshell + Python/Rust)."""

from __future__ import annotations

import json
import os
from pathlib import Path

from ..tools.shell import resolve_workspace

VALID_ENGINES = ("python", "rust")

GEMA_UI_INSTRUCTIONS = (
    "You are in App, the Gema UI Kit application builder workspace. "
    "Build and evolve a native Wayland/Hyprland desktop application using the Gema UI Kit technology stack:\n"
    "1. Frontend: Quickshell (`qs`) + QtQuick 6 QML (`shell.qml`, `ui/AppBridge.qml`, `ui/AppWindow.qml`).\n"
    "2. Visual Design (Gema UI Kit Dark Glassmorphism): Always use the Gema UI Kit components in `ui/components/` "
    "(`GlassPanel`, `MattePanel`, `WaterReflection`, `ActionButton`, `GlassComboBox`, `GlassDialog`). "
    "Keep windows translucent (`color: \"transparent\"`), enable Wayland blur with "
    "`BackgroundEffect.blurRegion: Region { item: glassSurface; radius: glassSurface.radius }`, "
    "use frosted matte dark gradients (`topColor: \"#701c1c1c\"`, `bottomColor: \"#7a101010\"`), "
    "subtle specular top highlights and thin luminous borders (`edgeColor: \"#50ffffff\"`).\n"
    "3. IPC Bridge: `ui/AppBridge.qml` launches the backend via Quickshell `Process` (`stdinEnabled: true`) "
    "and exchanges JSON Lines v2 (`{\"version\": 2, \"type\": \"...\", \"data\": {...}}`) over stdin/stdout.\n"
    "4. Verification & Launching: Run `./scripts/check.sh` (or button 'Probar') to validate QML syntax with "
    "`qmllint` and backend checks, and `./scripts/run.sh` (or button 'Iniciar') to launch the app window.\n"
)

_GLASS_PANEL_QML = """import QtQuick

// Capas estáticas de vidrio Gema UI Kit; el desenfoque lo realiza el compositor Wayland/Hyprland.
Rectangle {
    id: panel
    property color topColor: "#243b3b3b"
    property color bottomColor: "#181c1c1c"
    property color edgeColor: "#38ffffff"
    property bool highlighted: false
    property bool reflective: true

    radius: 12
    border.width: 1
    border.color: highlighted ? "#99ffffff" : edgeColor
    gradient: Gradient {
        GradientStop { position: 0; color: panel.topColor }
        GradientStop { position: 1; color: panel.bottomColor }
    }

    Rectangle {
        visible: panel.reflective
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, panel.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: "#09ffffff"
    }
    Rectangle {
        visible: panel.reflective
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: panel.radius
        anchors.rightMargin: panel.radius
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#00ffffff" }
            GradientStop { position: 0.35; color: "#52ffffff" }
            GradientStop { position: 1; color: "#00ffffff" }
        }
    }
}
"""

_WATER_REFLECTION_QML = """import QtQuick

// Luz sobre agua de Gema UI Kit: velos y ondas suaves.
Canvas {
    id: reflection
    property real cornerRadius: 16
    property real strength: 1
    contextType: "2d"
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onCornerRadiusChanged: requestPaint()
    onStrengthChanged: requestPaint()
    onPaint: {
        if (width <= 2 || height <= 2) return;
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        ctx.beginPath();
        const radius = Math.min(cornerRadius, (width - 2) / 2, (height - 2) / 2);
        ctx.roundedRect(1, 1, width - 2, height - 2, radius, radius);
        ctx.clip();
        ctx.globalAlpha = strength;

        const sheen = ctx.createRadialGradient(width * 0.16, 0, 0,
                                               width * 0.16, 0, width * 0.85);
        sheen.addColorStop(0, "#16ffffff");
        sheen.addColorStop(0.45, "#07ffffff");
        sheen.addColorStop(1, "#00ffffff");
        ctx.fillStyle = sheen;
        ctx.fillRect(0, 0, width, height);

        const light = ctx.createLinearGradient(0, 0, width, 0);
        light.addColorStop(0, "#00ffffff");
        light.addColorStop(0.18, "#24ffffff");
        light.addColorStop(0.5, "#08ffffff");
        light.addColorStop(0.8, "#1cffffff");
        light.addColorStop(1, "#00ffffff");
        ctx.strokeStyle = light;
        const band = Math.min(height * 0.14, 65);
        for (let i = 0; i < 3; ++i) {
            const offset = i * 8;
            ctx.beginPath();
            ctx.moveTo(-width * 0.08, band * 0.45 + offset);
            ctx.bezierCurveTo(width * 0.18, -band * 0.2 + offset,
                              width * 0.31, band * 1.25 + offset,
                              width * 0.57, band * 0.6 + offset);
            ctx.bezierCurveTo(width * 0.78, -band * 0.15 + offset,
                              width * 0.95, band * 0.8 + offset,
                              width * 1.08, band * 0.3 + offset);
            ctx.globalAlpha = strength * 0.18;
            ctx.lineWidth = 9 - i * 2;
            ctx.stroke();
            ctx.globalAlpha = strength * (0.85 - i * 0.2);
            ctx.lineWidth = 1.1;
            ctx.stroke();
        }
    }
}
"""

_MATTE_PANEL_QML = """import QtQuick

// Vidrio esmerilado oscuro de Gema UI Kit con reflejos de agua.
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
"""

_ACTION_BUTTON_QML = """import QtQuick
import QtQuick.Controls

// Botón Glassmorphism de Gema UI Kit.
Button {
    id: control
    property bool accent: false
    horizontalPadding: 14
    verticalPadding: 10
    hoverEnabled: true
    font.pixelSize: 13
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? (control.accent ? "#ffffff" : "#f5f5f5") : "#888888"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: GlassPanel {
        radius: 10
        topColor: control.down ? "#80555555"
                  : control.accent && control.enabled ? "#70707070"
                  : control.hovered && control.enabled ? "#70555555" : "#443c3c3c"
        bottomColor: control.accent && control.enabled ? "#504d4d4d" : "#30202020"
        edgeColor: control.accent && control.enabled ? "#70ffffff" : "#38ffffff"
        highlighted: control.activeFocus
        opacity: control.enabled ? 1 : 0.55
    }
}
"""

_GLASS_DIALOG_QML = """import QtQuick
import QtQuick.Controls

// Diálogo modal Glassmorphism de Gema UI Kit.
Dialog {
    id: control
    padding: 20
    background: MattePanel {
        overlay: true
        radius: 16
    }
    header: Label {
        text: control.title
        color: "#f5f5f5"
        font.pixelSize: 20
        font.bold: true
        padding: 20
        bottomPadding: 4
        elide: Text.ElideRight
    }
    footer: DialogButtonBox {
        standardButtons: control.standardButtons
        padding: 16
        spacing: 8
        background: null
        delegate: ActionButton {}
    }
    Overlay.modal: Rectangle { color: "#66000000" }
}
"""

_GLASS_COMBOBOX_QML = """import QtQuick
import QtQuick.Controls

// Selector desplegable Glassmorphism de Gema UI Kit.
ComboBox {
    id: control
    property bool opensAbove: false
    implicitHeight: 40
    hoverEnabled: true
    font.pixelSize: 13
    leftPadding: 14
    rightPadding: 36
    topPadding: 10
    bottomPadding: 10

    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled ? "#f5f5f5" : "#888888"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 14
        y: (control.height - height) / 2
        text: control.opensAbove ? "⌃" : "⌄"
        font.pixelSize: 18
        color: control.enabled ? "#ffffff" : "#888888"
    }
    background: GlassPanel {
        implicitWidth: 180
        implicitHeight: 40
        radius: 10
        highlighted: control.activeFocus || control.popup.visible
        topColor: control.hovered ? "#70555555" : "#443c3c3c"
        bottomColor: "#30202020"
        opacity: control.enabled ? 1 : 0.55
    }
}
"""

_SHELL_QML = """import Quickshell
import "ui"

// Punto de entrada Gema UI Kit: conecta AppBridge con AppWindow.
ShellRoot {
    AppBridge { id: bridge }

    AppWindow {
        bridge: bridge
        onClosed: Qt.quit()
    }
}
"""


def _app_bridge_qml(engine: str) -> str:
    cmd = (
        '[Quickshell.shellDir + "/backend/run-backend.sh"]'
        if engine == "rust"
        else '["python3", "-u", Quickshell.shellDir + "/backend/main.py"]'
    )
    return f"""import QtQuick
import Quickshell
import Quickshell.Io

// Puente IPC JSON-Lines v2 sobre stdin/stdout (Gema UI Kit · motor {engine}).
QtObject {{
    id: bridge
    property bool ready: false
    property string appName: ""
    property string engine: "{engine}"
    property string status: "Iniciando motor…"
    property int pingCount: 0
    signal eventReceived(var event)

    function sendCommand(command) {{
        if (backend.running) backend.write(JSON.stringify(command) + "\\n");
    }}

    function ping(message = "Hola desde Gema UI Kit") {{
        sendCommand({{ type: "app.ping", message: message }});
    }}

    function receive(line) {{
        let event;
        try {{
            event = JSON.parse(line);
            if (event.version !== 2 || !event.data || typeof event.type !== "string")
                throw new Error("Formato de evento incompatible");
        }} catch (error) {{
            status = "Error IPC: " + error.message;
            return;
        }}
        const data = event.data;
        if (event.type === "app.ready") {{
            ready = true;
            appName = data.name || appName;
            engine = data.engine || engine;
            status = data.message || "Motor Gema UI Kit conectado.";
        }} else if (event.type === "app.pong") {{
            pingCount = data.count || (pingCount + 1);
            status = data.message || ("Respuesta #" + pingCount);
        }} else if (event.type === "error") {{
            status = data.message || "Error del motor.";
        }}
        eventReceived(event);
    }}

    readonly property Process backend: Process {{
        command: {cmd}
        workingDirectory: Quickshell.shellDir
        stdinEnabled: true
        running: true
        stdout: SplitParser {{ onRead: data => bridge.receive(data) }}
        stderr: SplitParser {{ onRead: data => console.warn("Backend: " + data) }}
        onExited: (exitCode, exitStatus) => {{
            bridge.ready = false;
            bridge.status = "Motor desconectado (" + exitCode + ").";
        }}
    }}
}}
"""


def _app_window_qml(name: str, engine: str) -> str:
    escaped_name = json.dumps(name, ensure_ascii=False)
    engine_label = "Rust" if engine == "rust" else "Python"
    return f"""import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components"

// Ventana principal con estética Dark Glassmorphism de Gema UI Kit.
FloatingWindow {{
    id: window
    required property AppBridge bridge
    title: {escaped_name}
    implicitWidth: 620
    implicitHeight: 520
    minimumSize: Qt.size(440, 360)
    color: "transparent"
    visible: true
    BackgroundEffect.blurRegion: Region {{ item: glassSurface; radius: glassSurface.radius }}

    MattePanel {{
        id: glassSurface
        anchors.fill: parent
        anchors.margins: 1
        radius: 20
        topColor: "#701c1c1c"
        bottomColor: "#7a101010"
        edgeColor: "#50ffffff"
    }}

    ColumnLayout {{
        anchors.fill: parent
        anchors.margins: 22
        spacing: 16

        RowLayout {{
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {{
                Layout.fillWidth: true
                spacing: 4
                Text {{
                    text: {escaped_name}
                    color: "#f5f5f5"
                    font.pixelSize: 22
                    font.bold: true
                    elide: Text.ElideRight
                }}
                Text {{
                    text: "Gema UI Kit · Glassmorphism · Motor {engine_label}"
                    color: "#aaaaaa"
                    font.pixelSize: 12
                }}
            }}
            GlassPanel {{
                implicitWidth: badgeText.implicitWidth + 20
                implicitHeight: 28
                radius: 9
                topColor: "#28484848"
                bottomColor: "#1c222222"
                Text {{
                    id: badgeText
                    anchors.centerIn: parent
                    text: window.bridge.ready ? "● Activo" : "○ Iniciando"
                    color: window.bridge.ready ? "#f5f5f5" : "#888888"
                    font.pixelSize: 11
                }}
            }}
        }}

        Rectangle {{ Layout.fillWidth: true; implicitHeight: 1; color: "#18ffffff" }}

        GlassPanel {{
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            topColor: "#14292929"
            bottomColor: "#24171717"
            edgeColor: "#20ffffff"

            ColumnLayout {{
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 460)
                spacing: 14

                Text {{
                    Layout.fillWidth: true
                    text: "Tu aplicación Gema UI Kit está lista"
                    color: "#f5f5f5"
                    font.pixelSize: 18
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }}
                Text {{
                    Layout.fillWidth: true
                    text: window.bridge.status
                    color: "#bbbbbb"
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }}
                ActionButton {{
                    Layout.alignment: Qt.AlignHCenter
                    text: "Probar conexión con el motor (" + window.bridge.pingCount + ")"
                    accent: true
                    enabled: window.bridge.ready
                    onClicked: window.bridge.ping("Pulso desde la interfaz QML")
                }}
            }}
        }}
    }}
}}
"""


def _python_backend(name: str) -> str:
    escaped_name = json.dumps(name, ensure_ascii=False)
    return f"""#!/usr/bin/env python3
\"\"\"Motor Python para {name} (protocolo JSON-Lines v2 de Gema UI Kit).\"\"\"

import json
import sys
from datetime import datetime, timezone


def emit(event_type: str, **data) -> None:
    event = {{
        "version": 2,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "type": event_type,
        "data": data,
    }}
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\\n")
    sys.stdout.flush()


def main() -> None:
    app_name = {escaped_name}
    ping_count = 0
    emit("app.ready", name=app_name, engine="python",
         message=f"Motor Python de {{app_name}} listo y conectado por stdio.")
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            emit("error", message="JSON inválido")
            continue
        action = request.get("type")
        if action == "app.ping":
            ping_count += 1
            msg = request.get("message", "")
            emit("app.pong", count=ping_count,
                 message=f"Motor Python recibió (#{{ping_count}}): {{msg}}")
        elif action == "app.check":
            emit("app.checked", ok=True, engine="python")
            return
        else:
            emit("error", message=f"Acción desconocida: {{action}}")


if __name__ == "__main__":
    main()
"""


def _rust_cargo_toml(slug: str) -> str:
    return f"""[package]
name = "{slug}"
version = "0.1.0"
edition = "2021"

[dependencies]
"""


def _rust_backend_rs(name: str) -> str:
    escaped_name = json.dumps(name, ensure_ascii=False)
    return f"""//! Motor Rust sin dependencias externas para {name} (protocolo JSON-Lines v2 de Gema UI Kit).

use std::io::{{self, BufRead, Write}};

fn escape_json(input: &str) -> String {{
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {{
        match ch {{
            '"' => out.push_str("\\\\\\""),
            '\\\\' => out.push_str("\\\\\\\\"),
            '\\n' => out.push_str("\\\\n"),
            '\\r' => out.push_str("\\\\r"),
            '\\t' => out.push_str("\\\\t"),
            c => out.push(c),
        }}
    }}
    out
}}

fn emit(event_type: &str, data_json: &str) {{
    println!("{{\\"version\\":2,\\"type\\":\\"{{}}\\",\\"data\\":{{}}}}", event_type, data_json);
    let _ = io::stdout().flush();
}}

fn main() {{
    let app_name = {escaped_name};
    let mut ping_count: u64 = 0;
    emit(
        "app.ready",
        &format!(
            "{{\\"name\\":\\"{{}}\\",\\"engine\\":\\"rust\\",\\"message\\":\\"Motor Rust de {{}} listo y conectado por stdio.\\"}}",
            escape_json(app_name),
            escape_json(app_name)
        ),
    );
    let stdin = io::stdin();
    for line in stdin.lock().lines().map_while(Result::ok) {{
        let trimmed = line.trim();
        if trimmed.is_empty() {{
            continue;
        }}
        if trimmed.contains("\\"app.check\\"") {{
            emit("app.checked", "{{\\"ok\\":true,\\"engine\\":\\"rust\\"}}");
            return;
        }} else if trimmed.contains("\\"app.ping\\"") {{
            ping_count += 1;
            emit(
                "app.pong",
                &format!(
                    "{{\\"count\\":{{}},\\"message\\":\\"Motor Rust respondió al pulso #{{}} en tiempo real.\\"}}",
                    ping_count, ping_count
                ),
            );
        }} else {{
            emit("error", "{{\\"message\\":\\"Acción no reconocida por el motor Rust.\\"}}");
        }}
    }}
}}
"""


_RUST_RUN_BACKEND_SH = """#!/usr/bin/env bash
set -euo pipefail
backend_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$backend_dir"
if [[ -x "$backend_dir/target/debug/gema-backend" && "$backend_dir/target/debug/gema-backend" -nt "$backend_dir/src/main.rs" ]]; then
    exec "$backend_dir/target/debug/gema-backend"
fi
if command -v cargo >/dev/null 2>&1; then
    cargo build --quiet
    exec "$backend_dir/target/debug/gema-backend"
elif command -v rustc >/dev/null 2>&1; then
    mkdir -p "$backend_dir/target/debug"
    rustc "$backend_dir/src/main.rs" -o "$backend_dir/target/debug/gema-backend"
    exec "$backend_dir/target/debug/gema-backend"
else
    echo '{"version":2,"type":"error","data":{"message":"Instala cargo o rustc para compilar el motor Rust."}}'
    exit 1
fi
"""

_RUN_SH = """#!/usr/bin/env bash
# Lanzador de aplicación Gema UI Kit en Quickshell.
set -euo pipefail
app_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec qs --no-duplicate --path "$app_root/shell.qml" "$@"
"""


def _check_sh(engine: str) -> str:
    backend_check = (
        'printf \'{"type":"app.check"}\\n\' | "$app_root/backend/run-backend.sh" | grep -q \'"app.checked"\''
        if engine == "rust"
        else 'python3 -m py_compile "$app_root/backend/main.py"\n'
             'printf \'{"type":"app.check"}\\n\' | python3 "$app_root/backend/main.py" | grep -q \'"app.checked"\''
    )
    return f"""#!/usr/bin/env bash
# Validación rápida de sintaxis QML y respuesta IPC del motor ({engine}).
set -euo pipefail
app_root="$(cd -- "$(dirname -- "${{BASH_SOURCE[0]}}")/.." && pwd)"
cd "$app_root"
if command -v qmllint >/dev/null 2>&1; then
    qmllint shell.qml ui/*.qml ui/components/*.qml
fi
{backend_check}
echo "GEMA_APP_CHECK_OK: QML Glassmorphism y motor {engine} verificados."
"""


def _agents_md(name: str, engine: str) -> str:
    engine_label = "Rust (`backend/src/main.rs`)" if engine == "rust" else "Python (`backend/main.py`)"
    return f"""# {name} · Gema UI Kit App

Aplicación de escritorio nativa para **Hyprland / Wayland** construida con el stack **Gema UI Kit**:

- **Estilo visual:** Dark Glassmorphism (`MattePanel`, `GlassPanel`, `WaterReflection`, `ActionButton`, `GlassDialog`, `GlassComboBox`) en `ui/components/`, con fondo translúcido y desenfoque real del compositor (`BackgroundEffect.blurRegion`).
- **Frontend:** Quickshell + QtQuick 6 QML (`shell.qml`, `ui/AppWindow.qml`, `ui/AppBridge.qml`).
- **Motor Backend:** {engine_label} conectado por `stdin`/`stdout` mediante JSON-Lines v2 (`{{"version": 2, "type": "...", "data": {{...}}}}`).
- **Probar aplicación:** `./scripts/check.sh`
- **Iniciar aplicación:** `./scripts/run.sh`
"""


def _write_if_missing(path: Path, content: str, executable: bool = False) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    if executable:
        os.chmod(path, 0o755)


def scaffold_gema_app(workdir: str | Path, name: str, engine: str = "python") -> Path:
    """Genera la estructura inicial Gema UI Kit sin sobrescribir archivos existentes del usuario."""
    if engine not in VALID_ENGINES:
        raise ValueError("Selecciona Python o Rust para el motor de la aplicación")
    target = Path(workdir).expanduser()
    if not target.exists():
        target.mkdir(parents=True, exist_ok=True)
    folder = resolve_workspace(target)

    _write_if_missing(folder / "AGENTS.md", _agents_md(name, engine))
    _write_if_missing(folder / "shell.qml", _SHELL_QML)
    _write_if_missing(folder / "ui" / "AppBridge.qml", _app_bridge_qml(engine))
    _write_if_missing(folder / "ui" / "AppWindow.qml", _app_window_qml(name, engine))

    components = folder / "ui" / "components"
    _write_if_missing(components / "GlassPanel.qml", _GLASS_PANEL_QML)
    _write_if_missing(components / "WaterReflection.qml", _WATER_REFLECTION_QML)
    _write_if_missing(components / "MattePanel.qml", _MATTE_PANEL_QML)
    _write_if_missing(components / "ActionButton.qml", _ACTION_BUTTON_QML)
    _write_if_missing(components / "GlassDialog.qml", _GLASS_DIALOG_QML)
    _write_if_missing(components / "GlassComboBox.qml", _GLASS_COMBOBOX_QML)

    _write_if_missing(folder / "scripts" / "run.sh", _RUN_SH, executable=True)
    _write_if_missing(folder / "scripts" / "check.sh", _check_sh(engine), executable=True)

    if engine == "rust":
        _write_if_missing(folder / "backend" / "Cargo.toml", _rust_cargo_toml("gema-backend"))
        _write_if_missing(folder / "backend" / "src" / "main.rs", _rust_backend_rs(name))
        _write_if_missing(folder / "backend" / "run-backend.sh", _RUST_RUN_BACKEND_SH, executable=True)
    else:
        _write_if_missing(folder / "backend" / "main.py", _python_backend(name), executable=True)

    return folder
