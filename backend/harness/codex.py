"""Transporte oficial de Codex App Server sobre stdin/stdout.

Codex administra sus credenciales. No se abre auth.json ni se intercambian tokens.
El lector separa respuestas RPC y notificaciones para permitir cancelación.
"""

import json
import subprocess
import threading
from collections.abc import Callable
from typing import Any


class CodexError(Exception):
    """Falla del transporte o error comunicado por Codex."""


class CodexClient:
    """Multiplexa solicitudes concurrentes y entrega eventos desde un hilo lector."""

    def __init__(self, command: list[str], on_message: Callable[[dict], None],
                 on_disconnect: Callable[[], None]) -> None:
        self.command = command
        self.on_message = on_message
        self.on_disconnect = on_disconnect
        self._write_lock = threading.Lock()
        self._state_lock = threading.Lock()
        self._pending: dict[int, dict] = {}
        self._sequence = 0
        self._closing = threading.Event()
        self._process: subprocess.Popen | None = None
        self._reader: threading.Thread | None = None
        self._stderr_reader: threading.Thread | None = None

    def start(self) -> None:
        """Inicia el ejecutable configurado sin pasar por un shell."""
        try:
            self._process = subprocess.Popen(
                self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1,
            )
        except OSError as error:
            raise CodexError("No se pudo iniciar Codex CLI. Comprueba su instalación y PATH.") from error
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._stderr_reader = threading.Thread(target=self._drain_stderr, daemon=True)
        self._reader.start()
        self._stderr_reader.start()

    def _write(self, message: dict) -> None:
        with self._write_lock:
            if not self._process or self._process.poll() is not None:
                raise CodexError("Codex está desconectado")
            try:
                self._process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
                self._process.stdin.flush()
            except (OSError, ValueError) as error:
                raise CodexError("Se cerró la conexión con Codex") from error

    def notify(self, method: str, params: dict | None = None) -> None:
        self._write({"method": method, "params": params or {}})

    def reply(self, request_id: Any, result: dict | None = None, error: dict | None = None) -> None:
        """Responde al servidor sin conceder permisos implícitos."""
        self._write({"id": request_id, **({"error": error} if error else {"result": result or {}})})

    def request(self, method: str, params: dict | None = None, timeout: float = 30) -> dict:
        """Espera una respuesta; no llamar desde el propio hilo lector."""
        waiter = {"ready": threading.Event(), "response": None}
        with self._state_lock:
            self._sequence += 1
            request_id = self._sequence
            self._pending[request_id] = waiter
        try:
            self._write({"id": request_id, "method": method, "params": params or {}})
            if not waiter["ready"].wait(timeout):
                raise CodexError(f"Codex no respondió a {method}; vuelve a intentarlo")
            response = waiter["response"]
            if "error" in response:
                raise CodexError(response["error"].get("message", "Codex rechazó la solicitud"))
            return response.get("result", {})
        finally:
            with self._state_lock:
                self._pending.pop(request_id, None)

    def _read(self) -> None:
        try:
            for line in self._process.stdout:
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError("Mensaje RPC inválido")
                if "id" in message and "method" not in message:
                    with self._state_lock:
                        waiter = self._pending.get(message["id"])
                        if waiter:
                            waiter["response"] = message
                            waiter["ready"].set()
                else:
                    self.on_message(message)
        except (OSError, ValueError, KeyError, TypeError, CodexError):
            pass
        finally:
            with self._state_lock:
                for waiter in self._pending.values():
                    waiter["response"] = {"error": {"message": "Codex se desconectó"}}
                    waiter["ready"].set()
            if not self._closing.is_set():
                self.on_disconnect()

    def _drain_stderr(self) -> None:
        # Evitar llenar el pipe; no copiar diagnósticos de cuenta al registro Qt.
        for _ in self._process.stderr:
            pass

    def close(self) -> None:
        """Libera el hijo y sus descriptores incluso si dejó de responder."""
        self._closing.set()
        process = self._process
        if not process:
            return
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for thread in (self._reader, self._stderr_reader):
            if thread and thread is not threading.current_thread():
                thread.join(timeout=3)
        for stream in (process.stdin, process.stdout, process.stderr):
            stream.close()
