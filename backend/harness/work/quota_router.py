"""Quota-aware worker selection: picks the cheapest provider with available quota."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from ..core.http import StreamControl
from .worker import WorkerResult, WorkerRouter, _is_quota_error


WORKER_PRIORITY: list[tuple[str, str, int]] = [
    ("agy",     "gemini-2.5-flash",   1),
    ("claude",  "claude-haiku",        2),
    ("chatgpt", "gpt-4.1-mini",       3),
    ("agy",     "gemini-2.5-pro",     4),
    ("claude",  "claude-sonnet",       5),
    ("chatgpt", "gpt-4.1",            6),
]


class QuotaExhausted(Exception):
    """All providers have exhausted their quota."""


class QuotaAwareRouter:
    """Wraps WorkerRouter with automatic provider/model selection and fallback."""

    def __init__(
        self,
        worker_router: WorkerRouter,
        priority: list[tuple[str, str, int]] | None = None,
        config_path: Path | None = None,
    ) -> None:
        self.router = worker_router
        self._exhausted: set[str] = set()
        self._exhausted_at: dict[str, float] = {}
        self._cooldown = 300.0
        self._priority = priority or self._load_priority(config_path)

    @staticmethod
    def _load_priority(config_path: Path | None) -> list[tuple[str, str, int]]:
        if config_path is not None:
            path = config_path / "worker_priority.json"
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(data, list):
                    return [(r[0], r[1], r[2]) for r in data
                            if isinstance(r, (list, tuple)) and len(r) >= 3]
            except (OSError, json.JSONDecodeError, KeyError, IndexError):
                pass
        return list(WORKER_PRIORITY)

    def _is_available(self, provider: str) -> bool:
        if provider == "agy":
            return bool(self.router.agy and self.router.agy.is_available())
        if provider == "claude":
            return bool(self.router.claude)
        if provider == "chatgpt":
            return bool(self.router.chatgpt)
        return False

    def _is_exhausted(self, provider: str) -> bool:
        if provider not in self._exhausted:
            return False
        cooldown_at = self._exhausted_at.get(provider, 0)
        if time.monotonic() - cooldown_at > self._cooldown:
            self._exhausted.discard(provider)
            self._exhausted_at.pop(provider, None)
            return False
        return True

    def select_worker(
        self,
        preferred_provider: str = "",
        preferred_model: str = "",
    ) -> tuple[str, str]:
        if preferred_provider and self._is_available(preferred_provider) and not self._is_exhausted(preferred_provider):
            return preferred_provider, preferred_model or self._cheapest_model(preferred_provider)

        for provider, model, _cost in self._priority:
            if self._is_available(provider) and not self._is_exhausted(provider):
                return provider, model

        raise QuotaExhausted("All providers have exhausted their available quota.")

    def _cheapest_model(self, provider: str) -> str:
        for p, model, _cost in self._priority:
            if p == provider:
                return model
        if provider == "agy":
            return "gemini-2.5-flash"
        if provider == "claude":
            return "claude-haiku"
        return "gpt-4.1-mini"

    def run(
        self,
        task: str,
        control: StreamControl,
        preferred_provider: str = "",
        preferred_model: str = "",
        max_steps: int = 16,
        max_retries: int = 2,
    ) -> WorkerResult:
        last_result: WorkerResult | None = None
        for attempt in range(max_retries + 1):
            try:
                provider, model = self.select_worker(preferred_provider, preferred_model)
            except QuotaExhausted:
                if last_result is not None:
                    return last_result
                return WorkerResult(
                    status="quota_exhausted",
                    error="All providers have exhausted their available quota.",
                )

            result = self.router.run(task, provider, model, control, max_steps)

            if result.status == "quota_exhausted":
                self._exhausted.add(provider)
                self._exhausted_at[provider] = time.monotonic()
                self.router._emit("worker.fallback",
                                  from_provider=provider, to_provider="auto",
                                  reason="quota exhausted")
                last_result = result
                preferred_provider = ""
                preferred_model = ""
                continue

            return result

        return last_result or WorkerResult(
            status="quota_exhausted",
            error="Exhausted all retry attempts across providers.",
        )

    def reset_exhausted(self, provider: str = "") -> None:
        if provider:
            self._exhausted.discard(provider)
            self._exhausted_at.pop(provider, None)
        else:
            self._exhausted.clear()
            self._exhausted_at.clear()
