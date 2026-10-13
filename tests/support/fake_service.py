"""Servicio HTTP/SSE local de pruebas; no contacta OpenAI ni ejecuta Codex."""

import json
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class FakeService:
    def __init__(self) -> None:
        self.requests = []
        self.models = [
            {"slug": "test-model", "display_name": "Modelo de prueba", "visibility": "list"},
            {"slug": "other-model", "display_name": "Otro modelo", "visibility": "list"},
            {"slug": "hidden-model", "visibility": "hidden"},
        ]
        self.stream_content_type = "text/event-stream; charset=utf-8"
        self.started = threading.Event()
        self.disconnected = threading.Event()
        self.tool_batches = []
        self.project_run_batches = [[{"command": "cat run.sh"}],
                                    [{"name": "launch_program", "command": "sh run.sh"}]]
        self.tool_completion_gate = None
        self.tool_preface = ""
        self.tool_stream_items = False
        self.response_delay = 0.0
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"models": fixture.models}).encode())

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                fixture.requests.append({"path": self.path, "body": body,
                                         "authorization": self.headers.get("Authorization")})
                if fixture.response_delay:
                    time.sleep(fixture.response_delay)
                self.send_response(200)
                if fixture.stream_content_type is not None:
                    self.send_header("Content-Type", fixture.stream_content_type)
                self.end_headers()
                last_user = max((i for i, item in enumerate(body["input"]) if item.get("role") == "user"), default=0)
                prompt = body["input"][last_user].get("content", "")
                results = [item for item in body["input"][last_user:] if item.get("type") == "function_call_output"]
                item_id = "message-" + uuid.uuid4().hex

                def event(value):
                    self.wfile.write(("data: " + json.dumps(value, ensure_ascii=False) + "\n\n").encode())
                    self.wfile.flush()

                try:
                    project_run = body.get("instructions", "").startswith("You execute the selected project")
                    batches = fixture.project_run_batches if project_run else fixture.tool_batches or [[{"command": "pwd"}]]
                    if ((project_run or isinstance(prompt, str) and prompt.startswith("shell")) and body.get("tools")):
                        if len(results) < len(batches):
                            specs = batches[len(results)]
                            output = [{"type": "reasoning", "id": "reason-" + uuid.uuid4().hex,
                                       "summary": [], "encrypted_content": "test-opaque-reasoning"}]
                            if fixture.tool_preface:
                                event({"type": "response.output_text.delta", "item_id": item_id,
                                       "delta": fixture.tool_preface})
                                output.append({"type": "message", "role": "assistant", "id": item_id,
                                               "phase": "commentary", "content": [{"type": "output_text", "text": fixture.tool_preface}]})
                            for spec in specs:
                                call = {"type": "function_call", "id": "fc-" + uuid.uuid4().hex,
                                        "call_id": "call-" + uuid.uuid4().hex, "name": spec.get("name", "shell"),
                                        "arguments": spec.get("arguments", json.dumps({"command": spec.get("command", "pwd")}))}
                                event({"type": "response.output_item.added", "item": {**call, "arguments": ""}})
                                event({"type": "response.function_call_arguments.delta", "item_id": call["id"], "delta": call["arguments"][:5]})
                                output.append(call)
                            if fixture.tool_stream_items:
                                for index, item in enumerate(output):
                                    event({"type": "response.output_item.done", "output_index": index, "item": item})
                            fixture.started.set()
                            if fixture.tool_completion_gate:
                                fixture.tool_completion_gate.wait(2)
                            event({"type": "response.completed", "response": {"status": "completed", "output": [] if fixture.tool_stream_items else output,
                                   "usage": {"input_tokens": 12, "output_tokens": 8, "total_tokens": 20}}})
                            return
                        text = "Terminal: " + "\n".join(json.loads(item["output"]).get("output", "") for item in results)
                        event({"type": "response.output_text.delta", "item_id": item_id, "delta": text})
                        message = {"type": "message", "id": item_id, "role": "assistant", "phase": "final",
                                   "content": [{"type": "output_text", "text": text}]}
                        if fixture.tool_stream_items:
                            event({"type": "response.output_item.done", "output_index": 0, "item": message})
                        event({"type": "response.completed", "response": {"status": "completed",
                               "usage": {"input_tokens": 12, "output_tokens": 8, "total_tokens": 20},
                               "output": [] if fixture.tool_stream_items else [message]}})
                        return
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
                        "status": "completed", "usage": {"input_tokens": 12, "output_tokens": 8,
                        "total_tokens": 20, "output_tokens_details": {"reasoning_tokens": 2},
                        "input_tokens_details": {"cached_tokens": 4}},
                        "output": [{"type": "message", "role": "assistant",
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
        self.selected_account = "fixture-account"

    def account(self):
        email = "fixture@example.invalid" if self.selected_account == "fixture-account" else "second@example.invalid"
        return {"authenticated": self.connected, "method": "chatgpt" if self.connected else "none",
                "email": email if self.connected else "", "plan": "",
                "plan_enabled": self.connected, "accounts": [
                    {"id": "fixture-account", "label": "Cuenta 1", "email": "fixture@example.invalid",
                     "active": self.selected_account == "fixture-account"},
                    {"id": "fixture-second", "label": "Cuenta 2", "email": "second@example.invalid",
                     "active": self.selected_account == "fixture-second"}]}

    def begin_login(self, cancel, new_account=False):
        # Verifica el botón de Qt sin abrir navegador ni emitir una URL OAuth.
        from harness.core.http import ServiceError
        raise ServiceError("Cuenta nueva solicitada (prueba)." if new_account else
                           "Cuenta actual solicitada (prueba).")

    def select_account(self, account_id):
        from harness.core.http import ServiceError
        if account_id not in ("fixture-account", "fixture-second"):
            raise ServiceError("Cuenta no registrada")
        self.selected_account = account_id
        self.connected = True

    def access_token(self):
        return "test-only-access-token"

    def logout(self):
        self.connected = False
        return True
