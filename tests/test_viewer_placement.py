"""Disposición inicial y selección aislada de las ventanas de texto."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "viewer_placement", Path(__file__).resolve().parents[1] / "scripts/place-text-viewer.py")
placement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placement)


class ViewerPlacementTests(unittest.TestCase):
    def monitor(self, **values):
        return dict(id=0, x=0, y=0, width=2560, height=1440, scale=1,
                    reserved=[10, 60, 10, 10], **values)

    def test_reference_layout(self):
        monitor = self.monitor()
        self.assertEqual(placement.geometry(monitor, 0), (164, 85, 553, 640))
        self.assertEqual(placement.geometry(monitor, 1), (1750, 78, 781, 1334))
        self.assertEqual(placement.geometry(monitor, 2), (29, 747, 857, 662))

    def test_scale_offset_and_reserved_edges(self):
        monitor = dict(id=1, x=-1280, y=100, width=2560, height=1440, scale=2,
                       reserved=[10, 30, 20, 10])
        for viewer in (0, 1, 2):
            x, y, w, h = placement.geometry(monitor, viewer)
            self.assertGreaterEqual(x, -1270)
            self.assertGreaterEqual(y, 130)
            self.assertLessEqual(x + w, -20)
            self.assertLessEqual(y + h, 810)

    def test_small_and_rotated_monitors(self):
        small = dict(x=0, y=0, width=400, height=300, scale=1, reserved=[0, 0, 0, 0])
        self.assertEqual(placement.geometry(small, 1), (0, 0, 400, 300))
        rotated = dict(small, width=1440, height=2560, transform=1)
        self.assertEqual(placement.geometry(rotated, 1), (1754, 19, 787, 1402))

    @patch.object(placement, "hyprctl")
    def test_targets_only_own_process_and_title(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=999, title="Visor 1", address="0xdead", monitor=0),
            dict(pid=123, title="Visor 2", address="0xbeef", monitor=0),
            dict(pid=123, title="Visor 1", address="0xcafe", monitor=0),
        ]), json.dumps([self.monitor()]), '{"version":"0.54.3"}', "ok\nok\nok\n"]
        self.assertTrue(placement.place(123, "Visor 1", 1))
        batch = ctl.call_args.args[1]
        self.assertIn("setfloating address:0xcafe", batch)
        self.assertIn("resizewindowpixel exact 781 1334,address:0xcafe", batch)
        self.assertIn("movewindowpixel exact 1750 78,address:0xcafe", batch)
        self.assertNotIn("dead", batch)
        self.assertNotIn("beef", batch)

    @patch.object(placement.time, "sleep")
    @patch.object(placement, "hyprctl", return_value="[]")
    def test_mapping_wait_is_bounded(self, ctl, sleep):
        self.assertFalse(placement.place(123, "Visor 1", 1))
        self.assertEqual(ctl.call_count, 20)

    @patch.object(placement, "hyprctl")
    def test_rotation_before_mapping_keeps_viewer_identity_and_process(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=999, title="Visor 1 · next.py", address="0xdead", monitor=0),
            dict(pid=123, title="Visor 2 · next.py", address="0xbeef", monitor=0),
            dict(pid=123, title="Visor 1 · next.py", address="0xcafe", monitor=0),
        ]), json.dumps([self.monitor()]), '{"version":"0.56.2"}', "ok\n"]
        self.assertTrue(placement.place(123, "Visor 1 · first.py", 1))
        self.assertIn("address:0xcafe", ctl.call_args.args[1])
        self.assertNotIn("dead", ctl.call_args.args[1])
        self.assertNotIn("beef", ctl.call_args.args[1])

    @patch.object(placement.time, "sleep")
    @patch.object(placement, "hyprctl")
    def test_waits_until_mapped(self, ctl, sleep):
        import json
        ctl.side_effect = ["[]", json.dumps([
            dict(pid=123, title="Visor 1", address="0xcafe", monitor=0)
        ]), json.dumps([self.monitor()]), '{"version":"0.54.3"}', "ok\nok\nok\n"]
        self.assertTrue(placement.place(123, "Visor 1", 1))
        sleep.assert_called_once_with(.1)

    @patch.object(placement, "hyprctl")
    def test_lua_dispatchers_for_current_hyprland_and_folder_window(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Explorador", address="0xcafe", monitor=0)
        ]), json.dumps([self.monitor()]), '{"version":"0.56.2"}', "ok\n"]
        self.assertTrue(placement.place(123, "Explorador", 0))
        command, code = ctl.call_args.args
        self.assertEqual(command, "eval")
        self.assertIn('float({action="enable", window="address:0xcafe"})', code)
        self.assertIn('resize({x=553, y=640, relative=false, window="address:0xcafe"})', code)
        self.assertIn('move({x=164, y=85, relative=false, window="address:0xcafe"})', code)

    @patch.object(placement, "hyprctl")
    def test_invalid_address_cannot_enter_lua_or_dispatcher(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Explorador", address='0xcafe;exit', monitor=0)
        ]), json.dumps([self.monitor()])]
        with self.assertRaises(ValueError):
            placement.place(123, "Explorador", 0)
        self.assertEqual(ctl.call_count, 2)
