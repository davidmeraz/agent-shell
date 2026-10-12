"""Imágenes reales en memoria, portapapeles acotado y contexto HTTP de prueba."""

import base64
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "backend"))

from fake_service import FakeService, FakeSession
from test_harness import BackendSession, QueueOutput
from harness.clipboard import _capture, read_clipboard
from harness.context import replay_items
from harness.history import HistoryStore
from harness.http import HttpClient
from harness.chatgpt import ChatGPTClient
from harness.images import validate_image, user_content
from harness.server import HarnessServer


def image_url(format="PNG", size=(16, 12)):
    output = io.BytesIO()
    Image.new("RGB", size, "white").save(output, format=format)
    mime = {"PNG": "image/png", "JPEG": "image/jpeg", "WEBP": "image/webp"}[format]
    return f"data:{mime};base64," + base64.b64encode(output.getvalue()).decode("ascii")


class ImageTests(unittest.TestCase):
    def test_supported_formats_roundtrip_and_text_remains_plain_without_image(self):
        for format in ("PNG", "JPEG", "WEBP"):
            with self.subTest(format=format):
                image = image_url(format)
                self.assertEqual(validate_image(image), image)
                self.assertEqual(user_content("Mira", image), [
                    {"type": "input_text", "text": "Mira"},
                    {"type": "input_image", "image_url": image, "detail": "auto"},
                ])
        self.assertEqual(user_content("hola"), "hola")
        self.assertEqual(len(user_content("", image_url())), 1)

    def test_remote_urls_paths_mismatched_mime_and_corrupt_payload_rejected(self):
        for image in (None, "file:///tmp/image.png", "https://example.invalid/image.png",
                      "data:image/svg+xml;base64,PHN2Zy8+", "data:image/png;base64,???",
                      "data:image/png;base64,", "data:image/png;base64,dGV4dG8=",
                      image_url().replace("image/png", "image/jpeg")):
            with self.subTest(image=image), self.assertRaises(ValueError):
                validate_image(image)

    def test_byte_and_pixel_limits_are_enforced_before_decoding_pixels(self):
        image = image_url()
        with patch("harness.images.MAX_IMAGE_BYTES", 10), self.assertRaises(ValueError):
            validate_image(image)
        with patch("harness.images.MAX_PIXELS", 100), self.assertRaises(ValueError):
            validate_image(image)

    def test_context_only_accepts_valid_user_images(self):
        message = {"role": "user", "content": user_content("", image_url())}
        self.assertEqual(replay_items([message]), [message])
        for invalid in ({**message, "role": "assistant"},
                        {"role": "user", "content": [{"type": "input_image", "image_url": "https://example.invalid/x.png"}]},
                        {"role": "user", "content": [{"type": "input_image", "image_url": image_url(), "detail": "invalid"}]}):
            with self.assertRaises(ValueError):
                replay_items([invalid])


class ClipboardTests(unittest.TestCase):
    def test_wayland_reads_binary_png_without_shell_interpolation(self):
        image = image_url()
        raw = base64.b64decode(image.split(",", 1)[1])
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "test-display"}), \
                patch("harness.clipboard.shutil.which", return_value="/test/wl-paste"), \
                patch("harness.clipboard._capture", side_effect=[b"image/png\ntext/plain\n", raw]) as capture:
            self.assertEqual(read_clipboard(), {"image": image})
            self.assertEqual(capture.call_args_list[1].args[0], ["wl-paste", "--no-newline", "--type", "image/png"])

    def test_x11_uses_image_target_and_text_only_returns_empty_image(self):
        image = image_url("JPEG")
        raw = base64.b64decode(image.split(",", 1)[1])
        with patch.dict(os.environ, {"DISPLAY": ":test"}, clear=True), \
                patch("harness.clipboard.shutil.which", return_value="/test/xclip"), \
                patch("harness.clipboard._capture", side_effect=[b"image/jpeg\n", raw]):
            self.assertEqual(read_clipboard(), {"image": image})
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "test"}), \
                patch("harness.clipboard.shutil.which", return_value="/test/wl-paste"), \
                patch("harness.clipboard._capture", return_value=b"text/plain\n") as capture:
            self.assertEqual(read_clipboard(), {"image": ""})
            self.assertEqual(capture.call_count, 1)

    def test_missing_reader_and_unsupported_image_are_reported(self):
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "test"}), \
                patch("harness.clipboard.shutil.which", return_value=None), self.assertRaisesRegex(ValueError, "wl-clipboard"):
            read_clipboard()
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "test"}), \
                patch("harness.clipboard.shutil.which", return_value="/test/wl-paste"), \
                patch("harness.clipboard._capture", return_value=b"image/svg+xml\n"), self.assertRaises(ValueError):
            read_clipboard()

    def test_capture_binary_bounds_and_process_errors(self):
        self.assertEqual(_capture([sys.executable, "-c", "import os; os.write(1, b'\\x00\\xff')"], 8), b"\x00\xff")
        with self.assertRaises(ValueError):
            _capture([sys.executable, "-c", "import os; os.write(1, b'x' * 10000)"], 100)
        with self.assertRaises(ValueError):
            _capture([sys.executable, "-c", "raise SystemExit(1)"], 100)


class ImageServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.service = FakeService().__enter__()
        self.addCleanup(self.service.__exit__)
        self.output = QueueOutput()
        session = FakeSession()
        client = ChatGPTClient(session, HttpClient(allow_loopback=True, timeout=2), self.service.url)
        self.server = HarnessServer(self.root / "chats", self.output, session, client, workspace=self.root)
        self.server._refresh_account()
        self.addCleanup(self.stop)

    def stop(self):
        self.server._stream.cancel()
        self.server._shell_control.cancel()
        for worker in self.server._workers:
            worker.join(3)

    def test_image_only_send_persists_and_followup_replays_image(self):
        image = image_url()
        self.server.handle({"type": "chat.send", "prompt": "", "image": image})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "completed")
        record = HistoryStore(self.root / "chats").load(self.server.conversation["chat_id"])
        self.assertEqual(record["title"], "Imagen adjunta")
        self.assertEqual(record["messages"][0]["image"], image)
        self.assertEqual(self.service.requests[0]["body"]["input"][0]["content"], user_content("", image))
        self.server.handle({"type": "chat.send", "prompt": "continúa"})
        self.output.wait_for("chat.finished")
        self.assertEqual(self.service.requests[-1]["body"]["input"][0]["content"], user_content("", image))

    def test_invalid_image_does_not_save_or_call_provider_and_busy_turn_is_preserved(self):
        self.server.handle({"type": "chat.send", "prompt": "hola", "image": "bad"})
        self.assertEqual(self.output.wait_for("chat.finished")["status"], "failed")
        self.assertIsNone(self.server.conversation)
        self.assertEqual(self.service.requests, [])
        self.server.busy = True
        self.server.handle({"type": "chat.send", "prompt": "hola", "image": "bad"})
        self.output.wait_for("error")
        self.assertTrue(self.server.busy)

    def test_clipboard_request_correlates_offline_and_failure_does_not_finish_turn(self):
        self.server.authenticated = False
        self.server.busy = True
        image = image_url()
        with patch("harness.server.read_clipboard", return_value={"image": image}):
            self.server.handle({"type": "clipboard.paste", "request_id": "paste-a"})
            self.assertEqual(self.output.wait_for("clipboard.result"), {"request_id": "paste-a", "image": image})
        with patch("harness.server.read_clipboard", side_effect=ValueError("error de prueba")):
            self.server.handle({"type": "clipboard.paste", "request_id": "paste-b"})
            result = self.output.wait_for("clipboard.result")
            self.assertEqual((result["request_id"], result["image"], result["message"]), ("paste-b", "", "error de prueba"))
        self.assertTrue(self.server.busy)
        self.assertEqual(self.service.requests, [])

    def test_large_image_crosses_ndjson_and_survives_backend_restart(self):
        output = io.BytesIO()
        Image.frombytes("RGB", (200, 200), os.urandom(120000)).save(output, format="PNG")
        image = "data:image/png;base64," + base64.b64encode(output.getvalue()).decode("ascii")
        self.assertGreater(len(image), 65536)
        with BackendSession(self.root) as session:
            session.send({"type": "chat.send", "prompt": "Describe", "image": image})
            chat_id = session.wait_for("chat.saved")["data"]["chat_id"]
            self.assertEqual(session.wait_for("chat.finished")["data"]["status"], "completed")
        with BackendSession(self.root) as session:
            session.send({"type": "chat.open", "chat_id": chat_id})
            self.assertEqual(session.wait_for("chat.loaded")["data"]["chat"]["messages"][0]["image"], image)
