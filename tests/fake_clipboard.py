"""Imagen PNG determinista para Qt offscreen; nunca lee el portapapeles del usuario."""

IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAYCAIAAAAH5iiXAAAAKUlEQVR4nO3NMREAAAgEILV/gW9rCs8FCtBJ6sO8rGKxWCwWi8Vi8YkFcAUB+5L6LdMAAAAASUVORK5CYII="


def read_clipboard():
    return {"image": IMAGE}
