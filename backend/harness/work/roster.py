"""Worker roster: ranks live provider catalogs by capability tier and remaining quota."""

from __future__ import annotations

import re
from dataclasses import dataclass

# Tiers come from product-line names, never from versions, so new releases are picked up
# from the live catalog. Unlisted lines (and flagships) are never selected as workers.
TIER_LINES = {
    "haiku": "fast", "flash": "fast", "luna": "fast", "mini": "fast", "nano": "fast", "lite": "fast",
    "sonnet": "balanced", "terra": "balanced",
    "opus": "strong", "sol": "strong",
}
ARCHITECT_LINES = frozenset({"astra", "opus", "argon"})
ROLE_TIERS = {
    "explorer": ("fast", "balanced", "strong"),
    "builder": ("balanced", "fast", "strong"),
    "specialist": ("strong", "balanced", "fast"),
    "reviewer": ("balanced", "strong", "fast"),
}
READ_ONLY_ROLES = frozenset({"explorer", "reviewer"})
TIER_EFFORTS = {
    "fast": ("medium", "high", "low"),
    "balanced": ("medium", "high", "low"),
    "strong": ("high", "medium", "low"),
}
LOW_QUOTA_PERCENT = 5.0
UNKNOWN_QUOTA_PERCENT = 50.0
EFFORT_SUFFIX_RE = re.compile(r"-(low|medium|high|xhigh|max)$")
ARCHITECT_EFFORTS = ("high", "xhigh", "max", "ultra", "medium", "low")


@dataclass(frozen=True)
class Candidate:
    provider: str
    model: str
    effort: str
    tier: str
    bucket: str

    @property
    def label(self) -> str:
        return f"{self.provider}/{self.model}"


def quota_bucket(provider: str, model: str = "") -> str:
    """agy bills Gemini, Argon and third-party models against independent quotas."""
    if provider == "agy":
        lower = (model or "").lower()
        if "argon" in lower:
            return "agy:argon"
        return "agy:3p" if lower and not lower.startswith("gemini") else "agy:gemini"
    return provider


def vendor(slug: str) -> str:
    return slug.split("-", 1)[0].lower()


def model_tier(slug: str) -> str:
    for part in EFFORT_SUFFIX_RE.sub("", slug.lower()).split("-"):
        if part in TIER_LINES:
            return TIER_LINES[part]
    return ""


def model_version(slug: str) -> tuple[int, ...]:
    return tuple(int(number) for number in re.findall(r"\d+", EFFORT_SUFFIX_RE.sub("", slug.lower())))


def build_roster(catalogs: dict[str, list[dict]]) -> list[Candidate]:
    """Newest model of each tier per quota bucket, with an effort suited to the tier."""
    groups: dict[tuple[str, str, str], list[dict]] = {}
    for provider, models in catalogs.items():
        for row in models:
            tier = model_tier(row["slug"])
            if tier:
                groups.setdefault((provider, quota_bucket(provider, row["slug"]), tier), []).append(row)
    roster = []
    for (provider, bucket, tier), rows in groups.items():
        newest = max(model_version(row["slug"]) for row in rows)
        rows = [row for row in rows if model_version(row["slug"]) == newest]
        row, effort = _pick_effort(rows, TIER_EFFORTS[tier])
        roster.append(Candidate(provider, row["slug"], effort, tier, bucket))
    return roster


def _pick_effort(rows: list[dict], preferred: tuple[str, ...]) -> tuple[dict, str]:
    for effort in preferred:
        for row in rows:
            if row["slug"].endswith("-" + effort):
                return row, ""
            if effort in row.get("reasoning_efforts", []):
                return row, effort
    return rows[0], ""


def architect_candidate(catalogs: dict[str, list[dict]], remaining: dict[str, float],
                        preferred_provider: str) -> Candidate | None:
    """Prefer flagships with quota. Versions are comparable only within a model family."""
    def capability(slug: str) -> int:
        parts = EFFORT_SUFFIX_RE.sub("", slug.lower()).split("-")
        if ARCHITECT_LINES.intersection(parts):
            return 4
        tier = model_tier(slug)
        if tier:
            return {"fast": 0, "balanced": 1, "strong": 3}[tier]
        # Sin línea rápida o equilibrada, las familias conocidas son buques insignia.
        return 3 if parts[0] in {"gpt", "gemini", "claude"} else 1

    groups: dict[tuple, list[dict]] = {}
    for provider, rows in catalogs.items():
        for row in rows:
            slug = row["slug"]
            key = (provider, quota_bucket(provider, slug), vendor(slug), capability(slug))
            groups.setdefault(key, []).append(row)

    ranked = []
    for (provider, bucket, _, strength), rows in groups.items():
        newest = max(model_version(row["slug"]) for row in rows)
        row, effort = _pick_effort([row for row in rows if model_version(row["slug"]) == newest], ARCHITECT_EFFORTS)
        left = remaining.get(bucket, UNKNOWN_QUOTA_PERCENT)
        priority = (left > 0, left >= LOW_QUOTA_PERCENT, strength, left, provider == preferred_provider)
        ranked.append((priority, Candidate(provider, row["slug"], effort, "architect", bucket)))
    return max(ranked, key=lambda entry: entry[0])[1] if ranked else None


def rank(roster: list[Candidate], role: str, remaining: dict[str, float], provider: str = "",
         architect_bucket: str = "", builder_vendor: str = "") -> list[Candidate]:
    """Best candidate first for a role, given the quota left and who else works on the turn."""
    tiers = ROLE_TIERS[role]

    def unsuited(candidate: Candidate) -> bool:
        # agy cannot enforce read-only access; headless Claude cannot run arbitrary commands.
        return (role == "explorer" and candidate.provider == "agy"
                or role == "reviewer" and candidate.provider == "claude")

    def conflicts(candidate: Candidate) -> bool:
        return (role == "specialist" and candidate.bucket == architect_bucket
                or role == "reviewer" and vendor(candidate.model) == builder_vendor)

    def key(candidate: Candidate):
        left = remaining.get(candidate.bucket, UNKNOWN_QUOTA_PERCENT)
        return (left < LOW_QUOTA_PERCENT, unsuited(candidate), bool(provider) and candidate.provider != provider,
                conflicts(candidate), tiers.index(candidate.tier), -left)

    return sorted(roster, key=key)
