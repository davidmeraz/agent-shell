"""Consulta de cuotas mediante la sesión administrada por Codex, sin inferencia."""

import json
import math
import os
import selectors
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone

from .version import get_version


class UsageError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def _number(value):
    if value is None:
        return None
    if (isinstance(value, bool) or not isinstance(value, (int, float))
            or not math.isfinite(value) or value < 0):
        raise UsageError("invalid_data", "Codex devolvió datos de uso inválidos.")
    return value


def _text(value, maximum=160):
    return value[:maximum] if isinstance(value, str) else ""


def _window(value):
    if value is None:
        return None
    if not isinstance(value, dict):
        raise UsageError("invalid_data", "Codex devolvió un límite inválido.")
    return {"used_percent": _number(value.get("usedPercent")),
            "window_minutes": _number(value.get("windowDurationMins")),
            "resets_at": _number(value.get("resetsAt"))}


def normalize_limits(result):
    if not isinstance(result, dict):
        raise UsageError("invalid_data", "Codex devolvió datos de uso inválidos.")
    buckets = result.get("rateLimitsByLimitId")
    if buckets is None:
        legacy = result.get("rateLimits")
        buckets = {"codex": legacy} if legacy else {}
    if not isinstance(buckets, dict) or len(buckets) > 64:
        raise UsageError("invalid_data", "Codex devolvió límites inválidos.")
    limits = []
    for key, bucket in buckets.items():
        if not isinstance(bucket, dict):
            raise UsageError("invalid_data", "Codex devolvió un límite inválido.")
        credits = bucket.get("credits")
        # No convertir saldos desconocidos en cero ni estimar mensajes disponibles.
        credit_view = None
        if isinstance(credits, dict):
            credit_view = {"unlimited": credits.get("unlimited") is True,
                           "has_credits": credits.get("hasCredits") is True,
                           "balance": _text(credits.get("balance"), 64) or None}
        limits.append({"id": _text(bucket.get("limitId") or key),
                       "name": _text(bucket.get("limitName")) or _text(key),
                       "primary": _window(bucket.get("primary")),
                       "secondary": _window(bucket.get("secondary")),
                       "credits": credit_view})
    return limits


class CodexUsageReader:
    """Sidecar transitorio y acotado. Nunca lee ni copia credenciales de Codex."""

    def __init__(self, command=None, timeout=20):
        self.command = command
        self.timeout = timeout
        self._lock = threading.Lock()
        self._process = None
        self._closed = False

    def close(self):
        with self._lock:
            self._closed = True
            process = self._process
        if process is not None:
            self._stop(process)

    @staticmethod
    def _stop(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)

    def read(self, expected_email=""):
        executable = os.environ.get("AGENT_SHELL_CODEX_BINARY") or shutil.which("codex")
        command = self.command or ([executable, "app-server", "--listen", "stdio://"] if executable else None)
        if not command:
            raise UsageError("codex_missing", "Instala Codex e inicia sesión con codex login para consultar tu uso.")
        process = None
        selector = selectors.DefaultSelector()
        buffer = bytearray()
        request_id = 0
        received = 0
        deadline = time.monotonic() + self.timeout

        def rpc(method, params, budget=None):
            nonlocal request_id, buffer, received
            request_id += 1
            wanted = request_id
            process.stdin.write((json.dumps({"id": wanted, "method": method, "params": params}) + "\n").encode())
            end = min(deadline, time.monotonic() + budget) if budget else deadline
            while time.monotonic() < end:
                while b"\n" in buffer:
                    line, _, tail = buffer.partition(b"\n")
                    buffer = bytearray(tail)
                    message = json.loads(line)
                    if not isinstance(message, dict):
                        raise ValueError("RPC inválido")
                    if message.get("id") == wanted:
                        if "error" in message:
                            # Los mensajes remotos pueden contener datos privados; no se propagan.
                            raise UsageError("rpc_error", "Codex no pudo consultar el uso. Comprueba su sesión y vuelve a intentarlo.")
                        return message.get("result")
                if selector.select(max(0, end - time.monotonic())):
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        raise UsageError("disconnected", "Codex se desconectó al consultar el uso.")
                    buffer.extend(chunk)
                    received += len(chunk)
                    if len(buffer) > 2 * 1024 * 1024 or received > 8 * 1024 * 1024:
                        raise ValueError("Respuesta demasiado grande")
            raise UsageError("timeout", "Codex tardó demasiado en responder. Vuelve a actualizar el uso.")

        def account_read(verify_expected=True):
            result = rpc("account/read", {"refreshToken": False})
            account = result.get("account") if isinstance(result, dict) else None
            if not isinstance(account, dict) or account.get("type") != "chatgpt":
                raise UsageError("login_required", "Inicia sesión en Codex con tu cuenta de ChatGPT: codex login.")
            email = _text(account.get("email"), 254)
            if not email:
                raise UsageError("invalid_data", "Codex no identificó la cuenta consultada.")
            if verify_expected and expected_email and email.casefold() != expected_email.casefold():
                raise UsageError("account_mismatch", "Codex está conectado a otra cuenta. Usa codex login con la cuenta activa de Agent Shell.")
            return {"email": email, "plan": _text(account.get("planType"), 32)}

        try:
            # Evita configuración específica del proyecto; no se crean hilos ni turnos.
            process = subprocess.Popen(command, cwd=tempfile.gettempdir(), stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0)
            with self._lock:
                if self._closed:
                    raise UsageError("disconnected", "Se cerró la consulta de uso.")
                self._process = process
            selector.register(process.stdout, selectors.EVENT_READ)
            rpc("initialize", {"clientInfo": {"name": "agent_shell_usage", "title": "Agent Shell Usage", "version": get_version()}})
            process.stdin.write(b'{"method":"initialized"}\n')
            account = account_read()
            limits = normalize_limits(rpc("account/rateLimits/read", {}))
            summary = None
            try:
                usage = rpc("account/usage/read", {}, budget=3)
                value = usage.get("summary") if isinstance(usage, dict) else None
                if isinstance(value, dict):
                    summary = {"lifetime_tokens": _number(value.get("lifetimeTokens"))}
            except UsageError:
                # El resumen es opcional en versiones anteriores; las cuotas siguen siendo válidas.
                pass
            if account_read(verify_expected=False) != account:
                raise UsageError("account_changed", "La sesión de Codex cambió durante la consulta. Vuelve a actualizar.")
            return {"source": "codex", "account": account, "limits": limits, "summary": summary,
                    "checked_at": datetime.now(timezone.utc).isoformat()}
        except UsageError:
            raise
        except (OSError, ValueError, TypeError, OverflowError):
            raise UsageError("unavailable", "No se pudo consultar Codex. Comprueba que esté instalado y conectado.") from None
        finally:
            selector.close()
            if process is not None:
                self._stop(process)
                for stream in (process.stdin, process.stdout):
                    if stream is not None:
                        stream.close()
            with self._lock:
                self._process = None
