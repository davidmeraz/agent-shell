"""Lectura binaria del portapapeles Linux con timeout y salida acotada.

Wayland usa wl-paste; X11 usa xclip. Nunca ejecuta texto del portapapeles.
La ausencia de imagen permite que Qt siga pegando texto de forma nativa.
"""

import base64
import os
import selectors
import shutil
import subprocess
import time

from .images import MAX_IMAGE_BYTES, MIME_FORMATS, validate_image


def _capture(command: list[str], limit: int) -> bytes:
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL)
    payload = bytearray()
    deadline = time.monotonic() + 3
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while selector.get_map():
                if time.monotonic() > deadline:
                    raise ValueError("El portapapeles no respondió a tiempo")
                for key, _ in selector.select(0.05):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                    else:
                        payload.extend(chunk)
                        if len(payload) > limit:
                            raise ValueError("La imagen del portapapeles supera 4 MiB")
        process.wait(timeout=max(0.01, deadline - time.monotonic()))
        if process.returncode:
            raise ValueError("No se pudo leer el portapapeles")
        return bytes(payload)
    except subprocess.TimeoutExpired:
        raise ValueError("El portapapeles no respondió a tiempo") from None
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def read_clipboard() -> dict:
    if os.environ.get("WAYLAND_DISPLAY"):
        if not shutil.which("wl-paste"):
            raise ValueError("Instala wl-clipboard para pegar imágenes en Wayland")
        types = _capture(["wl-paste", "--list-types"], 16384).decode("utf-8", "replace").splitlines()
        command = lambda mime: ["wl-paste", "--no-newline", "--type", mime]
    elif os.environ.get("DISPLAY"):
        if not shutil.which("xclip"):
            raise ValueError("Instala xclip para pegar imágenes en X11")
        types = _capture(["xclip", "-selection", "clipboard", "-o", "-t", "TARGETS"], 16384).decode("utf-8", "replace").splitlines()
        command = lambda mime: ["xclip", "-selection", "clipboard", "-o", "-t", mime]
    else:
        raise ValueError("No hay un portapapeles gráfico disponible")
    mime = next((mime for mime in MIME_FORMATS if mime in types), None)
    if not mime:
        if any(kind.startswith("image/") for kind in types):
            raise ValueError("El portapapeles debe contener PNG, JPEG o WebP")
        return {"image": ""}
    raw = _capture(command(mime), MAX_IMAGE_BYTES)
    image = validate_image(f"data:{mime};base64," + base64.b64encode(raw).decode("ascii"))
    return {"image": image}
