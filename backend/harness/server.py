"""Puente entre el chat Qt y el App Server oficial de Codex.

Conserva el thread durante la aplicación. Las llamadas RPC ocurren fuera del
lector de instrucciones, permitiendo cancelar aun al preparar una respuesta.
"""

import json
import threading
import uuid
from pathlib import Path
from typing import Any, TextIO
from urllib.parse import urlparse

from .codex import CodexClient, CodexError
from .events import EventEmitter
from .history import HistoryStore
from .version import get_version

MAX_REQUEST_BYTES = 65536
MAX_PROMPT_LENGTH = 16000
CHAT_INSTRUCTIONS = (
    "You are the conversational assistant in Agent Shell. Respond in the user's language. "
    "This application currently supports chat only. Do not use tools, inspect the filesystem, "
    "execute commands, create files, or delegate to agents. When asked for code, include it "
    "in your reply."
)


class HarnessServer:
    """Administra cuenta, conversación y turno; Codex conserva la autenticación."""

    def __init__(self, chat_root: Path, output: TextIO, command: list[str],
                 history_root: Path | None = None) -> None:
        self.root = chat_root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.events = EventEmitter(output)
        self.history = HistoryStore(history_root if history_root is not None else self.root / "history")
        self.conversation: dict | None = None
        self._resume_thread_id: str | None = None
        self.client = CodexClient(command, self._on_message, self._disconnected)
        self._lock = threading.RLock()
        self._closing = threading.Event()
        self.ready = False
        self.authenticated = False
        self.busy = False
        self.login_pending = False
        self.login_id: str | None = None
        self.thread_id: str | None = None
        self.turn_id: str | None = None
        self._cancel_pending = False
        self._login_cancel_pending = False
        self._generation = 0

    def _spawn(self, operation) -> None:
        """Mantiene libres stdin y el lector RPC; comunica fallas a la interfaz."""
        def guarded():
            try:
                operation()
            except (CodexError, OSError, KeyError, TypeError, ValueError) as error:
                if not self._closing.is_set():
                    self.events.emit("error", message=str(error))
        threading.Thread(target=guarded, daemon=True).start()

    def _publish_history(self) -> None:
        self.events.emit("history.list", chats=self.history.list())
        if self.history.invalid_files:
            self.events.emit("history.notice", message="Hay archivos de historial dañados o incompatibles; se conservaron.")

    def _save_message(self, item_id: str, text: str, append: bool, status: str) -> None:
        """Persiste tanto fragmentos como texto final, sin duplicar el mismo mensaje."""
        if self.conversation is None:
            return
        messages = self.conversation["messages"]
        message = next((entry for entry in messages if entry["id"] == item_id), None)
        if message is None:
            messages.append({"id": item_id, "role": "assistant", "text": text, "status": status})
        else:
            message["text"] = message["text"] + text if append else text
            message["status"] = status
        try:
            self.history.save(self.conversation)
        except (OSError, ValueError):
            self.events.emit("history.notice", message="No se pudo guardar un fragmento del chat; el texto sigue visible.")

    def _open_chat(self, chat_id: str) -> None:
        record = self.history.load(chat_id)  # Una falla conserva la conversación actual.
        self.conversation = record
        self.thread_id = None
        self.turn_id = None
        self._resume_thread_id = record.get("thread_id")
        self.events.emit("chat.loaded", chat=record)

    def _thread_options(self) -> dict:
        return {
            "cwd": str(self.root), "sandbox": "read-only", "approvalPolicy": "never",
            "modelProvider": "openai", "developerInstructions": CHAT_INSTRUCTIONS,
            "config": {
                "features": {"shell_tool": False, "unified_exec": False, "apps": False},
                "web_search": "disabled",
            },
        }

    def _read_account(self) -> None:
        account = self.client.request("account/read", {"refreshToken": False}).get("account") or {}
        with self._lock:
            # Una API key configurada en CLI no equivale a la cuenta solicitada.
            self.authenticated = account.get("type") == "chatgpt"
            self.events.emit(
                "auth.state", authenticated=self.authenticated,
                method=account.get("type", "none"), email=account.get("email") or "",
                plan=account.get("planType") or "",
            )

    def _login(self) -> None:
        try:
            result = self.client.request("account/login/start", {"type": "chatgpt"})
            url = result["authUrl"]
            parsed = urlparse(url)
            if parsed.scheme != "https" or parsed.hostname != "auth.openai.com":
                raise CodexError("Codex devolvió una dirección de autenticación inesperada")
            with self._lock:
                if not self.login_pending:
                    return
                self.login_id = result["loginId"]
                cancel = self._login_cancel_pending
            if cancel:
                self._cancel_login()
            else:
                self.events.emit("auth.login.started", url=url)
        except Exception:
            with self._lock:
                self.login_pending = False
            self.events.emit("auth.login.finished", success=False, message="No se pudo iniciar la sesión")
            raise

    def _cancel_login(self) -> None:
        with self._lock:
            login_id = self.login_id
        if login_id:
            self.client.request("account/login/cancel", {"loginId": login_id})

    def _start_turn(self, prompt: str, generation: int | None = None) -> None:
        try:
            with self._lock:
                if generation is None:
                    generation = self._generation
                thread_id = self.thread_id
            if not thread_id:
                if self._resume_thread_id:
                    result = self.client.request("thread/resume", {
                        **self._thread_options(), "threadId": self._resume_thread_id,
                    })
                else:
                    result = self.client.request("thread/start", {
                        **self._thread_options(), "ephemeral": False,
                    })
                with self._lock:
                    self.thread_id = thread_id = result["thread"]["id"]
                    self._resume_thread_id = None
                    if self.conversation is not None:
                        self.conversation["thread_id"] = thread_id
                        self.conversation["model"] = result.get("model", "")
                        self.history.save(self.conversation)
                self.events.emit("chat.thread", thread_id=thread_id, model=result.get("model", ""))
            with self._lock:
                if self._cancel_pending:
                    self._finish("interrupted")
                    return
            result = self.client.request("turn/start", {
                "threadId": thread_id,
                "input": [{"type": "text", "text": prompt, "text_elements": []}],
            })
            with self._lock:
                # completed puede llegar antes que la respuesta al RPC turn/start.
                if not self.busy or generation != self._generation:
                    return
                self.turn_id = result["turn"]["id"]
                cancel = self._cancel_pending
            if cancel:
                self._interrupt()
        except Exception:
            with self._lock:
                if generation == self._generation:
                    self._finish("failed", "No se pudo iniciar la respuesta de Codex")
            raise

    def _interrupt(self) -> None:
        with self._lock:
            thread_id, turn_id = self.thread_id, self.turn_id
        if thread_id and turn_id:
            self.client.request("turn/interrupt", {"threadId": thread_id, "turnId": turn_id})

    def _finish(self, status: str, message: str = "") -> None:
        with self._lock:
            self.busy = False
            self.turn_id = None
            self._cancel_pending = False
            if self.conversation is not None:
                for entry in self.conversation["messages"]:
                    if entry["status"] == "streaming":
                        entry["status"] = status
                try:
                    self.history.save(self.conversation)
                except OSError:
                    self.events.emit("history.notice", message="No se pudo guardar el último estado del chat")
            self.events.emit("chat.finished", status=status, message=message)
            if self.conversation is not None:
                self._publish_history()

    def _disconnected(self) -> None:
        with self._lock:
            if self.busy:
                self._finish("interrupted", "Se perdió la conexión con Codex")
            self.ready = False
            self.authenticated = False
            self.busy = False
            self.login_pending = False
        self.events.emit("backend.disconnected", message="Codex se desconectó. Reinicia la aplicación.")

    def _on_message(self, message: dict) -> None:
        """Normaliza datos del chat; no reenvía tokens ni eventos de razonamiento."""
        if self._closing.is_set():
            return
        method, params = message.get("method"), message.get("params") or {}
        if "id" in message:
            # Este chat no tiene pantallas de herramientas; no dejar solicitudes
            # del servidor pendientes ni conceder acceso de forma implícita.
            if method in ("item/commandExecution/requestApproval", "item/fileChange/requestApproval"):
                self.client.reply(message["id"], {"decision": "decline"})
            elif method == "item/permissions/requestApproval":
                self.client.reply(message["id"], {"permissions": {}, "scope": "turn"})
            else:
                self.client.reply(message["id"], error={
                    "code": -32601, "message": "Agent Shell sólo admite conversación en esta versión",
                })
            return
        if method == "account/login/completed":
            with self._lock:
                self.login_pending = False
                self.login_id = None
            self.events.emit(
                "auth.login.finished", success=bool(params.get("success")),
                message=params.get("error") or "",
            )
            if params.get("success"):
                self._spawn(self._read_account)
            return
        if method == "account/updated":
            self._spawn(self._read_account)
            return
        with self._lock:
            if params.get("threadId") != self.thread_id or not self.busy:
                return
            if method == "turn/started":
                self.turn_id = params["turn"]["id"]
                if self._cancel_pending:
                    self._spawn(self._interrupt)
            elif method == "item/agentMessage/delta":
                self._save_message(params["itemId"], params["delta"], True, "streaming")
                self.events.emit("chat.delta", item_id=params["itemId"], text=params["delta"])
            elif method == "item/completed" and params.get("item", {}).get("type") == "agentMessage":
                item = params["item"]
                self._save_message(item["id"], item.get("text", ""), False, "completed")
                self.events.emit("chat.message", item_id=item["id"], text=item.get("text", ""))
            elif method == "turn/completed":
                turn = params["turn"]
                self._finish(turn["status"], (turn.get("error") or {}).get("message", ""))
            elif method == "error":
                self.events.emit("chat.notice", message=(params.get("error") or {}).get("message", "Error de Codex"))

    def handle(self, request: Any) -> None:
        """Valida instrucciones de Qt antes de llamar al proveedor."""
        if not isinstance(request, dict):
            self.events.emit("error", message="La instrucción debe ser un objeto JSON")
            return
        action = request.get("type")
        with self._lock:
            # El historial local se puede leer incluso cuando Codex está desconectado.
            if action in ("history.list", "chat.open", "chat.new"):
                if self.busy or self.login_pending:
                    self.events.emit("error", message="Detén la operación actual antes de abrir otro chat")
                else:
                    try:
                        if action == "history.list":
                            self._publish_history()
                        elif action == "chat.open":
                            self._open_chat(request.get("chat_id"))
                        else:
                            self.thread_id = None
                            self.turn_id = None
                            self.conversation = None
                            self._resume_thread_id = None
                            self.events.emit("chat.reset")
                    except (OSError, ValueError, KeyError, TypeError):
                        self.events.emit("error", message="No se pudo abrir la conversación guardada")
                return
            if not self.ready:
                self.events.emit("error", message="Codex todavía no está conectado")
                return
            if action == "chat.send":
                prompt = request.get("prompt")
                if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > MAX_PROMPT_LENGTH:
                    self.events.emit("error", message="Escribe entre 1 y 16000 caracteres")
                elif not self.authenticated:
                    self.events.emit("error", message="Inicia sesión con ChatGPT para conversar")
                elif self.busy or self.login_pending:
                    self.events.emit("error", message="Espera a que termine la operación actual")
                else:
                    try:
                        if self.conversation is None:
                            self.conversation = self.history.create(prompt.strip())
                        self.conversation["messages"].append({
                            "id": uuid.uuid4().hex, "role": "user", "text": prompt.strip(), "status": "completed",
                        })
                        self.history.save(self.conversation)
                    except OSError:
                        self.events.emit("chat.finished", status="failed", message="No se pudo guardar el mensaje")
                        return
                    self.events.emit("chat.saved", chat_id=self.conversation["chat_id"], title=self.conversation["title"])
                    self._publish_history()
                    self.busy = True
                    self.turn_id = None
                    self._cancel_pending = False
                    self._generation += 1
                    generation = self._generation
                    self.events.emit("chat.busy")
                    self._spawn(lambda: self._start_turn(prompt.strip(), generation))
            elif action == "chat.cancel":
                if self.busy:
                    self._cancel_pending = True
                    self._spawn(self._interrupt)
            elif action == "auth.login":
                if self.busy or self.login_pending:
                    self.events.emit("error", message="Ya hay una operación en curso")
                else:
                    self.login_pending = True
                    self._login_cancel_pending = False
                    self._spawn(self._login)
            elif action == "auth.refresh":
                self._spawn(self._read_account)
            elif action == "auth.cancel":
                self._login_cancel_pending = True
                self._spawn(self._cancel_login)
            else:
                self.events.emit("error", message="Instrucción desconocida")

    def serve(self, source: TextIO) -> None:
        """Hace handshake y lee instrucciones; cerrar stdin libera App Server."""
        try:
            self.events.emit("history.ready", directory=str(self.history.root))
            self._publish_history()
            try:
                self.client.start()
                self.client.request("initialize", {"clientInfo": {
                    "name": "agent_shell", "title": "Agent Shell", "version": get_version(),
                }})
                self.client.notify("initialized")
                with self._lock:
                    self.ready = True
                self.events.emit("backend.ready", provider="codex", app_version=get_version())
                self._read_account()
            except (CodexError, OSError) as error:
                self.ready = False
                self.authenticated = False
                self.events.emit("backend.disconnected", message=str(error))
            while line := source.readline(MAX_REQUEST_BYTES + 1):
                if len(line.encode("utf-8")) > MAX_REQUEST_BYTES:
                    while not line.endswith("\n"):
                        line = source.readline(MAX_REQUEST_BYTES + 1)
                        if not line:
                            break
                    self.events.emit("error", message="Instrucción demasiado grande")
                    continue
                try:
                    request = json.loads(line)
                except json.JSONDecodeError:
                    self.events.emit("error", message="JSON inválido")
                    continue
                self.handle(request)
        except (CodexError, OSError) as error:
            self.events.emit("backend.disconnected", message=str(error))
        finally:
            self._closing.set()
            self.client.close()
            with self._lock:
                if self.busy and self.conversation is not None:
                    for message in self.conversation["messages"]:
                        if message["status"] == "streaming":
                            message["status"] = "interrupted"
                    try:
                        self.history.save(self.conversation)
                    except OSError:
                        pass  # Los deltas anteriores ya están en el JSON atómico.
