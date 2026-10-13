#!/usr/bin/env bash
# Pruebas del motor y revisión sintáctica de todos los componentes QML.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
"${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}" -m unittest discover -s tests -t . -v
qmllint shell.qml tests/ui/*.qml ui/*.qml ui/components/*/*.qml
