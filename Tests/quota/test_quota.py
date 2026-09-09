#!/usr/bin/env python3
"""Accuracy tests for Resources/quota.py token counting and window mapping.

These guard the four regressions that made the numbers wrong:
  1. Claude usage records were summed without de-duplication, so resumed /
     branched / compacted sessions counted the same API call many times.
  2. Claude token totals ignored cache tokens, which are ~99% of real traffic.
  3. "Today" used a UTC midnight boundary, dropping the user's morning east
     of UTC.
  4. Codex rate limits were mapped by the primary/secondary slot NAME, so a
     weekly-only plan painted its 7-day percentage onto the 5-hour ring.

Pure stdlib, no network, no user data: every fixture is written into a temp
dir and the module's paths are redirected with HELM_* env vars.
"""
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="quota-test-")
CLAUDE_PROJECTS = Path(TMP) / "claude" / "projects"
CODEX_SESSIONS = Path(TMP) / "codex" / "sessions"
CLAUDE_PROJECTS.mkdir(parents=True)
CODEX_SESSIONS.mkdir(parents=True)

# Must be set BEFORE import: CODEX_SESSIONS is resolved at module load.
os.environ["HELM_CLAUDE_PROJECTS"] = str(CLAUDE_PROJECTS)
os.environ["HELM_CODEX_SESSIONS"] = str(CODEX_SESSIONS)
os.environ["HELM_ARK_AGENT_KEY"] = str(Path(TMP) / "no-such-key")

sys.path.insert(0, str(ROOT / "Resources"))
import quota  # noqa: E402


def iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).isoformat().replace("+00:00", "Z")


# A moment safely inside today's local window, and one safely inside yesterday.
TODAY = quota.TODAY_START + 3600
YESTERDAY = quota.TODAY_START - 7200


def usage_row(msg_id, req_id, *, ts=TODAY, inp=10, out=5, cread=1000,
              ccreate=100, model="claude-opus-5", session="s1"):
    return {
        "timestamp": iso(ts),
        "sessionId": session,
        "requestId": req_id,
        "message": {
            "id": msg_id,
            "model": model,
            "usage": {
                "input_tokens": inp,
                "output_tokens": out,
                "cache_read_input_tokens": cread,
                "cache_creation_input_tokens": ccreate,
            },
        },
    }


def write_jsonl(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def clear_claude():
    for p in CLAUDE_PROJECTS.rglob("*.jsonl"):
        p.unlink()


class TestLocalDayBoundary(unittest.TestCase):
    def test_boundary_is_local_midnight(self):
        start = datetime.fromtimestamp(quota.TODAY_START).astimezone()
        self.assertEqual((start.hour, start.minute, start.second), (0, 0, 0),
                         "TODAY_START must land on LOCAL midnight, not UTC")

    def test_records_before_local_midnight_excluded(self):
        clear_claude()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [
            usage_row("m-old", "r-old", ts=YESTERDAY),
            usage_row("m-new", "r-new", ts=TODAY),
        ])
        _, tokens, _, _, _ = quota.claude_code()
        self.assertEqual(tokens, 1115, "only today's record should be counted")


class TestClaudeTokenCounting(unittest.TestCase):
    def test_cache_tokens_are_included(self):
        clear_claude()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [
            usage_row("m1", "r1", inp=10, out=5, cread=1000, ccreate=100),
        ])
        _, tokens, _, by_project, _ = quota.claude_code()
        self.assertEqual(tokens, 1115)
        self.assertEqual(by_project["proj-a"], 1115)

    def test_duplicate_records_counted_once_across_files(self):
        clear_claude()
        rows = [usage_row("m1", "r1"), usage_row("m2", "r2")]
        # A resumed session rewrites the same turns into a second file.
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", rows)
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "b.jsonl", rows + [usage_row("m3", "r3")])
        _, tokens, _, _, _ = quota.claude_code()
        self.assertEqual(tokens, 3 * 1115, "each (message.id, requestId) counts once")

    def test_records_without_dedup_key_still_counted(self):
        clear_claude()
        rows = [usage_row("m1", "r1")]
        rows.append({"timestamp": iso(TODAY), "sessionId": "s1",
                     "message": {"model": "claude-opus-5",
                                 "usage": {"input_tokens": 7, "output_tokens": 3}}})
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", rows)
        _, tokens, _, _, _ = quota.claude_code()
        self.assertEqual(tokens, 1115 + 10)

    def test_synthetic_rows_excluded(self):
        clear_claude()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [
            usage_row("m1", "r1"),
            usage_row("m2", "r2", model="<synthetic>"),
        ])
        _, tokens, _, _, _ = quota.claude_code()
        self.assertEqual(tokens, 1115, "<synthetic> placeholders are not billed")

    def test_subagent_files_included(self):
        clear_claude()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [usage_row("m1", "r1")])
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "subagents" / "s.jsonl",
                    [usage_row("m2", "r2")])
        _, tokens, _, _, _ = quota.claude_code()
        self.assertEqual(tokens, 2 * 1115, "sidechain turns are real usage")

    def test_context_window_from_newest_record(self):
        clear_claude()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [
            usage_row("m1", "r1", ts=TODAY, cread=5000),
            usage_row("m2", "r2", ts=TODAY + 60, cread=9000),
        ])
        _, _, _, _, context = quota.claude_code()
        self.assertEqual(context["proj-a"]["used"], 9000 + 10 + 100)
        self.assertEqual(context["proj-a"]["window"], 200_000)

    def test_million_window_model(self):
        clear_claude()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [
            usage_row("m1", "r1", model="claude-sonnet-4-5[1m]", cread=400_000),
        ])
        _, _, _, _, context = quota.claude_code()
        self.assertEqual(context["proj-a"]["window"], 1_000_000)

    def test_multiple_config_roots(self):
        clear_claude()
        other = Path(TMP) / "claude-alt" / "projects"
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [usage_row("m1", "r1")])
        write_jsonl(other / "proj-b" / "b.jsonl", [usage_row("m2", "r2")])
        prev = os.environ["HELM_CLAUDE_PROJECTS"]
        os.environ["HELM_CLAUDE_PROJECTS"] = f"{CLAUDE_PROJECTS},{other}"
        try:
            _, tokens, _, by_project, _ = quota.claude_code()
        finally:
            os.environ["HELM_CLAUDE_PROJECTS"] = prev
        self.assertEqual(tokens, 2 * 1115)
        self.assertEqual(sorted(by_project), ["proj-a", "proj-b"])

    def test_missing_root_is_not_an_error(self):
        prev = os.environ["HELM_CLAUDE_PROJECTS"]
        os.environ["HELM_CLAUDE_PROJECTS"] = str(Path(TMP) / "nope")
        try:
            self.assertEqual(quota.claude_code(), (0, 0, None, {}, {}))
        finally:
            os.environ["HELM_CLAUDE_PROJECTS"] = prev


def codex_rollout(name, events, cwd="/tmp/work"):
    day = datetime.now().astimezone().strftime("%Y/%m/%d")
    p = CODEX_SESSIONS / day / f"rollout-{name}.jsonl"
    p.parent.mkdir(parents=True, exist_ok=True)
    rows = [{"timestamp": iso(TODAY), "type": "session_meta",
             "payload": {"session_id": name, "cwd": cwd}}]
    rows += events
    write_jsonl(p, rows)
    return p


def token_count(total, last, ts=TODAY, rate_limits=None, window=237_500):
    payload = {
        "type": "token_count",
        "info": {
            "total_token_usage": {"total_tokens": total},
            "last_token_usage": {"total_tokens": last,
                                 "input_tokens": last, "cached_input_tokens": 0},
            "model_context_window": window,
        },
    }
    if rate_limits is not None:
        payload["rate_limits"] = rate_limits
    return {"timestamp": iso(ts), "type": "event_msg", "payload": payload}


def clear_codex():
    for p in CODEX_SESSIONS.rglob("*.jsonl"):
        p.unlink()


class TestCodexTokenCounting(unittest.TestCase):
    def test_sums_per_turn_usage_not_lifetime_cumulative(self):
        clear_codex()
        # A session carried over from previous days: cumulative is 1_000_000 but
        # only 300 + 400 tokens were spent today.
        codex_rollout("s1", [
            token_count(999_300, 500, ts=YESTERDAY),
            token_count(999_600, 300, ts=TODAY),
            token_count(1_000_000, 400, ts=TODAY),
        ])
        _, tokens, _, _, _, _ = quota.codex()
        self.assertEqual(tokens, 700,
                         "only today's turns count, not the session lifetime")

    def test_repeated_identical_snapshots_not_double_counted(self):
        clear_codex()
        codex_rollout("s1", [
            token_count(1000, 1000, ts=TODAY),
            token_count(1000, 1000, ts=TODAY),   # TUI re-emit on redraw
            token_count(1500, 500, ts=TODAY),
        ])
        _, tokens, _, _, _, _ = quota.codex()
        self.assertEqual(tokens, 1500)

    def test_tokens_attributed_to_session_cwd(self):
        clear_codex()
        codex_rollout("s1", [token_count(100, 100)], cwd="/tmp/a")
        codex_rollout("s2", [token_count(250, 250)], cwd="/tmp/b")
        _, tokens, _, _, by_project, _ = quota.codex()
        self.assertEqual(tokens, 350)
        self.assertEqual(by_project, {"/tmp/a": 100, "/tmp/b": 250})

    def test_context_uses_model_context_window(self):
        clear_codex()
        codex_rollout("s1", [token_count(100, 40, window=237_500)], cwd="/tmp/a")
        _, _, _, _, _, context = quota.codex()
        self.assertEqual(context["/tmp/a"], {"used": 40, "window": 237_500})

    def test_sessions_today_uses_local_day(self):
        clear_codex()
        # Touched within 24h but before local midnight -> not "today".
        p = codex_rollout("s1", [token_count(100, 100, ts=YESTERDAY)])
        os.utime(p, (YESTERDAY, YESTERDAY))
        codex_rollout("s2", [token_count(200, 200, ts=TODAY)])
        sessions, tokens, _, _, _, _ = quota.codex()
        self.assertEqual(sessions, 1)
        self.assertEqual(tokens, 200)

    def test_no_sessions_reports_none(self):
        clear_codex()
        sessions, tokens, _, _, _, _ = quota.codex()
        self.assertEqual((sessions, tokens), (0, None))


class TestCodexWindowMapping(unittest.TestCase):
    """Slot NAME must never decide which ring a percentage lands on."""

    def test_weekly_only_plan_does_not_fill_the_five_hour_ring(self):
        rl = {"primary": {"used_percent": 100.0, "window_minutes": 10080,
                          "resets_at": 1789437979},
              "secondary": None, "plan_type": "prolite"}
        out = quota._codex_map_rate_limits(
            rl, "used_percent", "resets_at", "window_minutes", "plan_type")
        self.assertNotIn("five_hour_used_percent", out)
        self.assertEqual(out["seven_day_used_percent"], 100.0)
        self.assertEqual(out["seven_day_resets_at"], 1789437979)
        self.assertEqual(out["plan"], "prolite")

    def test_standard_two_window_plan(self):
        rl = {"primary": {"used_percent": 12.0, "window_minutes": 300},
              "secondary": {"used_percent": 44.0, "window_minutes": 10080}}
        out = quota._codex_map_rate_limits(
            rl, "used_percent", "resets_at", "window_minutes", "plan_type")
        self.assertEqual(out["five_hour_used_percent"], 12.0)
        self.assertEqual(out["seven_day_used_percent"], 44.0)

    def test_app_server_camel_case_keys(self):
        rl = {"primary": {"usedPercent": 100, "windowDurationMins": 10080,
                          "resetsAt": 1789437979},
              "secondary": None, "planType": "prolite"}
        out = quota._codex_map_rate_limits(
            rl, "usedPercent", "resetsAt", "windowDurationMins", "planType")
        self.assertEqual(out.get("seven_day_used_percent"), 100)
        self.assertIsNone(out.get("five_hour_used_percent"))

    def test_missing_window_length_falls_back_to_slot_meaning(self):
        rl = {"primary": {"used_percent": 30.0},
              "secondary": {"used_percent": 60.0}}
        out = quota._codex_map_rate_limits(
            rl, "used_percent", "resets_at", "window_minutes", "plan_type")
        self.assertEqual(out["five_hour_used_percent"], 30.0)
        self.assertEqual(out["seven_day_used_percent"], 60.0)

    def test_plan_label_alone_is_not_a_reading(self):
        self.assertIsNone(quota._codex_map_rate_limits(
            {"primary": None, "secondary": None, "plan_type": "prolite"},
            "used_percent", "resets_at", "window_minutes", "plan_type"))

    def test_walk_continues_past_a_plan_only_rate_limits_event(self):
        clear_codex()
        newest = codex_rollout("s2", [token_count(
            100, 100, rate_limits={"primary": None, "secondary": None,
                                   "plan_type": "prolite"})])
        older = codex_rollout("s1", [token_count(
            50, 50, rate_limits={"primary": {"used_percent": 22.0,
                                             "window_minutes": 300}})])
        os.utime(older, (TODAY - 600, TODAY - 600))
        os.utime(newest, (TODAY, TODAY))
        _, _, _, limits, _, _ = quota.codex()
        self.assertEqual(limits["five_hour_used_percent"], 22.0,
                         "a plan-label-only event must not end the search")

    def test_non_dict_input(self):
        self.assertIsNone(quota._codex_map_rate_limits(
            None, "used_percent", "resets_at", "window_minutes", "plan_type"))


class TestIntCoercion(unittest.TestCase):
    def test_rejects_bool_and_junk(self):
        self.assertEqual(quota._int(True), 0)
        self.assertEqual(quota._int(None), 0)
        self.assertEqual(quota._int("500"), 0)
        self.assertEqual(quota._int(7), 7)
        self.assertEqual(quota._int(7.9), 7)


class TestJSONShape(unittest.TestCase):
    def test_emit_json_is_valid_and_has_expected_keys(self):
        clear_claude()
        clear_codex()
        write_jsonl(CLAUDE_PROJECTS / "proj-a" / "a.jsonl", [usage_row("m1", "r1")])
        codex_rollout("s1", [token_count(100, 100)], cwd="/tmp/a")
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            quota.emit_json()
        data = json.loads(buf.getvalue())
        self.assertEqual(data["claude"]["tokens_today"], 1115)
        self.assertEqual(data["codex"]["tokens_today"], 100)
        self.assertEqual(data["codex"]["by_project"], {"/tmp/a": 100})


if __name__ == "__main__":
    unittest.main(verbosity=2)
