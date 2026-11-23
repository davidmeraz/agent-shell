"""Quota-aware delegation: tries ranked workers until one has quota to run the task."""

from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import Callable

from ..core.http import StreamControl
from .roster import Candidate, rank
from .worker import WorkerResult, WorkerRouter

EXHAUSTED_COOLDOWN = 300.0
HANDOFF_NOTE = (
    "\n\nA previous worker ran out of quota while on this task and may have left partial edits. "
    "Inspect the current state of the files before changing them."
)


class QuotaAwareRouter:
    def __init__(self, worker_router: WorkerRouter, clock: Callable[[], float] = time.monotonic) -> None:
        self.router = worker_router
        self._clock = clock
        self._lock = threading.Lock()
        self._exhausted_until: dict[str, float] = {}

    def mark_exhausted(self, bucket: str) -> None:
        with self._lock:
            self._exhausted_until[bucket] = self._clock() + EXHAUSTED_COOLDOWN

    def _available(self, candidate: Candidate) -> bool:
        with self._lock:
            return self._exhausted_until.get(candidate.bucket, 0) <= self._clock()

    def exhausted_buckets(self) -> set[str]:
        with self._lock:
            now = self._clock()
            return {bucket for bucket, until in self._exhausted_until.items() if until > now}

    def candidates(self, roster: list[Candidate], role: str, remaining: dict[str, float],
                   **context: str) -> list[Candidate]:
        return [row for row in rank(roster, role, remaining, **context) if self._available(row)]

    def run_candidates(
        self,
        task: str,
        control: StreamControl,
        candidates: list[Candidate],
        role: str = "builder",
        max_steps: int = 16,
        on_start: Callable[[Candidate], None] = lambda candidate: None,
        progress: Callable[[str], None] = lambda line: None,
        *,
        workspace: Path | None = None,
        shell_timeout: int | None = None,
        context_output_chars: int | None = None,
    ) -> WorkerResult:
        result = WorkerResult(status="quota_exhausted", error="No worker has available quota.")
        prompt = task
        for candidate in candidates:
            control.check()
            if not self._available(candidate):
                continue
            on_start(candidate)
            run_kwargs = {}
            if workspace is not None:
                run_kwargs["workspace"] = workspace
            if shell_timeout is not None:
                run_kwargs["shell_timeout"] = shell_timeout
            if context_output_chars is not None:
                run_kwargs["context_output_chars"] = context_output_chars
            result = self.router.run(prompt, candidate, control, max_steps, progress, role, **run_kwargs)
            if result.status != "quota_exhausted":
                return result
            self.mark_exhausted(candidate.bucket)
            progress(f"{candidate.label}: quota exhausted, trying the next worker")
            if result.tool_calls:
                prompt = task + HANDOFF_NOTE
        return result

    def run(
        self,
        task: str,
        control: StreamControl,
        roster: list[Candidate],
        remaining: dict[str, float],
        role: str = "builder",
        max_steps: int = 16,
        on_start: Callable[[Candidate], None] = lambda candidate: None,
        progress: Callable[[str], None] = lambda line: None,
        **context: str,
    ) -> WorkerResult:
        return self.run_candidates(
            task,
            control,
            self.candidates(roster, role, remaining, **context),
            role=role,
            max_steps=max_steps,
            on_start=on_start,
            progress=progress,
        )
