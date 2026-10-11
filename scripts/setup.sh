#!/usr/bin/env bash
# Instala el backend y el validador de identidad en un entorno local al proyecto.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -m venv "$project_root/.venv"
"$project_root/.venv/bin/python" -m pip install -e "$project_root"
