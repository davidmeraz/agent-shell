#!/usr/bin/env python3
"""Entrada del chat directo con ChatGPT; no inicia procesos de Codex."""

import argparse
import os
import signal
import sys
from pathlib import Path

from harness.core.limits import AgentLimits, LimitsStore
from harness.core.paths import (
    default_workspace,
    legacy_runtime_for,
    migrate_legacy_runtime,
    resolve_runtime_paths,
)
from harness.core.server import HarnessServer
from harness.core.version import get_version


def main() -> None:
    parser = argparse.ArgumentParser(description="Chat de Agent Shell con sesión propia de ChatGPT")
    parser.add_argument("--version", action="version", version=f"Agent Shell {get_version()}")
    parser.add_argument(
        "--history-root", type=Path, default=None,
        help="Directorio de datos del historial y proyectos (por defecto $XDG_DATA_HOME/agent-shell)",
    )
    parser.add_argument(
        "--session-root", type=Path, default=None,
        help="Directorio privado de la sesión de ChatGPT (por defecto $XDG_STATE_HOME/agent-shell/session)",
    )
    parser.add_argument(
        "--config-root", type=Path, default=None,
        help="Directorio de configuración persistente (por defecto $XDG_CONFIG_HOME/agent-shell)",
    )
    parser.add_argument(
        "--workspace", type=Path, default=default_workspace(),
        help="Directorio inicial de la terminal de Chat; cada proyecto de Work usa su propia carpeta",
    )
    parser.add_argument(
        "--model", default=os.environ.get("AGENT_SHELL_MODEL", ""),
        help="Modelo inicial, si está disponible en el catálogo de tu cuenta",
    )
    args = parser.parse_args()
    paths = resolve_runtime_paths(
        history_arg=args.history_root,
        session_arg=args.session_root,
        config_arg=args.config_root,
    )
    legacy = legacy_runtime_for(Path(__file__))
    if legacy is not None:
        migrate_legacy_runtime(legacy, paths)
    from harness.tools.shell import resolve_workspace
    try:
        args.workspace = resolve_workspace(args.workspace)
    except (ValueError, OSError):
        parser.error("--workspace debe indicar un directorio existente")
    try:
        persisted_limits = LimitsStore(paths.config_root).load()
        limits = AgentLimits.from_environment(base=persisted_limits)
    except ValueError as error:
        parser.error(str(error))
    from harness.account.auth import ChatGPTSession
    from harness.chat.agy import AgyClient
    from harness.chat.chatgpt import ChatGPTClient
    from harness.chat.claude import ClaudeClient
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    session = ChatGPTSession(paths.session_root)
    HarnessServer(
        paths.history_root, sys.stdout, session, ChatGPTClient(session), args.model,
        args.workspace, limits=limits, config_root=paths.config_root,
        agy_client=AgyClient(), claude_client=ClaudeClient(),
        track_chat_quota=True,
    ).serve(sys.stdin)


if __name__ == "__main__":
    main()
