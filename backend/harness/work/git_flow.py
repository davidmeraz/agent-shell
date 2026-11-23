"""Lector de flujo Git de solo lectura para los espacios Work y App.

Calcula topología de ramas/carriles (graph lanes), estado del árbol de trabajo
y detalles por commit usando `git` sin shell y con tiempos de espera acotados.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

MAX_COMMITS_LIMIT = 150
DEFAULT_MAX_COMMITS = 80
MAX_STATUS_FILES = 40
MAX_DETAIL_FILES = 80
GIT_TIMEOUT_SECONDS = 3.0

_HASH_RE = re.compile(r"^[0-9a-fA-F]{4,40}$")
_CONVENTIONAL_RE = re.compile(
    r"^(feat|fix|refactor|docs|test|chore|style|perf|build|ci|revert)(?:\([^)]+\))?!?:\s*",
    re.IGNORECASE,
)


def _run_git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=GIT_TIMEOUT_SECONDS,
        check=False,
    )


def _parse_refs(raw: str) -> tuple[bool, list[dict[str, str]]]:
    """Separa decoraciones de `git log %D` en etiquetas estructuradas."""
    if not raw.strip():
        return False, []
    is_head = False
    refs: list[dict[str, str]] = []
    for token in (part.strip() for part in raw.split(",") if part.strip()):
        if token == "HEAD":
            is_head = True
            refs.append({"name": "HEAD", "kind": "head"})
        elif token.startswith("HEAD -> "):
            is_head = True
            branch = token[len("HEAD -> "):].strip()
            if branch:
                refs.append({"name": branch, "kind": "head"})
        elif token.startswith("tag: "):
            tag = token[len("tag: "):].strip()
            if tag:
                refs.append({"name": tag, "kind": "tag"})
        elif "/" in token:
            refs.append({"name": token, "kind": "remote"})
        else:
            refs.append({"name": token, "kind": "branch"})
    return is_head, refs


def _detect_commit_kind(subject: str) -> str:
    match = _CONVENTIONAL_RE.match(subject or "")
    return match.group(1).lower() if match else ""


def compute_graph_lanes(commits: list[dict]) -> list[dict]:
    """Asigna carriles y aristas de entrada/salida para dibujar el grafo de commits."""
    active_lanes: list[str | None] = []
    max_lanes_seen = 1

    for commit in commits:
        commit_hash = commit["hash"]
        parents: list[str] = commit["parents"]

        matching = [idx for idx, expected in enumerate(active_lanes) if expected == commit_hash]
        if matching:
            lane = matching[0]
            in_edges = [{"from": idx, "to": lane} for idx in matching]
            for extra in matching[1:]:
                active_lanes[extra] = None
        else:
            free = next((idx for idx, val in enumerate(active_lanes) if val is None), None)
            if free is not None:
                lane = free
                active_lanes[lane] = commit_hash
            else:
                lane = len(active_lanes)
                active_lanes.append(commit_hash)
            in_edges = []

        pass_lanes = [idx for idx, val in enumerate(active_lanes) if idx != lane and val is not None]
        out_edges: list[dict] = []

        if not parents:
            active_lanes[lane] = None
        else:
            primary = parents[0]
            existing_primary = next(
                (idx for idx, val in enumerate(active_lanes) if idx != lane and val == primary),
                None,
            )
            if existing_primary is not None and existing_primary < lane:
                active_lanes[lane] = None
                out_edges.append({"from": lane, "to": existing_primary, "merge": False})
            else:
                active_lanes[lane] = primary
                out_edges.append({"from": lane, "to": lane, "merge": False})

            for parent in parents[1:]:
                existing = next((idx for idx, val in enumerate(active_lanes) if val == parent), None)
                if existing is not None:
                    out_edges.append({"from": lane, "to": existing, "merge": True})
                else:
                    free = next((idx for idx, val in enumerate(active_lanes) if val is None), None)
                    if free is not None:
                        active_lanes[free] = parent
                        target = free
                    else:
                        target = len(active_lanes)
                        active_lanes.append(parent)
                    out_edges.append({"from": lane, "to": target, "merge": True})

        while active_lanes and active_lanes[-1] is None:
            active_lanes.pop()

        row_max = max(
            [lane + 1, len(active_lanes)]
            + [e["from"] + 1 for e in in_edges]
            + [e["to"] + 1 for e in out_edges]
            + [col + 1 for col in pass_lanes]
        )
        max_lanes_seen = max(max_lanes_seen, row_max)

        commit["lane"] = lane
        commit["color_idx"] = lane % 6
        commit["in_edges"] = in_edges
        commit["pass_lanes"] = pass_lanes
        commit["out_edges"] = out_edges
        commit["lane_count"] = row_max

    for commit in commits:
        commit["graph_lanes"] = min(max_lanes_seen, 8)
    return commits


def _parse_porcelain(output: str) -> dict:
    branch = ""
    upstream = ""
    ahead = 0
    behind = 0
    staged: list[dict[str, str]] = []
    modified: list[dict[str, str]] = []
    untracked: list[dict[str, str]] = []

    for line in output.splitlines():
        if line.startswith("## "):
            header = line[3:].strip()
            if header.startswith("No commits yet on "):
                branch = header[len("No commits yet on "):].strip()
                continue
            if header.startswith("HEAD (no branch)"):
                branch = "HEAD"
                continue
            bracket = re.search(r"\[(.+)\]$", header)
            if bracket:
                meta = bracket.group(1)
                a = re.search(r"ahead (\d+)", meta)
                b = re.search(r"behind (\d+)", meta)
                if a:
                    ahead = int(a.group(1))
                if b:
                    behind = int(b.group(1))
                header = header[:bracket.start()].strip()
            if "..." in header:
                local_part, remote_part = header.split("...", 1)
                branch = local_part.strip()
                upstream = remote_part.strip()
            else:
                branch = header.strip()
            continue

        if len(line) < 4:
            continue
        x, y = line[0], line[1]
        raw_path = line[3:].strip()
        if " -> " in raw_path:
            raw_path = raw_path.split(" -> ", 1)[1].strip()
        if x == "?" and y == "?":
            untracked.append({"status": "?", "path": raw_path})
            continue
        if x not in (" ", "?"):
            staged.append({"status": x, "path": raw_path})
        if y not in (" ", "?"):
            modified.append({"status": y, "path": raw_path})

    return {
        "branch": branch,
        "upstream": upstream,
        "ahead": ahead,
        "behind": behind,
        "staged_count": len(staged),
        "modified_count": len(modified),
        "untracked_count": len(untracked),
        "clean": not (staged or modified or untracked),
        "staged": staged[:MAX_STATUS_FILES],
        "modified": modified[:MAX_STATUS_FILES],
        "untracked": untracked[:MAX_STATUS_FILES],
    }


class GitFlowReader:
    """Lee el grafo de commits, ramas y estado Git del directorio de un proyecto."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root).resolve(strict=True)

    def summary(self, max_commits: int = DEFAULT_MAX_COMMITS) -> dict:
        limit = max(1, min(MAX_COMMITS_LIMIT, int(max_commits)))
        try:
            probe = _run_git(self.root, "rev-parse", "--is-inside-work-tree", "--show-toplevel")
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            return {
                "is_repo": False,
                "root": "",
                "branch": "",
                "upstream": "",
                "ahead": 0,
                "behind": 0,
                "head_hash": "",
                "clean": True,
                "staged_count": 0,
                "modified_count": 0,
                "untracked_count": 0,
                "staged": [],
                "modified": [],
                "untracked": [],
                "branches": [],
                "commits": [],
                "graph_lanes": 1,
            }

        probe_lines = [line.strip() for line in probe.stdout.splitlines() if line.strip()]
        if probe.returncode != 0 or len(probe_lines) < 2 or probe_lines[0] != "true":
            return {
                "is_repo": False,
                "root": "",
                "branch": "",
                "upstream": "",
                "ahead": 0,
                "behind": 0,
                "head_hash": "",
                "clean": True,
                "staged_count": 0,
                "modified_count": 0,
                "untracked_count": 0,
                "staged": [],
                "modified": [],
                "untracked": [],
                "branches": [],
                "commits": [],
                "graph_lanes": 1,
            }

        repo_root = Path(probe_lines[1])
        status_proc = _run_git(repo_root, "status", "--porcelain=v1", "--branch")
        status_info = _parse_porcelain(status_proc.stdout if status_proc.returncode == 0 else "")

        head_proc = _run_git(repo_root, "rev-parse", "--short", "HEAD")
        head_hash = head_proc.stdout.strip() if head_proc.returncode == 0 else ""

        branch_proc = _run_git(
            repo_root,
            "branch",
            "--format=%(HEAD)%1f%(refname:short)%1f%(objectname:short)",
        )
        branches: list[dict] = []
        if branch_proc.returncode == 0:
            for line in branch_proc.stdout.splitlines():
                parts = line.split("\x1f")
                if len(parts) >= 3:
                    branches.append({
                        "current": parts[0].strip() == "*",
                        "name": parts[1].strip(),
                        "hash": parts[2].strip(),
                    })

        log_proc = _run_git(
            repo_root,
            "log",
            "--all",
            "--topo-order",
            f"-n{limit}",
            "--format=%H%x1f%h%x1f%P%x1f%D%x1f%an%x1f%ar%x1f%at%x1f%s",
        )
        commits: list[dict] = []
        if log_proc.returncode == 0:
            for line in log_proc.stdout.splitlines():
                parts = line.split("\x1f")
                if len(parts) < 8:
                    continue
                full_hash, short_hash, parents_raw, refs_raw, author, rel_date, ts_raw, subject = parts[:8]
                parents = [p for p in parents_raw.split() if p]
                is_head, refs = _parse_refs(refs_raw)
                commits.append({
                    "hash": full_hash,
                    "short_hash": short_hash,
                    "parents": parents,
                    "is_head": is_head,
                    "is_merge": len(parents) > 1,
                    "refs": refs,
                    "author": author,
                    "relative_date": rel_date,
                    "timestamp": int(ts_raw) if ts_raw.isdigit() else 0,
                    "subject": subject,
                    "kind": _detect_commit_kind(subject),
                })

        compute_graph_lanes(commits)
        graph_lanes = commits[0]["graph_lanes"] if commits else 1

        return {
            "is_repo": True,
            "root": str(repo_root),
            "head_hash": head_hash,
            "branches": branches[:24],
            "commits": commits,
            "graph_lanes": graph_lanes,
            **status_info,
        }

    def commit_detail(self, commit_hash: str) -> dict:
        if not isinstance(commit_hash, str) or not _HASH_RE.fullmatch(commit_hash.strip()):
            raise ValueError("Identificador de commit inválido")
        target = commit_hash.strip()
        meta_proc = _run_git(
            self.root,
            "show",
            "--no-patch",
            "--format=%H%x1f%h%x1f%an%x1f%ai%x1f%ar%x1f%P%x1f%D%x1f%s%x1f%b",
            target,
        )
        if meta_proc.returncode != 0:
            raise ValueError("No se encontró el commit solicitado")
        parts = meta_proc.stdout.split("\x1f", 8)
        if len(parts) < 9:
            raise ValueError("No se pudieron leer los metadatos del commit")
        full_hash, short_hash, author, date_iso, rel_date, parents_raw, refs_raw, subject, body = parts
        is_head, refs = _parse_refs(refs_raw)

        stat_proc = _run_git(self.root, "show", "--numstat", "--format=", target)
        files: list[dict] = []
        total_added = 0
        total_deleted = 0
        if stat_proc.returncode == 0:
            for line in stat_proc.stdout.splitlines():
                cols = line.split("\t", 2)
                if len(cols) != 3:
                    continue
                add_raw, del_raw, path_str = cols
                binary = add_raw == "-" or del_raw == "-"
                added = 0 if binary else int(add_raw)
                deleted = 0 if binary else int(del_raw)
                total_added += added
                total_deleted += deleted
                files.append({
                    "path": path_str,
                    "added": added,
                    "deleted": deleted,
                    "binary": binary,
                })

        return {
            "hash": full_hash.strip(),
            "short_hash": short_hash.strip(),
            "author": author.strip(),
            "date_iso": date_iso.strip(),
            "relative_date": rel_date.strip(),
            "parents": [p for p in parents_raw.split() if p],
            "is_head": is_head,
            "refs": refs,
            "subject": subject.strip(),
            "body": body.strip(),
            "kind": _detect_commit_kind(subject.strip()),
            "files": files[:MAX_DETAIL_FILES],
            "file_count": len(files),
            "total_added": total_added,
            "total_deleted": total_deleted,
        }
