#!/usr/bin/env bash
# Resuelve la raíz para que el lanzador funcione desde cualquier directorio.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec qs --no-duplicate --path "$project_root/shell.qml" "$@"
