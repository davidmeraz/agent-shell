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

from ..core.http import Cancelled
from .output import BoundedOutput

MAX_COMMAND_LENGTH = 8000
MAX_OUTPUT_LENGTH = 16000
MAX_STREAM_BYTES = 2 * 1024 * 1024
MAX_BINARY_NULS = 64
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
                   "Each call starts a fresh shell: cd, variables and activated environments do not persist. "
                   "Use explicit paths or combine dependent commands with &&. "
                   "Output is bounded and may contain only its beginning and end; prefer targeted reads. "
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
                 max_output: int = MAX_OUTPUT_LENGTH,
                 max_stream_bytes: int = MAX_STREAM_BYTES) -> None:
        self.workspace = resolve_workspace(workspace)
        self.timeout = timeout
        self.max_output = max_output
        self.max_stream_bytes = max_stream_bytes

    def execute(self, command: str, control: ShellControl, on_output=lambda output: None,
                on_started=lambda: None) -> dict:
        started = time.monotonic()
        captured = BoundedOutput(self.max_output)
        process = control.start(command, self.workspace)
        status = "completed"
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        last_emitted = started
        ended_at = None
        stream_bytes = 0
        nul_bytes = 0
        flood_note = ""
        try:
            on_started()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                # EOF sólo describe las tuberías: un proceso puede cerrarlas y seguir trabajando.
                while selector.get_map() or process.poll() is None:
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
                        stream_bytes += len(chunk)
                        if b"\x00" in chunk:
                            nul_bytes += chunk.count(b"\x00")
                            chunk = chunk.replace(b"\x00", b"")
                        text = decoder.decode(chunk)
                        captured.append(text)
                        if nul_bytes >= MAX_BINARY_NULS:
                            status = "error"
                            flood_note = (
                                "Comando detenido por producir salida binaria (bytes NUL) en la terminal. "
                                "Usa filtros de texto o herramientas específicas."
                            )
                            control.kill()
                            break
                        if self.max_stream_bytes and stream_bytes > self.max_stream_bytes:
                            status = "error"
                            limit_kb = max(1, self.max_stream_bytes // 1024)
                            flood_note = (
                                f"Comando detenido por inundación de salida (>{limit_kb} KiB). "
                                "Filtra o acota la orden para evitar bucles de impresión."
                            )
                            control.kill()
                            break
                    if flood_note:
                        break
                    if now - last_emitted >= 0.25:
                        # También actúa como pulso para comprobar inicios de Work sin salida.
                        on_output(captured.text)
                        last_emitted = now
            captured.append(decoder.decode(b"", final=True))
        finally:
            control.kill()
            process.wait(timeout=2)
            process.stdout.close()
            control.release()
        output = captured.text
        if flood_note:
            suffix = f"\n[… {flood_note} …]"
            if self.max_output and len(output) + len(suffix) > self.max_output:
                output = output[:max(0, self.max_output - len(suffix))] + suffix[:self.max_output]
            else:
                output = output + suffix
        on_output(output)
        if control.cancelled.is_set():
            status = "interrupted"
        if status == "completed" and process.returncode != 0:
            status = "error"
        payload = {
            "status": status,
            "output": output,
            "exit_code": process.returncode,
            "truncated": bool(captured.truncated or flood_note),
            "duration_ms": round((time.monotonic() - started) * 1000, 3),
        }
        if captured.diagnostics:
            payload["diagnostics"] = captured.diagnostics
        if flood_note:
            payload["flood_stopped"] = True
            payload["output_note"] = flood_note
        return payload
