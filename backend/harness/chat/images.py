"""Una imagen por mensaje: URL de datos validada, sin rutas ni URLs remotas."""

import base64
import binascii
import io
import warnings

from PIL import Image

MAX_IMAGE_BYTES = 4 * 1024 * 1024
MAX_PIXELS = 16_000_000
MAX_IMAGE_URL = (MAX_IMAGE_BYTES + 2) // 3 * 4 + 64
MIME_FORMATS = {"image/png": "PNG", "image/jpeg": "JPEG", "image/webp": "WEBP"}


def validate_image(value: str) -> str:
    if not isinstance(value, str) or len(value) > MAX_IMAGE_URL:
        raise ValueError("La imagen puede ocupar como máximo 4 MiB")
    header, separator, encoded = value.partition(",")
    mime = header.removeprefix("data:").removesuffix(";base64")
    if not separator or header != f"data:{mime};base64" or mime not in MIME_FORMATS:
        raise ValueError("Adjunta una imagen PNG, JPEG o WebP")
    try:
        raw = base64.b64decode(encoded, validate=True)
        if not raw or len(raw) > MAX_IMAGE_BYTES:
            raise ValueError("La imagen puede ocupar como máximo 4 MiB")
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as image:
                if image.format != MIME_FORMATS[mime] or image.width * image.height > MAX_PIXELS:
                    raise ValueError("La imagen debe tener como máximo 16 megapíxeles")
                image.verify()
    except (OSError, binascii.Error, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ValueError("La imagen está dañada o es demasiado grande") from None
    return f"data:{mime};base64," + base64.b64encode(raw).decode("ascii")


def user_content(text: str, image: str = ""):
    if not image:
        return text
    content = [{"type": "input_text", "text": text}] if text else []
    return content + [{"type": "input_image", "image_url": image, "detail": "auto"}]
