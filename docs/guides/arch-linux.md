# Integración nativa en Arch Linux

[← Índice de documentación](../README.md)

Agent Shell sigue las rutas estándar **XDG Base Directory** y ofrece empaquetado nativo para Arch Linux (`PKGBUILD`, entrada `.desktop`, ícono SVG y unidad `systemd --user`).

## Directorios XDG

Sin argumentos ni variables de sobreescritura, Agent Shell separa configuración, datos y sesión privada:

| Propósito | Variable / Ruta predeterminada | Contenido | Permisos |
| --- | --- | --- | --- |
| **Configuración** | `$XDG_CONFIG_HOME/agent-shell` (`~/.config/agent-shell`) | `limits.json` (perfiles y límites de `/limites`, seguro para dotfiles) | `0700` / `0600` |
| **Datos** | `$XDG_DATA_HOME/agent-shell` (`~/.local/share/agent-shell`) | `agent-shell.db` (SQLite WAL), `blobs/` (imágenes SHA-256), migraciones | `0700` / `0600` |
| **Sesión privada** | `$XDG_STATE_HOME/agent-shell/session` (`~/.local/state/agent-shell/session`) | `session.json`, `host_id` y bloqueo (nunca en `~/.config`) | `0700` / `0600` |

Puedes sobrescribir cualquiera de las tres rutas con `--history-root` / `AGENT_SHELL_HISTORY_DIR`, `--session-root` / `AGENT_SHELL_SESSION_DIR` y `--config-root` / `AGENT_SHELL_CONFIG_DIR`. Cuando pasas un `--history-root` o `AGENT_SHELL_HISTORY_DIR` explícito sin `--config-root`, `limits.json` se aísla dentro de `<history-root>/config` (útil para pruebas o perfiles paralelos).

### Migración automática desde `.runtime/`

Si ya usabas Agent Shell desde el repositorio con `.runtime/`, la primera vez que arranque con rutas XDG copiará automáticamente (sin borrar `.runtime/`):

- `.runtime/session/session.json` → `~/.local/state/agent-shell/session/session.json` (`0600`)
- `.runtime/chats/config/limits.json` → `~/.config/agent-shell/limits.json` (`0600`)
- `.runtime/chats/` (`agent-shell.db` con `sqlite3.backup()`, `blobs/` y/o JSON heredados) → `~/.local/share/agent-shell/`

Se escribe el marcador `.migrated-from-runtime` para que la migración sea idempotente y no vuelva a importar chats que borres más adelante.

## Opción A: Paquete nativo de Arch Linux (`PKGBUILD`)

Requiere los paquetes de Arch (`quickshell`, `python`, `python-pyjwt`, `python-cryptography`, `python-pillow`) y las herramientas de construcción (`python-build`, `python-installer`, `python-setuptools`, `python-wheel`):

```bash
cd packaging/arch
makepkg -si
```

Esto instala:

- `/usr/bin/agent-shell`
- `/usr/share/agent-shell/` (`shell.qml`, `ui/`, `backend/main.py`) y el paquete Python `harness` en `site-packages`
- `/usr/share/applications/agent-shell.desktop`
- `/usr/share/icons/hicolor/scalable/apps/agent-shell.svg`
- `/usr/lib/systemd/user/agent-shell.service`

## Opción B: Integración local de usuario (sin `root`, usando `.venv`)

Si prefieres seguir ejecutando directamente desde el repositorio con `./scripts/setup.sh`:

```bash
./scripts/install-user.sh
```

Para desinstalar la integración de usuario (conservando tus datos en XDG):

```bash
./scripts/install-user.sh --uninstall
```

## Servicio `systemd --user` e Hyprland

Para iniciar Agent Shell automáticamente con tu sesión gráfica:

```bash
systemctl --user enable --now agent-shell.service
systemctl --user status agent-shell.service
```

También puedes lanzarlo bajo demanda con un atajo en `hyprland.conf`:

```ini
bind = SUPER, A, exec, agent-shell
```

`qs --no-duplicate` evita abrir instancias duplicadas.
