"""Ejecutor de benchmarks contra HarnessServer real (modo --live o --mock) y auditoría local."""

from __future__ import annotations

import json
import queue
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = PROJECT_ROOT / "backend"
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from harness.account.auth import ChatGPTSession
from harness.account.codex_usage import CodexUsageReader, UsageError
from harness.chat.chatgpt import ChatGPTClient
from harness.chat.performance import safe_usage
from harness.core.http import HttpClient
from harness.core.limits import AgentLimits
from harness.core.server import HarnessServer
from harness.core.version import get_version

from .metrics import compute_area_stats, git_metadata, summarize_run, summarize_steps
from .tasks import BenchmarkTask, select_tasks


class EventCollector:
    """Receptor NDJSON compatible con HarnessServer, con callbacks de progreso en vivo."""

    def __init__(self, on_event: Callable[[dict[str, Any]], None] | None = None) -> None:
        self._queue: queue.Queue[dict[str, Any]] = queue.Queue()
        self._on_event = on_event
        self.events: list[dict[str, Any]] = []
        self._lock = threading.Lock()

    def write(self, text: str) -> int:
        for line in text.splitlines():
            if not line.strip():
                continue
            event = json.loads(line)
            with self._lock:
                self.events.append(event)
            self._queue.put(event)
            if self._on_event:
                self._on_event(event)
        return len(text)

    def flush(self) -> None:
        pass

    def wait_for(self, event_type: str, timeout: float = 900.0) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"Tiempo agotado esperando el evento '{event_type}'")
            try:
                event = self._queue.get(timeout=min(remaining, 1.0))
            except queue.Empty:
                continue
            if event["type"] == event_type:
                return event["data"]


class InstrumentedHttp:
    """Envuelve HttpClient para capturar métricas reales del payload sin modificar backend/."""

    def __init__(self, inner: HttpClient) -> None:
        self._inner = inner
        self._lock = threading.Lock()
        self.last_wire: dict[str, Any] = {}

    def json(self, *args, **kwargs):
        return self._inner.json(*args, **kwargs)

    def stream(self, url: str, payload: dict[str, Any], token: str, control,
               extra_headers: dict[str, str] | None = None):
        raw_bytes = len(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
        tools = payload.get("tools") or []
        wire = {
            "payload_bytes": raw_bytes,
            "input_items": len(payload.get("input") or []),
            "parallel_tool_calls": bool(payload.get("parallel_tool_calls", False)),
            "has_prompt_cache_key": bool(payload.get("prompt_cache_key")),
            "tools_offered": [t.get("name", "") for t in tools if isinstance(t, dict) and t.get("name")],
            "store": bool(payload.get("store", False)),
        }
        with self._lock:
            self.last_wire = wire
        return self._inner.stream(url, payload, token, control, extra_headers=extra_headers)


class InstrumentedClient:
    """Envuelve ChatGPTClient y registra métricas detalladas por cada llamada al modelo."""

    def __init__(self, inner: ChatGPTClient, wire: InstrumentedHttp) -> None:
        self._inner = inner
        self._wire = wire
        self._lock = threading.Lock()
        self.steps: list[dict[str, Any]] = []

    def reset_steps(self) -> None:
        with self._lock:
            self.steps = []

    def models(self):
        return self._inner.models()

    def stream(self, model: str, messages: list[dict], instructions: str, control,
               tools: list[dict] | None = None, reasoning_effort: str = "",
               prompt_cache_key: str = "", parallel_tool_calls: bool = False):
        started = time.perf_counter()
        first_event: float | None = None
        record: dict[str, Any] = {
            "step": 0,
            "model": model,
            "reasoning_effort": reasoning_effort,
            "status": "error",
            "http_ms": 0.0,
            "first_event_ms": None,
            "input_tokens": 0,
            "cached_tokens": 0,
            "output_tokens": 0,
            "reasoning_tokens": 0,
            "total_tokens": 0,
            "tool_calls_returned": 0,
        }
        stream = self._inner.stream(
            model, messages, instructions, control, tools=tools,
            reasoning_effort=reasoning_effort, prompt_cache_key=prompt_cache_key,
            parallel_tool_calls=parallel_tool_calls,
        )
        try:
            for event in stream:
                now = time.perf_counter()
                if first_event is None:
                    first_event = now
                    record["first_event_ms"] = round((first_event - started) * 1000.0, 1)
                if event.get("type") == "response.completed":
                    response = event.get("response") or {}
                    record["status"] = response.get("status", "completed")
                    usage = safe_usage(response.get("usage")) or {}
                    for key in ("input_tokens", "cached_tokens", "output_tokens",
                                "reasoning_tokens", "total_tokens"):
                        record[key] = usage.get(key, 0)
                    output = response.get("output") or []
                    record["tool_calls_returned"] = sum(
                        1 for item in output
                        if isinstance(item, dict) and item.get("type") == "function_call"
                    )
                yield event
        finally:
            close = getattr(stream, "close", None)
            if close:
                close()
            record["http_ms"] = round((time.perf_counter() - started) * 1000.0, 1)
            with self._wire._lock:
                record.update(self._wire.last_wire)
            with self._lock:
                record["step"] = len(self.steps) + 1
                self.steps.append(record)


# ---------------------------------------------------------------------------
# Lectura segura de cuota Codex (sin guardar PII)
# ---------------------------------------------------------------------------

def read_quota_snapshot(expected_email: str = "") -> dict[str, Any] | None:
    reader = CodexUsageReader(timeout=20)
    try:
        raw = reader.read(expected_email=expected_email)
    except (UsageError, OSError, ValueError):
        return None
    finally:
        reader.close()

    # No guardamos correo electrónico ni identificadores privados en los reportes.
    limits = raw.get("limits") or []
    codex_bucket = next(
        (b for b in limits if "codex" in (b.get("id") or "").lower()),
        limits[0] if limits else None,
    )
    return {
        "checked_at": raw.get("checked_at"),
        "plan": (raw.get("account") or {}).get("plan", ""),
        "primary": codex_bucket.get("primary") if codex_bucket else None,
        "secondary": codex_bucket.get("secondary") if codex_bucket else None,
        "lifetime_tokens": (raw.get("summary") or {}).get("lifetime_tokens"),
    }


def compute_quota_delta(before: dict[str, Any] | None, after: dict[str, Any] | None) -> dict[str, Any]:
    if not before or not after:
        return {"available": False}

    def _win_delta(key: str) -> tuple[float | None, bool]:
        b, a = before.get(key), after.get(key)
        if not b or not a:
            return None, False
        if b.get("used_percent") is None or a.get("used_percent") is None:
            return None, False
        if b.get("resets_at") != a.get("resets_at"):
            return None, True
        return round(a["used_percent"] - b["used_percent"], 2), False

    p_delta, p_reset = _win_delta("primary")
    s_delta, s_reset = _win_delta("secondary")
    lt_b, lt_a = before.get("lifetime_tokens"), after.get("lifetime_tokens")
    lt_delta = (lt_a - lt_b) if (isinstance(lt_b, int) and isinstance(lt_a, int) and lt_a >= lt_b) else None

    return {
        "available": True,
        "plan": after.get("plan") or before.get("plan") or "",
        "primary_before_pct": (before.get("primary") or {}).get("used_percent"),
        "primary_after_pct": (after.get("primary") or {}).get("used_percent"),
        "primary_delta_pct": p_delta,
        "primary_window_reset": p_reset,
        "secondary_before_pct": (before.get("secondary") or {}).get("used_percent"),
        "secondary_after_pct": (after.get("secondary") or {}).get("used_percent"),
        "secondary_delta_pct": s_delta,
        "secondary_window_reset": s_reset,
        "lifetime_tokens_delta": lt_delta,
    }


# ---------------------------------------------------------------------------
# Modo 1: Auditoría offline de .runtime/chats (0 tokens, sin Pillow)
# ---------------------------------------------------------------------------

def audit_history(history_root: Path) -> dict[str, Any]:
    """Lee únicamente metadatos numéricos de `performance` (SQLite o JSON legado) sin exponer prompts ni imágenes."""
    if not history_root.exists():
        return {
            "history_root": str(history_root),
            "chat_files": 0,
            "turns_total": 0,
            "turns_with_usage": 0,
            "overall": compute_area_stats([]),
            "by_area": {},
            "multicall_turns": 0,
            "multicall_zero_cache": 0,
            "tools_per_call": 0.0,
            "wasted_tokens_failed": 0,
        }

    import sqlite3

    turns_total = 0
    turns: list[dict[str, Any]] = []
    seen_chat_ids: set[str] = set()
    chat_count = 0

    def _consume_perf(area: str, perf: dict) -> None:
        nonlocal turns_total
        if not isinstance(perf, dict):
            return
        turns_total += 1
        usage = perf.get("usage")
        if not isinstance(usage, dict) or usage.get("total_tokens") is None:
            return
        turns.append({
            "area": area,
            "model": perf.get("model", ""),
            "status": perf.get("status", ""),
            "model_calls": perf.get("model_calls") or 0,
            "tool_calls": perf.get("tool_calls") or 0,
            "context_tokens": perf.get("context_tokens") or 0,
            "input_tokens": usage.get("input_tokens") or 0,
            "cached_tokens": usage.get("cached_tokens") or 0,
            "output_tokens": usage.get("output_tokens") or 0,
            "reasoning_tokens": usage.get("reasoning_tokens") or 0,
            "total_tokens": usage.get("total_tokens") or 0,
        })

    db_path = history_root / "agent-shell.db"
    if db_path.exists() and not db_path.is_symlink():
        try:
            conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5.0)
            try:
                for (cid,) in conn.execute("SELECT chat_id FROM chats"):
                    seen_chat_ids.add(cid)
                    chat_count += 1
                for area, m_json in conn.execute("SELECT area, measurement_json FROM turn_performance"):
                    try:
                        _consume_perf(area or "chat", json.loads(m_json))
                    except ValueError:
                        continue
            finally:
                conn.close()
        except sqlite3.Error:
            pass

    files = sorted(history_root.glob("*.json"))
    for path in files:
        if path.stem in seen_chat_ids:
            continue
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(record, dict):
            continue
        chat_count += 1
        area = record.get("area", "chat")
        for perf in record.get("performance") or []:
            _consume_perf(area, perf)

    by_area: dict[str, Any] = {}
    for area in sorted({t["area"] for t in turns}):
        by_area[area] = compute_area_stats([t for t in turns if t["area"] == area])

    multicall = [t for t in turns if t["model_calls"] >= 2]
    total_calls = sum(t["model_calls"] for t in turns)
    total_tools = sum(t["tool_calls"] for t in turns)
    wasted_failed = sum(
        max(0, t["input_tokens"] - t["cached_tokens"]) + t["output_tokens"]
        for t in turns if t["status"] == "failed"
    )
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "history_root": str(history_root),
        "chat_files": chat_count,
        "turns_total": turns_total,
        "turns_with_usage": len(turns),
        "overall": compute_area_stats(turns),
        "by_area": by_area,
        "multicall_turns": len(multicall),
        "multicall_zero_cache": sum(1 for t in multicall if t["cached_tokens"] == 0),
        "tools_per_call": round(total_tools / total_calls, 2) if total_calls else 0.0,
        "wasted_tokens_failed": wasted_failed,
    }


# ---------------------------------------------------------------------------
# Servidor simulado offline (--mock) para probar el pipeline sin gastar cuota
# ---------------------------------------------------------------------------

class _MockSession:
    def account(self):
        return {
            "authenticated": True, "method": "chatgpt", "email": "", "plan": "mock",
            "plan_enabled": True, "accounts": [{"id": "mock", "label": "Mock", "email": "", "active": True}],
        }

    def access_token(self):
        return "mock-benchmark-token"


class MockBenchmarkService:
    """Simula respuestas deterministas de Responses API + caché según `prompt_cache_key`."""

    def __init__(self) -> None:
        self.models = [
            {"slug": "mock-model", "display_name": "Mock Benchmark", "visibility": "list",
             "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}]},
        ]
        self._seen_keys: dict[str, int] = {}
        self._lock = threading.Lock()
        service = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"models": service.models}).encode())

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                items = body.get("input") or []
                last_user = max((i for i, it in enumerate(items) if it.get("role") == "user"), default=0)
                prompt = str(items[last_user].get("content", ""))
                results = [it for it in items[last_user:] if it.get("type") == "function_call_output"]
                step = len(results)

                # Aproximar tokens reales (~4 chars/token) y simular KV cache realista:
                # con prompt_cache_key acierta ~85% del prefijo previo; sin ella ~30%.
                payload_chars = len(json.dumps(body, ensure_ascii=False))
                input_tokens = max(400, payload_chars // 4)
                cache_key = body.get("prompt_cache_key")
                with service._lock:
                    prev_tokens = service._seen_keys.get(cache_key, 0) if cache_key else 0
                    if cache_key:
                        service._seen_keys[cache_key] = input_tokens
                if step == 0 and prev_tokens == 0:
                    cached_tokens = 0
                elif cache_key:
                    cached_tokens = int(min(input_tokens, prev_tokens or input_tokens * 0.85) * 0.88)
                else:
                    cached_tokens = int(input_tokens * 0.25)

                output_items, out_tokens = service._script_response(prompt, step)
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.end_headers()

                def send(ev: dict[str, Any]) -> None:
                    self.wfile.write(("data: " + json.dumps(ev, ensure_ascii=False) + "\n\n").encode())
                    self.wfile.flush()

                for idx, item in enumerate(output_items):
                    if item.get("type") == "message":
                        for part in item.get("content", []):
                            if part.get("type") == "output_text":
                                send({"type": "response.output_text.delta", "item_id": item["id"],
                                      "content_index": 0, "delta": part["text"]})
                    send({"type": "response.output_item.done", "output_index": idx, "item": item})

                send({
                    "type": "response.completed",
                    "response": {
                        "status": "completed",
                        "output": output_items,
                        "usage": {
                            "input_tokens": input_tokens,
                            "output_tokens": out_tokens,
                            "total_tokens": input_tokens + out_tokens,
                            "input_tokens_details": {"cached_tokens": cached_tokens},
                            "output_tokens_details": {"reasoning_tokens": max(0, out_tokens // 5)},
                        },
                    },
                })

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}/v1"
        self.thread = threading.Thread(
            target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True,
        )

    @staticmethod
    def _call(step: int, cmd: str) -> list[dict[str, Any]]:
        return [
            {"type": "reasoning", "id": f"rs-{step}", "summary": [], "encrypted_content": "mock-enc"},
            {"type": "function_call", "id": f"fc-{step}", "call_id": f"call-{step}-{time.monotonic_ns()}",
             "name": "shell", "arguments": json.dumps({"command": cmd})},
        ]

    @staticmethod
    def _final(text: str) -> list[dict[str, Any]]:
        return [{
            "type": "message", "id": f"msg-{time.monotonic_ns()}", "role": "assistant",
            "phase": "final_answer", "content": [{"type": "output_text", "text": text}],
        }]

    def _script_response(self, prompt: str, step: int) -> tuple[list[dict[str, Any]], int]:
        # Scripts mínimos para probar de punta a punta las 5 tareas en modo --mock.
        if "ORD-42" in prompt:
            if step == 0:
                return self._call(step, "grep -n 'ORD-42' logs/build.log && cat app/pricing.py"), 90
            return self._final(
                "El bug está en app/pricing.py dentro de calculate_order_total: aplica el impuesto "
                "(tax) antes de restar el descuento del cupón. Código en logs/build.log: ERR-PRICING-402."
            ), 110

        if "retry_budget.py" in prompt:
            if step == 0:
                return self._call(step, "cat retry_budget.py"), 70
            if step == 1:
                patch_cmd = (
                    f"{sys.executable} -c '"
                    "from pathlib import Path; "
                    "p = Path(\"retry_budget.py\"); "
                    "s = p.read_text(); "
                    "s = s.replace(\"return attempt <= max_attempts\", \"return attempt < max_attempts\"); "
                    "s = s.replace(\"if retry_index > 0 and delay > max_delay:\", \"if delay > max_delay:\"); "
                    "p.write_text(s); "
                    "t = Path(\"tests/test_retry_budget.py\"); "
                    "t.write_text(t.read_text() + \"\\n    def test_regressions(self):\\n"
                    "        self.assertFalse(can_retry(3, 3))\\n"
                    "        self.assertEqual(compute_delay(0, 15.0, 10.0), 10.0)\\n\")'"
                )
                return self._call(step, patch_cmd), 140
            if step == 2:
                return self._call(step, f"{sys.executable} -m unittest discover -s tests -v"), 60
            return self._final("Corregidos ambos bugs en retry_budget.py y añadidos tests de regresión."), 80

        if "paquete inventory" in prompt:
            if step == 0:
                return self._call(step, "ls inventory && cat inventory/store.py inventory/cli.py"), 80
            if step == 1:
                store_src = (
                    'import json\n'
                    'from pathlib import Path\n'
                    'from .models import Item\n\n'
                    'def load_items(path: Path) -> list[Item]:\n'
                    '    raw = json.loads(path.read_text(encoding="utf-8"))\n'
                    '    return [Item(row["sku"], row["name"], row["category"], int(row["qty"])) for row in raw]\n\n'
                    'def filter_items(items: list[Item], include_zero: bool = False, category: str | None = None) -> list[Item]:\n'
                    '    out = [i for i in items if include_zero or i.qty > 0]\n'
                    '    if category is not None:\n'
                    '        out = [i for i in out if i.category == category]\n'
                    '    return out\n'
                )
                cli_src = (
                    'import argparse\nimport csv\nimport io\nimport json\n'
                    'from pathlib import Path\n'
                    'from .store import filter_items, load_items\n\n'
                    'def format_json(items) -> str:\n'
                    '    return json.dumps(\n'
                    '        [{"sku": i.sku, "name": i.name, "category": i.category, "qty": i.qty} for i in items],\n'
                    '        ensure_ascii=False,\n'
                    '    )\n\n'
                    'def format_csv(items) -> str:\n'
                    '    buf = io.StringIO()\n'
                    '    w = csv.writer(buf, lineterminator="\\n")\n'
                    '    w.writerow(["sku", "name", "category", "qty"])\n'
                    '    for i in items:\n'
                    '        w.writerow([i.sku, i.name, i.category, i.qty])\n'
                    '    return buf.getvalue().rstrip("\\n")\n\n'
                    'def main(argv: list[str] | None = None) -> int:\n'
                    '    parser = argparse.ArgumentParser(prog="inventory")\n'
                    '    parser.add_argument("data_file", type=Path)\n'
                    '    parser.add_argument("--include-zero", action="store_true")\n'
                    '    parser.add_argument("--category", default=None)\n'
                    '    parser.add_argument("--format", choices=["json", "csv"], default="json")\n'
                    '    args = parser.parse_args(argv)\n'
                    '    items = filter_items(load_items(args.data_file), include_zero=args.include_zero, category=args.category)\n'
                    '    print(format_csv(items) if args.format == "csv" else format_json(items))\n'
                    '    return 0\n'
                )
                extra_test = (
                    '\n    def test_category_filter(self):\n'
                    '        with tempfile.TemporaryDirectory() as tmp:\n'
                    '            p = self._write_sample(tmp)\n'
                    '            buf = io.StringIO()\n'
                    '            with redirect_stdout(buf):\n'
                    '                main([str(p), "--category", "books"])\n'
                    '            self.assertEqual([r["sku"] for r in json.loads(buf.getvalue())], ["B1"])\n'
                    '\n    def test_csv_export(self):\n'
                    '        with tempfile.TemporaryDirectory() as tmp:\n'
                    '            p = self._write_sample(tmp)\n'
                    '            buf = io.StringIO()\n'
                    '            with redirect_stdout(buf):\n'
                    '                main([str(p), "--include-zero", "--format", "csv"])\n'
                    '            self.assertIn(\'"Mouse, Wireless"\', buf.getvalue())\n'
                )
                payload = json.dumps({"store": store_src, "cli": cli_src, "extra": extra_test})
                patch_cmd = (
                    f"{sys.executable} - <<'PY'\n"
                    f"import json\nfrom pathlib import Path\n"
                    f"data = json.loads({payload!r})\n"
                    "Path('inventory/store.py').write_text(data['store'], encoding='utf-8')\n"
                    "Path('inventory/cli.py').write_text(data['cli'], encoding='utf-8')\n"
                    "t = Path('tests/test_inventory.py')\n"
                    "t.write_text(t.read_text(encoding='utf-8') + data['extra'], encoding='utf-8')\n"
                    "PY"
                )
                return self._call(step, patch_cmd), 260
            if step == 2:
                return self._call(step, f"{sys.executable} -m unittest discover -s tests -v"), 60
            return self._final("Implementados filtro --category, salida --format csv y pruebas."), 85

        if "logparser/parser.py" in prompt:
            if step == 0:
                return self._call(step, f"{sys.executable} -m unittest discover -s tests -v"), 70
            if step == 1:
                patch_cmd = (
                    f"{sys.executable} - <<'PY'\n"
                    "from pathlib import Path\n"
                    "Path('logparser/parser.py').write_text('''import re\n\n"
                    "def parse_duration(spec: str) -> int:\n"
                    "    text = spec.strip()\n"
                    "    if not text:\n"
                    "        raise ValueError(\"empty duration\")\n"
                    "    m = re.fullmatch(r\"(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?\", text)\n"
                    "    if not m or not any(m.groups()):\n"
                    "        raise ValueError(f\"invalid duration: {spec}\")\n"
                    "    h, mi, s = (int(g or 0) for g in m.groups())\n"
                    "    return h * 3600 + mi * 60 + s\n\n"
                    "def parse_kv_line(line: str) -> dict[str, str]:\n"
                    "    result: dict[str, str] = {}\n"
                    "    for token in line.strip().split():\n"
                    "        if \"=\" not in token:\n"
                    "            raise ValueError(f\"invalid token: {token}\")\n"
                    "        key, value = token.split(\"=\", 1)\n"
                    "        if not key:\n"
                    "            raise ValueError(f\"invalid token: {token}\")\n"
                    "        result[key] = value\n"
                    "    return result\n''')\n"
                    "PY"
                )
                return self._call(step, patch_cmd), 190
            if step == 2:
                return self._call(step, f"{sys.executable} -m unittest discover -s tests -v"), 60
            return self._final("Corregidos parse_duration y parse_kv_line; suite en verde."), 80

        # T5 multi-turno
        if "Sin editar nada todavía" in prompt:
            if step == 0:
                return self._call(step, "cat ledger/account.py ledger/report.py"), 70
            return self._final("Módulos: ledger/account.py (Account) y ledger/report.py (total_balance)."), 80
        if "transfer(source, target, amount)" in prompt:
            if step == 0:
                patch_cmd = (
                    f"{sys.executable} - <<'PY'\n"
                    "from pathlib import Path\n"
                    "p = Path('ledger/account.py')\n"
                    "p.write_text(p.read_text() + '''\n\ndef transfer(source: Account, target: Account, amount: int) -> None:\n"
                    "    if source is target:\n"
                    "        raise ValueError(\"same account\")\n"
                    "    if amount <= 0:\n"
                    "        raise ValueError(\"amount must be positive\")\n"
                    "    source.withdraw(amount)\n"
                    "    target.deposit(amount)\n''')\n"
                    "t = Path('tests/test_ledger.py')\n"
                    "t.write_text(t.read_text() + '''\n    def test_transfer(self):\n"
                    "        from ledger.account import transfer\n"
                    "        a, b = Account(\"a\", 100), Account(\"b\", 20)\n"
                    "        transfer(a, b, 30)\n"
                    "        self.assertEqual((a.balance, b.balance), (70, 50))\n''')\n"
                    "PY"
                )
                return self._call(step, patch_cmd), 150
            if step == 1:
                return self._call(step, f"{sys.executable} -m unittest discover -s tests -v"), 60
            return self._final("Añadida transfer() con validaciones y pruebas."), 70
        if "summary_by_tag" in prompt:
            if step == 0:
                patch_cmd = (
                    f"{sys.executable} - <<'PY'\n"
                    "from pathlib import Path\n"
                    "p = Path('ledger/report.py')\n"
                    "p.write_text(p.read_text() + '''\n\ndef summary_by_tag(entries) -> dict[str, int]:\n"
                    "    totals: dict[str, int] = {}\n"
                    "    for entry in entries:\n"
                    "        tag = entry[\"tag\"]\n"
                    "        totals[tag] = totals.get(tag, 0) + entry[\"amount\"]\n"
                    "    return dict(sorted(totals.items()))\n''')\n"
                    "t = Path('tests/test_ledger.py')\n"
                    "t.write_text(t.read_text() + '''\n    def test_summary_by_tag(self):\n"
                    "        from ledger.report import summary_by_tag\n"
                    "        out = summary_by_tag([{\"tag\": \"b\", \"amount\": 2}, {\"tag\": \"a\", \"amount\": 3}])\n"
                    "        self.assertEqual(list(out.items()), [(\"a\", 3), (\"b\", 2)])\n''')\n"
                    "PY"
                )
                return self._call(step, patch_cmd), 150
            if step == 1:
                return self._call(step, f"{sys.executable} -m unittest discover -s tests -v"), 60
            return self._final("Añadida summary_by_tag() ordenada alfabéticamente; todas las pruebas pasan."), 75

        return self._final("OK"), 20

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)


# ---------------------------------------------------------------------------
# Modo 2: Ejecución reproducible del benchmark contra HarnessServer
# ---------------------------------------------------------------------------

def _run_single_task(
    task: BenchmarkTask,
    session,
    raw_client: ChatGPTClient,
    wire: InstrumentedHttp,
    model: str,
    effort: str,
    limits: AgentLimits,
    turn_timeout: float,
    on_progress: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    client = InstrumentedClient(raw_client, wire)
    with tempfile.TemporaryDirectory(prefix=f"as-bench-{task.task_id}-") as tmp:
        root = Path(tmp)
        history_dir = root / "history"
        workspace = root / "workspace"
        workspace.mkdir()
        baseline = task.setup(workspace)

        seen_running_calls: set[str] = set()

        def _on_event(ev: dict[str, Any]) -> None:
            if not on_progress:
                return
            kind = ev.get("type")
            data = ev.get("data") or {}
            if kind == "tool.updated":
                call = data.get("call") or {}
                call_id = call.get("id") or ""
                if call.get("status") == "running" and call_id not in seen_running_calls:
                    seen_running_calls.add(call_id)
                    cmd = (call.get("command") or "").replace("\n", " ")[:68]
                    on_progress(f"  [{task.task_id}] shell → {cmd}")

        collector = EventCollector(on_event=_on_event)
        server = HarnessServer(
            history_dir, collector, session, client, model=model,
            workspace=workspace, usage_reader=object(), limits=limits,
        )
        server._refresh_account()
        if not server.authenticated or not server.models:
            raise RuntimeError("La sesión no está autenticada o no devolvió modelos disponibles.")
        selected_model = model or server.model
        if model or effort:
            req = {"type": "model.select", "model": selected_model}
            if effort:
                req["reasoning_effort"] = effort
            server.handle(req)
        server.handle({"type": "project.create", "name": task.task_id, "workdir": str(workspace)})

        started = time.perf_counter()
        turn_statuses: list[str] = []
        turn_errors: list[str] = []
        final_texts: list[str] = []
        try:
            for turn_idx, prompt in enumerate(task.prompts, start=1):
                if on_progress:
                    on_progress(f"[{task.task_id}] turno {turn_idx}/{len(task.prompts)} iniciando…")
                server.handle({"type": "chat.send", "prompt": prompt})
                finished = collector.wait_for("chat.finished", timeout=turn_timeout)
                turn_statuses.append(finished.get("status", "unknown"))
                if finished.get("status") != "completed":
                    turn_errors.append(finished.get("message", ""))
                    break
                if server.conversation:
                    assistant_msgs = [
                        m["text"] for m in server.conversation.get("messages", [])
                        if m.get("role") == "assistant" and m.get("text")
                    ]
                    if assistant_msgs:
                        final_texts.append(assistant_msgs[-1])
        finally:
            server._stream.cancel()
            server._shell_control.cancel()
            for worker in list(server._workers):
                worker.join(timeout=5)

        duration_ms = round((time.perf_counter() - started) * 1000.0, 1)
        verified = task.verify(workspace, final_texts, baseline)
        # Si algún turno falló/interrumpió, nunca se considera aprobado aunque haya dejado archivos.
        if any(status != "completed" for status in turn_statuses):
            verified["passed"] = False
            verified["summary"] = f"turno incompleto: {turn_statuses}"

        steps = list(client.steps)
        metrics = summarize_steps(steps)
        if on_progress:
            badge = "PASS" if verified["passed"] else "FAIL"
            on_progress(
                f"[{task.task_id}] {badge} · calls={metrics['model_calls']} "
                f"uncached={metrics['uncached_input_tokens']:,} "
                f"hit2+={metrics['followup_cache_hit_rate']}% · {duration_ms/1000:.1f}s"
            )
        return {
            "task_id": task.task_id,
            "title": task.title,
            "category": task.category,
            "turns_configured": len(task.prompts),
            "turn_statuses": turn_statuses,
            "turn_errors": [e for e in turn_errors if e],
            "duration_ms": duration_ms,
            "verified": verified,
            "metrics": metrics,
            "steps": steps,
        }


def run_benchmark(
    *,
    live: bool = False,
    suite: str = "quick",
    task_ids: list[str] | None = None,
    model: str = "",
    effort: str = "",
    label: str = "",
    session_root: Path | None = None,
    check_quota: bool = True,
    turn_timeout: float = 900.0,
    limits: AgentLimits | None = None,
    on_progress: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    tasks = select_tasks(suite=suite, task_ids=task_ids)
    effective_limits = limits or AgentLimits.from_environment()
    git = git_metadata(PROJECT_ROOT)

    if live:
        from harness.core.paths import default_session_root
        xdg_session = default_session_root()
        s_root = session_root or (
            xdg_session if (xdg_session / "session.json").exists() else (PROJECT_ROOT / ".runtime" / "session")
        )
        session = ChatGPTSession(s_root)
        account = session.account()
        if not account.get("authenticated"):
            raise RuntimeError(
                f"No hay sesión autenticada en {s_root}. Conecta tu cuenta en Agent Shell primero."
            )
        wire = InstrumentedHttp(HttpClient())
        raw_client = ChatGPTClient(session, http=wire)
        quota_before = read_quota_snapshot(account.get("email", "")) if check_quota else None
        results = [
            _run_single_task(
                task, session, raw_client, wire, model, effort, effective_limits,
                turn_timeout, on_progress=on_progress,
            )
            for task in tasks
        ]
        quota_after = read_quota_snapshot(account.get("email", "")) if check_quota else None
        quota_delta = compute_quota_delta(quota_before, quota_after)
        resolved_model = (
            model or next((r["steps"][0]["model"] for r in results if r["steps"]), "")
        )
        mode = "live"
    else:
        with MockBenchmarkService() as mock_srv:
            session = _MockSession()
            wire = InstrumentedHttp(HttpClient(allow_loopback=True, timeout=10))
            raw_client = ChatGPTClient(session, http=wire, base_url=mock_srv.url)
            results = [
                _run_single_task(
                    task, session, raw_client, wire, model or "mock-model", effort,
                    effective_limits, turn_timeout=60.0, on_progress=on_progress,
                )
                for task in tasks
            ]
        quota_delta = {"available": False}
        resolved_model = model or "mock-model"
        mode = "mock"

    return {
        "schema_version": 1,
        "app_version": get_version(),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "mode": mode,
        "label": label,
        "suite": "custom" if task_ids else suite,
        "model": resolved_model,
        "reasoning_effort": effort,
        "limits": {
            "max_steps": effective_limits.max_steps,
            "max_tool_calls": effective_limits.max_tool_calls,
            "shell_timeout": effective_limits.shell_timeout,
            "context_output_chars": effective_limits.context_output_chars,
            "max_turn_tokens": effective_limits.max_turn_tokens,
            "repeated_failures": effective_limits.repeated_failures,
        },
        "git": git,
        "quota_delta": quota_delta,
        "summary": summarize_run(results),
        "tasks": results,
    }


def save_report(report: dict[str, Any], destination: Path | None = None) -> Path:
    if destination is None:
        out_dir = PROJECT_ROOT / ".runtime" / "benchmarks"
        out_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        safe_label = "".join(c if c.isalnum() or c in "-_" else "-" for c in (report.get("label") or report.get("mode", "run")))
        destination = out_dir / f"{stamp}-{safe_label}.json"
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return destination
