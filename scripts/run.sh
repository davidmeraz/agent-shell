#!/usr/bin/env bash
# Compila si hace falta y ejecuta el binario nativo Qt6/Wayland desde el repositorio.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${AGENT_SHELL_BUILD_DIR:-$project_root/build}"
binary="$build_dir/agent-shell"

export AGENT_SHELL_APP_DIR="${AGENT_SHELL_APP_DIR:-$project_root}"
export AGENT_SHELL_PYTHON="${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}"
export AGENT_SHELL_WORKSPACE="${AGENT_SHELL_WORKSPACE:-$PWD}"

if [[ ! -x "$AGENT_SHELL_PYTHON" ]]; then
    echo 'Prepara Python con ./scripts/setup.sh antes de iniciar Agent Shell.' >&2
    exit 1
fi

needs_build=0
if [[ ! -x "$binary" ]]; then
    needs_build=1
elif find "$project_root/native" -type f \( -name '*.cpp' -o -name '*.h' -o -name 'CMakeLists.txt' \) -newer "$binary" | grep -q .; then
    needs_build=1
fi

if [[ "$needs_build" -eq 1 ]]; then
    "$project_root/scripts/build.sh"
fi

exec "$binary" "$@"
