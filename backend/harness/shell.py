"""Herramienta shell local: argumentos estrictos, salida acotada y cancelación POSIX."""

import codecs
import json
import os
import selectors
import signal
import subprocess
import threading
import time
from pathlib import Path

from .http import Cancelled

MAX_COMMAND_LENGTH = 8000
MAX_OUTPUT_LENGTH = 16000
DEFAULT_TIMEOUT = 120
# Conservar la sesión de escritorio sin heredar variables privadas del backend.
SHELL_ENVIRONMENT = (
    "PATH", "LANG", "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "LC_TIME", "TZ",
    "HOME", "USER", "LOGNAME", "SHELL",
    "WAYLAND_DISPLAY", "DISPLAY", "XDG_RUNTIME_DIR", "XAUTHORITY",
    "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE", "XDG_SESSION_ID",
    "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION",
    "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME",
    "XDG_CONFIG_DIRS", "XDG_DATA_DIRS",
    "QT_QPA_PLATFORM", "QT_QPA_PLATFORMTHEME", "QT_STYLE_OVERRIDE", "QT_IM_MODULE",
    "GTK_IM_MODULE", "XMODIFIERS", "GDK_BACKEND",
    "HYPRLAND_INSTANCE_SIGNATURE", "SWAYSOCK",
)
SHELL_TOOL = {
    "type": "function", "name": "shell", "strict": True,
    "description": "Run a non-interactive POSIX shell command in the application's selected working directory. "
                   "Commands execute automatically; all commands are permitted without user approval. "
                   "Return stdout/stderr, exit code and status. "
                   "The UI displays the output in a terminal card; acknowledge the outcome briefly without repeating the output. "
                   "Do not request background jobs or interactive input.",
    "parameters": {"type": "object", "properties": {"command": {"type": "string"}},
                   "required": ["command"], "additionalProperties": False},
}


def parse_command(arguments: str) -> str:
    if not isinstance(arguments, str) or len(arguments) > MAX_COMMAND_LENGTH * 6 + 100:
        raise ValueError("Argumentos de shell inválidos")
    value = json.loads(arguments)
    if (not isinstance(value, dict) or set(value) != {"command"}
            or not isinstance(value["command"], str) or not value["command"].strip()
            or len(value["command"]) > MAX_COMMAND_LENGTH or "\0" in value["command"]):
        raise ValueError("Shell requiere únicamente un comando de entre 1 y 8000 caracteres")
    return value["command"]


def resolve_workspace(value: str | Path) -> Path:
    if not isinstance(value, (str, Path)) or not str(value).strip():
        raise ValueError("Selecciona un directorio de trabajo")
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_dir():
        raise ValueError("El directorio de trabajo no existe")
    return path


def command_environment() -> dict[str, str]:
    """Hereda sólo configuración conocida; no inventa pantallas ni permisos."""
    environment = {name: os.environ[name] for name in SHELL_ENVIRONMENT if name in os.environ}
    environment.setdefault("PATH", os.defpath)
    environment.setdefault("LANG", "C.UTF-8")
    environment["TERM"] = "dumb"
    return environment


class ShellControl:
    """Evita crear el proceso si el turno ya se canceló."""

    def __init__(self, cancelled: threading.Event) -> None:
        self.cancelled = cancelled
        self._lock = threading.Lock()
        self._process = None

    def start(self, command: str, workspace: Path):
        with self._lock:
            if self.cancelled.is_set():
                raise Cancelled()
            self._process = subprocess.Popen(
                ["/bin/sh", "-c", command], cwd=workspace,
                env=command_environment(),
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            return self._process

    def kill(self) -> None:
        with self._lock:
            if self._process is not None:
                try:
                    os.killpg(self._process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def cancel(self) -> None:
        self.cancelled.set()
        self.kill()

    def release(self) -> None:
        with self._lock:
            self._process = None


class ShellExecutor:
    def __init__(self, workspace: Path, timeout: float | None = DEFAULT_TIMEOUT,
                 max_output: int = MAX_OUTPUT_LENGTH) -> None:
        self.workspace = resolve_workspace(workspace)
        self.timeout = timeout
        self.max_output = max_output

    def execute(self, command: str, control: ShellControl, on_output=lambda output: None,
                on_started=lambda: None) -> dict:
        started = time.monotonic()
        process = control.start(command, self.workspace)
        output, truncated, status = "", False, "completed"
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        last_emitted = started
        ended_at = None
        try:
            on_started()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while selector.get_map():
                    now = time.monotonic()
                    if control.cancelled.is_set():
                        status = "interrupted"
                        control.kill()
                        break
                    if self.timeout is not None and now - started >= self.timeout:
                        status = "timeout"
                        control.kill()
                        break
                    if process.poll() is not None:
                        if ended_at is None:
                            ended_at = now
                            # No dejamos trabajos de fondo después de acabar la orden.
                            control.kill()
                        if now - ended_at > 0.5:
                            break
                    for key, _ in selector.select(timeout=0.05):
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            selector.unregister(key.fileobj)
                            continue
                        text = decoder.decode(chunk)
                        available = max(0, self.max_output - len(output))
                        truncated = truncated or len(text) > available
                        output += text[:available]
                    if now - last_emitted >= 0.25:
                        on_output(output)
                        last_emitted = now
            tail = decoder.decode(b"", final=True)
            available = max(0, self.max_output - len(output))
            truncated = truncated or len(tail) > available
            output += tail[:available]
        finally:
            control.kill()
            process.wait(timeout=2)
            process.stdout.close()
            control.release()
        on_output(output)
        if control.cancelled.is_set():
            status = "interrupted"
        if status == "completed" and process.returncode != 0:
            status = "error"
        return {"status": status, "output": output, "exit_code": process.returncode,
                "truncated": truncated, "duration_ms": round((time.monotonic() - started) * 1000, 3)}
