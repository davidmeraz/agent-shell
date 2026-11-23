"""Pruebas del lector de flujo Git (topología de ramas, estado y detalle de commits)."""

from __future__ import annotations

import io
import json
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from harness.core.server import HarnessServer
from harness.work.git_flow import GitFlowReader, compute_graph_lanes


def _git(cwd: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(cwd), *args],
        capture_output=True,
        text=True,
        check=True,
        env={
            "PATH": "/usr/bin:/bin",
            "GIT_AUTHOR_NAME": "Test Dev",
            "GIT_AUTHOR_EMAIL": "dev@example.invalid",
            "GIT_COMMITTER_NAME": "Test Dev",
            "GIT_COMMITTER_EMAIL": "dev@example.invalid",
        },
    )
    return proc.stdout.strip()


class _DummySession:
    def account(self):
        return {"authenticated": False, "method": "none", "email": "", "plan": "", "plan_enabled": False, "accounts": []}


class GitFlowTests(unittest.TestCase):
    def test_non_git_directory_returns_clean_empty_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = GitFlowReader(Path(tmp)).summary()
            self.assertFalse(data["is_repo"])
            self.assertEqual(data["commits"], [])
            self.assertTrue(data["clean"])

    def test_branch_merge_graph_status_and_commit_detail(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "demo"
            repo.mkdir()
            _git(repo, "init", "-b", "main")
            (repo / "README.md").write_text("# Demo\n", encoding="utf-8")
            _git(repo, "add", "README.md")
            _git(repo, "commit", "-m", "chore: commit inicial")

            _git(repo, "checkout", "-b", "feat/ui")
            (repo / "app.py").write_text("print('hola')\nprint('mundo')\n", encoding="utf-8")
            _git(repo, "add", "app.py")
            _git(repo, "commit", "-m", "feat(ui): añadir módulo principal")

            _git(repo, "checkout", "main")
            (repo / "notes.txt").write_text("nota\n", encoding="utf-8")
            _git(repo, "add", "notes.txt")
            _git(repo, "commit", "-m", "docs: añadir notas")

            _git(repo, "merge", "--no-ff", "feat/ui", "-m", "feat: integrar rama ui")
            _git(repo, "tag", "v0.1.0")

            # Cambios pendientes: 1 staged, 1 modified, 1 untracked
            (repo / "staged.txt").write_text("ready\n", encoding="utf-8")
            _git(repo, "add", "staged.txt")
            (repo / "README.md").write_text("# Demo editado\n", encoding="utf-8")
            (repo / "scratch.tmp").write_text("temp\n", encoding="utf-8")

            reader = GitFlowReader(repo)
            summary = reader.summary()
            self.assertTrue(summary["is_repo"])
            self.assertEqual(summary["branch"], "main")
            self.assertFalse(summary["clean"])
            self.assertEqual(summary["staged_count"], 1)
            self.assertEqual(summary["modified_count"], 1)
            self.assertEqual(summary["untracked_count"], 1)
            self.assertEqual(len(summary["commits"]), 4)
            self.assertGreaterEqual(summary["graph_lanes"], 2)

            head = summary["commits"][0]
            self.assertTrue(head["is_head"])
            self.assertTrue(head["is_merge"])
            self.assertEqual(head["kind"], "feat")
            self.assertTrue(any(r["kind"] == "tag" and r["name"] == "v0.1.0" for r in head["refs"]))
            self.assertEqual(len(head["out_edges"]), 2)

            feat_commit = next(c for c in summary["commits"] if c["subject"] == "feat(ui): añadir módulo principal")
            detail = reader.commit_detail(feat_commit["hash"])
            self.assertEqual(detail["short_hash"], feat_commit["short_hash"])
            self.assertEqual(detail["file_count"], 1)
            self.assertEqual(detail["total_added"], 2)
            self.assertEqual(detail["files"][0]["path"], "app.py")

            with self.assertRaises(ValueError):
                reader.commit_detail("not-a-valid-hash;rm -rf")

    def test_compute_graph_lanes_converges_cleanly(self):
        commits = [
            {"hash": "m1", "parents": ["p1", "b1"]},
            {"hash": "b1", "parents": ["base"]},
            {"hash": "p1", "parents": ["base"]},
            {"hash": "base", "parents": []},
        ]
        result = compute_graph_lanes(commits)
        self.assertEqual(result[0]["lane"], 0)
        self.assertEqual(result[1]["lane"], 1)
        self.assertEqual(result[2]["lane"], 0)
        self.assertEqual(result[3]["lane"], 0)
        self.assertGreaterEqual(len(result[3]["in_edges"]), 2)

    def test_server_git_flow_and_commit_ipc(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "work-repo"
            repo.mkdir()
            _git(repo, "init", "-b", "main")
            (repo / "main.py").write_text("x = 1\n", encoding="utf-8")
            _git(repo, "add", "main.py")
            _git(repo, "commit", "-m", "feat: inicio")

            output = io.StringIO()
            server = HarnessServer(root / "chats", output, _DummySession(), client=None, config_root=root / "config")
            server.handle({"type": "project.create", "name": "Demo", "workdir": str(repo)})
            project_id = server.project["project_id"]

            server.handle({"type": "git.flow", "project_id": project_id, "request_id": "req-1"})
            deadline = time.monotonic() + 3.0
            flow_event = None
            while time.monotonic() < deadline:
                events = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
                flow_event = next((e for e in events if e["type"] == "git.flow.state" and e["data"]["request_id"] == "req-1"), None)
                if flow_event:
                    break
                time.sleep(0.02)
            self.assertIsNotNone(flow_event)
            self.assertTrue(flow_event["data"]["is_repo"])
            commit_hash = flow_event["data"]["commits"][0]["hash"]

            server.handle({"type": "git.commit", "project_id": project_id, "request_id": "req-2", "hash": commit_hash})
            detail_event = None
            deadline = time.monotonic() + 3.0
            while time.monotonic() < deadline:
                events = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
                detail_event = next((e for e in events if e["type"] == "git.commit.detail" and e["data"]["request_id"] == "req-2"), None)
                if detail_event:
                    break
                time.sleep(0.02)
            self.assertIsNotNone(detail_event)
            self.assertEqual(detail_event["data"]["subject"], "feat: inicio")


if __name__ == "__main__":
    unittest.main()
