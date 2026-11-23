#!/usr/bin/env bash
# Compila el binario nativo Qt6/C++ de Agent Shell.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${AGENT_SHELL_BUILD_DIR:-$project_root/build}"
build_type="${AGENT_SHELL_BUILD_TYPE:-Release}"

generator=()
if command -v ninja >/dev/null 2>&1; then
    generator=(-G Ninja)
fi

cmake -S "$project_root/native" -B "$build_dir" "${generator[@]}" \
    -DCMAKE_BUILD_TYPE="$build_type" \
    -DAGENT_SHELL_INSTALL_DATADIR="${AGENT_SHELL_INSTALL_DATADIR:-/usr/share/agent-shell}"
cmake --build "$build_dir" --parallel
