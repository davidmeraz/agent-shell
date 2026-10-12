"""Observación Linux acotada mientras una herramienta de IA trabaja en Work.

inotify informa cambios del disco, no autoría ni texto futuro del modelo.
Las vistas son instantáneas UTF-8 confinadas al proyecto por ProjectExplorer.
"""

import ctypes
import os
import select
import stat
import struct
import threading
import time
from pathlib import Path

from .explorer import EXCLUDED, ProjectExplorer

CREATE, DELETE, MODIFY = 0x100, 0x200, 0x2
CLOSE_WRITE, MOVED_FROM, MOVED_TO = 0x8, 0x40, 0x80
ISDIR, IGNORED, OVERFLOW = 0x40000000, 0x8000, 0x4000
MASK = CREATE | DELETE | MODIFY | CLOSE_WRITE | MOVED_FROM | MOVED_TO
MAX_WATCHES, MAX_PENDING, MAX_BATCH = 1024, 512, 16
INTERVAL = 0.18


class ProjectActivity:
    def __init__(self, root: Path, emit, ignored: tuple[Path, ...] = ()) -> None:
        self.explorer = ProjectExplorer(root)
        self.ignored = [str(path.resolve().relative_to(self.explorer.root)) for path in ignored
                        if path.resolve().is_relative_to(self.explorer.root)]
        self.emit = emit
        self.fd = -1
        self.watches = {}
        self.pending = {}
        self.sequence = 0
        self.limited = False
        self.stopped = threading.Event()
        self.thread = None
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.libc.inotify_init1.argtypes = [ctypes.c_int]
        self.libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]

    def __enter__(self):
        try:
            self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
            if self.fd < 0:
                raise OSError(ctypes.get_errno(), "inotify no disponible")
            self._watch_tree("", announce=False)
            if not self.watches:
                raise OSError("No se pudo observar el proyecto")
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()
        except (OSError, ValueError):
            self.emit({"action": "notice", "message": "Seguimiento en vivo no disponible; se conserva la actualización periódica."})
        return self

    def __exit__(self, *_):
        self.stopped.set()
        if self.thread:
            self.thread.join()
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1

    def _queue(self, path, action, directory):
        if any(path == prefix or path.startswith(prefix + "/") for prefix in self.ignored):
            return
        if len(self.pending) >= MAX_PENDING and path not in self.pending:
            self.limited = True
            return
        previous = self.pending.get(path)
        if previous and previous["action"] == "created" and action == "modified":
            action = "created"
        self.pending[path] = {"path": path, "action": action, "directory": directory}

    def _watch_tree(self, relative, announce):
        queue = [relative]
        seen = set(self.watches.values())
        while queue:
            path = queue.pop()
            if path in seen:
                continue
            if len(self.watches) >= MAX_WATCHES:
                self.limited = True
                break
            try:
                descriptor = self.explorer._open(path, directory=True)
                try:
                    watch = self.libc.inotify_add_watch(self.fd, os.fsencode(f"/proc/self/fd/{descriptor}"), MASK)
                finally:
                    os.close(descriptor)
                if watch < 0:
                    self.limited = True
                    continue
                self.watches[watch] = path
                seen.add(path)
                result = self.explorer.list(path)
                self.limited |= result["truncated"]
                for entry in result["entries"]:
                    if any(entry["path"] == prefix or entry["path"].startswith(prefix + "/") for prefix in self.ignored):
                        continue
                    if announce:
                        self._queue(entry["path"], "created", entry["directory"])
                    if entry["directory"]:
                        queue.append(entry["path"])
            except (OSError, ValueError):
                continue

    def _drain(self):
        # Una ráfaga enorme no impide cancelar ni terminar el comando.
        for _ in range(16):
            try:
                data = os.read(self.fd, 65536)
            except BlockingIOError:
                return
            offset = 0
            while offset + 16 <= len(data):
                watch, mask, _, length = struct.unpack_from("iIII", data, offset)
                name = os.fsdecode(data[offset + 16:offset + 16 + length].split(b"\0", 1)[0])
                offset += 16 + length
                if mask & OVERFLOW:
                    self.limited = True
                if mask & IGNORED:
                    self.watches.pop(watch, None)
                    continue
                parent = self.watches.get(watch)
                if parent is None or not name or name in EXCLUDED:
                    continue
                path = str(Path(parent) / name)
                directory = bool(mask & ISDIR)
                action = "deleted" if mask & (DELETE | MOVED_FROM) else "created" if mask & (CREATE | MOVED_TO) else "modified"
                self._queue(path, action, directory)
                if directory and mask & (CREATE | MOVED_TO):
                    self._watch_tree(path, announce=True)
                if directory and mask & (DELETE | MOVED_FROM):
                    for key, value in list(self.watches.items()):
                        if value == path or value.startswith(path + "/"):
                            self.libc.inotify_rm_watch(self.fd, key)
                            self.watches.pop(key, None)

    def _flush(self, final=False):
        count = len(self.pending) if final else min(MAX_BATCH, len(self.pending))
        for _ in range(count):
            path = next(iter(self.pending))
            change = self.pending.pop(path)
            if change["action"] != "deleted":
                # Descarta enlaces, archivos especiales y rutas que ya desaparecieron.
                try:
                    descriptor = self.explorer._open(path, directory=change["directory"])
                    try:
                        mode = os.fstat(descriptor).st_mode
                        if not (stat.S_ISDIR(mode) if change["directory"] else stat.S_ISREG(mode)):
                            continue
                    finally:
                        os.close(descriptor)
                except (OSError, ValueError):
                    continue
                if not change["directory"]:
                    try:
                        change["preview"] = self.explorer.read(path)
                    except (OSError, ValueError):
                        pass
            self.sequence += 1
            self.emit({**change, "sequence": self.sequence})
        if self.limited:
            self.emit({"action": "notice", "message": "Seguimiento parcial: se alcanzó un límite del observador. Las vistas siguen actualizándose."})
            self.limited = False

    def _run(self):
        last = time.monotonic()
        try:
            while not self.stopped.is_set():
                if select.select([self.fd], [], [], .05)[0]:
                    self._drain()
                if time.monotonic() - last >= INTERVAL:
                    self._flush()
                    last = time.monotonic()
            self._drain()
            self._flush(final=True)
        except (OSError, ValueError):
            self.emit({"action": "notice", "message": "El seguimiento en vivo se interrumpió; las vistas siguen actualizándose."})
