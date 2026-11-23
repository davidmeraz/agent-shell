"""Versión de la aplicación leída desde pyproject.toml o metadatos del paquete instalado.

El protocolo NDJSON tiene su propia versión; cambiar la versión del proyecto
no implica cambiar el formato de sus eventos.
"""

from importlib import metadata as importlib_metadata
from pathlib import Path
import tomllib


def get_version() -> str:
    """Obtiene la versión declarada del proyecto sin mantener copias en Python o QML."""
    manifest = Path(__file__).resolve().parents[3] / "pyproject.toml"
    if manifest.is_file():
        with manifest.open("rb") as source:
            return tomllib.load(source)["project"]["version"]
    return importlib_metadata.version("agent-shell")
