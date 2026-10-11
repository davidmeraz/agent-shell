#!/usr/bin/env bash
# Pruebas del motor y revisión sintáctica de todos los componentes QML.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
"${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}" -m unittest discover -s tests -v
qmllint shell.qml smoke.qml commands-smoke.qml conversation-smoke.qml shell-command-smoke.qml ui/*.qml ui/components/*.qml
