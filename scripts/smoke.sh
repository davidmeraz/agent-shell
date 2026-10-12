#!/usr/bin/env bash
# Runtime temporal y servicio HTTP local: no abre OAuth ni consume una cuenta real.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
smoke_runtime="$(mktemp -d /tmp/agent-shell-smoke.XXXXXX)"
trap 'rm -rf -- "$smoke_runtime"' EXIT
for smoke_config in smoke.qml commands-smoke.qml conversation-smoke.qml shell-command-smoke.qml workspaces-smoke.qml; do
    smoke_marker=SMOKE_OK
    if [[ "$smoke_config" == commands-smoke.qml ]]; then smoke_marker=COMMANDS_OK; fi
    if [[ "$smoke_config" == conversation-smoke.qml ]]; then smoke_marker=CONVERSATION_OK; fi
    if [[ "$smoke_config" == shell-command-smoke.qml ]]; then smoke_marker=SHELL_COMMAND_OK; fi
    if [[ "$smoke_config" == workspaces-smoke.qml ]]; then smoke_marker=WORKSPACES_OK; fi
    smoke_run="$smoke_runtime/${smoke_config%.qml}"
    mkdir -p "$smoke_run"
    env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$smoke_runtime" QT_QPA_PLATFORM=offscreen \
        AGENT_SHELL_PYTHON="${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}" \
        AGENT_SHELL_BACKEND_ENTRY="$project_root/tests/fake_backend.py" \
        AGENT_SHELL_HISTORY_DIR="$smoke_run/chats" \
        timeout --kill-after=2s 12s qs --path "$project_root/$smoke_config" > "$smoke_run/output.log" 2>&1 || {
        cat "$smoke_run/output.log"
        exit 1
    }
    cat "$smoke_run/output.log"
    if ! rg -q "$smoke_marker" "$smoke_run/output.log"; then exit 1; fi
    # Algunos entornos restringidos impiden crear el socket IPC auxiliar de qs.
    # El arnés usa stdio: se tolera sólo ese diagnóstico, nunca errores de QML.
    if rg 'SMOKE_FAILED|COMMANDS_FAILED|CONVERSATION_FAILED|SHELL_COMMAND_FAILED|WORKSPACES_FAILED|FATAL|ERROR|TypeError|ReferenceError|Binding loop' "$smoke_run/output.log" \
        | rg -v 'ERROR quickshell.ipc: Failed to start IPC server on path'; then
        exit 1
    fi
done
