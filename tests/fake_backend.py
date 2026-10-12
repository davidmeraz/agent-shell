#!/usr/bin/env python3
"""Entrada de integración Qt: backend real, servicio HTTP local y cuenta de prueba."""

import os
import signal
import shlex
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeService, FakeSession
from harness.chatgpt import ChatGPTClient
from harness.http import HttpClient
from harness.server import HarnessServer
from harness.codex_usage import CodexUsageReader


def main():
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    if os.environ.get("AGENT_SHELL_TEST_CLIPBOARD") == "1":
        from harness import server
        from fake_clipboard import read_clipboard
        server.read_clipboard = read_clipboard
    with FakeService() as service:
        if os.environ.get("AGENT_SHELL_TEST_ACTIVITY") == "1":
            service.tool_batches = [
                [{"command": "mkdir -p src; printf 'uno\\n' > src/a.txt; sleep .35; printf 'dos\\n' >> src/a.txt; sleep .35; printf b > src/b.txt; sleep .35; printf c > src/c.txt; sleep .35; printf final >> src/c.txt"}],
                [{"command": "mv src/b.txt src/renamed.txt; rm src/a.txt; printf terminado > src/c.txt; sleep .4"}],
            ]
        if os.environ.get("AGENT_SHELL_TEST_WRITING") == "1":
            source = "// Escritura de prueba 🙂: <texto>\n" + "".join(
                f"const valor_{index} = {index};\n" for index in range(35))
            service.tool_batches = [[{"command": "mkdir -p src; printf %s "
                + shlex.quote(source) + " > src/main.js"}]]
        session = FakeSession()
        client = ChatGPTClient(session, HttpClient(allow_loopback=True), service.url)
        workspace = Path(os.environ.get("AGENT_SHELL_WORKSPACE", str(Path(os.environ["AGENT_SHELL_HISTORY_DIR"]).parent)))
        if (os.environ.get("AGENT_SHELL_TEST_ACTIVITY") == "1" or os.environ.get("AGENT_SHELL_TEST_WRITING") == "1") and not os.environ.get("AGENT_SHELL_WORKSPACE"):
            # Los logs de qs y su IPC no son archivos del proyecto observado.
            workspace = workspace / "project"
            workspace.mkdir()
        usage = CodexUsageReader(command=[sys.executable, str(PROJECT / "tests/fake_codex.py")])
        HarnessServer(Path(os.environ["AGENT_SHELL_HISTORY_DIR"]), sys.stdout, session, client,
                      workspace=workspace, usage_reader=usage).serve(sys.stdin)


if __name__ == "__main__":
    main()
