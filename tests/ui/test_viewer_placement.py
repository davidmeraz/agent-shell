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
        f5 = placement.geometry(monitor, 5)
        f6 = placement.geometry(monitor, 6)
        self.assertGreaterEqual(f5[2], 520)
        self.assertGreaterEqual(f5[3], 440)
        self.assertEqual(f6[0] - f5[0], 28)
        self.assertEqual(f6[1] - f5[1], 24)

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

    def test_provider_usage_windows_share_the_chat_column(self):
        for width in (2560, 1920, 1366):
            for count in (1, 2, 3):
                with self.subTest(width=width, count=count):
                    monitor = {**self.monitor(), "width": width}
                    chat = placement.geometry(monitor, 3, 160)
                    row = [placement.provider_usage_geometry(monitor, i, count, 160) for i in range(count)]
                    self.assertEqual(row[0][0], chat[0])
                    self.assertEqual(row[-1][0] + row[-1][2], chat[0] + chat[2])
                    self.assertTrue(all(a[0] + a[2] < b[0] for a, b in zip(row, row[1:])))
                    self.assertTrue(all(rect[1] + rect[3] <= chat[1] and rect[3] == 160 for rect in row))

    @patch.object(placement, "hyprctl")
    def test_placing_one_provider_usage_window_aligns_all_and_the_chat(self, ctl):
        import json
        titles = placement.PROVIDER_USAGE_TITLES
        clients = [dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2})]
        clients += [dict(pid=123, title=title, address=f"0xa{i}", monitor=0, workspace={"id": 2}, size=[260, 140 + i])
                    for i, title in enumerate(titles)]
        clients.append(dict(pid=999, title=titles[0], address="0xdead", monitor=0, size=[260, 400]))
        ctl.side_effect = [json.dumps(clients), json.dumps([self.monitor()]), '{"version":"0.56.2"}', "ok\n"]
        self.assertTrue(placement.place(123, titles[2], placement.PROVIDER_USAGE_ROLE, "Chat"))
        code = ctl.call_args.args[1]
        for i in range(3):
            x, y, w, h = placement.provider_usage_geometry(self.monitor(), i, 3, 142)
            self.assertIn(f'resize({{x={w}, y={h}, relative=false, window="address:0xa{i}"}})', code)
            self.assertIn(f'move({{x={x}, y={y}, relative=false, window="address:0xa{i}"}})', code)
        self.assertIn('move({x=870, y=242, relative=false, window="address:0xabcd"})', code)
        self.assertNotIn("dead", code)

    def test_agent_windows_stack_in_the_right_column_without_covering_the_chat(self):
        for width, height in ((2560, 1440), (1920, 1080), (1366, 768)):
            with self.subTest(width=width):
                monitor = {**self.monitor(), "width": width, "height": height}
                chat = placement.geometry(monitor, 3, 160)
                slots = [placement.agent_geometry(monitor, slot) for slot in range(4)]
                for x, y, w, h in slots:
                    self.assertGreaterEqual(x, 10)
                    self.assertLessEqual(x + w, width - 10)
                    self.assertGreaterEqual(w, 360)
                    self.assertLessEqual(w, placement.AGENT_WIDTH_MAX)
                    self.assertGreaterEqual(h, placement.AGENT_EXPANDED_MIN_HEIGHT)
                    self.assertTrue(60 <= y and y + h <= height - 10)
                if width >= 1920:
                    self.assertTrue(all(x >= chat[0] + chat[2] for x, _, _, _ in slots))
                self.assertEqual(len({rect[1] for rect in slots}), 4)
        big = [placement.agent_geometry(self.monitor(), slot) for slot in range(4)]
        self.assertTrue(all(a[1] + a[3] <= b[1] for a, b in zip(big, big[1:])))
        self.assertEqual(big[0][2], placement.AGENT_WIDTH_MAX)

    def test_agent_stack_handles_compact_expanded_and_fallback_positions(self):
        # 1 solo agente expandido aprovecha 460 px; 3 compactos + 1 expandido no se solapan ni en 1080p.
        for width, height in ((2560, 1440), (1920, 1080)):
            monitor = {**self.monitor(), "width": width, "height": height}
            side, solo = placement.agent_stack_geometry(monitor, [False])
            self.assertEqual(side, "right")
            self.assertEqual(solo[0][3], placement.AGENT_SOLO_EXPANDED_HEIGHT)
            side, mixed = placement.agent_stack_geometry(monitor, [True, True, True, False])
            self.assertEqual(side, "right")
            self.assertEqual([r[3] for r in mixed[:3]], [placement.AGENT_COMPACT_HEIGHT] * 3)
            self.assertEqual(mixed[3][3], placement.AGENT_EXPANDED_HEIGHT)
            self.assertTrue(all(a[1] + a[3] < b[1] for a, b in zip(mixed, mixed[1:])))
            self.assertLessEqual(mixed[-1][1] + mixed[-1][3], height - 10)

        # Cuando Visor 1 ocupa la derecha y el Explorador está abierto, los agentes pasan debajo del Explorador.
        monitor = self.monitor()
        explorer = placement.geometry(monitor, 0)
        chat = placement.geometry(monitor, 3)
        side, below = placement.agent_stack_geometry(monitor, [True, False], right_occupied=True, explorer_open=True)
        self.assertEqual(side, "left")
        for x, y, w, h in below:
            self.assertLessEqual(x + w, chat[0])
            self.assertGreaterEqual(y, explorer[1] + explorer[3])
            self.assertLessEqual(y + h, monitor["height"] - 10)
        self.assertLess(below[0][1] + below[0][3], below[1][1])

        # Si Visor 1 está abierto pero el Explorador no, usan toda la columna izquierda.
        side, full_left = placement.agent_stack_geometry(monitor, [False], right_occupied=True, explorer_open=False)
        self.assertEqual(side, "left")
        self.assertEqual(full_left[0][1], explorer[1])
        self.assertLessEqual(full_left[0][0] + full_left[0][2], chat[0])

    @patch.object(placement, "hyprctl")
    def test_place_agents_stacks_group_detects_visor_and_validates_inputs(self, ctl):
        import json
        specs = [
            {"title": "Agent Shell · Agente · Explorador", "compact": True},
            {"title": "Agent Shell · Agente · Constructor", "compact": False},
        ]
        # Sin Visor 1: columna derecha en Lua.
        ctl.side_effect = [json.dumps([
            dict(pid=999, title="Agent Shell · Agente · Explorador", address="0xdead", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Explorador · app", address="0x1111", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Explorador", address="0xcafe", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Constructor", address="0xbeef", monitor=0, workspace={"id": 5}),
        ]), json.dumps([self.monitor()]), '{"version":"0.57.2"}', "ok\n"]
        self.assertEqual(placement.place_agents(123, "Chat", specs), "right")
        code = ctl.call_args.args[1]
        _, rects = placement.agent_stack_geometry(self.monitor(), [True, False])
        self.assertIn(f'resize({{x={rects[0][2]}, y={rects[0][3]}, relative=false, window="address:0xcafe"}})', code)
        self.assertIn(f'move({{x={rects[0][0]}, y={rects[0][1]}, relative=false, window="address:0xcafe"}})', code)
        self.assertIn('workspace="2", follow=false, window="address:0xbeef"', code)
        self.assertIn(f'move({{x={rects[1][0]}, y={rects[1][1]}, relative=false, window="address:0xbeef"}})', code)
        self.assertNotIn("dead", code)
        self.assertNotIn("abcd", code)

        # Con Visor 1 y Explorador en el mismo escritorio: respaldo abajo a la izquierda en modo legado.
        ctl.reset_mock(side_effect=True)
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Explorador · app", address="0x1111", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Visor 1 · main.py", address="0x2222", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Explorador", address="0xcafe", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Constructor", address="0xbeef", monitor=0, workspace={"id": 2}),
        ]), json.dumps([self.monitor()]), '{"version":"0.54.3"}', "ok\nok\nok\nok\nok\nok\n"]
        self.assertEqual(placement.place_agents(123, "Chat", specs), "left")
        command, batch = ctl.call_args.args
        self.assertEqual(command, "--batch")
        _, left_rects = placement.agent_stack_geometry(self.monitor(), [True, False], right_occupied=True, explorer_open=True)
        self.assertIn(f"movewindowpixel exact {left_rects[0][0]} {left_rects[0][1]},address:0xcafe", batch)
        self.assertIn(f"resizewindowpixel exact {left_rects[1][2]} {left_rects[1][3]},address:0xbeef", batch)

        # Rechaza títulos ajenos o direcciones inválidas.
        with self.assertRaises(ValueError):
            placement.place_agents(123, "Chat", [{"title": "Otro título", "compact": False}])
        ctl.reset_mock(side_effect=True)
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Explorador", address="0xcafe;evil", monitor=0, workspace={"id": 2}),
        ]), json.dumps([self.monitor()])]
        with self.assertRaises(ValueError):
            placement.place_agents(123, "Chat", [{"title": "Agent Shell · Agente · Explorador", "compact": True}])

    @patch.object(placement, "hyprctl")
    def test_opening_right_viewer_relocates_open_agents_below_explorer(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Explorador · app", address="0x1111", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Visor 1 · app.py", address="0x2222", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Explorador", address="0xcafe", monitor=0, workspace={"id": 2},
                 at=[1710, 80], size=[480, 126]),
            dict(pid=123, title="Agent Shell · Agente · Constructor", address="0xbeef", monitor=0, workspace={"id": 2},
                 at=[1710, 218], size=[480, 420]),
        ]), json.dumps([self.monitor()]), '{"version":"0.57.2"}', "ok\n"]
        self.assertTrue(placement.place(123, "Visor 1 · app.py", 1, "Chat"))
        code = ctl.call_args.args[1]
        _, left_rects = placement.agent_stack_geometry(self.monitor(), [True, False], right_occupied=True, explorer_open=True)
        self.assertIn('window="address:0x2222"', code)
        self.assertIn(f'move({{x={left_rects[0][0]}, y={left_rects[0][1]}, relative=false, window="address:0xcafe"}})', code)
        self.assertIn(f'move({{x={left_rects[1][0]}, y={left_rects[1][1]}, relative=false, window="address:0xbeef"}})', code)

    @patch.object(placement, "hyprctl")
    def test_placing_an_agent_moves_only_that_window(self, ctl):
        import json
        ctl.side_effect = [json.dumps([
            dict(pid=123, title="Chat", address="0xabcd", monitor=0, workspace={"id": 2}),
            dict(pid=123, title="Agent Shell · Agente · Revisor", address="0xcafe", monitor=0, workspace={"id": 5}),
            dict(pid=123, title="Agent Shell · Agente · Constructor", address="0xbeef", monitor=0, workspace={"id": 2}),
        ]), json.dumps([self.monitor()]), '{"version":"0.57.2"}', "ok\n"]
        self.assertTrue(placement.place(123, "Agent Shell · Agente · Revisor", placement.AGENT_ROLES[1], "Chat"))
        code = ctl.call_args.args[1]
        x, y, w, h = placement.agent_geometry(self.monitor(), 1)
        self.assertIn(f'move({{x={x}, y={y}, relative=false, window="address:0xcafe"}})', code)
        self.assertIn('workspace="2", follow=false, window="address:0xcafe"', code)
        self.assertNotIn("beef", code)
        self.assertNotIn('window="address:0xabcd"', code)

    @patch.object(placement, "hyprctl")
    def test_agent_rule_is_named_scoped_and_only_for_lua(self, ctl):
        ctl.side_effect = ['{"version":"0.57.2"}', "ok\n"]
        placement.prepare_agent_windows()
        code = ctl.call_args.args[1]
        for part in ('name = "agent-shell-agents"', 'class = "^agent-shell$"', "Agente", "no_initial_focus = true"):
            self.assertIn(part, code)
        ctl.reset_mock(side_effect=True)
        ctl.side_effect = ['{"version":"0.54.3"}']
        placement.prepare_agent_windows()
        self.assertEqual(ctl.call_count, 1)

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
