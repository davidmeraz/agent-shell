"""Versión de la aplicación leída desde su única fuente: pyproject.toml.

El protocolo NDJSON tiene su propia versión; cambiar la versión del proyecto
no implica cambiar el formato de sus eventos.
"""

from pathlib import Path
import tomllib


def get_version() -> str:
    """Obtiene la versión declarada del proyecto sin mantener copias en Python o QML."""
    metadata = Path(__file__).resolve().parents[2] / "pyproject.toml"
    with metadata.open("rb") as source:
        return tomllib.load(source)["project"]["version"]
