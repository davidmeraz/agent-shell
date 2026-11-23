"""Roster built from live catalogs and quota-aware worker selection."""

import unittest

from tests.support import paths  # noqa: F401
from harness.core.http import Cancelled, StreamControl
from harness.work.quota_router import EXHAUSTED_COOLDOWN, QuotaAwareRouter
from harness.work.roster import (
    Candidate, architect_candidate, build_configured_workers, build_roster, model_tier,
    quota_bucket, rank, rank_worker_slots, select_architect,
)
from harness.work.unified_config import ArchitectStep, UnifiedConfig, WorkerSlotConfig
from harness.work.worker import WorkerResult


def row(slug, efforts=()):
    return {"slug": slug, "reasoning_efforts": list(efforts)}


CATALOGS = {
    "claude": [row("claude-sonnet", ("low", "medium", "high")), row("claude-opus", ("medium", "high")),
               row("claude-haiku", ("low", "medium")), row("claude-fable", ("high",))],
    "chatgpt": [row("gpt-6.2-sol", ("low", "high")), row("gpt-6.2-astra", ("high",)),
                row("gpt-6.1-terra", ("medium",)), row("gpt-6.1-sol", ("high",)),
                row("gpt-6-luna", ("medium",)), row("gpt-5.6-luna", ("medium",))],
    "agy": [row("gemini-4-neon-high"), row("gemini-4-argon-high"), row("gemini-3.8-flash-high"),
            row("gemini-3.8-flash-medium"), row("gemini-3.7-flash-medium"),
            row("claude-sonnet-5-5-low"), row("claude-sonnet-5-5-medium"), row("gpt-oss-120b-medium")],
}


class RosterTests(unittest.TestCase):
    def test_newest_model_per_tier_and_bucket_with_matching_effort(self):
        found = {(c.bucket, c.tier): (c.model, c.effort) for c in build_roster(CATALOGS)}
        self.assertEqual(found, {
            ("claude", "fast"): ("claude-haiku", "medium"),
            ("claude", "balanced"): ("claude-sonnet", "medium"),
            ("claude", "strong"): ("claude-opus", "high"),
            ("chatgpt", "fast"): ("gpt-6-luna", "medium"),
            ("chatgpt", "balanced"): ("gpt-6.1-terra", "medium"),
            ("chatgpt", "strong"): ("gpt-6.2-sol", "high"),
            ("agy:gemini", "fast"): ("gemini-3.8-flash-medium", ""),
            ("agy:3p", "balanced"): ("claude-sonnet-5-5-medium", ""),
        })

    def test_future_version_is_selected_without_code_changes(self):
        roster = build_roster({"chatgpt": [row("gpt-6-luna"), row("gpt-7.1-luna")]})
        self.assertEqual([c.model for c in roster], ["gpt-7.1-luna"])

    def test_flagships_and_unknown_lines_are_never_workers(self):
        for slug in ("claude-fable", "gpt-6.2-astra", "gemini-4-argon-high", "gemini-4-neon-low", "gpt-oss-120b-medium"):
            self.assertEqual(model_tier(slug), "", slug)

    def test_agy_buckets_are_independent(self):
        self.assertEqual(quota_bucket("agy", "gemini-3.8-flash-medium"), "agy:gemini")
        self.assertEqual(quota_bucket("agy", "claude-sonnet-5-5-medium"), "agy:3p")
        self.assertEqual(quota_bucket("agy", "gemini-4-argon-high"), "agy:argon")


class ArchitectCandidateTests(unittest.TestCase):
    def test_strength_and_unknown_family(self):
        catalogs = {"claude": [row("claude-haiku-9")], "chatgpt": [row("gpt-5.5")],
                    "other": [row("other-pro-99")]}
        self.assertEqual(architect_candidate(catalogs, {}, "claude").model, "gpt-5.5")

    def test_newest_within_family_and_high_effort(self):
        catalogs = {"claude": [row("claude-opus-4", ("high",)),
                               row("claude-opus-5", ("low", "high"))]}
        candidate = architect_candidate(catalogs, {}, "")
        self.assertEqual((candidate.model, candidate.effort), ("claude-opus-5", "high"))

    def test_low_and_exhausted_quota_lose_to_weaker_model(self):
        catalogs = {"claude": [row("claude-opus")], "chatgpt": [row("gpt-mini")]}
        for left in (0, 4):
            with self.subTest(left=left):
                self.assertEqual(architect_candidate(catalogs, {"claude": left, "chatgpt": 50},
                                                     "claude").provider, "chatgpt")

    def test_flagships_tie_by_quota_then_preference(self):
        catalogs = {"claude": [row("claude-opus-5")], "chatgpt": [row("gpt-6.2-astra")]}
        self.assertEqual(architect_candidate(catalogs, {"claude": 80, "chatgpt": 80}, "chatgpt").provider,
                         "chatgpt")
        self.assertEqual(architect_candidate(catalogs, {"claude": 90, "chatgpt": 80}, "chatgpt").provider,
                         "claude")

    def test_each_provider_contributes_its_flagship(self):
        for provider, model in (("chatgpt", "gpt-6.2-astra"), ("claude", "claude-opus"), ("agy", "gemini-4-argon-high")):
            self.assertEqual(architect_candidate({provider: CATALOGS[provider]}, {}, provider).model, model)

    def test_flagship_with_most_quota_wins_and_spent_argon_is_skipped(self):
        remaining = {"chatgpt": 60, "claude": 87, "agy:argon": 0.1, "agy:gemini": 99, "agy:3p": 78}
        self.assertEqual(architect_candidate(CATALOGS, remaining, "agy").model, "claude-opus")
        self.assertEqual(architect_candidate(CATALOGS, {**remaining, "chatgpt": 95}, "agy").model, "gpt-6.2-astra")

    def test_empty_catalogs(self):
        self.assertIsNone(architect_candidate({"claude": []}, {}, "claude"))
        self.assertIsNone(architect_candidate({}, {}, ""))


class RankTests(unittest.TestCase):
    QUOTA = {"claude": 87, "chatgpt": 74, "agy:gemini": 90, "agy:3p": 78}

    def first(self, role, remaining=None, **context):
        catalogs = {**CATALOGS, "agy": CATALOGS["agy"] + [row("claude-opus-5-5-high")]}
        return rank(build_roster(catalogs), role, remaining or self.QUOTA, **context)[0].label

    def test_each_role_prefers_its_tier_and_quota_breaks_ties(self):
        self.assertEqual(self.first("explorer"), "claude/claude-haiku")
        self.assertEqual(self.first("builder"), "claude/claude-sonnet")
        self.assertEqual(self.first("specialist"), "claude/claude-opus")
        self.assertEqual(self.first("builder", {**self.QUOTA, "claude": 20}), "agy/claude-sonnet-5-5-medium")

    def test_specialist_leaves_the_architect_quota_alone(self):
        self.assertEqual(self.first("specialist", architect_bucket="claude"), "agy/claude-opus-5-5-high")
        self.assertEqual(self.first("builder", architect_bucket="claude"), "claude/claude-sonnet")

    def test_reviewer_comes_from_another_vendor_even_through_agy(self):
        self.assertEqual(self.first("reviewer", builder_vendor="claude"), "chatgpt/gpt-6.1-terra")
        self.assertEqual(self.first("reviewer", builder_vendor="gpt"), "agy/claude-sonnet-5-5-medium")

    def test_reviewer_needs_commands_and_explorer_needs_enforced_read_only(self):
        self.assertEqual(self.first("reviewer", {**self.QUOTA, "claude": 100}), "agy/claude-sonnet-5-5-medium")
        self.assertNotIn("agy/", self.first("explorer", {**self.QUOTA, "agy:gemini": 100, "claude": 10, "chatgpt": 9}))

    def test_nearly_empty_bucket_goes_last_even_when_preferred(self):
        self.assertEqual(self.first("builder", {**self.QUOTA, "claude": 2}, provider="claude"),
                         "agy/claude-sonnet-5-5-medium")

    def test_preferred_provider_wins_while_it_has_quota(self):
        self.assertEqual(self.first("builder", provider="chatgpt"), "chatgpt/gpt-6.1-terra")


class StubWorkers:
    def __init__(self, outcomes):
        self.outcomes = outcomes
        self.calls = []

    def run(self, task, candidate, control, max_steps, progress, role):
        self.calls.append((candidate.label, task))
        return self.outcomes.get(candidate.bucket, WorkerResult(summary="ok"))


ROSTER = [Candidate("agy", "gemini-3.8-flash-medium", "", "strong", "agy:gemini"),
          Candidate("claude", "claude-haiku", "medium", "strong", "claude"),
          Candidate("agy", "claude-sonnet-5-5-medium", "", "balanced", "agy:3p")]
REMAINING = {"agy:gemini": 90, "claude": 80, "agy:3p": 70}


class QuotaRouterTests(unittest.TestCase):
    def setUp(self):
        self.now = 0.0

    def route(self, outcomes):
        workers = StubWorkers(outcomes)
        return workers, QuotaAwareRouter(workers, clock=lambda: self.now)

    def test_exhausted_bucket_falls_back_and_cools_down(self):
        workers, router = self.route({"agy:gemini": WorkerResult(status="quota_exhausted")})
        router.run("t", StreamControl(), ROSTER, REMAINING, role="specialist")
        router.run("t", StreamControl(), ROSTER, REMAINING, role="specialist")
        self.now = EXHAUSTED_COOLDOWN + 1
        router.run("t", StreamControl(), ROSTER, REMAINING, role="specialist")
        self.assertEqual([label.split("/")[1] for label, _ in workers.calls],
                         ["gemini-3.8-flash-medium", "claude-haiku", "claude-haiku",
                          "gemini-3.8-flash-medium", "claude-haiku"])

    def test_next_worker_is_warned_about_partial_edits(self):
        workers, router = self.route({"agy:gemini": WorkerResult(status="quota_exhausted", tool_calls=3)})
        router.run("task", StreamControl(), ROSTER, REMAINING, role="specialist")
        self.assertIn("partial edits", workers.calls[1][1])

    def test_ordinary_failure_is_returned_without_trying_others(self):
        workers, router = self.route({"agy:gemini": WorkerResult(status="failed", error="boom")})
        self.assertEqual(router.run("t", StreamControl(), ROSTER, REMAINING, role="specialist").status, "failed")
        self.assertEqual(len(workers.calls), 1)

    def test_all_exhausted_and_empty_roster_report_quota(self):
        spent = WorkerResult(status="quota_exhausted")
        _, router = self.route({"agy:gemini": spent, "claude": spent, "agy:3p": spent})
        for roster in (ROSTER, []):
            self.assertEqual(router.run("t", StreamControl(), roster, REMAINING).status, "quota_exhausted")

    def test_cancellation_stops_before_the_next_worker(self):
        _, router = self.route({})
        control = StreamControl()
        control.cancel()
        with self.assertRaises(Cancelled):
            router.run("t", control, ROSTER, REMAINING)


class ArchitectCascadeAndWorkersTests(unittest.TestCase):
    LIVE_CATALOGS = {
        "agy": [
            row("gemini-4-neon-high"),
            row("gemini-4-neon-xhigh"),
            row("gemini-4-argon-high"),
            row("gemini-3.8-flash-medium"),
        ],
        "claude": [
            row("claude-opus", ("low", "medium", "high", "xhigh", "max")),
            row("claude-sonnet", ("low", "medium", "high", "xhigh", "max")),
            row("claude-haiku", ("low", "medium", "high")),
        ],
        "chatgpt": [
            row("gpt-6.2-astra", ("low", "medium", "high", "xhigh", "max")),
            row("gpt-6.2-sol", ("low", "medium", "high", "xhigh")),
            row("gpt-6.1-terra", ("low", "medium", "high")),
            row("gpt-6-luna", ("low", "medium", "high")),
        ],
    }

    def test_default_cascade_switches_at_35_percent_remaining(self):
        cfg = UnifiedConfig.default()
        # Start: Gemini above 35% -> Gemini 4 Neon (xhigh)
        first = select_architect(self.LIVE_CATALOGS, {"agy:gemini": 76, "claude": 90, "chatgpt": 95}, cfg)
        self.assertEqual((first.provider, first.model, first.effort), ("agy", "gemini-4-neon-xhigh", ""))

        # Gemini drops to 35% -> switches to Claude Opus 5.5 (xhigh)
        second = select_architect(self.LIVE_CATALOGS, {"agy:gemini": 35, "claude": 80, "chatgpt": 95}, cfg)
        self.assertEqual((second.provider, second.model, second.effort), ("claude", "claude-opus", "xhigh"))

        # Claude also drops to 35% -> switches to GPT-6.2-Astra (high)
        third = select_architect(self.LIVE_CATALOGS, {"agy:gemini": 35, "claude": 35, "chatgpt": 70}, cfg)
        self.assertEqual((third.provider, third.model, third.effort), ("chatgpt", "gpt-6.2-astra", "high"))

        # Last step stays active below 35% (above 5%) without ping-ponging back to Gemini
        still_third = select_architect(self.LIVE_CATALOGS, {"agy:gemini": 35, "claude": 34, "chatgpt": 20}, cfg)
        self.assertEqual((still_third.provider, still_third.model), ("chatgpt", "gpt-6.2-astra"))

        # When last step drops <= 5%, emergency fallback picks highest remaining quota > 0
        fallback = select_architect(self.LIVE_CATALOGS, {"agy:gemini": 35, "claude": 34, "chatgpt": 4}, cfg)
        self.assertEqual((fallback.provider, fallback.model), ("agy", "gemini-4-neon-xhigh"))

    def test_cascade_respects_custom_order_and_threshold(self):
        cfg = UnifiedConfig(
            quota_threshold=50,
            architect_cascade=(
                ArchitectStep("claude", "claude-opus", "max"),
                ArchitectStep("chatgpt", "gpt-6.2-astra", "xhigh"),
                ArchitectStep("agy", "gemini-4-neon-high", "high"),
            ),
        )
        c1 = select_architect(self.LIVE_CATALOGS, {"claude": 60, "chatgpt": 90, "agy:gemini": 99}, cfg)
        self.assertEqual((c1.provider, c1.model, c1.effort), ("claude", "claude-opus", "max"))
        c2 = select_architect(self.LIVE_CATALOGS, {"claude": 50, "chatgpt": 55, "agy:gemini": 99}, cfg)
        self.assertEqual((c2.provider, c2.model, c2.effort), ("chatgpt", "gpt-6.2-astra", "xhigh"))
        c3 = select_architect(self.LIVE_CATALOGS, {"claude": 50, "chatgpt": 49, "agy:gemini": 80}, cfg)
        self.assertEqual((c3.provider, c3.model), ("agy", "gemini-4-neon-high"))

    def test_future_version_in_same_line_is_resolved(self):
        future = {
            "agy": [row("gemini-5-neon-xhigh")],
            "claude": [row("claude-opus", ("high", "xhigh"))],
            "chatgpt": [row("gpt-6.5-astra", ("high", "xhigh"))],
        }
        cfg = UnifiedConfig.default()
        self.assertEqual(select_architect(future, {"agy:gemini": 80}, cfg).model, "gemini-5-neon-xhigh")
        self.assertEqual(select_architect(future, {"agy:gemini": 30, "claude": 20, "chatgpt": 60}, cfg).model, "gpt-6.5-astra")

    def test_two_dedicated_workers_balanced_defaults_and_overrides(self):
        cfg = UnifiedConfig.default()
        workers = build_configured_workers(self.LIVE_CATALOGS, cfg)
        self.assertEqual(set(workers), {"chatgpt", "claude"})
        self.assertEqual((workers["chatgpt"].model, workers["chatgpt"].effort), ("gpt-6.1-terra", "medium"))
        self.assertEqual((workers["claude"].model, workers["claude"].effort), ("claude-sonnet", "medium"))

        # Without terra, ChatGPT balanced worker cleanly falls back to sol
        no_terra = {**self.LIVE_CATALOGS, "chatgpt": [row("gpt-6.2-sol", ("low", "medium", "high")), row("gpt-6-luna", ("medium",))]}
        workers_no_terra = build_configured_workers(no_terra, cfg)
        self.assertEqual((workers_no_terra["chatgpt"].model, workers_no_terra["chatgpt"].effort), ("gpt-6.2-sol", "medium"))

        # Explicit model override via UI config
        custom = UnifiedConfig(workers=(
            WorkerSlotConfig("chatgpt", "chatgpt", "gpt-6.2-sol", "high", "strong"),
            WorkerSlotConfig("claude", "claude", "claude-haiku", "low", "fast"),
        ))
        custom_workers = build_configured_workers(self.LIVE_CATALOGS, custom)
        self.assertEqual((custom_workers["chatgpt"].model, custom_workers["chatgpt"].effort), ("gpt-6.2-sol", "high"))
        self.assertEqual((custom_workers["claude"].model, custom_workers["claude"].effort), ("claude-haiku", "low"))

    def test_rank_worker_slots_honors_preference_and_falls_back_when_empty(self):
        workers = build_configured_workers(self.LIVE_CATALOGS, UnifiedConfig.default())
        # Auto picks higher remaining quota
        auto = rank_worker_slots(workers, {"chatgpt": 40, "claude": 85})
        self.assertEqual([slot for slot, _ in auto], ["claude", "chatgpt"])
        # Explicit preference wins even when lower quota (> 0)
        explicit = rank_worker_slots(workers, {"chatgpt": 3, "claude": 85}, preferred_slot="chatgpt")
        self.assertEqual([slot for slot, _ in explicit], ["chatgpt", "claude"])
        # Explicit preference at 0% falls back to the other worker
        empty = rank_worker_slots(workers, {"chatgpt": 0, "claude": 85}, preferred_slot="chatgpt")
        self.assertEqual([slot for slot, _ in empty], ["claude", "chatgpt"])


if __name__ == "__main__":
    unittest.main()
