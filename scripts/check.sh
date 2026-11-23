#!/usr/bin/env bash
# Compila el módulo nativo, ejecuta pruebas de Python y valida todos los componentes QML.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
"$project_root/scripts/build.sh"
"${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}" -m unittest discover -s tests -t . -v
qmllint -I "$project_root/build" shell.qml tests/ui/*.qml ui/*.qml ui/components/*/*.qml
