"""Servicio HTTP/SSE local de pruebas; no contacta OpenAI ni ejecuta Codex."""

import json
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FakeService:
    def __init__(self) -> None:
        self.requests = []
        self.stream_content_type = "text/event-stream; charset=utf-8"
        self.started = threading.Event()
        self.disconnected = threading.Event()
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"models": [
                    {"slug": "test-model", "display_name": "Modelo de prueba", "visibility": "list"},
                    {"slug": "other-model", "display_name": "Otro modelo", "visibility": "list"},
                    {"slug": "hidden-model", "visibility": "hidden"},
                ]}).encode())

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                fixture.requests.append({"path": self.path, "body": body,
                                         "authorization": self.headers.get("Authorization")})
                self.send_response(200)
                if fixture.stream_content_type is not None:
                    self.send_header("Content-Type", fixture.stream_content_type)
                self.end_headers()
                prompt = body["input"][-1]["content"]
                item_id = "message-" + uuid.uuid4().hex

                def event(value):
                    self.wfile.write(("data: " + json.dumps(value, ensure_ascii=False) + "\n\n").encode())
                    self.wfile.flush()

                try:
                    event({"type": "response.output_text.delta", "item_id": item_id,
                           "content_index": 0, "delta": "Hola "})
                    fixture.started.set()
                    if prompt == "cancel":
                        while True:
                            time.sleep(0.02)
                            self.wfile.write(b": heartbeat\n\n")
                            self.wfile.flush()
                    elif prompt == "disconnect":
                        return
                    elif prompt == "fail":
                        event({"type": "response.failed", "response": {"error": {
                            "code": "subscription_sharing_usage_limit_exceeded", "message": "private diagnostics"}}})
                        return
                    elif prompt == "incomplete":
                        event({"type": "response.incomplete", "response": {"status": "incomplete"}})
                        return
                    text = "Hola desde ChatGPT. 🎵"
                    event({"type": "response.output_text.delta", "item_id": item_id,
                           "content_index": 0, "delta": "desde ChatGPT. 🎵"})
                    event({"type": "response.output_text.done", "item_id": item_id,
                           "content_index": 0, "text": text})
                    event({"type": "response.completed", "response": {
                        "status": "completed", "output": [{"type": "message", "role": "assistant",
                        "id": item_id, "content": [{"type": "output_text", "text": text}]}]}})
                except (BrokenPipeError, ConnectionResetError):
                    fixture.disconnected.set()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}/v1"
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


class FakeSession:
    """Sólo las pruebas inyectan esta cuenta; el backend normal usa ChatGPTSession."""

    def __init__(self) -> None:
        self.connected = True

    def account(self):
        return {"authenticated": self.connected, "method": "chatgpt" if self.connected else "none",
                "email": "fixture@example.invalid" if self.connected else "", "plan": "",
                "plan_enabled": self.connected}

    def access_token(self):
        return "test-only-access-token"

    def logout(self):
        self.connected = False
        return True
