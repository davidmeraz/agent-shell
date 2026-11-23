#!/usr/bin/env bash
# Compila e instala Agent Shell como aplicación nativa independiente en ~/.local e integra Hyprland/Gema.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
bin_dir="$HOME/.local/bin"
app_dir="$xdg_data/agent-shell/app"
apps_dir="$xdg_data/applications"
icons_dir="$xdg_data/icons/hicolor/scalable/apps"
systemd_dir="$xdg_config/systemd/user"

uninstall=0
integrate_hyprland=1
pin_dock=1
keybind="SUPER + A"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) uninstall=1; shift ;;
        --no-hyprland) integrate_hyprland=0; shift ;;
        --no-dock) pin_dock=0; shift ;;
        --keybind) keybind="$2"; shift 2 ;;
        -h|--help)
            echo "Uso: $0 [--uninstall] [--no-hyprland] [--no-dock] [--keybind 'SUPER + A']"
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1" >&2
            exit 2
            ;;
    esac
done

if [[ "$uninstall" -eq 1 ]]; then
    if [[ -x "$bin_dir/agent-shell" ]]; then
        "$bin_dir/agent-shell" --quit 2>/dev/null || true
    fi
    rm -f "$bin_dir/agent-shell" \
          "$apps_dir/agent-shell.desktop" \
          "$icons_dir/agent-shell.svg" \
          "$systemd_dir/agent-shell.service"
    rm -rf "$app_dir"
    if [[ "$integrate_hyprland" -eq 1 && -f "$project_root/scripts/hyprland-integrate.py" ]]; then
        python3 "$project_root/scripts/hyprland-integrate.py" remove || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$xdg_data/icons/hicolor" 2>/dev/null || true
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    echo "Aplicación nativa Agent Shell eliminada (tus chats, proyectos y sesión en XDG se conservan)."
    exit 0
fi

# 1. Compila el binario nativo Qt6/C++ en modo Release.
"$project_root/scripts/build.sh"

mkdir -p "$bin_dir" "$app_dir" "$apps_dir" "$icons_dir" "$systemd_dir"

# 2. Instala una copia independiente de los recursos QML y del backend en ~/.local/share/agent-shell/app
#    (sin tocar ~/.local/share/agent-shell/agent-shell.db ni blobs/).
rm -rf "$app_dir/ui" "$app_dir/backend" "$app_dir/scripts" "$app_dir/shell.qml" "$app_dir/pyproject.toml" "$app_dir/agent-shell.svg"
mkdir -p "$app_dir/backend" "$app_dir/scripts"
cp -a "$project_root/ui" "$app_dir/ui"
cp -a "$project_root/backend/main.py" "$app_dir/backend/main.py"
cp -a "$project_root/backend/harness" "$app_dir/backend/harness"
find "$app_dir/backend" -type d -name '__pycache__' -exec rm -rf {} +
install -Dm755 "$project_root/scripts/place-text-viewer.py" "$app_dir/scripts/place-text-viewer.py"
install -Dm644 "$project_root/shell.qml" "$app_dir/shell.qml"
install -Dm644 "$project_root/pyproject.toml" "$app_dir/pyproject.toml"
install -Dm644 "$project_root/packaging/arch/agent-shell.svg" "$app_dir/agent-shell.svg"

# 3. Prepara un entorno Python aislado para la copia instalada (reutiliza paquetes de .venv si ya existen).
if [[ ! -x "$app_dir/.venv/bin/python" ]]; then
    python3 -m venv "$app_dir/.venv"
fi
app_site="$("$app_dir/.venv/bin/python" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
if [[ -d "$project_root/.venv" ]]; then
    repo_site="$("$project_root/.venv/bin/python" -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
    if [[ -d "$repo_site" ]]; then
        python3 - "$repo_site" "$app_site" "$app_dir/backend" <<'PY'
import shutil, sys
from pathlib import Path

src_site = Path(sys.argv[1])
dst_site = Path(sys.argv[2])
backend_dir = sys.argv[3]

for entry in src_site.iterdir():
    name = entry.name
    if name.startswith(("pip", "__editable__", "agent_shell", "_virtualenv")):
        continue
    target = dst_site / name
    if target.exists():
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        else:
            target.unlink()
    if entry.is_dir():
        shutil.copytree(entry, target, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    else:
        shutil.copy2(entry, target)

(dst_site / "agent_shell_app.pth").write_text(backend_dir + "\n", encoding="utf-8")
PY
    fi
else
    "$app_dir/.venv/bin/python" -m pip install --quiet "$project_root"
fi

# Verificación inmediata de dependencias del backend instalado.
"$app_dir/.venv/bin/python" -c "import jwt, cryptography, PIL, harness"

# 4. Instala el binario nativo ELF, .desktop, ícono SVG y unidad systemd --user.
install -Dm755 "$project_root/build/agent-shell" "$bin_dir/agent-shell"

sed "s|/usr/bin/agent-shell|$bin_dir/agent-shell|g" \
    "$project_root/packaging/arch/agent-shell.desktop" > "$apps_dir/agent-shell.desktop"
chmod 644 "$apps_dir/agent-shell.desktop"

install -Dm644 "$project_root/packaging/arch/agent-shell.svg" "$icons_dir/agent-shell.svg"

sed "s|^ExecStart=/usr/bin/agent-shell|ExecStart=$bin_dir/agent-shell|" \
    "$project_root/packaging/arch/agent-shell.service" > "$systemd_dir/agent-shell.service"
chmod 644 "$systemd_dir/agent-shell.service"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$xdg_data/icons/hicolor" 2>/dev/null || true
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

# 5. Integra reglas de ventana Wayland (app_id=agent-shell), atajo global y Dock de Gema.
if [[ "$integrate_hyprland" -eq 1 ]]; then
    extra_args=()
    if [[ "$pin_dock" -eq 0 ]]; then
        extra_args+=(--no-dock)
    fi
    python3 "$project_root/scripts/hyprland-integrate.py" install \
        --binary "$bin_dir/agent-shell" \
        --keybind "$keybind" \
        "${extra_args[@]}"
fi

echo ""
echo "Agent Shell instalado como aplicación nativa independiente:"
echo "  Binario ELF: $bin_dir/agent-shell"
echo "  Runtime app: $app_dir"
echo "  Escritorio:  $apps_dir/agent-shell.desktop (StartupWMClass=agent-shell)"
echo "  Ícono SVG:   $icons_dir/agent-shell.svg"
echo "  Systemd:     $systemd_dir/agent-shell.service"
echo ""
echo "Comandos útiles:"
echo "  agent-shell            # Inicia o enfoca la ventana nativa"
echo "  agent-shell --toggle   # Alterna visibilidad (atajo $keybind en Hyprland)"
echo "  agent-shell --status   # Estado IPC en JSON"
echo "  agent-shell --quit     # Cierra la instancia en ejecución"
echo "  systemctl --user enable --now agent-shell.service"
