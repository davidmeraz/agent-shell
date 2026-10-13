"""Rutas del proyecto y acceso al backend desde el paquete de pruebas."""

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
BACKEND = PROJECT / "backend"
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))
