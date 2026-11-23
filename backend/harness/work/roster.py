"""Worker roster: ranks live provider catalogs by capability tier, cascade config, and remaining quota."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .unified_config import UnifiedConfig

# Tiers come from product-line names, never from versions, so new releases are picked up
# from the live catalog. Unlisted lines (and flagships) are never selected as workers.
TIER_LINES = {
    "haiku": "fast", "flash": "fast", "luna": "fast", "mini": "fast", "nano": "fast", "lite": "fast",
    "sonnet": "balanced", "terra": "balanced",
    "opus": "strong", "sol": "strong",
}
ARCHITECT_LINES = frozenset({"astra", "opus", "argon"})
CASCADE_PRODUCT_LINES = frozenset({"neon", "argon", "hydrogen", "astra", "opus", "fable", *TIER_LINES})
ROLE_TIERS = {
    "explorer": ("fast", "balanced", "strong"),
    "builder": ("balanced", "fast", "strong"),
    "specialist": ("strong", "balanced", "fast"),
    "reviewer": ("balanced", "strong", "fast"),
}
WORKER_TIER_FALLBACKS = {
    "fast": ("fast", "balanced", "strong"),
    "balanced": ("balanced", "strong", "fast"),
    "strong": ("strong", "balanced", "fast"),
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


def bucket_remaining(bucket: str, remaining: dict[str, float]) -> float | None:
    """Porcentaje restante del bucket; agy:argon comparte cuota Gemini si no hay bucket propio."""
    if bucket in remaining:
        return remaining[bucket]
    if bucket == "agy:argon" and "agy:gemini" in remaining:
        return remaining["agy:gemini"]
    return None


def vendor(slug: str) -> str:
    return slug.split("-", 1)[0].lower()


def model_tier(slug: str) -> str:
    for part in EFFORT_SUFFIX_RE.sub("", slug.lower()).split("-"):
        if part in TIER_LINES:
            return TIER_LINES[part]
    return ""


def model_version(slug: str) -> tuple[int, ...]:
    return tuple(int(number) for number in re.findall(r"\d+", EFFORT_SUFFIX_RE.sub("", slug.lower())))


def _product_line(slug: str) -> str:
    for part in EFFORT_SUFFIX_RE.sub("", slug.lower()).split("-"):
        if part in CASCADE_PRODUCT_LINES:
            return part
    return ""


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
    seen: set[str] = set()
    ordered = [effort for effort in preferred if effort and not (effort in seen or seen.add(effort))]
    for effort in ordered:
        for row in rows:
            if row["slug"].endswith("-" + effort):
                return row, ""
            if effort in row.get("reasoning_efforts", []):
                return row, effort
    return rows[0], ""


def _pick_provider_effort(provider: str, rows: list[dict], preferred: tuple[str, ...]) -> tuple[dict, str]:
    row, effort = _pick_effort(rows, preferred)
    if provider == "agy":
        return row, ""
    return row, effort


def resolve_model_candidate(
    provider: str,
    model: str,
    effort: str,
    catalogs: dict[str, list[dict]],
    *,
    tier: str = "balanced",
    role: str = "architect",
) -> Candidate | None:
    """Resuelve un modelo explícito o automático contra el catálogo en vivo del proveedor."""
    rows = catalogs.get(provider) or []
    if not rows:
        return None
    fallback_efforts = (effort, *ARCHITECT_EFFORTS) if role == "architect" else (effort, *TIER_EFFORTS.get(tier, ("medium", "high", "low")))

    if model:
        base = EFFORT_SUFFIX_RE.sub("", model)
        if provider == "agy" and effort:
            target = f"{base}-{effort}"
            variant = next((row for row in rows if row["slug"] == target), None)
            if variant is not None:
                return Candidate(provider, variant["slug"], "", role, quota_bucket(provider, variant["slug"]))

        exact = [row for row in rows if row["slug"] == model]
        if exact:
            row, picked_effort = _pick_provider_effort(provider, exact, fallback_efforts)
            return Candidate(provider, row["slug"], picked_effort, role, quota_bucket(provider, row["slug"]))

        # Si cambió la versión en el catálogo (p. ej. gpt-6.3-astra o gemini-4.5-neon), busca la misma línea.
        line = _product_line(model)
        if line:
            same_line = [row for row in rows if _product_line(row["slug"]) == line]
            if same_line:
                newest = max(model_version(row["slug"]) for row in same_line)
                newest_rows = [row for row in same_line if model_version(row["slug"]) == newest]
                row, picked_effort = _pick_provider_effort(provider, newest_rows, fallback_efforts)
                return Candidate(provider, row["slug"], picked_effort, role, quota_bucket(provider, row["slug"]))

    if role == "architect":
        if provider == "agy":
            for line in ("neon", "argon", "hydrogen"):
                line_rows = [row for row in rows if _product_line(row["slug"]) == line]
                if line_rows:
                    newest = max(model_version(row["slug"]) for row in line_rows)
                    newest_rows = [row for row in line_rows if model_version(row["slug"]) == newest]
                    row, picked_effort = _pick_provider_effort(provider, newest_rows, fallback_efforts)
                    return Candidate(provider, row["slug"], picked_effort, role, quota_bucket(provider, row["slug"]))
        fallback = architect_candidate({provider: rows}, {}, provider)
        if fallback is None:
            return None
        if effort and provider != "agy":
            matched = [row for row in rows if row["slug"] == fallback.model]
            if matched and effort in matched[0].get("reasoning_efforts", []):
                return Candidate(fallback.provider, fallback.model, effort, role, fallback.bucket)
        return fallback

    # Obrero automático según nivel preferido (balanceado por defecto).
    for target_tier in WORKER_TIER_FALLBACKS.get(tier, ("balanced", "strong", "fast")):
        tier_rows = [row for row in rows if model_tier(row["slug"]) == target_tier]
        if tier_rows:
            newest = max(model_version(row["slug"]) for row in tier_rows)
            newest_rows = [row for row in tier_rows if model_version(row["slug"]) == newest]
            row, picked_effort = _pick_provider_effort(provider, newest_rows, fallback_efforts)
            return Candidate(provider, row["slug"], picked_effort, target_tier, quota_bucket(provider, row["slug"]))

    row, picked_effort = _pick_provider_effort(provider, rows, fallback_efforts)
    return Candidate(provider, row["slug"], picked_effort, tier, quota_bucket(provider, row["slug"]))


def select_architect(
    catalogs: dict[str, list[dict]],
    remaining: dict[str, float],
    config: UnifiedConfig,
    exhausted: set[str] | None = None,
) -> Candidate | None:
    """Recorre la cascada configurada cambiando al siguiente cuando la cuota restante <= umbral."""
    spent = exhausted or set()
    threshold = float(config.quota_threshold)
    resolved: list[Candidate] = []
    for step in config.architect_cascade:
        candidate = resolve_model_candidate(step.provider, step.model, step.effort, catalogs, role="architect")
        if candidate is not None and candidate.bucket not in spent:
            resolved.append(candidate)

    if not resolved:
        fallback_remaining = {**remaining, **dict.fromkeys(spent, 0.0)}
        return architect_candidate(catalogs, fallback_remaining, "")

    for idx, candidate in enumerate(resolved):
        left = bucket_remaining(candidate.bucket, remaining)
        is_last = idx == len(resolved) - 1
        if left is None:
            return candidate
        if not is_last and left > threshold:
            return candidate
        if is_last and left > LOW_QUOTA_PERCENT:
            return candidate

    positive = [
        (bucket_remaining(candidate.bucket, remaining) or 0.0, -idx, candidate)
        for idx, candidate in enumerate(resolved)
        if (bucket_remaining(candidate.bucket, remaining) or 0.0) > 0
    ]
    if positive:
        return max(positive, key=lambda entry: (entry[0], entry[1]))[2]
    return resolved[0]


def build_configured_workers(
    catalogs: dict[str, list[dict]],
    config: UnifiedConfig,
) -> dict[str, Candidate | None]:
    """Resuelve cada ranura de obrero configurada (p. ej. ChatGPT y Claude)."""
    result: dict[str, Candidate | None] = {}
    for worker in config.workers:
        result[worker.slot] = resolve_model_candidate(
            worker.provider,
            worker.model,
            worker.effort,
            catalogs,
            tier=worker.tier,
            role=worker.slot,
        )
    return result


def rank_worker_slots(
    workers: dict[str, Candidate | None],
    remaining: dict[str, float],
    preferred_slot: str = "",
    read_only: bool = False,
) -> list[tuple[str, Candidate]]:
    """Ordena los obreros configurados disponibles priorizando la ranura elegida y la cuota."""
    entries = [(slot, candidate) for slot, candidate in workers.items() if candidate is not None]

    def key(item: tuple[str, Candidate]):
        slot, candidate = item
        left = bucket_remaining(candidate.bucket, remaining)
        score = UNKNOWN_QUOTA_PERCENT if left is None else left
        unsuited = read_only and candidate.provider == "agy"
        return (
            score <= 0,
            bool(preferred_slot) and slot != preferred_slot,
            score < LOW_QUOTA_PERCENT,
            unsuited,
            -score,
        )

    return sorted(entries, key=key)


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
