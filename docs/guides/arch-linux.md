# Integración nativa en Arch Linux, Hyprland y Gema

[← Índice de documentación](../README.md)

Agent Shell se compila como una **aplicación nativa Qt6/C++20 para Wayland** con su propia identidad (`app_id = agent-shell`, sin depender de Quickshell en tiempo de ejecución), instancia única por IPC (`QLocalSocket`), empaquetado oficial para Arch Linux (`PKGBUILD`) e integración directa con Hyprland y el tema **Gema**.

## Compilación y ejecución nativa

Requiere `cmake`, `ninja`, compilador C++20 y los paquetes de Qt6 (`qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`).

```bash
./scripts/build.sh
./scripts/run.sh
```

El binario compilado (`build/agent-shell` o `~/.local/bin/agent-shell` / `/usr/bin/agent-shell`) admite control por línea de comandos sobre la instancia activa:

| Comando | Acción |
| --- | --- |
| `agent-shell` | Inicia la aplicación o enfoca la instancia activa si ya está abierta |
| `agent-shell --toggle` | Alterna visibilidad (oculta si está enfocada manteniendo la sesión viva, o la trae al frente) |
| `agent-shell --focus` | Trae la ventana principal al frente y la enfoca en Hyprland |
| `agent-shell --status` | Muestra en JSON si hay una instancia activa, su `pid`, `version` y `app_id` |
| `agent-shell --quit` | Cierra limpiamente la instancia en ejecución |
| `agent-shell --workspace <ruta>` | Define el directorio de trabajo inicial |

## Directorios XDG

Sin argumentos ni variables de sobreescritura, Agent Shell separa configuración, datos, runtime instalado y sesión privada:

| Propósito | Variable / Ruta predeterminada | Contenido | Permisos |
| --- | --- | --- | --- |
| **Configuración** | `$XDG_CONFIG_HOME/agent-shell` (`~/.config/agent-shell`) | `limits.json` (perfiles y límites de `/limites`, seguro para dotfiles) | `0700` / `0600` |
| **Datos** | `$XDG_DATA_HOME/agent-shell` (`~/.local/share/agent-shell`) | `agent-shell.db` (SQLite WAL), `blobs/` (imágenes SHA-256) | `0700` / `0600` |
| **Runtime instalado (usuario)** | `$XDG_DATA_HOME/agent-shell/app` (`~/.local/share/agent-shell/app`) | Copia independiente de `shell.qml`, `ui/`, `backend/`, `scripts/` y `.venv` | `0755` |
| **Sesión privada** | `$XDG_STATE_HOME/agent-shell/session` (`~/.local/state/agent-shell/session`) | `session.json`, `host_id` y bloqueo (nunca en `~/.config`) | `0700` / `0600` |

## Opción A: Instalación local independiente (sin `root`, con integración Hyprland + Gema)

Compila el binario nativo en modo `Release`, instala una copia independiente del repositorio en `~/.local/share/agent-shell/app`, copia el ejecutable a `~/.local/bin/agent-shell`, registra el `.desktop`, el ícono SVG y la unidad `systemd --user`, y aplica las reglas de Hyprland y Gema (con respaldo automático en `~/.local/state/agent-shell/backups/`):

```bash
./scripts/install-user.sh
```

Opciones disponibles:

- `./scripts/install-user.sh --keybind "SUPER + A"`: personaliza el atajo global en Hyprland.
- `./scripts/install-user.sh --no-dock`: omite fijar `agent-shell` en `~/.config/gema/dock.json`.
- `./scripts/install-user.sh --no-hyprland`: instala solo binario, `.desktop`, ícono y `systemd`.
- `./scripts/install-user.sh --uninstall`: retira la aplicación y los bloques gestionados en Hyprland/Gema conservando tus chats, proyectos y sesión.

## Opción B: Paquete nativo de Arch Linux (`PKGBUILD`)

Requiere los paquetes de Arch (`qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-svg`, `python`, `python-pyjwt`, `python-cryptography`, `python-pillow`) y las herramientas de compilación (`cmake`, `ninja`, `python-build`, `python-installer`, `python-setuptools`, `python-wheel`):

```bash
cd packaging/arch
makepkg -si
```

Esto instala:

- `/usr/bin/agent-shell` (binario nativo ELF Qt6/C++)
- `/usr/share/agent-shell/` (`shell.qml`, `ui/`, `backend/main.py`, `scripts/place-text-viewer.py`, `hyprland/agent-shell.lua`, `agent-shell.svg`) y el paquete Python `harness` en `site-packages`
- `/usr/share/applications/agent-shell.desktop` (`StartupWMClass=agent-shell`)
- `/usr/share/icons/hicolor/scalable/apps/agent-shell.svg`
- `/usr/lib/systemd/user/agent-shell.service`

## Integración con Hyprland y el tema Gema

Al ejecutarse con `app_id = agent-shell`, Hyprland identifica todas las ventanas de Agent Shell bajo `class = "agent-shell"` (sin mezclarse con `org.quickshell`):

- **Sincronización en vivo con Gema:** `NativeFileView` observa `~/.config/gema/preferences.json` (incluidas las escrituras atómicas por reemplazo de archivo) y sincroniza al instante color de acento, gema activa, animaciones, `blur` y `darkText` sin reiniciar.
- **Reglas de ventana en `~/.config/gema/hypr-user.lua`:** `float = true`, `opaque = false`, `opacity = "1.0 override"`, `border_size = 0`, `no_shadow = true` y `rounding = 20` para que el desenfoque nativo de Hyprland encaje exactamente con el cristal redondeado de la interfaz.
- **Atajo global:** `SUPER + A` ejecuta `agent-shell --toggle`.
- **Launcher y Dock de Gema:** `StartupWMClass=agent-shell` coincide con la clase Wayland para mostrar el ícono correcto, estado activo y anclaje en el dock.

## Servicio `systemd --user`

Para iniciar Agent Shell automáticamente con tu sesión gráfica:

```bash
systemctl --user enable --now agent-shell.service
systemctl --user status agent-shell.service
```
