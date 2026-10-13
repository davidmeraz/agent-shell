"""Disposición inicial y selección aislada de las ventanas de texto."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

from tests.support.paths import PROJECT

spec = importlib.util.spec_from_file_location(
    "viewer_placement", PROJECT / "scripts/place-text-viewer.py")
placement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placement)


class ViewerPlacementTests(unittest.TestCase):
    def monitor(self, **values):
        return dict(id=0, x=0, y=0, width=2560, height=1440, scale=1,
                    reserved=[10, 60, 10, 10], **values)

    def test_reference_layout(self):
        monitor = self.monitor()
        self.assertEqual(placement.geometry(monitor, 0), (30, 80, 820, 655))
        self.assertEqual(placement.geometry(monitor, 1), (1710, 80, 820, 1330))
        self.assertEqual(placement.geometry(monitor, 2), (30, 755, 820, 655))
        self.assertEqual(placement.geometry(monitor, 3), (870, 240, 820, 1170))
        self.assertEqual(placement.geometry(monitor, 4), (870, 80, 820, 140))

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
        self.assertEqual(placement.geometry(rotated, 1), (1714, 20, 826, 1400))

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
        self.assertIn("resizewindowpixel exact 820 1330,address:0xcafe", batch)
        self.assertIn("movewindowpixel exact 1710 80,address:0xcafe", batch)
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
        self.assertIn('resize({x=820, y=655, relative=false, window="address:0xcafe"})', code)
        self.assertIn('move({x=30, y=80, relative=false, window="address:0xcafe"})', code)

    @patch.object(placement, "hyprctl")
    def test_invalid_address_cannot_enter_lua_or_dispatcher(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Explorador", address='0xcafe;exit', monitor=0)
        ]), json.dumps([self.monitor()])]
        with self.assertRaises(ValueError):
            placement.place(123, "Explorador", 0)
        self.assertEqual(ctl.call_count, 2)

    @patch.object(placement, "hyprctl")
    def test_all_three_windows_follow_own_chat_workspace_and_monitor(self, ctl):
        import json
        for viewer in (0, 1, 2):
            with self.subTest(viewer=viewer):
                title = "Explorador" if viewer == 0 else f"Visor {viewer} · main.py"
                ctl.reset_mock()
                main_monitor = dict(self.monitor(), id=1, x=2560)
                ctl.side_effect = [json.dumps([
                    dict(pid=999, title="Chat principal", address="0xdead", monitor=0, workspace={"id": 3}),
                    dict(pid=123, title="Chat principal", address="0xabcd", monitor=1,
                         workspace={"id": 9, "name": "Proyecto"}),
                    dict(pid=123, title=title, address="0xcafe", monitor=0, workspace={"id": 3}),
                ]), json.dumps([self.monitor(), main_monitor]), '{"version":"0.56.2"}', "ok\n"]
                self.assertTrue(placement.place(123, title, viewer, "Chat principal"))
                code = ctl.call_args.args[1]
                self.assertIn('workspace="9", follow=false, window="address:0xcafe"', code)
                x, y, _, _ = placement.geometry(main_monitor, viewer)
                self.assertIn(f'x={x}, y={y}, relative=false', code)
                self.assertNotIn("dead", code)
                self.assertEqual("abcd" in code, viewer == 0)

    @patch.object(placement, "hyprctl")
    def test_legacy_dispatcher_uses_silent_workspace_move(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 12, "name": "named workspace"}),
            dict(pid=123, title="Explorador", address="0xcafe", monitor=0, workspace={"id": 2}),
        ]), json.dumps([self.monitor()]), '{"version":"0.54.3"}', "ok\n"]
        self.assertTrue(placement.place(123, "Explorador", 0, "Chat"))
        command, code = ctl.call_args.args
        self.assertEqual(command, "--batch")
        self.assertIn("movetoworkspacesilent 12,address:0xcafe", code)
        self.assertNotIn("named workspace", code)

    @patch.object(placement, "hyprctl")
    def test_same_workspace_does_not_dispatch_an_unnecessary_move(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Explorador", address="0xcafe", monitor=0, workspace={"id": 2}),
        ]), json.dumps([self.monitor()]), '{"version":"0.56.2"}', "ok\n"]
        self.assertTrue(placement.place(123, "Explorador", 0, "Chat"))
        self.assertNotIn("workspace=", ctl.call_args.args[1])
        self.assertNotIn("follow=", ctl.call_args.args[1])

    @patch.object(placement.time, "sleep")
    @patch.object(placement, "hyprctl")
    def test_missing_or_ambiguous_own_chat_never_uses_another_process(self, ctl, sleep):
        import json
        viewer = dict(pid=123, title="Explorador", address="0xcafe", monitor=0)
        for mains in ([dict(pid=999, title="Chat")],
                      [dict(pid=123, title="Chat", mapped=False)],
                      [dict(pid=123, title="Chat"), dict(pid=123, title="Chat")]):
            with self.subTest(mains=mains):
                ctl.reset_mock()
                ctl.return_value = json.dumps([viewer, *mains])
                self.assertFalse(placement.place(123, "Explorador", 0, "Chat"))
                self.assertEqual(ctl.call_count, 20)
                self.assertTrue(all(call.args == ("-j", "clients") for call in ctl.call_args_list))

    @patch.object(placement, "hyprctl")
    def test_reopen_uses_current_chat_workspace_including_special(self, ctl):
        import json
        for identifier, name, expected in ((4, "4", "4"), (-1337, "Proyecto", "name:Proyecto"),
                                           (-99, "special:proyecto", "special:proyecto"), (-99, "special", "special")):
            with self.subTest(workspace=identifier):
                ctl.side_effect = [json.dumps([
                    dict(pid=123, title="Chat", monitor=0, workspace={"id": identifier, "name": name}),
                    dict(pid=123, title="Visor 1", address="0xcafe", monitor=0, workspace={"id": 2}),
                ]), json.dumps([self.monitor()]), '{"version":"0.56.2"}', "ok\n"]
                self.assertTrue(placement.place(123, "Visor 1", 1, "Chat"))
                self.assertIn(f'workspace="{expected}", follow=false', ctl.call_args.args[1])

    def test_invalid_workspace_cannot_enter_commands(self):
        for workspace in ({"id": "4;evil"}, {"id": True}, {"id": 0},
                          {"id": -99, "name": "special:x;evil"},
                          {"id": -99, "name": 'special:x"'}, {"id": -99, "name": "special:x,evil"}):
            with self.subTest(workspace=workspace), self.assertRaises(ValueError):
                placement.workspace_selector({"workspace": workspace})

    def test_grid_symmetry_alignment_and_no_overlap_on_large_displays(self):
        # Incluye dimensiones impares, escala fraccional, rotación y origen negativo.
        for width, height, scale, transform in ((2560, 1440, 1, 0), (1921, 1081, 1, 0),
                                                (3840, 2160, 1.5, 0), (2160, 3840, 1, 1)):
            for quota_height in ((140, 260) if height == 1081 else (140, 260, 420)):
                with self.subTest(width=width, scale=scale, quota=quota_height):
                    monitor = dict(x=-600, y=70, width=width, height=height, scale=scale,
                                   transform=transform, reserved=[11, 51, 19, 13])
                    grid = [placement.geometry(monitor, role, quota_height) for role in placement.ROLES]
                    tree, right, left, chat, usage = grid
                    self.assertEqual(len({rect[2] for rect in grid}), 1)
                    self.assertEqual(tree[0], left[0])
                    self.assertEqual(tree[3], left[3])
                    self.assertEqual(chat[0], usage[0])
                    self.assertEqual(tree[1], right[1])
                    self.assertEqual(usage[1], right[1])
                    self.assertEqual(left[1] + left[3], right[1] + right[3])
                    self.assertEqual(chat[1] + chat[3], right[1] + right[3])
                    logical_width = round((height if transform % 2 else width) / scale) - 30
                    self.assertLessEqual(abs(2 * chat[0] + chat[2] - (2 * (-600 + 11) + logical_width)), 1)
                    gap_left = chat[0] - tree[0] - tree[2]
                    gap_right = right[0] - chat[0] - chat[2]
                    self.assertLessEqual(abs(gap_left - gap_right), 1)
                    self.assertLessEqual(abs(gap_left - 20), 1)
                    for i, a in enumerate(grid):
                        for b in grid[i + 1:]:
                            self.assertTrue(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0]
                                            or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1])

    def test_hidden_usage_leaves_full_height_chat(self):
        self.assertEqual(placement.geometry(self.monitor(), 3, 0), (870, 80, 820, 1330))

    @patch.object(placement, "hyprctl")
    def test_opening_tree_aligns_chat_and_own_usage_with_real_height(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Explorador", address="0xcafe", monitor=0, workspace={"id": 2}),
            dict(pid=123, title=placement.USAGE_TITLE, address="0xface", monitor=0,
                 workspace={"id": 4}, size=[320, 260]),
            dict(pid=999, title=placement.USAGE_TITLE, address="0xdead", monitor=0, size=[320, 420]),
        ]), json.dumps([self.monitor()]), '{"version":"0.56.2"}', "ok\n"]
        self.assertTrue(placement.place(123, "Explorador", 0, "Chat"))
        code = ctl.call_args.args[1]
        self.assertIn('resize({x=820, y=1050, relative=false, window="address:0xabcd"})', code)
        self.assertIn('move({x=870, y=360, relative=false, window="address:0xabcd"})', code)
        self.assertIn('resize({x=820, y=260, relative=false, window="address:0xface"})', code)
        self.assertIn('workspace="2", follow=false, window="address:0xface"', code)
        self.assertNotIn("dead", code)

    @patch.object(placement, "hyprctl")
    def test_opening_usage_aligns_center_without_moving_file_windows(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title=placement.USAGE_TITLE, address="0xface", monitor=0,
                 workspace={"id": 2}, size=[320, 140]),
            dict(pid=123, title="Visor 1", address="0xbeef", monitor=0, workspace={"id": 2}),
        ]), json.dumps([self.monitor()]), '{"version":"0.54.3"}', "ok\n"]
        self.assertTrue(placement.place(123, placement.USAGE_TITLE, 4, "Chat"))
        code = ctl.call_args.args[1]
        self.assertIn("resizewindowpixel exact 820 140,address:0xface", code)
        self.assertIn("movewindowpixel exact 870 240,address:0xabcd", code)
        self.assertNotIn("beef", code)
