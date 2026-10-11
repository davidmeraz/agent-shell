"""Eventos de la interfaz: un objeto JSON por línea; stdout nunca contiene logs."""

import json
import threading
from datetime import datetime, timezone
from typing import Any, TextIO


class EventEmitter:
    """Serializa eventos de varios hilos sin mezclar líneas ni números de secuencia."""

    def __init__(self, output: TextIO) -> None:
        self.output = output
        self._lock = threading.Lock()
        self._sequence = 0

    def emit(self, event_type: str, run_id: str | None = None, **data: Any) -> None:
        with self._lock:
            self._sequence += 1
            event = {
                "version": 1,
                "seq": self._sequence,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "type": event_type,
                "run_id": run_id,
                "data": data,
            }
            self.output.write(json.dumps(event, ensure_ascii=False) + "\n")
            self.output.flush()
