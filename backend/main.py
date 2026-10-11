#!/usr/bin/env python3
"""Entrada del chat directo con ChatGPT; no inicia procesos de Codex."""

import argparse
import os
import signal
import sys
from pathlib import Path

from harness.server import HarnessServer
from harness.version import get_version


def main() -> None:
    parser = argparse.ArgumentParser(description="Chat de Agent Shell con sesión propia de ChatGPT")
    parser.add_argument("--version", action="version", version=f"Agent Shell {get_version()}")
    parser.add_argument(
        "--history-root", type=Path,
        default=Path(os.environ.get(
            "AGENT_SHELL_HISTORY_DIR", str(Path(__file__).resolve().parents[1] / ".runtime" / "chats"),
        )),
        help="Directorio de los archivos JSON de conversación",
    )
    parser.add_argument(
        "--session-root", type=Path,
        default=Path(os.environ.get("AGENT_SHELL_SESSION_DIR", str(
            Path(__file__).resolve().parents[1] / ".runtime" / "session",
        ))),
        help="Directorio privado de la sesión propia de ChatGPT",
    )
    parser.add_argument(
        "--model", default=os.environ.get("AGENT_SHELL_MODEL", ""),
        help="Modelo inicial, si está disponible en el catálogo de tu cuenta",
    )
    args = parser.parse_args()
    from harness.auth import ChatGPTSession
    from harness.chatgpt import ChatGPTClient
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    session = ChatGPTSession(args.session_root)
    HarnessServer(args.history_root, sys.stdout, session, ChatGPTClient(session), args.model).serve(sys.stdin)


if __name__ == "__main__":
    main()
