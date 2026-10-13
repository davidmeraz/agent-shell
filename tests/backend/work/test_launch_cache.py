"""Persistencia y detección de cambios del inicio reutilizable de Work."""

import os
import sys
import tempfile
import unittest
from pathlib import Path

from tests.support.paths import PROJECT
from harness.work.launch_cache import LaunchCache, MAX_CONTEXT_BYTES, command_paths, project_snapshot
from harness.work.projects import ProjectStore


class LaunchCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folder = self.root / "workspace"
        self.folder.mkdir()
        self.store = ProjectStore(self.root / "projects")
        self.project = self.store.create("Fixture", str(self.folder))
        self.cache = LaunchCache(self.store)

    def test_manifest_changes_are_detected_even_with_same_size_and_mtime(self):
        manifest = self.folder / "package.json"
        manifest.write_text('{"scripts":{"dev":"vite"}}')
        before = project_snapshot(self.folder)
        stamp = manifest.stat()
        manifest.write_text('{"scripts":{"dev":"next"}}')
        os.utime(manifest, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
        self.assertNotEqual(before.fingerprint, project_snapshot(self.folder).fingerprint)

    def test_source_edits_and_generated_logs_keep_command_but_entry_removal_invalidates(self):
        entry = self.folder / "main.py"
        entry.write_text("print('original')")
        before = project_snapshot(self.folder)
        entry.write_text("print('new source')")
        (self.folder / "generated.log").write_text("runtime output")
        self.assertEqual(before.fingerprint, project_snapshot(self.folder, before.watched_paths).fingerprint)
        entry.unlink()
        self.assertNotEqual(before.fingerprint, project_snapshot(self.folder, before.watched_paths).fingerprint)

    def test_nested_launch_script_changes_and_permissions_invalidate(self):
        (self.folder / "tools").mkdir()
        entry = self.folder / "tools" / "run.sh"
        entry.write_text("printf before")
        watched = command_paths("sh tools/run.sh", self.folder)
        self.assertEqual(watched, ["tools/run.sh"])
        before = project_snapshot(self.folder, watched)
        entry.chmod(0o700)
        self.assertNotEqual(before.fingerprint, project_snapshot(self.folder, watched).fingerprint)
        before = project_snapshot(self.folder, watched)
        entry.write_text("printf after")
        self.assertNotEqual(before.fingerprint, project_snapshot(self.folder, watched).fingerprint)

    def test_bounded_prefetch_excludes_env_external_symlinks_and_fifos(self):
        (self.folder / "README.md").write_text("x" * 40000)
        (self.folder / ".env").write_text("PRIVATE_VALUE=do-not-prefetch")
        outside = self.root / "outside"
        outside.write_text("external private contents")
        (self.folder / "package.json").symlink_to(outside)
        os.mkfifo(self.folder / "run.sh")
        snapshot = project_snapshot(self.folder, [".env", "../outside"])
        self.assertFalse(snapshot.cacheable)
        contents = "".join(file["text"] for file in snapshot.context["files"])
        self.assertNotIn("do-not-prefetch", contents)
        self.assertNotIn("external private", contents)
        self.assertLessEqual(len(contents.encode()), MAX_CONTEXT_BYTES)
        self.assertTrue(snapshot.context["files"][0]["truncated"])

    def test_profile_persists_is_private_and_old_workspace_cannot_overwrite_it(self):
        snapshot = project_snapshot(self.folder)
        self.assertTrue(self.cache.save(self.project["project_id"], self.folder, "printf ok", snapshot))
        reopened = LaunchCache(ProjectStore(self.store.root))
        self.assertEqual(reopened.load(self.project["project_id"], self.folder)["command"], "printf ok")
        self.assertEqual(self.store._path(self.project["project_id"]).stat().st_mode & 0o777, 0o600)
        other = self.root / "other"
        other.mkdir()
        self.store.update_workdir(self.project["project_id"], str(other))
        self.assertFalse(self.cache.save(self.project["project_id"], self.folder, "printf stale", snapshot))
        self.assertIsNone(reopened.load(self.project["project_id"], other))
        self.assertEqual(self.store.load(self.project["project_id"])["workdir"], str(other))

    def test_malformed_profile_is_ignored_and_projects_are_isolated(self):
        snapshot = project_snapshot(self.folder)
        self.cache.save(self.project["project_id"], self.folder, "printf ok", snapshot)
        other = self.root / "other"
        other.mkdir()
        second = self.store.create("Second", str(other))
        self.assertIsNone(self.cache.load(second["project_id"], other))
        good = self.store.load(self.project["project_id"])
        for value in ({"command": ""}, {"workspace": str(other)}, {"watched_paths": [None]}):
            bad = {**good, "launch_profile": {**good["launch_profile"], **value}}
            self.store.save(bad)
            self.assertIsNone(self.cache.load(self.project["project_id"], self.folder))
