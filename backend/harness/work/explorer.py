"""Explorador de solo lectura: listado perezoso y texto acotado dentro del proyecto.

No sigue enlaces simbólicos. El sondeo de la interfaz sólo consulta carpetas
expandidas; no observa ni indexa todo el árbol y no atribuye cambios a la IA.
"""

import os
import stat
from pathlib import Path

EXCLUDED = {".git", ".venv", "venv", "node_modules", "__pycache__", ".runtime"}
MAX_ENTRIES = 1000
MAX_PREVIEW = 128 * 1024


class ProjectExplorer:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve(strict=True)

    def _open(self, relative: str, directory: bool = False) -> int:
        """Recorre mediante dir_fd: ni una sustitución concurrente sigue symlinks."""
        if not isinstance(relative, str) or len(relative) > 4096 or "\0" in relative:
            raise ValueError("Ruta inválida")
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or any(p in EXCLUDED for p in path.parts):
            raise ValueError("La ruta debe pertenecer a una carpeta visible del proyecto")
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        descriptor = os.open(self.root, flags | os.O_DIRECTORY)
        try:
            for index, part in enumerate(path.parts):
                is_directory = directory or index < len(path.parts) - 1
                child = os.open(part, flags | (os.O_DIRECTORY if is_directory else 0),
                                dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
            return descriptor
        except BaseException:
            os.close(descriptor)
            raise

    def list(self, relative: str) -> dict:
        descriptor = self._open(relative, directory=True)
        entries = []
        truncated = False
        try:
            iterator = os.scandir(descriptor)
        except BaseException:
            os.close(descriptor)
            raise
        try:
            with iterator:
                for entry in iterator:
                    if entry.name in EXCLUDED or entry.is_symlink():
                        continue
                    try:
                        info = entry.stat(follow_symlinks=False)
                    except FileNotFoundError:
                        continue
                    directory = stat.S_ISDIR(info.st_mode)
                    if not directory and not stat.S_ISREG(info.st_mode):
                        continue
                    if len(entries) >= MAX_ENTRIES:
                        truncated = True
                        break
                    entries.append({"name": entry.name,
                                    "path": str(Path(relative) / entry.name),
                                    "directory": directory, "size": info.st_size,
                                    "modified_ns": str(info.st_mtime_ns)})
        finally:
            os.close(descriptor)
        entries.sort(key=lambda row: (not row["directory"], row["name"].casefold()))
        return {"path": relative, "entries": entries, "truncated": truncated}

    def read(self, relative: str) -> dict:
        descriptor = self._open(relative)
        with os.fdopen(descriptor, "rb") as handle:
            if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                raise ValueError("Selecciona un archivo de texto regular")
            payload = handle.read(MAX_PREVIEW + 1)
        if b"\0" in payload:
            raise ValueError("El archivo es binario; no hay vista previa")
        truncated = len(payload) > MAX_PREVIEW
        try:
            text = payload[:MAX_PREVIEW].decode("utf-8", errors="replace" if truncated else "strict")
        except UnicodeError:
            raise ValueError("La vista previa admite texto UTF-8") from None
        return {"path": relative, "text": text, "truncated": truncated}
