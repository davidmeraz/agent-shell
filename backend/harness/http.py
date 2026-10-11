"""HTTP verificado y SSE del servicio; los errores nunca incluyen credenciales."""

import http.client
import json
import socket
import ssl
import threading
from urllib.parse import urlsplit


class ServiceError(Exception):
    """Error apto para mostrar al usuario, sin cuerpos HTTP ni tokens."""

    def __init__(self, message: str, status: int = 0, code: str = "") -> None:
        super().__init__(message)
        self.status = status
        self.code = code


class Cancelled(Exception):
    """La operación se interrumpió por solicitud del usuario."""


ERROR_MESSAGES = {
    "invalid_grant": "La sesión caducó. Vuelve a conectar tu cuenta de ChatGPT.",
    "subscription_sharing_usage_limit_exceeded": "Alcanzaste el límite de uso de tu plan para esta aplicación.",
    "subscription_sharing_usage_unavailable": "El uso de tu plan no está disponible. Revisa tu conexión en ChatGPT.",
    "context_length_exceeded": "Esta conversación supera el contexto del modelo. Inicia un nuevo chat.",
    "model_not_found": "El modelo ya no está disponible. Actualiza la cuenta y selecciona otro.",
}


def service_error(status: int = 0, error: dict | None = None) -> ServiceError:
    code = error.get("code", "") if isinstance(error, dict) else ""
    if not isinstance(code, str):
        code = ""
    message = ERROR_MESSAGES.get(code)
    if message is None:
        message = {
            401: "La sesión no es válida. Vuelve a conectar tu cuenta de ChatGPT.",
            403: "Tu cuenta no tiene permiso para esta solicitud. Revisa la autorización de tu plan.",
            429: "Alcanzaste un límite de uso. Espera y revisa el uso de tu plan en ChatGPT.",
        }.get(status, f"El servicio rechazó la solicitud (HTTP {status})." if status else
              "El servicio no pudo completar la respuesta.")
    return ServiceError(message, status, code if code in ERROR_MESSAGES else "")


class StreamControl:
    """Despierta lecturas bloqueadas sin cerrar un BufferedReader desde otro hilo."""

    def __init__(self) -> None:
        self.cancelled = threading.Event()
        self._lock = threading.Lock()
        self._connection: http.client.HTTPConnection | None = None
        self._socket: socket.socket | None = None

    def check(self) -> None:
        if self.cancelled.is_set():
            raise Cancelled()

    def attach(self, connection: http.client.HTTPConnection | None) -> None:
        with self._lock:
            self._connection = connection
            self._socket = connection.sock if connection else None
            if connection is not None:
                self.check()

    def cancel(self) -> None:
        self.cancelled.set()
        with self._lock:
            sock = self._socket or (self._connection.sock if self._connection else None)
            if sock:
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass


class HttpClient:
    """Sin redirecciones automáticas; los tokens sólo van al destino solicitado."""

    def __init__(self, allow_loopback: bool = False, timeout: float = 30) -> None:
        self.allow_loopback = allow_loopback
        self.timeout = timeout

    def _open(self, method: str, url: str, body: bytes | None, headers: dict,
              control: StreamControl | None = None):
        parsed = urlsplit(url)
        if parsed.username or parsed.password or parsed.fragment:
            raise ServiceError("Dirección del servicio inválida")
        if parsed.scheme == "https":
            connection = http.client.HTTPSConnection(
                parsed.hostname, parsed.port, timeout=self.timeout,
                context=ssl.create_default_context(),
            )
        elif self.allow_loopback and parsed.scheme == "http" and parsed.hostname == "127.0.0.1":
            connection = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=self.timeout)
        else:
            raise ServiceError("El servicio requiere una conexión HTTPS")
        try:
            if control:
                control.attach(connection)
            connection.request(method, parsed.path + ("?" + parsed.query if parsed.query else ""),
                               body=body, headers=headers)
            if control:
                # HTTP/1.0 puede separar el socket de connection al leer las cabeceras.
                control.attach(connection)
                control.check()
            response = connection.getresponse()
            if response.status >= 300:
                error = None
                try:
                    payload = json.loads(response.read(65536))
                    error = payload.get("error") if isinstance(payload, dict) else None
                    if isinstance(error, str):
                        error = {"code": error}
                except (ValueError, OSError):
                    pass
                raise service_error(response.status, error)
            return connection, response
        except BaseException:
            connection.close()
            if control:
                control.attach(None)
            raise

    def json(self, method: str, url: str, body: bytes | None = None,
             headers: dict | None = None) -> dict:
        connection = None
        try:
            connection, response = self._open(method, url, body, headers or {})
            payload = response.read(8 * 1024 * 1024 + 1)
            if len(payload) > 8 * 1024 * 1024:
                raise ServiceError("La respuesta del servicio es demasiado grande")
            value = json.loads(payload) if payload else {}
            if not isinstance(value, dict):
                raise ValueError()
            return value
        except (OSError, http.client.HTTPException):
            raise ServiceError("No se pudo conectar con OpenAI. Comprueba tu conexión y vuelve a intentarlo.") from None
        except ValueError:
            raise ServiceError("El servicio devolvió datos incompatibles") from None
        finally:
            if connection:
                connection.close()

    def stream(self, url: str, payload: dict, token: str, control: StreamControl):
        connection = None
        try:
            control.check()
            connection, response = self._open("POST", url, json.dumps(payload).encode("utf-8"), {
                "Content-Type": "application/json", "Accept": "text/event-stream",
                "Authorization": "Bearer " + token,
            }, control)
            content_type = response.getheader("Content-Type", "").split(";")[0].strip().lower()
            # La ruta real puede omitir Content-Type aunque entregue eventos SSE.
            # En ese caso validamos el cuerpo con read_sse y el evento terminal.
            if content_type and content_type != "text/event-stream":
                raise ServiceError("El servicio no devolvió una respuesta progresiva")
            for event in read_sse(response):
                control.check()
                yield event
            control.check()
        except (OSError, http.client.HTTPException):
            control.check()
            raise ServiceError("Se interrumpió la conexión. Puedes volver a enviar un mensaje.") from None
        finally:
            control.attach(None)
            if connection:
                connection.close()


def read_sse(source):
    """Agrupa campos data multilínea; [DONE] no equivale a response.completed."""
    data = []
    size = 0
    while True:
        raw = source.readline(1024 * 1024 + 1)
        if not raw:
            if data:
                raise ServiceError("La transmisión terminó en mitad de un evento")
            return
        size += len(raw)
        if size > 1024 * 1024:
            raise ServiceError("Un evento del servicio es demasiado grande")
        try:
            line = raw.decode("utf-8").rstrip("\r\n")
        except UnicodeError:
            raise ServiceError("El servicio devolvió texto inválido") from None
        if not line:
            if data:
                value = "\n".join(data)
                if value == "[DONE]":
                    return
                try:
                    event = json.loads(value)
                except ValueError:
                    raise ServiceError("El servicio devolvió un evento inválido") from None
                if not isinstance(event, dict) or not isinstance(event.get("type"), str):
                    raise ServiceError("El servicio devolvió un evento incompatible")
                yield event
            data, size = [], 0
        elif line.startswith("data:"):
            data.append(line[5:].lstrip(" "))
