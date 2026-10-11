#!/usr/bin/env bash
# Resuelve la raíz para que el lanzador funcione desde cualquier directorio.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export AGENT_SHELL_PYTHON="${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}"
if [[ ! -x "$AGENT_SHELL_PYTHON" ]]; then
    echo 'Prepara Python con ./scripts/setup.sh antes de iniciar Agent Shell.' >&2
    exit 1
fi
exec qs --no-duplicate --path "$project_root/shell.qml" "$@"
