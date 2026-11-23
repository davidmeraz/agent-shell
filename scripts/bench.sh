#!/usr/bin/env bash
# Ejecuta auditoría, benchmark reproducible o comparación A/B de Agent Shell.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}"
if [[ ! -x "$python_bin" ]]; then
    echo 'Prepara Python con ./scripts/setup.sh antes de ejecutar el benchmark.' >&2
    exit 1
fi
cd "$project_root"
exec "$python_bin" -m benchmarks.cli "$@"
