"""Cliente oficial para Claude Code CLI (`claude`) en modo headless NDJSON.

Invoca únicamente comandos documentados del binario oficial `claude`:
- `claude auth status --json` / `claude auth login --claudeai` para estado e inicio de sesión.
- `claude -p <prompt> --output-format stream-json --verbose --include-partial-messages
  --disable-slash-commands --permission-mode acceptEdits --permission-prompts none`
  para turnos en streaming con herramientas, esfuerzo (`--effort`) y continuación (`--resume`).
- `claude -p "/usage" --output-format json` para consultar cuotas reales (0 tokens).

Nunca lee, copia ni manipula archivos privados de credenciales de Anthropic.
"""

from __future__ import annotations

import base64
import json
import math
import os
import re
import shutil
import signal
import subprocess
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ..account.codex_usage import UsageError
from ..core.http import Cancelled, ServiceError, StreamControl

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
DATA_IMAGE_RE = re.compile(r"^data:image/(png|jpeg|jpg|webp|gif);base64,([A-Za-z0-9+/=\s]+)$")
MAX_TOOL_OUTPUT_CHARS = 64 * 1024

SESSION_USAGE_RE = re.compile(
    r"Current session:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*[·•|-]\s*resets\s+([^\n]+))?",
    re.IGNORECASE,
)
WEEKLY_USAGE_RE = re.compile(
    r"Current week(?:\s*\([^)]*\))?:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*[·•|-]\s*resets\s+([^\n]+))?",
    re.IGNORECASE,
)
RESET_MONTH_RE = re.compile(
    r"^(?:([A-Za-z]{3,9})\s+(\d{1,2})(?:,\s*(\d{4}))?,?\s*)?"
    r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:\(([^)]+)\))?$",
    re.IGNORECASE,
)
MONTH_MAP = {
    "jan": 1, "january": 1,
    "feb": 2, "february": 2,
    "mar": 3, "march": 3,
    "apr": 4, "april": 4,
    "may": 5,
    "jun": 6, "june": 6,
    "jul": 7, "july": 7,
    "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9,
    "oct": 10, "october": 10,
    "nov": 11, "november": 11,
    "dec": 12, "december": 12,
}

CLAUDE_MODEL_SPECS = (
    {
        "slug": "claude-sonnet",
        "cli_model": "sonnet",
        "display_name": "Claude Sonnet",
        "family": "claude",
        "reasoning_efforts": ["low", "medium", "high", "xhigh", "max"],
        "default_reasoning_effort": "high",
    },
    {
        "slug": "claude-opus",
        "cli_model": "opus",
        "display_name": "Claude Opus",
        "family": "claude",
        "reasoning_efforts": ["low", "medium", "high", "xhigh", "max"],
        "default_reasoning_effort": "high",
    },
    {
        "slug": "claude-haiku",
        "cli_model": "haiku",
        "display_name": "Claude Haiku",
        "family": "claude",
        "reasoning_efforts": ["low", "medium", "high", "xhigh", "max"],
        "default_reasoning_effort": "medium",
    },
    {
        "slug": "claude-fable",
        "cli_model": "fable",
        "display_name": "Claude Fable",
        "family": "claude",
        "reasoning_efforts": ["low", "medium", "high", "xhigh", "max"],
        "default_reasoning_effort": "high",
    },
)
CLI_MODEL_MAP = {row["slug"]: row["cli_model"] for row in CLAUDE_MODEL_SPECS}


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def _extract_json_object(text: str) -> dict | None:
    cleaned = strip_ansi(text)
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        parsed = json.loads(cleaned[start:end + 1])
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def resolve_cli_model(slug: str) -> str:
    cleaned = (slug or "").strip()
    return CLI_MODEL_MAP.get(cleaned, cleaned)


def model_label(model_id: str) -> str:
    """`claude-opus-5-5` → `Claude Opus 5.5`."""
    match = re.match(r"^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:\D|$)", model_id)
    if not match:
        return ""
    version = match[2] + ("." + match[3] if match[3] else "")
    return f"Claude {match[1].capitalize()} {version}"


def isolation_flags() -> list[str]:
    """Omite memoria global, estilo y MCP del usuario; conserva sus permisos, hooks y el CLAUDE.md del proyecto."""
    config_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    settings = {"claudeMdExcludes": [str(config_dir / "CLAUDE.md")], "outputStyle": "default"}
    return ["--strict-mcp-config", "--settings", json.dumps(settings)]


def claude_catalog() -> list[dict]:
    return [
        {k: (list(v) if isinstance(v, list) else v) for k, v in row.items() if k != "cli_model"}
        for row in CLAUDE_MODEL_SPECS
    ]


def parse_claude_auth_status(raw_text: str) -> dict:
    payload = _extract_json_object(raw_text)
    if payload is None:
        return {"authenticated": False, "email": "", "plan": "", "method": "none"}
    logged_in = payload.get("loggedIn") is True
    email = payload.get("email") if isinstance(payload.get("email"), str) else ""
    plan = payload.get("planTier") or payload.get("subscriptionType") or ""
    method = payload.get("authMethod") if isinstance(payload.get("authMethod"), str) else "none"
    return {
        "authenticated": logged_in,
        "email": email[:254],
        "plan": str(plan)[:48] if plan else "",
        "method": method[:48],
    }


def normalize_claude_usage(raw) -> dict | None:
    """Convierte el bloque `usage` de Claude Code al formato de `TurnPerformance`."""
    if not isinstance(raw, dict):
        return None
    base_in = raw.get("input_tokens")
    cache_read = raw.get("cache_read_input_tokens")
    cache_create = raw.get("cache_creation_input_tokens")
    output = raw.get("output_tokens")

    in_parts = [v for v in (base_in, cache_read, cache_create) if type(v) is int and v >= 0]
    total_in = sum(in_parts) if in_parts else None
    result: dict = {}
    if total_in is not None:
        result["input_tokens"] = total_in
    if type(output) is int and output >= 0:
        result["output_tokens"] = output
    if total_in is not None and type(output) is int and output >= 0:
        result["total_tokens"] = total_in + output
    if type(cache_read) is int and cache_read >= 0:
        result["input_tokens_details"] = {"cached_tokens": cache_read}
    details = raw.get("output_tokens_details")
    if isinstance(details, dict):
        thinking = details.get("thinking_tokens")
        if type(thinking) is int and thinking >= 0:
            result["output_tokens_details"] = {"reasoning_tokens": thinking}
    return result or None


def _short_path(path_value: str, workspace: Path | None) -> str:
    cleaned = path_value.strip()
    if not cleaned:
        return ""
    if workspace is not None:
        try:
            rel = Path(cleaned).resolve().relative_to(workspace.resolve())
            return str(rel) or "."
        except (OSError, ValueError):
            pass
    return cleaned


def summarize_claude_tool(tool_name: str, parameters: dict | None, workspace: Path | None = None) -> str:
    """Genera un resumen conciso compatible con los iconos de ToolCallCard.qml."""
    name = (tool_name or "tool").strip()
    lower = name.lower()
    params = parameters if isinstance(parameters, dict) else {}

    if lower in ("bash", "shell", "powershell"):
        cmd = params.get("command") or params.get("cmd")
        if isinstance(cmd, str) and cmd.strip():
            return " ".join(cmd.strip().splitlines())[:400]
        return name

    if lower in ("read", "read_file", "ls"):
        path_val = params.get("file_path") or params.get("path") or ""
        short = _short_path(str(path_val), workspace) if path_val else ""
        return f"read_file {short}".strip() if short else f"read_file ({name})"

    if lower in ("grep", "glob"):
        pattern = params.get("pattern") or params.get("query") or ""
        target = params.get("path") or ""
        parts = ["grep_files"]
        if isinstance(pattern, str) and pattern.strip():
            parts.append(pattern.strip()[:120])
        if isinstance(target, str) and target.strip():
            parts.append(_short_path(target, workspace))
        return " ".join(parts)

    if lower in ("edit", "write", "multiedit", "notebookedit"):
        path_val = params.get("file_path") or params.get("notebook_path") or params.get("path") or ""
        short = _short_path(str(path_val), workspace) if path_val else ""
        return f"apply_patch {short}".strip() if short else f"apply_patch ({name})"

    if lower in ("websearch", "webfetch"):
        target = params.get("query") or params.get("url") or ""
        if isinstance(target, str) and target.strip():
            return f"{name} {target.strip()[:160]}"
        return name

    if lower in ("task", "agent"):
        desc = params.get("description") or params.get("prompt") or ""
        if isinstance(desc, str) and desc.strip():
            return f"agent {desc.strip()[:160]}"
        return "agent"

    for value in params.values():
        if isinstance(value, str) and value.strip():
            return f"{name} {value.strip()[:160]}"
    return name


def format_claude_tool_output(raw_content) -> tuple[str, bool]:
    if raw_content is None:
        return "", False
    if isinstance(raw_content, str):
        text = raw_content
    elif isinstance(raw_content, list):
        parts: list[str] = []
        for item in raw_content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
            else:
                try:
                    parts.append(json.dumps(item, ensure_ascii=False))
                except (TypeError, ValueError):
                    parts.append(str(item))
        text = "\n".join(parts)
    else:
        try:
            text = json.dumps(raw_content, ensure_ascii=False, indent=2)
        except (TypeError, ValueError):
            text = str(raw_content)
    if len(text) > MAX_TOOL_OUTPUT_CHARS:
        return text[:MAX_TOOL_OUTPUT_CHARS] + "\n… [salida recortada]", True
    return text, False


def _friendly_claude_error(raw_message: str, code: str = "") -> str:
    lower = f"{code} {raw_message}".lower()
    if any(token in lower for token in ("authentication_failed", "failed to authenticate", "oauth", "not logged in", "please run /login")):
        return "Sesión de Claude Code no iniciada o expirada. Pulsa 'Conectar Claude' o ejecuta `claude auth login`."
    cleaned = strip_ansi(raw_message or "").strip()
    return cleaned[:280] if cleaned else "Claude Code devolvió un error durante el turno."


def parse_claude_stream_line(line: str) -> list[dict]:
    """Convierte una línea NDJSON de `claude -p --output-format stream-json` en eventos normalizados."""
    stripped = line.strip()
    if not stripped or not stripped.startswith("{"):
        return []
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return []
    if not isinstance(payload, dict):
        return []

    kind = payload.get("type")
    session_id = payload.get("session_id") if isinstance(payload.get("session_id"), str) else ""

    if kind == "system":
        if payload.get("subtype") == "init":
            return [{
                "type": "init",
                "session_id": session_id,
                "model": payload.get("model", "") if isinstance(payload.get("model"), str) else "",
            }]
        return []

    if kind == "stream_event":
        inner = payload.get("event")
        if not isinstance(inner, dict):
            return []
        inner_type = inner.get("type")
        msg_id = payload.get("api_message_id") if isinstance(payload.get("api_message_id"), str) else ""
        if inner_type == "message_start":
            msg = inner.get("message") if isinstance(inner.get("message"), dict) else {}
            resolved_id = msg.get("id") if isinstance(msg.get("id"), str) and msg.get("id") else msg_id
            return [{"type": "message_start", "session_id": session_id, "message_id": resolved_id}]
        if inner_type == "content_block_delta":
            delta = inner.get("delta")
            if isinstance(delta, dict) and delta.get("type") == "text_delta":
                text = delta.get("text", "")
                if isinstance(text, str) and text:
                    return [{
                        "type": "text_delta",
                        "session_id": session_id,
                        "message_id": msg_id,
                        "text": text,
                    }]
        if inner_type == "message_delta":
            usage = normalize_claude_usage(inner.get("usage"))
            if usage:
                return [{"type": "usage", "session_id": session_id, "usage": usage}]
        return []

    if kind == "assistant":
        msg = payload.get("message") if isinstance(payload.get("message"), dict) else {}
        if payload.get("is_api_error_message") or payload.get("error"):
            err_code = str(payload.get("error") or "")
            raw_text = ""
            for block in msg.get("content") or []:
                if isinstance(block, dict) and isinstance(block.get("text"), str):
                    raw_text += block["text"]
            return [{"type": "error", "message": _friendly_claude_error(raw_text, err_code)}]

        events: list[dict] = []
        msg_id = msg.get("id") if isinstance(msg.get("id"), str) else ""
        text_parts: list[str] = []
        for block in msg.get("content") or []:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "text" and isinstance(block.get("text"), str) and block["text"]:
                text_parts.append(block["text"])
            elif btype == "tool_use":
                tool_id = str(block.get("id") or "")
                tool_name = str(block.get("name") or "tool")
                tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
                events.append({
                    "type": "tool_start",
                    "session_id": session_id,
                    "tool_use_id": tool_id,
                    "tool_name": tool_name,
                    "parameters": tool_input,
                })
        if text_parts:
            events.append({
                "type": "assistant_text",
                "session_id": session_id,
                "message_id": msg_id,
                "text": "".join(text_parts),
            })
        usage = normalize_claude_usage(msg.get("usage"))
        if usage:
            events.append({"type": "usage", "session_id": session_id, "usage": usage})
        return events

    if kind == "user":
        msg = payload.get("message") if isinstance(payload.get("message"), dict) else {}
        events = []
        for block in msg.get("content") or []:
            if not isinstance(block, dict) or block.get("type") != "tool_result":
                continue
            output_text, truncated = format_claude_tool_output(block.get("content"))
            events.append({
                "type": "tool_done",
                "session_id": session_id,
                "tool_use_id": str(block.get("tool_use_id") or ""),
                "output": output_text,
                "truncated": truncated,
                "is_error": block.get("is_error") is True,
            })
        return events

    if kind == "result":
        is_error = payload.get("is_error") is True
        res_text = payload.get("result") if isinstance(payload.get("result"), str) else ""
        return [{
            "type": "result",
            "session_id": session_id,
            "is_error": is_error,
            "result": res_text,
            "error": _friendly_claude_error(res_text) if is_error else "",
            "usage": normalize_claude_usage(payload.get("usage")),
        }]

    return []


def parse_claude_reset_time(raw: str | None, now_dt: datetime | None = None) -> float | None:
    """Convierte etiquetas como 'Nov 23, 6:10am (America/Mazatlan)' a epoch UTC."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    cleaned = " ".join(raw.strip().rstrip(".").split())
    match = RESET_MONTH_RE.match(cleaned)
    if not match:
        return None
    month_str, day_str, year_str, hour_str, minute_str, ampm, tz_name = match.groups()
    tz: timezone | ZoneInfo = timezone.utc
    if tz_name:
        try:
            tz = ZoneInfo(tz_name.strip())
        except ZoneInfoNotFoundError:
            tz = timezone.utc
    ref = (now_dt or datetime.now(timezone.utc)).astimezone(tz)

    hour = int(hour_str)
    minute = int(minute_str or 0)
    if ampm:
        ampm_low = ampm.lower()
        if ampm_low == "pm" and hour != 12:
            hour += 12
        elif ampm_low == "am" and hour == 12:
            hour = 0
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None

    if month_str and day_str:
        month = MONTH_MAP.get(month_str.lower())
        if not month:
            return None
        day = int(day_str)
        year = int(year_str) if year_str else ref.year
        try:
            candidate = datetime(year, month, day, hour, minute, tzinfo=tz)
        except ValueError:
            return None
        if not year_str and candidate < ref - timedelta(days=2):
            try:
                candidate = datetime(year + 1, month, day, hour, minute, tzinfo=tz)
            except ValueError:
                return None
        return candidate.timestamp()

    candidate = ref.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate < ref:
        candidate += timedelta(days=1)
    return candidate.timestamp()


def parse_claude_usage(raw_text: str, now_dt: datetime | None = None) -> dict:
    """Analiza la salida JSON de `claude -p \"/usage\" --output-format json`."""
    payload = _extract_json_object(raw_text)
    if payload is None:
        raise UsageError("invalid_data", "Claude Code no devolvió datos de uso válidos.")
    if payload.get("is_error") is True:
        raise UsageError("rpc_error", _friendly_claude_error(str(payload.get("result") or "")))
    text = payload.get("result") if isinstance(payload.get("result"), str) else ""
    if not text.strip():
        raise UsageError("invalid_data", "Claude Code no informó cuotas disponibles.")

    primary = None
    secondary = None

    m_session = SESSION_USAGE_RE.search(text)
    if m_session:
        used = float(m_session.group(1))
        if math.isfinite(used) and 0.0 <= used <= 100.0:
            primary = {
                "used_percent": round(used, 2),
                "window_minutes": 300,
                "resets_at": parse_claude_reset_time(m_session.group(2), now_dt=now_dt),
            }

    m_week = WEEKLY_USAGE_RE.search(text)
    if m_week:
        used = float(m_week.group(1))
        if math.isfinite(used) and 0.0 <= used <= 100.0:
            secondary = {
                "used_percent": round(used, 2),
                "window_minutes": 10080,
                "resets_at": parse_claude_reset_time(m_week.group(2), now_dt=now_dt),
            }

    if primary is None and secondary is None:
        if "authenticate" in text.lower() or "login" in text.lower():
            raise UsageError("login_required", "Inicia sesión en Claude Code (`claude auth login`) para consultar tu uso.")
        raise UsageError("invalid_data", "Claude Code no informó porcentajes de cuota en esta cuenta.")

    return {
        "source": "claude",
        "account": {"email": "", "plan": "Claude"},
        "limits": [{
            "id": "claude",
            "name": "Claude",
            "description": "",
            "primary": primary,
            "secondary": secondary,
            "credits": None,
        }],
        "summary": None,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }


def _terminate_process_group(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (OSError, ProcessLookupError):
        try:
            proc.terminate()
        except OSError:
            return
    try:
        proc.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError):
            try:
                proc.kill()
            except OSError:
                pass


def _write_temp_image(image_data_uri: str, directory: Path) -> Path | None:
    match = DATA_IMAGE_RE.match(image_data_uri.strip())
    if not match:
        return None
    ext = "jpg" if match.group(1) == "jpeg" else match.group(1)
    try:
        raw = base64.b64decode(match.group(2), validate=True)
    except (ValueError, TypeError):
        return None
    target = directory / f"attached.{ext}"
    target.write_bytes(raw)
    try:
        os.chmod(target, 0o600)
    except OSError:
        pass
    return target


class ClaudeClient:
    """Interfaz limpia hacia el CLI oficial `claude` (Claude Code)."""

    def __init__(self, binary: str = "claude", status_timeout: float = 10.0, usage_timeout: float = 20.0) -> None:
        self.binary = binary
        self.resolved_models: dict[str, str] = {}
        self.status_timeout = status_timeout
        self.usage_timeout = usage_timeout
        self._lock = threading.Lock()
        self._usage_process: subprocess.Popen | None = None
        self._login_process: subprocess.Popen | None = None
        self._closed = False

    def _resolve_binary(self) -> str | None:
        if os.environ.get("AGENT_SHELL_DISABLE_CLAUDE") == "1":
            return None
        candidate = Path(self.binary)
        if candidate.is_absolute():
            return str(candidate) if candidate.is_file() and os.access(candidate, os.X_OK) else None
        return shutil.which(self.binary)

    def is_available(self) -> bool:
        return self._resolve_binary() is not None

    def models(self) -> list[dict]:
        return claude_catalog()

    def close(self) -> None:
        with self._lock:
            self._closed = True
            procs = [p for p in (self._usage_process, self._login_process) if p is not None]
        for proc in procs:
            _terminate_process_group(proc)

    def auth_status(self) -> dict:
        exe = self._resolve_binary()
        if not exe:
            return {"authenticated": False, "email": "", "plan": "", "method": "none"}
        try:
            completed = subprocess.run(
                [exe, "auth", "status", "--json"],
                cwd=tempfile.gettempdir(),
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=self.status_timeout,
                check=False,
            )
        except (subprocess.TimeoutExpired, OSError):
            return {"authenticated": False, "email": "", "plan": "", "method": "none"}
        return parse_claude_auth_status(completed.stdout or completed.stderr or "")

    def login(self, cancel: threading.Event | None = None, timeout: float = 180.0) -> dict:
        exe = self._resolve_binary()
        if not exe:
            raise ServiceError("Claude Code CLI (`claude`) no está disponible en este equipo.")
        proc: subprocess.Popen | None = None
        try:
            proc = subprocess.Popen(
                [exe, "auth", "login", "--claudeai"],
                cwd=tempfile.gettempdir(),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                start_new_session=True,
            )
            with self._lock:
                if self._closed:
                    raise Cancelled()
                self._login_process = proc

            deadline = threading.Event()

            def _watch():
                while not deadline.is_set():
                    if cancel is not None and cancel.wait(timeout=0.1):
                        _terminate_process_group(proc)
                        return
                    if cancel is None:
                        return

            watcher = threading.Thread(target=_watch, daemon=True)
            watcher.start()
            try:
                stdout, stderr = proc.communicate(timeout=timeout)
            finally:
                deadline.set()
                watcher.join(timeout=0.5)
        except subprocess.TimeoutExpired as exc:
            if proc is not None:
                _terminate_process_group(proc)
            raise ServiceError("Tiempo agotado esperando el inicio de sesión en Claude Code.") from exc
        except OSError as exc:
            raise ServiceError("No se pudo iniciar `claude auth login`.") from exc
        finally:
            if proc is not None:
                _terminate_process_group(proc)
            with self._lock:
                self._login_process = None

        if cancel is not None and cancel.is_set():
            raise Cancelled()
        status = self.auth_status()
        if not status["authenticated"]:
            detail = strip_ansi((stderr or stdout or "")).strip().splitlines()
            reason = detail[-1][:200] if detail else "No se completó el inicio de sesión en Claude Code."
            raise ServiceError(reason)
        return status

    def usage(self) -> dict:
        exe = self._resolve_binary()
        if not exe:
            raise UsageError("claude_missing", "Instala e inicia sesión en Claude Code (`claude auth login`) para consultar tu uso.")
        proc: subprocess.Popen | None = None
        try:
            proc = subprocess.Popen(
                [exe, "-p", "/usage", "--output-format", "json"],
                cwd=tempfile.gettempdir(),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                start_new_session=True,
            )
            with self._lock:
                if self._closed:
                    raise UsageError("disconnected", "Se cerró la consulta de uso de Claude.")
                self._usage_process = proc
            stdout, _stderr = proc.communicate(timeout=self.usage_timeout)
        except subprocess.TimeoutExpired as exc:
            if proc is not None:
                _terminate_process_group(proc)
            raise UsageError("timeout", "Claude Code tardó demasiado en responder. Vuelve a actualizar el uso.") from exc
        except UsageError:
            if proc is not None:
                _terminate_process_group(proc)
            raise
        except OSError as exc:
            raise UsageError("unavailable", "No se pudo consultar el uso de Claude Code.") from exc
        finally:
            if proc is not None:
                _terminate_process_group(proc)
            with self._lock:
                self._usage_process = None

        if proc.returncode != 0 and not (stdout or "").strip():
            raise UsageError("rpc_error", "Claude Code no pudo consultar tu uso. Comprueba tu sesión con `claude auth status`.")
        return parse_claude_usage(stdout or "")

    def stream_turn(
        self,
        prompt: str,
        model: str,
        workspace: Path,
        control: StreamControl,
        *,
        session_id: str = "",
        effort: str = "",
        image: str = "",
        isolated: bool = False,
        tools: str = "",
    ) -> Iterator[dict]:
        exe = self._resolve_binary()
        if not exe:
            raise ServiceError("Claude Code CLI (`claude`) no está disponible en este equipo.")
        control.check()

        temp_dir_obj: tempfile.TemporaryDirectory | None = None
        effective_prompt = prompt
        if image:
            temp_dir_obj = tempfile.TemporaryDirectory(prefix="agent-shell-claude-")
            img_path = _write_temp_image(image, Path(temp_dir_obj.name))
            if img_path is not None:
                note = (
                    f"[Imagen adjunta por el usuario en: {img_path}. "
                    "Usa la herramienta Read para inspeccionar este archivo de imagen antes de responder.]"
                )
                effective_prompt = f"{effective_prompt}\n\n{note}" if effective_prompt else note

        cmd = [
            exe,
            "-p", effective_prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--disable-slash-commands",
            "--permission-mode", "acceptEdits",
            "--permission-prompts", "none",
        ]
        cli_model = resolve_cli_model(model)
        if cli_model:
            cmd.extend(["--model", cli_model])
        if effort:
            cmd.extend(["--effort", effort])
        if session_id:
            cmd.extend(["--resume", session_id])
        if isolated:
            cmd.extend(isolation_flags())
        if tools:
            cmd.extend(["--tools", tools])

        stderr_chunks: list[str] = []
        done = threading.Event()
        proc: subprocess.Popen | None = None
        watcher: threading.Thread | None = None
        stderr_thread: threading.Thread | None = None

        try:
            control.mark("request")
            try:
                proc = subprocess.Popen(
                    cmd,
                    cwd=str(workspace),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1,
                    start_new_session=True,
                )
            except OSError as exc:
                raise ServiceError("No se pudo iniciar Claude Code CLI (`claude`).") from exc

            def _drain_stderr() -> None:
                assert proc is not None and proc.stderr is not None
                total = 0
                try:
                    for chunk in proc.stderr:
                        if total < 8192:
                            stderr_chunks.append(chunk)
                            total += len(chunk)
                except OSError:
                    pass

            def _watch_cancel() -> None:
                assert proc is not None
                while not done.is_set():
                    if control.cancelled.wait(timeout=0.05):
                        _terminate_process_group(proc)
                        return

            stderr_thread = threading.Thread(target=_drain_stderr, daemon=True)
            watcher = threading.Thread(target=_watch_cancel, daemon=True)
            stderr_thread.start()
            watcher.start()

            saw_headers = False
            saw_result = False
            assert proc.stdout is not None
            for raw_line in proc.stdout:
                control.check()
                events = parse_claude_stream_line(raw_line)
                if not events:
                    continue
                if not saw_headers:
                    saw_headers = True
                    control.mark("headers")
                for event in events:
                    if event["type"] == "init" and event.get("model"):
                        self.resolved_models[model] = event["model"]
                    if event["type"] == "result":
                        saw_result = True
                    yield event

            proc.wait()
            done.set()
            stderr_thread.join(timeout=1.0)
            control.check()

            if proc.returncode != 0 and not saw_result:
                err_lines = [
                    line.strip()
                    for line in strip_ansi("".join(stderr_chunks)).splitlines()
                    if line.strip()
                ]
                detail = err_lines[-1][:280] if err_lines else f"código {proc.returncode}"
                raise ServiceError(_friendly_claude_error(detail))
        finally:
            done.set()
            if proc is not None:
                _terminate_process_group(proc)
                for pipe in (proc.stdout, proc.stderr):
                    if pipe is not None:
                        try:
                            pipe.close()
                        except OSError:
                            pass
            if watcher is not None:
                watcher.join(timeout=0.5)
            if stderr_thread is not None:
                stderr_thread.join(timeout=0.5)
            if temp_dir_obj is not None:
                temp_dir_obj.cleanup()
