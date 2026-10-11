"""Mediciones locales por turno; nunca almacenan texto ni credenciales."""

import math
import time
from datetime import datetime, timezone


NUMBER_FIELDS = (
    "elapsed_ms", "total_ms", "first_text_ms", "prepare_ms", "session_ms",
    "headers_ms", "request_first_text_ms", "stream_ms", "characters",
    "characters_per_second", "input_characters", "context_messages",
    "first_visible_ms", "ui_frame_ms",
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

    def mark(self, phase: str) -> None:
        self.phases.setdefault(phase, self.clock())

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
        rate = None
        if (self.first_text is not None and self.last_text is not None
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
            "input_characters": self.input_characters, "context_messages": self.context_messages,
            "first_visible_ms": self.frontend.get("first_visible_ms"),
            "ui_frame_ms": self.frontend.get("ui_frame_ms"), "usage": self.usage,
        }
