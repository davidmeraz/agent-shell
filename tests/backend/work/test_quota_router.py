"""Roster built from live catalogs and quota-aware worker selection."""

import unittest

from tests.support import paths  # noqa: F401
from harness.core.http import Cancelled, StreamControl
from harness.work.quota_router import EXHAUSTED_COOLDOWN, QuotaAwareRouter
from harness.work.roster import Candidate, build_roster, model_tier, quota_bucket, rank
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


class RankTests(unittest.TestCase):
    def first(self, level, remaining, provider=""):
        return rank(build_roster(CATALOGS), level, remaining, provider)[0].label

    def test_level_chooses_tier_and_quota_breaks_ties(self):
        remaining = {"claude": 20, "chatgpt": 74, "agy:gemini": 15, "agy:3p": 98}
        self.assertEqual(self.first("simple", remaining), "chatgpt/gpt-6-luna")
        self.assertEqual(self.first("standard", remaining), "agy/claude-sonnet-5-5-medium")
        self.assertEqual(self.first("hard", remaining), "chatgpt/gpt-6.2-sol")

    def test_nearly_empty_bucket_goes_last_even_when_preferred(self):
        remaining = {"claude": 2, "chatgpt": 60, "agy:gemini": 50, "agy:3p": 50}
        self.assertEqual(self.first("simple", remaining, "claude"), "chatgpt/gpt-6-luna")

    def test_preferred_provider_wins_while_it_has_quota(self):
        self.assertEqual(self.first("simple", {"claude": 30, "chatgpt": 90}, "claude"), "claude/claude-haiku")


class StubWorkers:
    def __init__(self, outcomes):
        self.outcomes = outcomes
        self.calls = []

    def run(self, task, candidate, control, max_steps, progress):
        self.calls.append((candidate.label, task))
        return self.outcomes.get(candidate.bucket, WorkerResult(summary="ok"))


ROSTER = [Candidate("agy", "gemini-3.8-flash-medium", "", "fast", "agy:gemini"),
          Candidate("claude", "claude-haiku", "medium", "fast", "claude"),
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
        router.run("t", StreamControl(), ROSTER, REMAINING, level="simple")
        router.run("t", StreamControl(), ROSTER, REMAINING, level="simple")
        self.now = EXHAUSTED_COOLDOWN + 1
        router.run("t", StreamControl(), ROSTER, REMAINING, level="simple")
        self.assertEqual([label.split("/")[1] for label, _ in workers.calls],
                         ["gemini-3.8-flash-medium", "claude-haiku", "claude-haiku",
                          "gemini-3.8-flash-medium", "claude-haiku"])

    def test_next_worker_is_warned_about_partial_edits(self):
        workers, router = self.route({"agy:gemini": WorkerResult(status="quota_exhausted", tool_calls=3)})
        router.run("task", StreamControl(), ROSTER, REMAINING, level="simple")
        self.assertIn("partial edits", workers.calls[1][1])

    def test_ordinary_failure_is_returned_without_trying_others(self):
        workers, router = self.route({"agy:gemini": WorkerResult(status="failed", error="boom")})
        self.assertEqual(router.run("t", StreamControl(), ROSTER, REMAINING, level="simple").status, "failed")
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


if __name__ == "__main__":
    unittest.main()
