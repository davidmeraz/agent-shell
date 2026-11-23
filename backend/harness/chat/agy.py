"""Cliente oficial para Google Antigravity CLI (`agy`) en modo headless NDJSON.

Invoca únicamente los comandos documentados del binario oficial `agy`:
- `agy models` para descubrir el catálogo disponible en la cuenta activa de `agy`.
- `agy -p <prompt> --output-format stream-json --disable-slash-commands` para ejecutar
  turnos con streaming de texto, tarjetas de herramientas y continuación de sesiones
  mediante `--conversation <id>`.

Nunca lee, copia ni manipula credenciales OAuth externas.
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
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from ..account.codex_usage import UsageError
from ..core.http import Cancelled, ServiceError, StreamControl
from .models import family

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
MODEL_LINE_RE = re.compile(r"^([a-z0-9][a-z0-9._-]+)(?:\t+|\s{2,})(.+)$")
DATA_IMAGE_RE = re.compile(r"^data:image/(png|jpeg|jpg|webp|gif);base64,([A-Za-z0-9+/=\s]+)$")
WINDOW_DURATION_RE = re.compile(r"^(\d+)\s*([hdm])(?:in)?$")
MAX_TOOL_OUTPUT_CHARS = 64 * 1024


def parse_window_minutes(raw) -> int | None:
    if not isinstance(raw, str):
        return None
    cleaned = raw.strip().lower()
    if cleaned == "weekly":
        return 10080
    if cleaned == "daily":
        return 1440
    match = WINDOW_DURATION_RE.match(cleaned)
    if not match:
        return None
    amount = int(match.group(1))
    unit = match.group(2)
    if amount <= 0:
        return None
    if unit == "h":
        return amount * 60
    if unit == "d":
        return amount * 1440
    return amount


def parse_iso_timestamp(raw) -> float | None:
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        text = raw.strip()
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


def _group_slug(name: str, index: int) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug[:64] if slug else f"agy-group-{index}"


def _clean_group_description(raw: str) -> str:
    text = " ".join(raw.split())
    prefix = "models within this group:"
    if text.lower().startswith(prefix):
        return text[len(prefix):].strip()[:180]
    return ""


def parse_agy_usage(raw_text: str) -> dict:
    """Normaliza la salida JSON de `agy -p \"/usage\" --output-format json` al esquema de UsageLimit."""
    text = strip_ansi(raw_text).strip()
    if not text:
        raise UsageError("invalid_data", "Antigravity (agy) no devolvió datos de uso.")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise UsageError("invalid_data", "Antigravity (agy) devolvió una respuesta de uso inválida.") from exc
    if not isinstance(payload, dict):
        raise UsageError("invalid_data", "Antigravity (agy) devolvió datos de uso inválidos.")
    status = payload.get("status")
    if status and status != "SUCCESS":
        raise UsageError("rpc_error", "Antigravity (agy) no pudo consultar las cuotas. Comprueba tu sesión en `agy`.")
    command = payload.get("command")
    data = command.get("data") if isinstance(command, dict) else None
    groups = data.get("groups") if isinstance(data, dict) else None
    if not isinstance(groups, list) or len(groups) > 64:
        raise UsageError("invalid_data", "Antigravity (agy) no informó grupos de cuotas compatibles.")

    limits: list[dict] = []
    for idx, group in enumerate(groups):
        if not isinstance(group, dict):
            continue
        group_name = str(group.get("name") or f"Antigravity {idx + 1}").strip()[:160]
        raw_desc = str(group.get("description") or "").strip()
        models_hint = _clean_group_description(raw_desc)
        raw_buckets = group.get("buckets")
        if not isinstance(raw_buckets, list):
            raw_buckets = []

        windows: list[tuple[int, dict]] = []
        for b_idx, bucket in enumerate(raw_buckets):
            if not isinstance(bucket, dict):
                continue
            rem = bucket.get("remaining_fraction")
            used_percent = None
            if not isinstance(rem, bool) and isinstance(rem, (int, float)) and math.isfinite(rem):
                clamped = max(0.0, min(1.0, float(rem)))
                used_percent = round((1.0 - clamped) * 100.0, 2)
            window_minutes = parse_window_minutes(bucket.get("window"))
            resets_at = parse_iso_timestamp(bucket.get("reset_time"))
            sort_key = window_minutes if window_minutes is not None else 10**9 + b_idx
            windows.append((
                sort_key,
                {
                    "used_percent": used_percent,
                    "window_minutes": window_minutes,
                    "resets_at": resets_at,
                },
            ))

        windows.sort(key=lambda item: item[0])
        ordered = [item[1] for item in windows]
        base_id = _group_slug(group_name, idx)
        if not ordered:
            limits.append({
                "id": base_id,
                "name": group_name,
                "description": models_hint,
                "primary": None,
                "secondary": None,
                "credits": None,
            })
            continue
        for chunk_index in range(0, len(ordered), 2):
            pair = ordered[chunk_index:chunk_index + 2]
            entry_id = base_id if chunk_index == 0 else f"{base_id}-{chunk_index // 2 + 1}"
            limits.append({
                "id": entry_id,
                "name": group_name,
                "description": models_hint if chunk_index == 0 else "",
                "primary": pair[0],
                "secondary": pair[1] if len(pair) > 1 else None,
                "credits": None,
            })

    return {
        "source": "agy",
        "account": {"email": "", "plan": "Antigravity"},
        "limits": limits,
        "summary": None,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def parse_models_output(text: str) -> list[dict]:
    """Analiza la salida de `agy models`, ignorando spinners y secuencias ANSI."""
    seen: set[str] = set()
    rows: list[dict] = []
    for raw_line in text.splitlines():
        segment = raw_line.split("\r")[-1]
        cleaned = strip_ansi(segment).strip()
        if not cleaned:
            continue
        match = MODEL_LINE_RE.match(cleaned)
        if not match:
            continue
        slug = match.group(1).strip()
        display_name = " ".join(match.group(2).split())
        if not slug or not display_name or slug in seen:
            continue
        seen.add(slug)
        rows.append({
            "slug": slug,
            "display_name": display_name,
            "family": family(slug),
            "reasoning_efforts": [],
            "default_reasoning_effort": "",
        })
    return rows


def normalize_agy_usage(raw) -> dict | None:
    """Convierte el bloque `usage` de `agy` al formato aceptado por `TurnPerformance`."""
    if not isinstance(raw, dict):
        return None
    result: dict = {}
    for key in ("input_tokens", "output_tokens", "total_tokens"):
        val = raw.get(key)
        if type(val) is int and val >= 0:
            result[key] = val
    cached = raw.get("cache_read_tokens")
    if type(cached) is int and cached >= 0:
        result["input_tokens_details"] = {"cached_tokens": cached}
    thinking = raw.get("thinking_tokens")
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


def summarize_agy_tool(tool_name: str, parameters: dict | None, workspace: Path | None = None) -> str:
    """Genera un resumen conciso compatible con los iconos de ToolCallCard.qml."""
    name = (tool_name or "tool").strip()
    params = parameters if isinstance(parameters, dict) else {}

    if name in ("run_command", "shell", "bash"):
        cmd = params.get("CommandLine") or params.get("command") or params.get("cmd")
        if isinstance(cmd, str) and cmd.strip():
            return " ".join(cmd.strip().splitlines())[:400]
        return name

    if name in ("read_file", "view_file", "view_file_outline", "view_code_item", "list_dir"):
        path_val = (
            params.get("Path") or params.get("AbsolutePath") or params.get("File")
            or params.get("DirectoryPath") or params.get("path") or ""
        )
        short = _short_path(str(path_val), workspace) if path_val else ""
        return f"read_file {short}".strip() if short else f"read_file ({name})"

    if name in ("grep_search", "find_by_name", "grep_files", "glob"):
        query = params.get("Query") or params.get("Pattern") or params.get("query") or params.get("pattern") or ""
        search_path = params.get("SearchPath") or params.get("SearchDirectory") or ""
        parts = ["grep_files"]
        if isinstance(query, str) and query.strip():
            parts.append(query.strip()[:120])
        if isinstance(search_path, str) and search_path.strip():
            parts.append(_short_path(search_path, workspace))
        return " ".join(parts)

    if name in ("edit_file", "write_file", "write_to_file", "replace_file_content", "multi_replace_file_content"):
        path_val = (
            params.get("Path") or params.get("TargetFile") or params.get("AbsolutePath")
            or params.get("path") or ""
        )
        short = _short_path(str(path_val), workspace) if path_val else ""
        return f"apply_patch {short}".strip() if short else f"apply_patch ({name})"

    if name in ("search_web", "web_search", "read_url_content"):
        target = params.get("query") or params.get("Query") or params.get("Url") or params.get("url") or ""
        if isinstance(target, str) and target.strip():
            return f"{name} {target.strip()[:160]}"
        return name

    for value in params.values():
        if isinstance(value, str) and value.strip():
            return f"{name} {value.strip()[:160]}"
    return name


def format_agy_tool_output(raw_output) -> tuple[str, bool]:
    """Serializa la salida de una herramienta de `agy` con tope seguro."""
    if raw_output is None:
        return "", False
    if isinstance(raw_output, str):
        text = raw_output
    else:
        try:
            text = json.dumps(raw_output, ensure_ascii=False, indent=2)
        except (TypeError, ValueError):
            text = str(raw_output)
    if len(text) > MAX_TOOL_OUTPUT_CHARS:
        return text[:MAX_TOOL_OUTPUT_CHARS] + "\n… [salida recortada]", True
    return text, False


def parse_stream_line(line: str) -> dict | None:
    """Normaliza una línea NDJSON emitida por `agy -p --output-format stream-json`."""
    stripped = line.strip()
    if not stripped or not stripped.startswith("{"):
        return None
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None

    kind = payload.get("event")
    if kind == "init":
        init_data = payload.get("init") if isinstance(payload.get("init"), dict) else {}
        conv_id = payload.get("conversation_id") or init_data.get("conversation_id") or ""
        return {
            "type": "init",
            "conversation_id": conv_id if isinstance(conv_id, str) else "",
            "model": init_data.get("model", "") if isinstance(init_data.get("model"), str) else "",
        }

    if kind == "step_update":
        step = payload.get("step_update")
        if not isinstance(step, dict):
            return None
        step_type = step.get("step_type", "")
        step_index = step.get("step_index")
        state = step.get("state", "")
        conv_id = step.get("conversation_id") or payload.get("conversation_id") or ""
        if step_type == "agent_response":
            delta = step.get("text_delta", "")
            return {
                "type": "text_delta",
                "conversation_id": conv_id if isinstance(conv_id, str) else "",
                "step_index": step_index if isinstance(step_index, int) else 0,
                "state": state if isinstance(state, str) else "",
                "text": delta if isinstance(delta, str) else "",
                "done": state == "DONE",
                "usage": normalize_agy_usage(step.get("usage")),
            }
        if step_type == "tool":
            info = step.get("tool_info") if isinstance(step.get("tool_info"), dict) else {}
            tool_name = step.get("tool_name") or info.get("name") or "tool"
            output_text, truncated = format_agy_tool_output(info.get("output"))
            duration = step.get("duration_seconds")
            err = step.get("error") or info.get("error") or ""
            return {
                "type": "tool",
                "conversation_id": conv_id if isinstance(conv_id, str) else "",
                "step_index": step_index if isinstance(step_index, int) else 0,
                "state": state if isinstance(state, str) else "",
                "tool_name": str(tool_name),
                "parameters": info.get("parameters") if isinstance(info.get("parameters"), dict) else {},
                "output": output_text,
                "truncated": truncated,
                "duration_seconds": float(duration) if isinstance(duration, (int, float)) and duration >= 0 else None,
                "error": str(err) if err else "",
            }
        if step_type == "error" or state == "ERROR":
            err = step.get("error") or step.get("message") or "Error durante el turno de Antigravity."
            return {"type": "error", "message": str(err)}
        return None

    if kind == "result":
        res = payload.get("result")
        if not isinstance(res, dict):
            return None
        conv_id = res.get("conversation_id") or payload.get("conversation_id") or ""
        status = res.get("status", "")
        response = res.get("response", "")
        error_text = res.get("error") or ""
        return {
            "type": "result",
            "conversation_id": conv_id if isinstance(conv_id, str) else "",
            "status": str(status),
            "response": response if isinstance(response, str) else "",
            "usage": normalize_agy_usage(res.get("usage")),
            "error": str(error_text) if error_text else "",
        }

    if kind == "error":
        err = payload.get("error") or payload.get("message") or "Antigravity devolvió un error."
        if isinstance(err, dict):
            err = err.get("message") or json.dumps(err, ensure_ascii=False)
        return {"type": "error", "message": str(err)}

    return None


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


class AgyClient:
    """Interfaz limpia hacia el CLI oficial `agy` (Google Antigravity)."""

    def __init__(self, binary: str = "agy", models_timeout: float = 12.0, usage_timeout: float = 20.0) -> None:
        self.binary = binary
        self.models_timeout = models_timeout
        self.usage_timeout = usage_timeout
        self._cached_models: list[dict] = []
        self._usage_lock = threading.Lock()
        self._usage_process: subprocess.Popen | None = None
        self._closed = False

    def close(self) -> None:
        with self._usage_lock:
            self._closed = True
            proc = self._usage_process
        if proc is not None:
            _terminate_process_group(proc)

    def usage(self) -> dict:
        """Consulta las cuotas reales de todos los grupos de modelos mediante `agy -p /usage`."""
        exe = self._resolve_binary()
        if not exe:
            raise UsageError("agy_missing", "Instala e inicia sesión en Antigravity CLI (`agy`) para consultar tu uso.")
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
            with self._usage_lock:
                if self._closed:
                    raise UsageError("disconnected", "Se cerró la consulta de uso de Antigravity.")
                self._usage_process = proc
            stdout, _stderr = proc.communicate(timeout=self.usage_timeout)
        except subprocess.TimeoutExpired as exc:
            if proc is not None:
                _terminate_process_group(proc)
            raise UsageError("timeout", "Antigravity (agy) tardó demasiado en responder. Vuelve a actualizar el uso.") from exc
        except UsageError:
            if proc is not None:
                _terminate_process_group(proc)
            raise
        except OSError as exc:
            raise UsageError("unavailable", "No se pudo consultar el uso de Antigravity (agy).") from exc
        finally:
            if proc is not None:
                _terminate_process_group(proc)
            with self._usage_lock:
                self._usage_process = None

        if proc.returncode != 0 and not (stdout or "").strip():
            raise UsageError("rpc_error", "Antigravity (agy) no pudo consultar tu uso. Comprueba tu sesión ejecutando `agy`.")
        return parse_agy_usage(stdout or "")

    def _resolve_binary(self) -> str | None:
        if os.environ.get("AGENT_SHELL_DISABLE_AGY") == "1":
            return None
        candidate = Path(self.binary)
        if candidate.is_absolute():
            return str(candidate) if candidate.is_file() and os.access(candidate, os.X_OK) else None
        return shutil.which(self.binary)

    def is_available(self) -> bool:
        return self._resolve_binary() is not None

    def models(self, force: bool = False) -> list[dict]:
        if not force and self._cached_models:
            return [dict(row) for row in self._cached_models]
        exe = self._resolve_binary()
        if not exe:
            raise ServiceError("Antigravity CLI (agy) no está disponible en este equipo.")
        try:
            completed = subprocess.run(
                [exe, "models"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=self.models_timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise ServiceError("Tiempo agotado al consultar los modelos de Antigravity (agy).") from exc
        except OSError as exc:
            raise ServiceError("No se pudo ejecutar Antigravity CLI (agy).") from exc

        parsed = parse_models_output(completed.stdout)
        if not parsed and completed.stderr:
            parsed = parse_models_output(completed.stderr)
        if completed.returncode != 0 and not parsed:
            detail = strip_ansi(completed.stderr or completed.stdout).strip().splitlines()
            reason = detail[-1][:240] if detail else "Comprueba tu sesión ejecutando `agy` en una terminal."
            raise ServiceError(f"No se pudo listar el catálogo de Antigravity (agy): {reason}")
        if not parsed:
            raise ServiceError("Antigravity (agy) no devolvió modelos disponibles. Inicia sesión con `agy`.")
        self._cached_models = parsed
        return [dict(row) for row in parsed]

    def stream_turn(
        self,
        prompt: str,
        model: str,
        workspace: Path,
        control: StreamControl,
        *,
        conversation_id: str = "",
        image: str = "",
        mode: str = "auto",
    ) -> Iterator[dict]:
        exe = self._resolve_binary()
        if not exe:
            raise ServiceError("Antigravity CLI (agy) no está disponible en este equipo.")
        control.check()

        temp_dir_obj: tempfile.TemporaryDirectory | None = None
        effective_prompt = prompt
        if image:
            temp_dir_obj = tempfile.TemporaryDirectory(prefix="agent-shell-agy-")
            img_path = _write_temp_image(image, Path(temp_dir_obj.name))
            if img_path is not None:
                note = (
                    f"[Imagen adjunta por el usuario en: {img_path}. "
                    "Inspecciona este archivo de imagen antes de responder.]"
                )
                effective_prompt = f"{effective_prompt}\n\n{note}" if effective_prompt else note

        cmd = [
            exe,
            "-p", effective_prompt,
            "--output-format", "stream-json",
            "--disable-slash-commands",
            "--mode", mode,
        ]
        if model:
            cmd.extend(["--model", model])
        if conversation_id:
            cmd.extend(["--conversation", conversation_id])

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
                raise ServiceError("No se pudo iniciar el proceso de Antigravity CLI (agy).") from exc

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
            saw_success = False
            assert proc.stdout is not None
            for raw_line in proc.stdout:
                control.check()
                event = parse_stream_line(raw_line)
                if event is None:
                    continue
                if not saw_headers:
                    saw_headers = True
                    control.mark("headers")
                if event["type"] == "result" and event.get("status") == "SUCCESS":
                    saw_success = True
                yield event

            proc.wait()
            done.set()
            stderr_thread.join(timeout=1.0)
            control.check()

            if proc.returncode != 0 and not saw_success:
                err_lines = [
                    line.strip()
                    for line in strip_ansi("".join(stderr_chunks)).splitlines()
                    if line.strip()
                ]
                detail = err_lines[-1][:280] if err_lines else f"código {proc.returncode}"
                raise ServiceError(f"Antigravity (agy) terminó con error: {detail}")
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
