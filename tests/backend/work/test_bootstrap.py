"""Pruebas del bootstrap estático inicial de proyectos en Work."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.support import paths  # noqa: F401
from harness.work.bootstrap import build_work_bootstrap, git_software_context


class WorkBootstrapTests(unittest.TestCase):
    def test_empty_folder_returns_empty_string(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(build_work_bootstrap(Path(tmp)), "")

    def test_includes_files_agents_md_and_excludes_secrets_symlinks_and_venv(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "AGENTS.md").write_text("# Guía\nUsa unittest.\n", encoding="utf-8")
            (root / "app.py").write_text("x = 1\n", encoding="utf-8")
            (root / ".env").write_text("SECRET=123\n", encoding="utf-8")
            (root / ".env.local").write_text("SECRET=456\n", encoding="utf-8")
            (root / ".env.example").write_text("EXAMPLE=ok\n", encoding="utf-8")
            (root / ".venv").mkdir()
            (root / ".venv" / "python").write_text("bin", encoding="utf-8")
            (root / "link.txt").symlink_to(root / "app.py")

            text = build_work_bootstrap(root)
            self.assertIn("git_repo: no", text)
            self.assertIn("app.py", text)
            self.assertIn(".env.example", text)
            self.assertIn("# Guía", text)
            self.assertNotIn("SECRET=123", text)
            self.assertNotIn("\n.env\n", text)
            self.assertNotIn(".env.local", text)
            self.assertNotIn(".venv", text)
            self.assertNotIn("link.txt", text)

    def test_detects_git_repo_and_bounds_agents_md(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".git").mkdir()
            (root / "AGENTS.md").write_text("A" * 6000, encoding="utf-8")
            text = build_work_bootstrap(root)
            self.assertIn("git_repo: yes", text)
            self.assertIn("[…]", text)
            self.assertLess(len(text), 4600)

    def test_real_git_repo_includes_branch_recent_commits_and_filtered_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = {
                "PATH": "/usr/bin:/bin", "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "t@e.invalid",
                "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "t@e.invalid",
            }
            subprocess.run(["git", "init", "-b", "main"], cwd=root, check=True, capture_output=True, env=env)
            (root / "app.py").write_text("v = 1\n", encoding="utf-8")
            subprocess.run(["git", "add", "app.py"], cwd=root, check=True, capture_output=True, env=env)
            subprocess.run(["git", "commit", "-m", "feat: primer modulo"], cwd=root, check=True, capture_output=True, env=env)
            (root / "app.py").write_text("v = 2\n", encoding="utf-8")
            (root / ".env").write_text("TOKEN=secret\n", encoding="utf-8")

            git_info = git_software_context(root)
            self.assertIn("git_branch: main", git_info)
            self.assertIn("feat: primer modulo", git_info)
            self.assertIn("app.py", git_info)
            self.assertNotIn(".env", git_info)

            full = build_work_bootstrap(root)
            self.assertIn("recent_commits:", full)
            self.assertIn("feat: primer modulo", full)


if __name__ == "__main__":
    unittest.main()
