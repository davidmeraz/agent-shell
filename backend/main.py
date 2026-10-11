#!/usr/bin/env python3
"""Punto de entrada del backend; compatible con Python 3.11+ y sin dependencias."""

import argparse
import os
import signal
import sys
from pathlib import Path

from harness.server import HarnessServer
from harness.version import get_version


def main() -> None:
    parser = argparse.ArgumentParser(description="Chat de Agent Shell sobre Codex App Server")
    parser.add_argument("--version", action="version", version=f"Agent Shell {get_version()}")
    parser.add_argument(
        "--chat-root", type=Path,
        default=Path(__file__).resolve().parents[1] / ".runtime" / "chat",
        help="Directorio de contexto vacío para las conversaciones",
    )
    parser.add_argument(
        "--codex-executable", default=os.environ.get("AGENT_SHELL_CODEX", "codex"),
        help="Ejecutable de Codex CLI (AGENT_SHELL_CODEX o codex en PATH)",
    )
    args = parser.parse_args()
    command = [args.codex_executable, "app-server", "--stdio"]
    # Quickshell envía SIGTERM a su proceso hijo al cerrar. SystemExit atraviesa
    # el finally de serve(), que también libera el proceso nieto de Codex.
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    HarnessServer(args.chat_root, sys.stdout, command).serve(sys.stdin)


if __name__ == "__main__":
    main()
