"""Sesión propia de ChatGPT mediante el flujo oficial para aplicaciones locales.

No consulta credenciales de otras aplicaciones. PKCE, state y nonce se generan
por intento; la identidad sólo se acepta después de validar la firma del JWT.
"""

import base64
import fcntl
import hashlib
import json
import math
import os
import secrets
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit

import jwt

from ..core.http import Cancelled, HttpClient, ServiceError

ISSUER = "https://auth.openai.com"
AUTHORIZE_URL = ISSUER + "/api/accounts/authorize"
TOKEN_URL = ISSUER + "/api/accounts/oauth/token"
JWKS_URL = ISSUER + "/.well-known/jwks.json"
RESOURCE = "https://api.openai.com/v1"
PLAN_SCOPE = "chatgpt.tokens.use.direct"
SCOPES = "openid profile email offline_access resource.invoke " + PLAN_SCOPE


class LoopbackServer(HTTPServer):
    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(2)
        return connection, address


class SessionStore:
    """Escritura atómica y exclusión entre procesos para tokens de renovación rotativos."""

    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        self.path = self.root / "session.json"
        self._lock = threading.RLock()

    @contextmanager
    def locked(self):
        with self._lock:
            descriptor = os.open(self.root / ".session.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            with os.fdopen(descriptor, "w") as handle:
                fcntl.flock(handle, fcntl.LOCK_EX)
                try:
                    yield
                finally:
                    fcntl.flock(handle, fcntl.LOCK_UN)

    def load(self) -> dict:
        if self.path.is_symlink():
            raise ServiceError("El archivo de sesión no puede ser un enlace simbólico")
        if not self.path.exists():
            record = {"schema_version": 1, "host_id": "urn:uuid:" + str(uuid.uuid4()), "connection": None}
            self.save(record)
            return record
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
            if (not isinstance(value, dict) or value.get("schema_version") != 1
                    or not isinstance(value.get("host_id"), str) or not value["host_id"]):
                raise ValueError()
            for key in ("pending_client_id", "pending_new_client_id"):
                if key in value and (not isinstance(value[key], str) or not value[key]
                                     or value[key] == "dynamic_agent_client"):
                    raise ValueError()
            saved = value.get("saved_connections", [])
            if not isinstance(saved, list):
                raise ValueError()
            profiles = saved + ([value["connection"]] if value.get("connection") is not None else [])
            identifiers = set()
            for profile in profiles:
                if not isinstance(profile, dict):
                    raise ValueError()
                if not all(isinstance(profile.get(key), str) and profile[key]
                           for key in ("client_id", "subject")):
                    raise ValueError()
                if profile["client_id"] == "dynamic_agent_client":
                    raise ValueError()
                if profile["client_id"] in identifiers:
                    raise ValueError()
                identifiers.add(profile["client_id"])
                if (not isinstance(profile.get("scopes", []), list)
                        or not all(isinstance(scope, str) for scope in profile.get("scopes", []))):
                    raise ValueError()
                if not isinstance(profile.get("expires_at", 0), (int, float)):
                    raise ValueError()
                for key in ("email", "access_token", "refresh_token", "id_token", "label"):
                    if key in profile and not isinstance(profile[key], str):
                        raise ValueError()
            return value
        except (ValueError, TypeError):
            raise ServiceError("El archivo de sesión es incompatible. Se conservó; revisa el directorio de sesión.") from None

    def save(self, record: dict) -> None:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.root,
                                             prefix=".session-", delete=False) as handle:
                temporary = Path(handle.name)
                json.dump(record, handle, ensure_ascii=False)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)


class LoginAttempt:
    """Listener loopback temporal. Un callback ajeno no consume el intento válido."""

    def __init__(self, record: dict, cancel: threading.Event, timeout: float = 600,
                 new_account: bool = False) -> None:
        self.cancel = cancel
        self.state = secrets.token_urlsafe(32)
        self.nonce = secrets.token_urlsafe(32)
        self.verifier = secrets.token_urlsafe(64)
        self.expires = time.monotonic() + timeout
        self.new_account = new_account
        self.profile = {} if new_account else record.get("connection") or {}
        pending_key = "pending_new_client_id" if new_account else "pending_client_id"
        self.client_id = self.profile.get("client_id") or record.get(pending_key) or "dynamic_agent_client"
        self.result: dict | None = None
        attempt = self

        class Callback(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass  # La URL contiene códigos OAuth; nunca escribirla en logs.

            def do_GET(self):
                parsed = urlsplit(self.path)
                status, text = 400, "Callback inválido. Regresa a Agent Shell."
                if parsed.path == "/auth/callback" and len(self.path) <= 8192:
                    values = parse_qs(parsed.query)
                    if (all(len(entries) == 1 for entries in values.values())
                            and secrets.compare_digest(values.get("state", [""])[0], attempt.state)
                            and attempt.result is None and not cancel.is_set()
                            and time.monotonic() < attempt.expires):
                        attempt.result = {key: entries[0] for key, entries in values.items()}
                        status, text = 200, "Autorización recibida. Regresa a Agent Shell para continuar."
                self.send_response(status)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
                self.end_headers()
                self.wfile.write(text.encode("utf-8"))

        self.server = LoopbackServer(("127.0.0.1", 0), Callback)
        self.server.timeout = 0.2
        self.redirect_uri = f"http://127.0.0.1:{self.server.server_port}/auth/callback"
        challenge = base64.urlsafe_b64encode(hashlib.sha256(self.verifier.encode()).digest()).decode().rstrip("=")
        params = {
            "client_id": self.client_id, "ext_agent_host_id": record["host_id"],
            "response_type": "code", "redirect_uri": self.redirect_uri,
            "scope": SCOPES, "resource": RESOURCE, "state": self.state, "nonce": self.nonce,
            "code_challenge_method": "S256", "code_challenge": challenge,
        }
        if self.client_id == "dynamic_agent_client":
            params["agent_name_hint"] = "Agent Shell"
        elif self.profile.get("id_token"):
            params["id_token_hint"] = self.profile["id_token"]
        self.url = AUTHORIZE_URL + "?" + urlencode(params)

    def wait(self) -> dict:
        try:
            while self.result is None:
                if self.cancel.is_set():
                    raise Cancelled()
                if time.monotonic() >= self.expires:
                    raise ServiceError("El inicio de sesión caducó. Vuelve a intentarlo.")
                self.server.handle_request()
            if self.cancel.is_set():
                raise Cancelled()
            return self.result
        finally:
            self.server.server_close()

    def close(self) -> None:
        self.server.server_close()


class ChatGPTSession:
    """Registros separados por cuenta; renovación independiente de Codex CLI."""

    def __init__(self, root: Path, http: HttpClient | None = None) -> None:
        self.store = SessionStore(root)
        self.http = http or HttpClient()

    def account(self) -> dict:
        with self.store.locked():
            record = self.store.load()
            profile = record.get("connection") or {}
            profiles = record.get("saved_connections", []) + ([profile] if profile else [])
            accounts = [{"id": self._account_id(item), "label": item.get("label", "Cuenta 1"),
                         "email": item.get("email", ""), "active": item is profile}
                        for item in profiles]
        connected = bool(profile.get("access_token") or profile.get("refresh_token"))
        return {"authenticated": connected and PLAN_SCOPE in profile.get("scopes", []),
                "method": "chatgpt" if connected else "none",
                "email": profile.get("email", "") if connected else "", "plan": "",
                "plan_enabled": connected and PLAN_SCOPE in profile.get("scopes", []),
                "accounts": accounts}

    @staticmethod
    def _account_id(profile: dict) -> str:
        return hashlib.sha256(profile["client_id"].encode()).hexdigest()

    def select_account(self, account_id: str) -> None:
        with self.store.locked():
            record = self.store.load()
            current = record.get("connection")
            if current and self._account_id(current) == account_id:
                return
            saved = record.get("saved_connections", [])
            selected = next((item for item in saved if self._account_id(item) == account_id), None)
            if selected is None:
                raise ServiceError("La cuenta seleccionada no está registrada")
            record["saved_connections"] = [item for item in saved if item is not selected]
            if current:
                record["saved_connections"].append(current)
            record["connection"] = selected
            self.store.save(record)

    def begin_login(self, cancel: threading.Event, new_account: bool = False) -> LoginAttempt:
        with self.store.locked():
            return LoginAttempt(self.store.load(), cancel, new_account=new_account)

    def _identity(self, token: str, client_id: str, nonce: str | None = None) -> dict:
        try:
            header = jwt.get_unverified_header(token)
            if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str):
                raise ValueError()
            keys = self.http.json("GET", JWKS_URL).get("keys", [])
            key = next(entry for entry in keys if entry.get("kid") == header["kid"])
            identity = jwt.decode(token, jwt.PyJWK.from_dict(key).key, algorithms=["RS256"],
                                  audience=client_id, issuer=ISSUER, leeway=5,
                                  options={"require": ["sub", "exp", "iat"]})
            if not isinstance(identity["sub"], str) or not identity["sub"]:
                raise ValueError()
            if "email" in identity and not isinstance(identity["email"], str):
                raise ValueError()
            if nonce is not None and identity.get("nonce") != nonce:
                raise ValueError()
            return identity
        except (jwt.PyJWTError, ValueError, TypeError, KeyError, StopIteration):
            raise ServiceError("No se pudo verificar la identidad devuelta por OpenAI") from None

    @staticmethod
    def _tokens(tokens: dict, previous: dict) -> dict:
        if (not isinstance(tokens.get("access_token"), str) or not tokens["access_token"]
                or not isinstance(tokens.get("token_type"), str) or tokens["token_type"].lower() != "bearer"
                or type(tokens.get("expires_in")) not in (int, float)
                or not math.isfinite(tokens["expires_in"]) or tokens["expires_in"] <= 0):
            raise ServiceError("OpenAI devolvió una sesión incompleta")
        for key in ("refresh_token", "id_token", "scope"):
            if key in tokens and not isinstance(tokens[key], str):
                raise ServiceError("OpenAI devolvió una sesión incompatible")
        scopes = tokens["scope"].split() if "scope" in tokens else previous.get("scopes", [])
        earliest = tokens.get("earliest_refresh_at") or 0
        if type(earliest) not in (int, float) or not math.isfinite(earliest) or earliest < 0:
            raise ServiceError("OpenAI devolvió un tiempo de renovación incompatible")
        return {**previous, "access_token": tokens["access_token"],
                "refresh_token": tokens.get("refresh_token", previous.get("refresh_token", "")),
                "id_token": tokens.get("id_token", previous.get("id_token", "")),
                "scopes": scopes, "expires_at": time.time() + tokens["expires_in"],
                "earliest_refresh_at": earliest}

    def complete_login(self, attempt: LoginAttempt, callback: dict) -> None:
        if attempt.cancel.is_set():
            raise Cancelled()
        if callback.get("error"):
            raise ServiceError("No se autorizó la conexión con ChatGPT")
        client_id = callback.get("client_id", attempt.client_id)
        if (not isinstance(client_id, str) or not client_id or client_id == "dynamic_agent_client"
                or (attempt.client_id != "dynamic_agent_client" and client_id != attempt.client_id)):
            raise ServiceError("El registro de la aplicación no se completó")
        if not callback.get("code"):
            raise ServiceError("OpenAI no devolvió un código de autorización")
        try:
            tokens = self.http.json("POST", TOKEN_URL, urlencode({
                "grant_type": "authorization_code", "client_id": client_id, "code": callback["code"],
                "code_verifier": attempt.verifier, "redirect_uri": attempt.redirect_uri, "resource": RESOURCE,
            }).encode(), {"Content-Type": "application/x-www-form-urlencoded"})
        except ServiceError as error:
            if error.code == "invalid_grant" and not attempt.profile and not attempt.cancel.is_set():
                with self.store.locked():
                    record = self.store.load()
                    record["pending_new_client_id" if attempt.new_account else "pending_client_id"] = client_id
                    self.store.save(record)
            raise
        identity = self._identity(tokens.get("id_token", ""), client_id, attempt.nonce)
        if attempt.profile.get("subject") and identity["sub"] != attempt.profile["subject"]:
            raise ServiceError("La cuenta no coincide con la registrada en esta aplicación")
        profile = self._tokens(tokens, {"client_id": client_id, "subject": identity["sub"],
                                      "email": identity.get("email", ""), "scopes": []})
        with self.store.locked():
            if attempt.cancel.is_set():
                raise Cancelled()
            record = self.store.load()
            current = record.get("connection")
            saved = record.get("saved_connections", [])
            profiles = saved + ([current] if current else [])
            previous = next((item for item in profiles if item["client_id"] == client_id), None)
            if previous and previous["subject"] != identity["sub"]:
                raise ServiceError("La cuenta no coincide con la registrada en esta aplicación")
            if attempt.profile and (not current or current["client_id"] != attempt.profile["client_id"]):
                raise ServiceError("La cuenta activa cambió durante el inicio de sesión. Vuelve a intentarlo.")
            profile["label"] = (previous.get("label", "Cuenta 1") if previous else
                                "Cuenta " + str(len(profiles) + 1))
            record["saved_connections"] = [item for item in saved if item["client_id"] != client_id]
            if current and current["client_id"] != client_id:
                record["saved_connections"].append(current)
            record.pop("pending_new_client_id" if attempt.new_account else "pending_client_id", None)
            record["connection"] = profile
            self.store.save(record)

    def access_token(self) -> str:
        with self.store.locked():
            record = self.store.load()
            profile = record.get("connection") or {}
            if PLAN_SCOPE not in profile.get("scopes", []):
                raise ServiceError("Conecta ChatGPT y autoriza el uso de tu plan para conversar")
            now = time.time()
            earliest = profile.get("earliest_refresh_at", 0)
            if profile.get("access_token") and profile.get("expires_at", 0) > now and (
                    profile["expires_at"] > now + 60 or earliest > now):
                return profile["access_token"]
            if earliest > now:
                raise ServiceError("La sesión todavía no puede renovarse. Espera un momento y vuelve a intentarlo.")
            if not profile.get("refresh_token"):
                raise ServiceError("La sesión caducó. Vuelve a conectar tu cuenta de ChatGPT.")
            try:
                tokens = self.http.json("POST", TOKEN_URL, urlencode({
                    "grant_type": "refresh_token", "client_id": profile["client_id"],
                    "refresh_token": profile["refresh_token"], "resource": RESOURCE,
                }).encode(), {"Content-Type": "application/x-www-form-urlencoded"})
            except ServiceError as error:
                if error.code == "invalid_grant" or error.status == 401:
                    for key in ("access_token", "refresh_token", "id_token"):
                        profile.pop(key, None)
                    self.store.save(record)
                raise
            replacement = self._tokens(tokens, profile)
            if tokens.get("id_token"):
                identity = self._identity(tokens["id_token"], profile["client_id"])
                if identity["sub"] != profile["subject"]:
                    raise ServiceError("La cuenta de la sesión renovada no coincide")
            record["connection"] = replacement
            self.store.save(record)
            if PLAN_SCOPE not in replacement["scopes"]:
                raise ServiceError("La sesión ya no autoriza el uso de tu plan. Vuelve a conectar ChatGPT.")
            return replacement["access_token"]

    def logout(self) -> bool:
        """Conserva registro/host; devuelve si la revocación remota se confirmó."""
        with self.store.locked():
            record = self.store.load()
            profile = record.get("connection") or {}
            confirmed = True
            if profile.get("refresh_token"):
                try:
                    discovery = self.http.json("GET", ISSUER + "/.well-known/openid-configuration")
                    endpoint = discovery.get("revocation_endpoint", "")
                    if urlsplit(endpoint).scheme != "https" or urlsplit(endpoint).hostname != "auth.openai.com":
                        raise ServiceError("Dirección de revocación incompatible")
                    self.http.json("POST", endpoint, urlencode({
                        "token": profile["refresh_token"], "token_type_hint": "refresh_token",
                        "client_id": profile["client_id"],
                    }).encode(), {"Content-Type": "application/x-www-form-urlencoded"})
                except ServiceError:
                    confirmed = False
            for key in ("access_token", "refresh_token", "id_token"):
                profile.pop(key, None)
            if profile:
                record["connection"] = profile
                self.store.save(record)
            return confirmed
