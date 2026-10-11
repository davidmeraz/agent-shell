"""Contrato Qt/Python para chat directo con ChatGPT y contexto local persistente."""

import copy
import json
import threading
import time
import uuid
from pathlib import Path
from typing import Any, TextIO

from .events import EventEmitter
from .history import HistoryStore
from .http import Cancelled, ServiceError, StreamControl, service_error
from .performance import TurnPerformance, safe_usage
from .version import get_version

MAX_REQUEST_BYTES = 65536
MAX_PROMPT_LENGTH = 16000
CHAT_INSTRUCTIONS = (
    "You are the conversational assistant in Agent Shell. Respond in the user's language. "
    "This application supports chat only. When asked for code, include it in your reply."
)


class HarnessServer:
    """Mantiene stdin libre durante OAuth, descubrimiento y streaming HTTP."""

    def __init__(self, history_root: Path, output: TextIO, session, client,
                 model: str = "") -> None:
        self.events = EventEmitter(output)
        self.history = HistoryStore(history_root)
        self.session = session
        self.client = client
        self.conversation: dict | None = None
        self.model = model
        self.models: list[dict] = []
        self.authenticated = False
        self.busy = False
        self.login_pending = False
        self.account_pending = False
        self._lock = threading.RLock()
        self._closing = threading.Event()
        self._login_cancel = threading.Event()
        self._stream = StreamControl()
        self._generation = 0
        self._last_saved = 0.0
        self._workers: list[threading.Thread] = []
        self._performance: TurnPerformance | None = None
        self._last_metrics_emitted = 0.0

    def _emit(self, event_type: str, **data) -> None:
        if not self._closing.is_set():
            self.events.emit(event_type, **data)

    def _spawn(self, operation) -> None:
        def guarded():
            try:
                operation()
            except (ServiceError, OSError, ValueError, KeyError, TypeError):
                self._emit("error", message="No se pudo completar la operación. Vuelve a intentarlo.")
        worker = threading.Thread(target=guarded, daemon=True)
        self._workers = [item for item in self._workers if item.is_alive()]
        self._workers.append(worker)
        worker.start()

    def _publish_history(self) -> None:
        self._emit("history.list", chats=self.history.list())
        if self.history.invalid_files:
            self._emit("history.notice", message="Hay archivos de historial dañados o incompatibles; se conservaron.")

    def _publish_account(self) -> None:
        account = self.session.account()
        self.authenticated = bool(account["authenticated"])
        self._emit("auth.state", **account)

    def _refresh_account(self) -> None:
        try:
            with self._lock:
                self._publish_account()
                connected = self.authenticated
            models = self.client.models() if connected else []
            with self._lock:
                if self._closing.is_set():
                    return
                self.models = models
                allowed = {row["slug"] for row in models}
                if self.model not in allowed:
                    self.model = models[0]["slug"] if models else ""
                self._emit("models.list", models=models, selected=self.model)
                self._publish_account()
        except (ServiceError, OSError) as error:
            with self._lock:
                self.models = []
                self._publish_account()
                self._emit("models.list", models=[], selected="")
                self._emit("error", message=str(error) if isinstance(error, ServiceError) else
                           "No se pudo leer la sesión guardada")
        finally:
            with self._lock:
                self.account_pending = False
                self._emit("auth.refresh.finished")

    def _login(self, cancel: threading.Event) -> None:
        attempt = None
        success, message = False, "Inicio de sesión cancelado."
        try:
            if cancel.is_set():
                raise Cancelled()
            attempt = self.session.begin_login(cancel)
            with self._lock:
                if cancel.is_set():
                    raise Cancelled()
                self._emit("auth.login.started", url=attempt.url)
            callback = attempt.wait()
            self.session.complete_login(attempt, callback)
            success, message = True, "Cuenta conectada."
        except Cancelled:
            pass
        except ServiceError as error:
            message = str(error)
        except (OSError, ValueError, KeyError, TypeError):
            message = "No se pudo iniciar sesión. Comprueba tu conexión y vuelve a intentarlo."
        finally:
            if attempt:
                attempt.close()
            with self._lock:
                self.login_pending = False
                welcome = (success and self.session.account()["plan_enabled"]
                           and not (attempt.profile.get("scopes") and
                                    "chatgpt.tokens.use.direct" in attempt.profile["scopes"]))
                self._emit("auth.login.finished", success=success, message=message, show_plan_welcome=bool(welcome))
                if success and not self._closing.is_set():
                    self._publish_account()
                    self.account_pending = True
                    self._emit("auth.refresh.started")
                    self._spawn(self._refresh_account)

    def _logout(self) -> None:
        try:
            confirmed = self.session.logout()
            with self._lock:
                self.models = []
                self._emit("models.list", models=[], selected="")
                self._publish_account()
                if not confirmed:
                    self._emit("error", message="Sesión local cerrada. No se confirmó la revocación remota; puedes desconectar Agent Shell en los ajustes de ChatGPT.")
        finally:
            with self._lock:
                self.account_pending = False
                self._emit("auth.refresh.finished")

    def _open_chat(self, chat_id: str) -> None:
        record = self.history.load(chat_id)
        for message in record["messages"]:
            if message["status"] == "streaming":
                message["status"] = "interrupted"
        for measurement in record["performance"]:
            if measurement["status"] == "streaming":
                measurement["status"] = "interrupted"
                measurement["total_ms"] = measurement["elapsed_ms"]
        self.conversation = record
        self._performance = None
        if record.get("model") in {row["slug"] for row in self.models}:
            self.model = record["model"]
        self._emit("chat.loaded", chat=record)
        self._emit("model.selected", model=self.model)

    def _save(self) -> None:
        if self.conversation is not None:
            try:
                self.history.save(self.conversation)
                self._last_saved = time.monotonic()
            except OSError:
                self._emit("history.notice", message="No se pudo guardar el último estado del chat; el texto sigue visible.")

    def _message(self, item_id: str, text: str, append: bool) -> None:
        messages = self.conversation["messages"]
        row = next((entry for entry in messages if entry["id"] == item_id), None)
        if row is None:
            row = {"id": item_id, "role": "assistant", "text": "", "status": "streaming",
                   "turn_id": self._performance.turn_id if self._performance else ""}
            messages.append(row)
        row["text"] = row["text"] + text if append else text
        first_text = bool(self._performance and self._performance.first_text is None and row["text"])
        if self._performance:
            self._performance.text(item_id, row["text"])
        self._emit("chat.delta" if append else "chat.message", item_id=item_id, text=text,
                   turn_id=row.get("turn_id", ""))
        self._update_performance(force=first_text)
        if time.monotonic() - self._last_saved >= 0.5:
            self._save()

    def _update_performance(self, force: bool = False) -> None:
        if not self._performance or self.conversation is None:
            return
        snapshot = self._performance.snapshot()
        measurements = self.conversation.setdefault("performance", [])
        index = next((i for i, row in enumerate(measurements)
                      if row["turn_id"] == snapshot["turn_id"]), None)
        if index is None:
            measurements.append(snapshot)
        else:
            measurements[index] = snapshot
        now = time.monotonic()
        if force or not self._last_metrics_emitted or now - self._last_metrics_emitted >= 0.25:
            self._last_metrics_emitted = now
            self._emit("performance.updated", measurement={**snapshot, "chat_id": self.conversation["chat_id"]})

    def _mark_phase(self, phase: str, generation: int) -> None:
        with self._lock:
            if self.busy and generation == self._generation and self._performance:
                self._performance.mark(phase)

    def _publish_performance(self) -> None:
        try:
            measurements = self.history.performance()
        except OSError:
            self._emit("performance.list", measurements=[])
            self._emit("history.notice", message="No se pudieron leer las mediciones guardadas. Vuelve a actualizar el panel.")
            return
        with self._lock:
            if self._performance and self.conversation is not None:
                snapshot = {**self._performance.snapshot(), "chat_id": self.conversation["chat_id"]}
                measurements = [row for row in measurements if row["turn_id"] != snapshot["turn_id"]]
                measurements.append(snapshot)
                measurements.sort(key=lambda row: row["started_at"], reverse=True)
            self._emit("performance.list", measurements=measurements[:200])

    def _finish(self, status: str, message: str = "") -> None:
        self.busy = False
        if self._performance and self._performance.status == "streaming":
            self._performance.finish(status)
            self._update_performance(force=True)
        if self.conversation is not None:
            for entry in self.conversation["messages"]:
                if entry["status"] == "streaming":
                    entry["status"] = status
            self._save()
        self._emit("chat.finished", status=status, message=message,
                   turn_id=self._performance.turn_id if self._performance else "")
        self._publish_history()

    def _response_event(self, event: dict, generation: int) -> bool:
        """No publica razonamiento ni eventos de una respuesta ya cancelada."""
        with self._lock:
            if not self.busy or generation != self._generation or self._closing.is_set():
                return True
            kind = event["type"]
            if kind in ("response.output_text.delta", "response.output_text.done"):
                item_id = event.get("item_id")
                text = event.get("delta" if kind.endswith("delta") else "text")
                if not isinstance(item_id, str) or not isinstance(text, str):
                    raise ServiceError("El servicio devolvió un fragmento incompatible")
                part = str(event.get("content_index", 0))
                self._message(item_id + ":" + part, text, kind.endswith("delta"))
            elif kind == "response.completed":
                response = event.get("response") or {}
                if response.get("status") != "completed":
                    raise ServiceError("El servicio no confirmó que la respuesta terminara")
                if self._performance:
                    self._performance.usage = safe_usage(response.get("usage"))
                for item in response.get("output", []):
                    if item.get("type") == "message" and item.get("role") == "assistant":
                        for index, content in enumerate(item.get("content", [])):
                            if content.get("type") in ("output_text", "refusal"):
                                self._message(item["id"] + ":" + str(index),
                                              content.get("text", content.get("refusal", "")), False)
                self._finish("completed")
                return True
            elif kind in ("response.failed", "response.incomplete", "error"):
                response = event.get("response") or {}
                if self._performance:
                    self._performance.usage = safe_usage(response.get("usage"))
                if kind == "response.incomplete":
                    raise ServiceError("La respuesta quedó incompleta. Puedes pedir que continúe.")
                raise service_error(error=response.get("error") or event.get("error") or event)
            return False

    def _start_turn(self, messages: list[dict], model: str, control: StreamControl,
                    generation: int) -> None:
        try:
            for event in self.client.stream(model, messages, CHAT_INSTRUCTIONS, control):
                if self._response_event(event, generation):
                    return
            control.check()
            raise ServiceError("La transmisión terminó antes de confirmar la respuesta completa")
        except Cancelled:
            with self._lock:
                if self.busy and generation == self._generation:
                    self._finish("interrupted")
        except (ServiceError, OSError, ValueError, KeyError, TypeError) as error:
            with self._lock:
                if self.busy and generation == self._generation:
                    self._finish("failed", str(error) if isinstance(error, ServiceError) else
                                 "No se pudo completar la respuesta")
                    self._publish_account()

    def handle(self, request: Any) -> None:
        received = time.perf_counter()
        if not isinstance(request, dict):
            self._emit("error", message="La instrucción debe ser un objeto JSON")
            return
        with self._lock:
            action = request.get("type")
            if action == "performance.list":
                self._spawn(self._publish_performance)
                return
            if action == "performance.presented":
                if (self._performance and request.get("turn_id") == self._performance.turn_id
                        and self.conversation is not None
                        and self._performance.presented(request.get("first_visible_ms"), request.get("ui_frame_ms"))):
                    self._update_performance(force=True)
                    if not self.busy:
                        self._save()
                return
            if action == "chat.cancel":
                if self.busy:
                    self._stream.cancel()
                    self._finish("interrupted")
                return
            if action == "auth.cancel":
                self._login_cancel.set()
                return
            if action in ("chat.new", "chat.open", "history.list", "model.select"):
                if self.busy or self.login_pending or (action == "model.select" and self.account_pending):
                    self._emit("error", message="Espera a que termine la operación actual")
                    return
                try:
                    if action == "chat.new":
                        self.conversation = None
                        self._performance = None
                        self._emit("chat.reset")
                        self._emit("model.selected", model=self.model)
                    elif action == "chat.open":
                        self._open_chat(request.get("chat_id"))
                    elif action == "history.list":
                        self._publish_history()
                    elif request.get("model") in {row["slug"] for row in self.models}:
                        self.model = request["model"]
                        self._emit("model.selected", model=self.model)
                    else:
                        self._emit("error", message="Selecciona un modelo disponible en tu cuenta")
                except (OSError, ValueError, KeyError, TypeError):
                    self._emit("error", message="No se pudo abrir la conversación guardada")
                return
            if action in ("auth.login", "auth.refresh", "auth.logout"):
                if self.busy or self.login_pending or self.account_pending:
                    self._emit("error", message="Ya hay una operación en curso")
                elif action == "auth.login":
                    self.login_pending = True
                    self._login_cancel = threading.Event()
                    cancel = self._login_cancel
                    self._spawn(lambda: self._login(cancel))
                else:
                    self.account_pending = True
                    self._emit("auth.refresh.started")
                    self._spawn(self._logout if action == "auth.logout" else self._refresh_account)
                return
            if action != "chat.send":
                self._emit("error", message="Instrucción desconocida")
                return
            prompt = request.get("prompt")
            if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > MAX_PROMPT_LENGTH:
                self._emit("chat.finished", status="failed", message="Escribe entre 1 y 16000 caracteres")
            elif self.busy or self.login_pending or self.account_pending:
                self._emit("error", message="Espera a que termine la operación actual")
            elif not self.authenticated or not self.models:
                self._emit("chat.finished", status="failed", message="Conecta ChatGPT y actualiza los modelos para conversar")
            else:
                try:
                    if self.conversation is None:
                        self.conversation = self.history.create(prompt.strip())
                    snapshot = copy.deepcopy(self.conversation)
                    turn_id = uuid.uuid4().hex
                    self.conversation["messages"].append({"id": turn_id, "role": "user",
                                                         "text": prompt.strip(), "status": "completed",
                                                         "turn_id": turn_id})
                    messages = [{"role": row["role"], "content": row["text"]}
                                for row in self.conversation["messages"] if row["text"]]
                    turn_performance = TurnPerformance(turn_id, self.model, received)
                    turn_performance.input_characters = sum(len(row["content"]) for row in messages)
                    turn_performance.context_messages = len(messages)
                    self.conversation.setdefault("performance", []).append(turn_performance.snapshot())
                    self.conversation["model"] = self.model
                    self.history.save(self.conversation)
                except OSError:
                    if "snapshot" in locals():
                        self.conversation = snapshot
                    self._emit("chat.finished", status="failed", message="No se pudo guardar el mensaje")
                    return
                self._last_saved = time.monotonic()
                self._emit("chat.saved", chat_id=self.conversation["chat_id"], title=self.conversation["title"])
                self._publish_history()
                self.busy = True
                self._generation += 1
                generation, model = self._generation, self.model
                self._performance = turn_performance
                self._last_metrics_emitted = 0.0
                self._stream = StreamControl(lambda phase: self._mark_phase(phase, generation))
                control = self._stream
                self._emit("chat.busy", turn_id=turn_id)
                self._emit("chat.thread", thread_id=self.conversation["chat_id"], model=model)
                self._performance.mark("prepared")
                self._update_performance(force=True)
                self._spawn(lambda: self._start_turn(messages, model, control, generation))

    def serve(self, source: TextIO) -> None:
        try:
            self._emit("history.ready", directory=str(self.history.root))
            self._publish_history()
            self._emit("backend.ready", provider="chatgpt", app_version=get_version())
            with self._lock:
                try:
                    self._publish_account()
                except (ServiceError, OSError):
                    self.authenticated = False
                    self._emit("auth.state", authenticated=False, method="none", email="", plan="", plan_enabled=False)
                    self._emit("error", message="No se pudo leer la sesión guardada. El historial sigue disponible.")
                if self.authenticated:
                    self.account_pending = True
                    self._emit("auth.refresh.started")
                    self._spawn(self._refresh_account)
                else:
                    self._emit("models.list", models=[], selected="")
                    self._emit("auth.refresh.finished")
            while line := source.readline(MAX_REQUEST_BYTES + 1):
                if len(line.encode("utf-8")) > MAX_REQUEST_BYTES:
                    while not line.endswith("\n"):
                        line = source.readline(MAX_REQUEST_BYTES + 1)
                        if not line:
                            break
                    self._emit("error", message="Instrucción demasiado grande")
                    continue
                try:
                    request = json.loads(line)
                except json.JSONDecodeError:
                    self._emit("error", message="JSON inválido")
                    continue
                self.handle(request)
        except (OSError, ServiceError):
            self._emit("backend.disconnected", message="No se pudo leer la sesión o comunicarse con la interfaz")
        finally:
            self._login_cancel.set()
            self._stream.cancel()
            with self._lock:
                if self.busy:
                    self._finish("interrupted")
                self._closing.set()
