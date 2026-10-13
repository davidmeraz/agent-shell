"""Captura de eventos y sesiones de backend compartidas por las pruebas."""

import io
import json
import os
import queue
import subprocess
import sys
import threading
import time

from tests.support.paths import PROJECT


class QueueOutput(io.StringIO):
    def __init__(self):
        super().__init__()
        self.events = queue.Queue()

    def write(self, text):
        result = super().write(text)
        self.events.put(json.loads(text))
        return result

    def wait_for(self, kind):
        deadline = time.monotonic() + 5
        while True:
            event = self.events.get(timeout=max(0.001, deadline - time.monotonic()))
            if event["type"] == kind:
                return event["data"]


class BackendSession:
    def __init__(self, root):
        self.process = subprocess.Popen([sys.executable, "-u", str(PROJECT / "tests/support/fake_backend.py")],
            env={**os.environ, "AGENT_SHELL_HISTORY_DIR": str(root / "chats")},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.events = queue.Queue()
        self.reader = threading.Thread(
            target=lambda: [self.events.put(json.loads(line)) for line in self.process.stdout], daemon=True)
        self.reader.start()

    def __enter__(self):
        self.wait_for("auth.refresh.finished")
        return self

    def send(self, message):
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.process.stdin.flush()

    def wait_for(self, kind):
        while True:
            event = self.events.get(timeout=5)
            if event["type"] == kind:
                return event

    def __exit__(self, *args):
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=2)
        errors = self.process.stderr.read()
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()
        if not args and errors:
            raise AssertionError(errors)
