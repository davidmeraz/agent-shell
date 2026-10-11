"""Mediciones locales por turno; nunca almacenan texto ni credenciales."""

import math
import time
from datetime import datetime, timezone


NUMBER_FIELDS = (
    "elapsed_ms", "total_ms", "first_text_ms", "prepare_ms", "session_ms",
    "headers_ms", "request_first_text_ms", "stream_ms", "characters",
    "characters_per_second", "input_characters", "context_messages",
    "first_visible_ms", "ui_frame_ms",
    "model_calls", "tool_calls", "tool_ms", "approval_ms",
    "context_tokens", "model_request_ms", "tokens_per_second",
)
STATUSES = ("streaming", "completed", "failed", "interrupted")


def nonnegative(value) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def safe_usage(value) -> dict | None:
    if not isinstance(value, dict):
        return None
    result = {key: value[key] for key in ("input_tokens", "output_tokens", "total_tokens")
              if type(value.get(key)) is int and value[key] >= 0}
    for group, key in (("output_tokens_details", "reasoning_tokens"),
                       ("input_tokens_details", "cached_tokens")):
        detail = value.get(group)
        if isinstance(detail, dict) and type(detail.get(key)) is int and detail[key] >= 0:
            result[key] = detail[key]
    return result or None


def safe_measurement(value) -> dict | None:
    """Un dato opcional dañado no impide recuperar los mensajes de un chat viejo."""
    if not isinstance(value, dict) or value.get("status") not in STATUSES:
        return None
    if not all(isinstance(value.get(key), str) and value[key]
               for key in ("turn_id", "model", "started_at")):
        return None
    result = {key: value[key] for key in ("turn_id", "model", "started_at", "status")}
    for key in NUMBER_FIELDS:
        result[key] = value.get(key) if nonnegative(value.get(key)) else None
    context = value.get("context_tokens")
    result["context_tokens"] = context if type(context) is int and context >= 0 else None
    # Los campos ya aplanados se vuelven a filtrar, sin conservar diagnósticos del proveedor.
    usage = value.get("usage")
    result["usage"] = None
    if isinstance(usage, dict):
        result["usage"] = {key: usage[key] for key in
                           ("input_tokens", "output_tokens", "total_tokens", "reasoning_tokens", "cached_tokens")
                           if type(usage.get(key)) is int and usage[key] >= 0} or None
    return result


class TurnPerformance:
    def __init__(self, turn_id: str, model: str, started: float, clock=None) -> None:
        self.clock = clock or time.perf_counter
        self.started = started
        self.phases: dict[str, float] = {}
        self.parts: dict[str, str] = {}
        self.first_text: float | None = None
        self.last_text: float | None = None
        self.first_characters = 0
        self.finished: float | None = None
        self.status = "streaming"
        self.usage = None
        self.frontend: dict = {}
        self.turn_id, self.model = turn_id, model
        self.started_at = datetime.now(timezone.utc).isoformat()
        self.input_characters, self.context_messages = 0, 0
        self.model_calls, self.tool_calls = 0, 0
        self.tool_ms, self.approval_ms = 0.0, 0.0
        self.context_tokens = None
        self._call_active = False
        self._request_started = None
        self._received_calls = 0
        self._timed_calls = 0
        self._usage_calls = 0
        self._model_request_seconds = 0.0
        self._output_tokens = 0

    def begin_model_call(self) -> None:
        self.model_calls += 1
        self.context_tokens = None
        self._call_active = True
        self._request_started = None

    def _end_request(self, ended: float) -> None:
        if self._request_started is not None:
            self._model_request_seconds += max(0, ended - self._request_started)
            self._timed_calls += 1
        self._request_started = None
        self._call_active = False

    def complete_model_call(self, value) -> None:
        if not self._call_active:
            return
        self._end_request(self.clock())
        self._received_calls += 1
        usage = safe_usage(value)
        self.context_tokens = usage.get("input_tokens") if usage else None
        if usage and "output_tokens" in usage:
            self._usage_calls += 1
            self._output_tokens += usage["output_tokens"]
        self.add_usage(value)

    def add_usage(self, value) -> None:
        usage = safe_usage(value)
        if usage:
            self.usage = self.usage or {}
            for key, count in usage.items():
                self.usage[key] = self.usage.get(key, 0) + count

    def mark(self, phase: str) -> None:
        now = self.clock()
        self.phases.setdefault(phase, now)
        if phase == "request" and self._call_active and self._request_started is None:
            self._request_started = now

    def text(self, item_id: str, text: str) -> None:
        before = self.parts.get(item_id, "")
        self.parts[item_id] = text
        if text and text != before:
            self.last_text = self.clock()
            if self.first_text is None:
                self.first_text = self.last_text
                self.first_characters = self.characters

    @property
    def characters(self) -> int:
        return sum(len(text) for text in self.parts.values())

    def finish(self, status: str) -> None:
        self.status, self.finished = status, self.clock()
        if self._call_active:
            self._end_request(self.finished)

    def presented(self, first_visible_ms, ui_frame_ms) -> bool:
        if (self.first_text is None or self.frontend or not nonnegative(first_visible_ms)
                or not nonnegative(ui_frame_ms) or ui_frame_ms > first_visible_ms
                or first_visible_ms > 86400000):
            return False
        self.frontend = {"first_visible_ms": first_visible_ms, "ui_frame_ms": ui_frame_ms}
        return True

    def snapshot(self) -> dict:
        end = self.finished if self.finished is not None else self.clock()

        def duration(start, stop):
            return round(max(0, stop - start) * 1000, 3) if start is not None and stop is not None else None

        request = self.phases.get("request")
        token_rate = None
        if (self.status == "completed" and self.model_calls > 0
                and self._received_calls == self._timed_calls == self._usage_calls == self.model_calls
                and self._model_request_seconds >= 0.1):
            token_rate = round(self._output_tokens / self._model_request_seconds, 2)
        rate = None
        if (not self.tool_calls and self.first_text is not None and self.last_text is not None
                and self.last_text - self.first_text >= 0.1
                and self.characters > self.first_characters):
            rate = round((self.characters - self.first_characters) / (self.last_text - self.first_text), 2)
        return {
            "turn_id": self.turn_id, "model": self.model, "started_at": self.started_at,
            "status": self.status, "elapsed_ms": duration(self.started, end),
            "total_ms": duration(self.started, self.finished),
            "first_text_ms": duration(self.started, self.first_text),
            "prepare_ms": duration(self.started, self.phases.get("prepared")),
            "session_ms": duration(self.phases.get("session_start"), self.phases.get("session_end")),
            "headers_ms": duration(request, self.phases.get("headers")),
            "request_first_text_ms": duration(request, self.first_text),
            "stream_ms": duration(self.first_text, end) if self.first_text is not None else None,
            "characters": self.characters, "characters_per_second": rate,
            "model_calls": self.model_calls, "tool_calls": self.tool_calls,
            "context_tokens": self.context_tokens,
            "model_request_ms": round(self._model_request_seconds * 1000, 3) if self._timed_calls else None,
            "tokens_per_second": token_rate,
            "tool_ms": round(self.tool_ms, 3), "approval_ms": round(self.approval_ms, 3),
            "input_characters": self.input_characters, "context_messages": self.context_messages,
            "first_visible_ms": self.frontend.get("first_visible_ms"),
            "ui_frame_ms": self.frontend.get("ui_frame_ms"), "usage": self.usage,
        }
