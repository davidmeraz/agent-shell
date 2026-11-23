#!/usr/bin/env bash
# Pruebas de integración UI reales sobre el binario nativo Qt6/C++ en modo offscreen.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${AGENT_SHELL_BUILD_DIR:-$project_root/build}/agent-shell"

if [[ ! -x "$binary" ]]; then
    "$project_root/scripts/build.sh"
fi

smoke_runtime="$(mktemp -d /tmp/agent-shell-smoke.XXXXXX)"
trap 'rm -rf -- "$smoke_runtime"' EXIT

for smoke_config in smoke.qml commands-smoke.qml models-smoke.qml conversation-smoke.qml shell-command-smoke.qml workspaces-smoke.qml explorer-smoke.qml images-smoke.qml activity-smoke.qml writing-smoke.qml usage-smoke.qml project-run-smoke.qml unified-smoke.qml; do
    smoke_marker=SMOKE_OK
    if [[ "$smoke_config" == commands-smoke.qml ]]; then smoke_marker=COMMANDS_OK; fi
    if [[ "$smoke_config" == models-smoke.qml ]]; then smoke_marker=MODELS_OK; fi
    if [[ "$smoke_config" == conversation-smoke.qml ]]; then smoke_marker=CONVERSATION_OK; fi
    if [[ "$smoke_config" == shell-command-smoke.qml ]]; then smoke_marker=SHELL_COMMAND_OK; fi
    if [[ "$smoke_config" == workspaces-smoke.qml ]]; then smoke_marker=WORKSPACES_OK; fi
    if [[ "$smoke_config" == explorer-smoke.qml ]]; then smoke_marker=EXPLORER_OK; fi
    if [[ "$smoke_config" == usage-smoke.qml ]]; then smoke_marker=USAGE_OK; fi
    if [[ "$smoke_config" == unified-smoke.qml ]]; then smoke_marker=UNIFIED_OK; fi
    if [[ "$smoke_config" == project-run-smoke.qml ]]; then smoke_marker=PROJECT_RUN_OK; fi
    smoke_clipboard=0
    smoke_activity=0
    smoke_writing=0
    smoke_project_run=0
    smoke_models=0
    if [[ "$smoke_config" == models-smoke.qml ]]; then smoke_models=1; fi
    if [[ "$smoke_config" == images-smoke.qml ]]; then smoke_marker=IMAGES_OK; smoke_clipboard=1; fi
    if [[ "$smoke_config" == activity-smoke.qml ]]; then smoke_marker=ACTIVITY_OK; smoke_activity=1; fi
    if [[ "$smoke_config" == writing-smoke.qml ]]; then smoke_marker=WRITING_OK; smoke_writing=1; fi
    if [[ "$smoke_config" == project-run-smoke.qml ]]; then smoke_project_run=1; fi
    smoke_run="$smoke_runtime/${smoke_config%.qml}"
    mkdir -p "$smoke_run/workspace"
    env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$smoke_runtime" QT_QPA_PLATFORM=offscreen \
        AGENT_SHELL_APP_DIR="$project_root" \
        AGENT_SHELL_WORKSPACE="$smoke_run/workspace" \
        AGENT_SHELL_PYTHON="${AGENT_SHELL_PYTHON:-$project_root/.venv/bin/python}" \
        AGENT_SHELL_BACKEND_ENTRY="$project_root/tests/support/fake_backend.py" \
        AGENT_SHELL_HISTORY_DIR="$smoke_run/chats" \
        AGENT_SHELL_TEST_CLIPBOARD="$smoke_clipboard" \
        AGENT_SHELL_TEST_ACTIVITY="$smoke_activity" \
        AGENT_SHELL_TEST_WRITING="$smoke_writing" \
        AGENT_SHELL_TEST_PROJECT_RUN="$smoke_project_run" \
        AGENT_SHELL_TEST_MODELS="$smoke_models" \
        timeout --kill-after=2s 12s "$binary" --no-single-instance \
            --qml "$project_root/tests/ui/$smoke_config" > "$smoke_run/output.log" 2>&1 || {
        cat "$smoke_run/output.log"
        exit 1
    }
    cat "$smoke_run/output.log"
    if ! rg -q "$smoke_marker" "$smoke_run/output.log"; then exit 1; fi
    if rg 'SMOKE_FAILED|COMMANDS_FAILED|MODELS_FAILED|CONVERSATION_FAILED|SHELL_COMMAND_FAILED|WORKSPACES_FAILED|EXPLORER_FAILED|IMAGES_FAILED|ACTIVITY_FAILED|WRITING_FAILED|USAGE_FAILED|PROJECT_RUN_FAILED|UNIFIED_FAILED|FATAL|ERROR|TypeError|ReferenceError|Binding loop' "$smoke_run/output.log"; then
        exit 1
    fi
done
