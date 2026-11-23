#!/usr/bin/env bash
# Instala o retira el lanzador, ícono y unidad systemd --user en ~/.local y ~/.config sin root.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
bin_dir="$HOME/.local/bin"
apps_dir="$xdg_data/applications"
icons_dir="$xdg_data/icons/hicolor/scalable/apps"
systemd_dir="$xdg_config/systemd/user"

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$bin_dir/agent-shell" \
          "$apps_dir/agent-shell.desktop" \
          "$icons_dir/agent-shell.svg" \
          "$systemd_dir/agent-shell.service"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    echo "Integración de usuario de Agent Shell eliminada (tus datos en XDG se conservan)."
    exit 0
fi

mkdir -p "$bin_dir" "$apps_dir" "$icons_dir" "$systemd_dir"

cat > "$bin_dir/agent-shell" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$project_root/scripts/run.sh" "\$@"
EOF
chmod 755 "$bin_dir/agent-shell"

sed "s|^Exec=/usr/bin/agent-shell|Exec=$bin_dir/agent-shell|" \
    "$project_root/packaging/arch/agent-shell.desktop" > "$apps_dir/agent-shell.desktop"
chmod 644 "$apps_dir/agent-shell.desktop"

cp "$project_root/packaging/arch/agent-shell.svg" "$icons_dir/agent-shell.svg"
chmod 644 "$icons_dir/agent-shell.svg"

sed "s|^ExecStart=/usr/bin/agent-shell|ExecStart=$bin_dir/agent-shell|" \
    "$project_root/packaging/arch/agent-shell.service" > "$systemd_dir/agent-shell.service"
chmod 644 "$systemd_dir/agent-shell.service"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" 2>/dev/null || true
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
fi

echo "Instalado en usuario:"
echo "  Ejecutable: $bin_dir/agent-shell"
echo "  Escritorio: $apps_dir/agent-shell.desktop"
echo "  Ícono:      $icons_dir/agent-shell.svg"
echo "  Systemd:    $systemd_dir/agent-shell.service"
echo "Activar al iniciar sesión gráfica: systemctl --user enable --now agent-shell.service"
