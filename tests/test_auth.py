"""OAuth con claves RSA de prueba: identidad, permisos y sesiones privadas."""

import hashlib
import http.client
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit
from unittest.mock import Mock

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from harness.auth import ChatGPTSession, ISSUER, JWKS_URL, PLAN_SCOPE, RESOURCE, SessionStore, TOKEN_URL
from harness.http import Cancelled, ServiceError


class AuthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(cls.key.public_key()))
        cls.jwk.update(kid="test-key", alg="RS256", use="sig")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.http = Mock()
        self.session = ChatGPTSession(Path(self.temp.name) / "session", self.http)

    def token(self, nonce, **claims):
        payload = {"sub": "subject-1", "email": "test@example.invalid", "iss": ISSUER,
                   "aud": "oaiapp_test", "iat": int(time.time()), "exp": int(time.time()) + 3600,
                   "nonce": nonce, **claims}
        return jwt.encode(payload, self.key, algorithm="RS256", headers={"kid": "test-key"})

    def tokens(self, nonce, **claims):
        return {"access_token": "access-test", "refresh_token": "refresh-test", "expires_in": 3600,
                "token_type": "Bearer", "scope": "openid email offline_access " + PLAN_SCOPE,
                "id_token": self.token(nonce, **claims)}

    def attempt(self):
        attempt = self.session.begin_login(threading.Event())
        self.addCleanup(attempt.close)
        return attempt

    def connect(self, **claims):
        attempt = self.attempt()
        self.http.json.side_effect = [self.tokens(attempt.nonce, **claims), {"keys": [self.jwk]}]
        self.session.complete_login(attempt, {"code": "test-code", "client_id": "oaiapp_test"})
        return attempt

    def test_initial_registration_uses_host_pkce_nonce_and_plan_scope(self):
        first, second = self.attempt(), self.attempt()
        values = parse_qs(urlsplit(first.url).query)
        self.assertEqual(values["client_id"], ["dynamic_agent_client"])
        self.assertEqual(values["agent_name_hint"], ["Agent Shell"])
        self.assertEqual(values["resource"], [RESOURCE])
        self.assertIn(PLAN_SCOPE, values["scope"][0])
        self.assertEqual(urlsplit(first.redirect_uri).hostname, "127.0.0.1")
        self.assertEqual(values["code_challenge_method"], ["S256"])
        self.assertNotEqual(first.state, second.state)
        self.assertNotEqual(first.nonce, second.nonce)
        self.assertEqual(values["ext_agent_host_id"], parse_qs(urlsplit(second.url).query)["ext_agent_host_id"])
        reopened = ChatGPTSession(self.session.store.root, self.http)
        self.assertEqual(reopened.store.load()["host_id"], self.session.store.load()["host_id"])

    def test_valid_login_verifies_identity_and_preserves_exact_exchange_uri(self):
        attempt = self.connect()
        call = self.http.json.call_args_list[0]
        self.assertEqual(call.args[:2], ("POST", TOKEN_URL))
        values = parse_qs(call.args[2].decode())
        self.assertEqual(values["client_id"], ["oaiapp_test"])
        self.assertEqual(values["redirect_uri"], [attempt.redirect_uri])
        self.assertEqual(values["code_verifier"], [attempt.verifier])
        self.assertEqual(self.session.access_token(), "access-test")
        self.assertTrue(self.session.account()["authenticated"])
        self.assertEqual(self.session.account()["email"], "test@example.invalid")
        self.assertNotIn("access-test", json.dumps(self.session.account()))

    def test_identity_without_plan_permission_cannot_send_requests(self):
        attempt = self.attempt()
        tokens = self.tokens(attempt.nonce)
        tokens["scope"] = "openid profile email"
        self.http.json.side_effect = [tokens, {"keys": [self.jwk]}]
        self.session.complete_login(attempt, {"code": "test", "client_id": "oaiapp_test"})
        self.assertEqual(self.session.account()["method"], "chatgpt")
        self.assertFalse(self.session.account()["authenticated"])
        with self.assertRaises(ServiceError):
            self.session.access_token()

    def test_bad_signature_issuer_audience_expiry_and_nonce_do_not_replace_session(self):
        self.connect()
        original = self.session.store.path.read_bytes()
        variants = ({"iss": "https://wrong.invalid"}, {"aud": "other-client"},
                    {"exp": int(time.time()) - 60}, {"nonce": "wrong"}, {"sub": "other-person"})
        for claims in variants:
            with self.subTest(claims=claims):
                attempt = self.attempt()
                nonce = claims.get("nonce", attempt.nonce)
                other = {key: value for key, value in claims.items() if key != "nonce"}
                self.http.json.side_effect = [self.tokens(nonce, **other), {"keys": [self.jwk]}]
                with self.assertRaises(ServiceError):
                    self.session.complete_login(attempt, {"code": "test", "client_id": "oaiapp_test"})
                self.assertEqual(self.session.store.path.read_bytes(), original)
        attempt = self.attempt()
        tokens = self.tokens(attempt.nonce)
        parts = tokens["id_token"].split(".")
        parts[2] = "A" * len(parts[2])
        tokens["id_token"] = ".".join(parts)
        self.http.json.side_effect = [tokens, {"keys": [self.jwk]}]
        with self.assertRaises(ServiceError):
            self.session.complete_login(attempt, {"code": "test", "client_id": "oaiapp_test"})
        self.assertEqual(self.session.store.path.read_bytes(), original)

    def test_returning_login_uses_issued_client_and_rejects_replacement(self):
        self.connect()
        attempt = self.attempt()
        values = parse_qs(urlsplit(attempt.url).query)
        self.assertEqual(values["client_id"], ["oaiapp_test"])
        self.assertNotIn("agent_name_hint", values)
        self.assertIn("id_token_hint", values)
        self.http.reset_mock()
        with self.assertRaises(ServiceError):
            self.session.complete_login(attempt, {"code": "test", "client_id": "oaiapp_other"})
        self.http.json.assert_not_called()

    def test_missing_registration_client_is_rejected(self):
        attempt = self.attempt()
        with self.assertRaises(ServiceError):
            self.session.complete_login(attempt, {"code": "test"})
        self.http.json.assert_not_called()

    def test_invalid_code_retains_issued_registration_for_fresh_login(self):
        attempt = self.attempt()
        self.http.json.side_effect = ServiceError("expired", 400, "invalid_grant")
        with self.assertRaises(ServiceError):
            self.session.complete_login(attempt, {"code": "expired", "client_id": "oaiapp_test"})
        following = self.attempt()
        self.assertEqual(following.client_id, "oaiapp_test")
        self.assertIsNone(self.session.store.load()["connection"])
        self.assertNotIn("agent_name_hint", parse_qs(urlsplit(following.url).query))

    def test_callback_rejects_wrong_state_and_then_accepts_correct_state(self):
        attempt = self.attempt()
        results = []
        waiter = threading.Thread(target=lambda: results.append(attempt.wait()))
        waiter.start()
        self.addCleanup(lambda: (attempt.cancel.set(), waiter.join(timeout=3)))
        address = urlsplit(attempt.redirect_uri)

        def callback(state):
            connection = http.client.HTTPConnection(address.hostname, address.port, timeout=2)
            try:
                connection.request("GET", address.path + "?" + urlencode({"state": state,
                    "code": "test-code", "client_id": "oaiapp_test"}))
                response = connection.getresponse()
                response.read()
                return response.status
            finally:
                connection.close()

        self.assertEqual(callback("wrong-state"), 400)
        self.assertIsNone(attempt.result)
        self.assertEqual(callback(attempt.state), 200)
        waiter.join(timeout=2)
        self.assertEqual(results[0]["code"], "test-code")

    def test_cancel_and_expiration_release_loopback_listener(self):
        attempt = self.attempt()
        attempt.cancel.set()
        with self.assertRaises(Cancelled):
            attempt.wait()
        self.assertEqual(attempt.server.fileno(), -1)
        attempt = self.attempt()
        attempt.expires = time.monotonic() - 1
        with self.assertRaises(ServiceError):
            attempt.wait()
        self.assertEqual(attempt.server.fileno(), -1)

    def test_cancel_during_exchange_does_not_save_new_credentials(self):
        attempt = self.attempt()

        def exchange(method, url, *args):
            if url == JWKS_URL:
                attempt.cancel.set()
                return {"keys": [self.jwk]}
            return self.tokens(attempt.nonce)

        self.http.json.side_effect = exchange
        with self.assertRaises(Cancelled):
            self.session.complete_login(attempt, {"code": "test", "client_id": "oaiapp_test"})
        self.assertIsNone(self.session.store.load()["connection"])

    def test_refresh_rotates_credentials_and_uses_saved_client_after_restart(self):
        self.connect()
        with self.session.store.locked():
            record = self.session.store.load()
            record["connection"]["expires_at"] = time.time() - 1
            self.session.store.save(record)
        new = self.tokens("unused")
        new.pop("id_token")
        new.update(access_token="new-access", refresh_token="new-refresh")
        self.http.json.side_effect = None
        self.http.json.return_value = new
        reopened = ChatGPTSession(self.session.store.root, self.http)
        self.assertEqual(reopened.access_token(), "new-access")
        values = parse_qs(self.http.json.call_args.args[2].decode())
        self.assertEqual(values["grant_type"], ["refresh_token"])
        self.assertEqual(values["client_id"], ["oaiapp_test"])
        self.assertNotIn("scope", values)
        self.assertEqual(reopened.store.load()["connection"]["refresh_token"], "new-refresh")

    def test_parallel_session_instances_refresh_only_once(self):
        self.connect()
        record = self.session.store.load()
        record["connection"]["expires_at"] = 0
        self.session.store.save(record)
        other = ChatGPTSession(self.session.store.root, self.http)
        refreshed = self.tokens("unused")
        refreshed.pop("id_token")
        self.http.json.reset_mock()
        self.http.json.side_effect = None
        self.http.json.return_value = refreshed
        results = []
        workers = [threading.Thread(target=lambda s=s: results.append(s.access_token()))
                   for s in (self.session, other)]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(timeout=2)
        self.assertEqual(len(results), 2)
        self.assertEqual(self.http.json.call_count, 1)

    def test_earliest_refresh_time_is_respected(self):
        self.connect()
        record = self.session.store.load()
        record["connection"].update(expires_at=time.time() + 30, earliest_refresh_at=time.time() + 20)
        self.session.store.save(record)
        self.http.reset_mock()
        self.assertEqual(self.session.access_token(), "access-test")
        self.http.json.assert_not_called()

    def test_invalid_refresh_clears_tokens_and_requires_login(self):
        self.connect()
        record = self.session.store.load()
        record["connection"]["expires_at"] = 0
        self.session.store.save(record)
        self.http.json.side_effect = ServiceError("expired", 400, "invalid_grant")
        with self.assertRaises(ServiceError):
            self.session.access_token()
        self.assertFalse(self.session.account()["authenticated"])
        self.assertNotIn("refresh_token", self.session.store.load()["connection"])

    def test_logout_revokes_and_preserves_registration_for_next_login(self):
        self.connect()
        self.http.json.side_effect = [{"revocation_endpoint": ISSUER + "/api/accounts/oauth/revoke"}, {}]
        self.assertTrue(self.session.logout())
        record = self.session.store.load()
        self.assertEqual(record["connection"]["client_id"], "oaiapp_test")
        self.assertNotIn("access_token", record["connection"])
        self.assertNotIn("id_token_hint", parse_qs(urlsplit(self.attempt().url).query))

    def test_credentials_have_private_permissions_and_atomic_failure_preserves_them(self):
        self.connect()
        self.assertEqual(self.session.store.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.session.store.root.stat().st_mode & 0o777, 0o700)
        original = self.session.store.path.read_bytes()
        from unittest.mock import patch
        with patch("harness.auth.os.replace", side_effect=OSError("disk error")):
            with self.assertRaises(OSError):
                self.session.store.save({"bad": "record"})
        self.assertEqual(self.session.store.path.read_bytes(), original)
        self.assertEqual(list(self.session.store.root.glob(".session-*")), [])

    def test_corrupt_credentials_are_preserved_and_not_exposed(self):
        self.session.store.path.write_text('{"token":"secret-test", broken')
        with self.assertRaises(ServiceError) as context:
            self.session.account()
        self.assertNotIn("secret-test", str(context.exception))
        self.assertIn("secret-test", self.session.store.path.read_text())
