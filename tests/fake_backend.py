#!/usr/bin/env python3
"""Entrada de integración Qt: backend real, servicio HTTP local y cuenta de prueba."""

import os
import signal
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeService, FakeSession
from harness.chatgpt import ChatGPTClient
from harness.http import HttpClient
from harness.server import HarnessServer


def main():
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    if os.environ.get("AGENT_SHELL_TEST_CLIPBOARD") == "1":
        from harness import server
        from fake_clipboard import read_clipboard
        server.read_clipboard = read_clipboard
    with FakeService() as service:
        session = FakeSession()
        client = ChatGPTClient(session, HttpClient(allow_loopback=True), service.url)
        workspace = Path(os.environ.get("AGENT_SHELL_WORKSPACE", str(Path(os.environ["AGENT_SHELL_HISTORY_DIR"]).parent)))
        HarnessServer(Path(os.environ["AGENT_SHELL_HISTORY_DIR"]), sys.stdout, session, client, workspace=workspace).serve(sys.stdin)


if __name__ == "__main__":
    main()
