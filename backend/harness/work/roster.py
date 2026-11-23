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
LEVEL_TIERS = {
    "simple": ("fast", "balanced", "strong"),
    "standard": ("balanced", "fast", "strong"),
    "hard": ("strong", "balanced", "fast"),
}
TIER_EFFORTS = {
    "fast": ("medium", "high", "low"),
    "balanced": ("medium", "high", "low"),
    "strong": ("high", "medium", "low"),
}
LOW_QUOTA_PERCENT = 5.0
UNKNOWN_QUOTA_PERCENT = 50.0
EFFORT_SUFFIX_RE = re.compile(r"-(low|medium|high|xhigh|max)$")


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
    """agy bills Gemini and third-party models against independent quotas."""
    if provider == "agy":
        lower = (model or "").lower()
        return "agy:3p" if lower and not lower.startswith("gemini") else "agy:gemini"
    return provider


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


def rank(roster: list[Candidate], level: str, remaining: dict[str, float],
         provider: str = "") -> list[Candidate]:
    """Best candidate first: quota left, requested provider, tier fit, then most quota left."""
    tiers = LEVEL_TIERS[level]

    def key(candidate: Candidate):
        left = remaining.get(candidate.bucket, UNKNOWN_QUOTA_PERCENT)
        return (left < LOW_QUOTA_PERCENT, bool(provider) and candidate.provider != provider,
                tiers.index(candidate.tier), -left)

    return sorted(roster, key=key)
