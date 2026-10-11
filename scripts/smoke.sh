#!/usr/bin/env bash
# Runtime temporal y servicio HTTP local: no abre OAuth ni consume una cuenta real.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
smoke_runtime="$(mktemp -d /tmp/agent-shell-smoke.XXXXXX)"
trap 'rm -rf -- "$smoke_runtime"' EXIT
env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$smoke_runtime" QT_QPA_PLATFORM=offscreen \
    AGENT_SHELL_PYTHON="${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}" \
    AGENT_SHELL_BACKEND_ENTRY="$project_root/tests/fake_backend.py" \
    AGENT_SHELL_HISTORY_DIR="$smoke_runtime/chats" \
    timeout 12s qs --path "$project_root/smoke.qml" > "$smoke_runtime/output.log" 2>&1 || {
        cat "$smoke_runtime/output.log"
        exit 1
    }
cat "$smoke_runtime/output.log"
if ! rg -q 'SMOKE_OK' "$smoke_runtime/output.log"; then exit 1; fi
# Algunos entornos restringidos impiden crear el socket IPC auxiliar de qs.
# El arnés usa stdio: se tolera sólo ese diagnóstico, nunca errores de QML.
if rg 'SMOKE_FAILED|ERROR|TypeError|ReferenceError|Binding loop' "$smoke_runtime/output.log" \
    | rg -v 'ERROR quickshell.ipc: Failed to start IPC server on path'; then
    exit 1
fi
