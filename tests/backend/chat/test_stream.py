"""Reconstrucción de Responses sin perder razonamiento ni mantener conexiones abiertas."""

import unittest
from unittest.mock import Mock

from tests.support import paths  # noqa: F401
from tests.support.fake_service import FakeSession
from harness.chat.chatgpt import ChatGPTClient
from harness.core.http import ServiceError, StreamControl
from harness.tools.shell import SHELL_TOOL


class StreamTests(unittest.TestCase):
    def setUp(self):
        self.http = Mock()
        self.client = ChatGPTClient(FakeSession(), self.http)
        self.reasoning = {"id": "reasoning-1", "type": "reasoning", "summary": [],
                          "encrypted_content": "opaque"}
        self.call = {"id": "function-1", "type": "function_call", "call_id": "call-1",
                     "name": "shell", "arguments": '{"command":"pwd"}'}

    def stream(self):
        return self.client.stream("test-model", [], "Instructions", StreamControl(), tools=[SHELL_TOOL])

    def events(self, final):
        return [{"type": "response.output_item.done", "output_index": index, "item": item}
                for index, item in enumerate([self.reasoning, self.call])] + [
                    {"type": "response.completed", "response": {"status": "completed", "output": final}}]

    def test_partial_final_output_preserves_reasoning_and_unique_tool_call(self):
        self.http.stream.return_value = iter(self.events([self.call]))
        output = list(self.stream())[-1]["response"]["output"]
        self.assertEqual(output, [self.reasoning, self.call])

    def test_final_fields_merge_with_completed_stream_items(self):
        self.http.stream.return_value = iter(self.events([
            {"id": "reasoning-1", "type": "reasoning", "summary": []}, {**self.call, "status": "completed"}
        ]))
        output = list(self.stream())[-1]["response"]["output"]
        self.assertEqual(output[0]["encrypted_content"], "opaque")
        self.assertEqual(output[1]["status"], "completed")

    def test_duplicate_final_items_are_rejected_before_execution(self):
        self.http.stream.return_value = iter(self.events([self.call, self.call]))
        with self.assertRaises(ServiceError):
            list(self.stream())

    def test_final_only_reasoning_stays_before_the_streamed_tool(self):
        events = self.events([self.reasoning, self.call])[1:]
        self.http.stream.return_value = iter(events)
        self.assertEqual(list(self.stream())[-1]["response"]["output"], [self.reasoning, self.call])

    def test_contradictory_final_order_is_rejected(self):
        self.http.stream.return_value = iter(self.events([self.call, self.reasoning]))
        with self.assertRaises(ServiceError):
            list(self.stream())

    def test_closing_adapter_closes_transport_even_before_end_of_stream(self):
        closed = []
        def transport():
            try:
                yield {"type": "response.created"}
                self.fail("No se debe consumir el resto del stream al cerrarlo")
            finally:
                closed.append(True)
        self.http.stream.return_value = transport()
        stream = self.stream()
        next(stream)
        stream.close()
        self.assertEqual(closed, [True])
