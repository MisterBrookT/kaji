#!/usr/bin/env python3
"""helm-quota: per-harness session/token usage summary.

Default: human-readable table.   `--json`: compact machine-readable JSON
(consumed by Helm's bottom status bar in kaku.lua).

────────────────────────────────────────────────────────────────────────
Usage sources investigated (2026-06) — what's actually available per harness:

  claude-code : No non-interactive CLI usage command. The interactive
                session has /cost and /usage, but nothing scriptable.
                `ccusage` (npm) is the popular community tool, but it just
                parses the same ~/.claude/projects/**/*.jsonl `message.usage`
                fields we read here — so our local parse IS the canonical
                source (accurate input+output token counts per turn).

  kiro        : No `kiro-cli usage` subcommand. Session files under
                ~/.kiro/sessions/cli/*.json carry NO token counts. Usage is
                only visible on the kiro.dev account dashboard. => session
                COUNT is the best local signal; tokens = N/A.

  opencode    : `opencode stats` exists but prints an all-time ASCII table
                (not today-scoped, not JSON) — too fragile to scrape. BUT the
                per-message JSON under
                ~/.local/share/opencode/storage/message/<ses>/<msg>.json
                contains tokens.{input,output,reasoning,cache} + cost +
                time.created. We sum those for today => accurate tokens.

  codex       : ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl carries
                `token_count` events with BOTH cumulative token usage AND
                rate_limits.{primary,secondary}.used_percent — the only
                harness exposing real account quota %% locally. The usage
                values are session-CUMULATIVE: take the LAST event per file,
                never sum events. (See SOURCES.md.)

Conclusion: local-file parsing gives the best today-scoped numbers for
claude-code + opencode + codex; kiro stays session-count only until a
CLI/API exists.
────────────────────────────────────────────────────────────────────────
"""
import json, os, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
# Overridable for tests.
CODEX_SESSIONS = Path(os.environ.get("HELM_CODEX_SESSIONS") or HOME / ".codex" / "sessions")
NOW = time.time()
TODAY_START = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()


def ago(ts: float) -> str:
    d = NOW - ts
    if d < 60: return f"{int(d)}s ago"
    if d < 3600: return f"{int(d/60)}m ago"
    if d < 86400: return f"{int(d/3600)}h ago"
    return f"{int(d/86400)}d ago"


# ── live account limits (claude oauth endpoint / codex app-server) ──────────
# Both report SERVER-side window utilization: five_hour + seven_day, 0-100.
# Cached on disk for LIMITS_TTL secs: the claude endpoint 429s under ~180s
# polling, and spawning codex app-server per call is not free. Fetch failures
# serve the stale cache (better an old number than none). Set
# HELM_QUOTA_OFFLINE=1 to disable live calls entirely (tests, air-gapped).
CACHE_DIR = HOME / ".helm" / "sessions"
LIMITS_TTL = 180


def _limits_cached(name, fetch):
    path = CACHE_DIR / name
    try:
        if time.time() - path.stat().st_mtime < LIMITS_TTL:
            return json.loads(path.read_text())
    except Exception:
        pass
    data = None
    if not os.environ.get("HELM_QUOTA_OFFLINE"):
        try:
            data = fetch()
        except Exception:
            data = None
    if data:
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            # Atomic write (tmp + rename): brain restarts quota.py every poll,
            # so a torn write would poison every reader for a TTL.
            tmp = path.with_name(path.name + ".%d.tmp" % os.getpid())
            tmp.write_text(json.dumps(data))
            tmp.replace(path)
        except Exception:
            pass
        return data
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def _claude_oauth_token():
    """Access token from ~/.claude/.credentials.json or the macOS keychain."""
    try:
        d = json.loads((HOME / ".claude" / ".credentials.json").read_text())
        return d["claudeAiOauth"]["accessToken"]
    except Exception:
        pass
    try:
        pr = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True, text=True, timeout=5)
        if pr.returncode == 0 and pr.stdout.strip():
            return json.loads(pr.stdout)["claudeAiOauth"]["accessToken"]
    except Exception:
        pass
    return None


def _fetch_claude_limits():
    token = _claude_oauth_token()
    if not token:
        return None
    import urllib.request
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": "Bearer " + token,
            "anthropic-beta": "oauth-2025-04-20",
            # Omitting a claude-code UA gets a persistent 429.
            "User-Agent": "claude-code/2.1.90",
            "Content-Type": "application/json",
        })
    with urllib.request.urlopen(req, timeout=10) as r:
        d = json.loads(r.read().decode("utf-8"))
    out = {}
    for key in ("five_hour", "seven_day"):
        w = d.get(key) or {}
        if w.get("utilization") is not None:
            out[key + "_used_percent"] = w["utilization"]
            if w.get("resets_at"):
                out[key + "_resets_at"] = w["resets_at"]
    return out or None


def claude_limits():
    return _limits_cached("claude-limits-cache.json", _fetch_claude_limits)


def _fetch_codex_limits():
    """codex app-server JSON-RPC account/rateLimits/read (official path)."""
    import select
    proc = subprocess.Popen(
        ["codex", "-s", "read-only", "-a", "untrusted", "app-server"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True)
    try:
        def send(o):
            proc.stdin.write(json.dumps(o) + "\n")
            proc.stdin.flush()
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "kaji-quota", "version": "1.0"}}})
        send({"jsonrpc": "2.0", "id": 2,
              "method": "account/rateLimits/read", "params": {}})
        deadline = time.time() + 10
        while time.time() < deadline:
            r, _, _ = select.select([proc.stdout], [], [], 1.0)
            if not r:
                continue
            line = proc.stdout.readline()
            if not line:
                break
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("id") == 2:
                rl = (d.get("result") or {}).get("rateLimits") or {}
                out = {}
                for src, key in (("primary", "five_hour"), ("secondary", "seven_day")):
                    w = rl.get(src) or {}
                    if w.get("usedPercent") is not None:
                        out[key + "_used_percent"] = w["usedPercent"]
                        if w.get("resetsAt") is not None:
                            out[key + "_resets_at"] = w["resetsAt"]
                if rl.get("planType"):
                    out["plan"] = rl["planType"]
                return out or None
        return None
    finally:
        try:
            proc.kill()
        except Exception:
            pass


def codex_limits():
    return _limits_cached("codex-limits-cache.json", _fetch_codex_limits)


def munge_cwd(cwd):
    """A cwd path the way ~/.claude/projects names its dirs (/ and . -> -)."""
    return str(cwd or "").replace("/", "-").replace(".", "-").replace("_", "-")


def claude_code():
    """Returns (sessions_today, tokens_today, last_active_ts, by_project, context).

    by_project: {munged project dir name: tokens_today} — keys match
    munge_cwd(session cwd), so a fleet session maps to its own burn.
    """
    base = HOME / ".claude" / "projects"
    if not base.exists():
        return 0, 0, None, {}, {}
    tokens_today, last = 0, None
    session_ids_today = set()
    by_project = {}
    context = {}        # proj -> {"used": n, "window": w, "ts": newest-seen}
    for jsonl in base.rglob("*.jsonl"):
        if "subagents" in str(jsonl):
            continue
        try:
            mtime = jsonl.stat().st_mtime
        except OSError:
            continue
        if last is None or mtime > last:
            last = mtime
        # A file not touched today cannot contain today's records — skip the
        # (potentially large) content scan entirely.
        if mtime < TODAY_START:
            continue
        proj = jsonl.parent.name
        try:
            with open(jsonl) as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    ts_str = d.get("timestamp")
                    if not ts_str:
                        continue
                    try:
                        ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).timestamp()
                    except Exception:
                        continue
                    if ts >= TODAY_START:
                        sid = d.get("sessionId")
                        if sid:
                            session_ids_today.add(sid)
                        usage = d.get("message", {}).get("usage") if isinstance(d.get("message"), dict) else None
                        if usage:
                            n = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
                            tokens_today += n
                            by_project[proj] = by_project.get(proj, 0) + n
                            # Live context size = the newest prompt's full input
                            # (incl. cache reads/creations). Window by model:
                            # "[1m]" models 1M, else 200k.
                            cur = context.get(proj)
                            if cur is None or ts > cur["ts"]:
                                used = (usage.get("input_tokens", 0)
                                        + usage.get("cache_read_input_tokens", 0)
                                        + usage.get("cache_creation_input_tokens", 0))
                                model = (d.get("message") or {}).get("model") or ""
                                window = 1_000_000 if ("[1m]" in model or "fable" in model) else 200_000
                                if used > window:
                                    window = 1_000_000
                                if used:
                                    context[proj] = {"used": used, "window": window, "ts": ts}
        except Exception:
            pass
    for v in context.values():
        v.pop("ts", None)
    return len(session_ids_today), tokens_today, last, by_project, context


def kiro():
    """Returns (sessions_today, tokens_today=None, last_active_ts). No token data."""
    base = HOME / ".kiro" / "sessions" / "cli"
    if not base.exists():
        return 0, None, None
    sessions_today, last = 0, None
    for f in base.glob("*.json"):
        try:
            d = json.loads(f.read_text())
            ts_str = d.get("updated_at") or d.get("created_at")
            if not ts_str:
                continue
            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).timestamp()
            if last is None or ts > last:
                last = ts
            if ts >= TODAY_START:
                sessions_today += 1
        except Exception:
            pass
    return sessions_today, None, last  # no token data in kiro session files


def opencode():
    """Returns (sessions_today, tokens_today, last_active_ts).

    sessions_today from storage/session; tokens_today summed from per-message
    JSON (tokens.input + tokens.output for assistant turns created today)."""
    storage = HOME / ".local" / "share" / "opencode" / "storage"
    sess_base = storage / "session"
    msg_base = storage / "message"
    sessions_today, last = 0, None
    if sess_base.exists():
        for f in sess_base.rglob("*.json"):
            try:
                d = json.loads(f.read_text())
                t = d.get("time", {})
                updated = t.get("updated") or t.get("created")
                if not updated:
                    continue
                ts = updated / 1000.0
                if last is None or ts > last:
                    last = ts
                if ts >= TODAY_START:
                    sessions_today += 1
            except Exception:
                pass
    tokens_today = 0
    if msg_base.exists():
        for f in msg_base.rglob("*.json"):
            try:
                d = json.loads(f.read_text())
                created = (d.get("time", {}) or {}).get("created")
                if not created:
                    continue
                ts = created / 1000.0
                if ts < TODAY_START:
                    continue
                tk = d.get("tokens") or {}
                tokens_today += (tk.get("input", 0) or 0) + (tk.get("output", 0) or 0)
            except Exception:
                pass
    return sessions_today, (tokens_today if tokens_today else None), last


def _codex_last_token_count(path):
    """Last token_count payload + session cwd in a rollout file:
    (info, rate_limits, cwd)."""
    info, rl, cwd = None, None, None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if cwd is None and '"cwd"' in line:
                    try:
                        rec0 = json.loads(line)
                        pl0 = rec0.get("payload") if isinstance(rec0, dict) else None
                        if isinstance(pl0, dict) and pl0.get("cwd"):
                            cwd = pl0["cwd"]
                    except Exception:
                        pass
                if '"token_count"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if not isinstance(rec, dict):
                    continue
                payload = rec.get("payload") or {}
                if not isinstance(payload, dict):
                    continue
                if payload.get("type") != "token_count":
                    continue
                info = payload.get("info") or info
                rl = payload.get("rate_limits") or rl
    except OSError:
        pass
    return info, rl, cwd


def codex():
    """Returns (sessions_today, tokens_today, last_active_ts, limits|None, by_project, context).

    tokens: token_count events are session-CUMULATIVE — take the LAST event
    per file and sum across today's files (UTC date dirs).
    limits: from the freshest session overall (account-level, not today-bound):
    {primary_used_percent?, secondary_used_percent?, *_resets_at?, plan?}.
    """
    base = CODEX_SESSIONS
    if not base.exists():
        return 0, None, None, None, {}, {}
    today = datetime.now(timezone.utc)
    day_dir = base / f"{today:%Y}" / f"{today:%m}" / f"{today:%d}"
    files_today = sorted(day_dir.glob("rollout-*.jsonl")) if day_dir.exists() else []

    tokens_today, last = 0, None
    by_project = {}
    context = {}        # cwd -> {"used", "window"} from the freshest session
    ctx_mtime = {}
    for p in files_today:
        info, _, cwd = _codex_last_token_count(p)
        try:
            m = p.stat().st_mtime
        except OSError:
            m = 0
        if info:
            n = ((info.get("total_token_usage") or {}).get("total_tokens") or 0)
            tokens_today += n
            if cwd:
                by_project[cwd] = by_project.get(cwd, 0) + n
                lt = info.get("last_token_usage") or {}
                used = (lt.get("input_tokens") or 0) + (lt.get("cached_input_tokens") or 0)
                window = info.get("model_context_window") or 0
                if used and window and m >= ctx_mtime.get(cwd, 0):
                    context[cwd] = {"used": used, "window": window}
                    ctx_mtime[cwd] = m
        last = max(last or 0, m) if m else last

    limits = None
    try:
        all_files = sorted(base.glob("*/*/*/rollout-*.jsonl"), key=lambda p: p.stat().st_mtime)
    except OSError:
        all_files = []
    if all_files:
        _, rl, _ = _codex_last_token_count(all_files[-1])
        if rl:
            limits = {}
            for src, key in (("primary", "five_hour"), ("secondary", "seven_day")):
                window = rl.get(src)
                if isinstance(window, dict) and window.get("used_percent") is not None:
                    limits[key + "_used_percent"] = window["used_percent"]
                    if window.get("resets_at") is not None:
                        limits[key + "_resets_at"] = window["resets_at"]
            if rl.get("plan_type"):
                limits["plan"] = rl["plan_type"]
            limits = limits or None

    return len(files_today), (tokens_today or None), last, limits, by_project, context


def fmt_tokens(n):
    if n is None: return "N/A"
    if n == 0: return "N/A"
    return f"~{n//1000}k" if n >= 1000 else str(n)


def fmt_last(ts):
    if ts is None: return "N/A"
    return ago(ts)


def collect():
    """Per-harness tuples (name, sessions, tokens, last, limits|None, by_project).

    Limits: live account windows (five_hour/seven_day used_percent) — claude
    via the oauth usage endpoint, codex via app-server; codex falls back to
    the freshest session file when the live call fails.
    """
    c_sess, c_tok, c_last, c_proj, c_ctx = claude_code()
    x_sess, x_tok, x_last, x_file_limits, x_proj, x_ctx = codex()
    return [
        ("claude", c_sess, c_tok, c_last, claude_limits(), c_proj, c_ctx),
        ("kiro",   *kiro(), None, {}, {}),
        ("opencode", *opencode(), None, {}, {}),
        ("codex", x_sess, x_tok, x_last, codex_limits() or x_file_limits, x_proj, x_ctx),
    ]


def emit_json():
    rows = collect()
    out = {}
    for name, sess, tok, _last, limits, by_project, context in rows:
        out[name] = {
            "tokens_today": tok if tok is not None else 0,
            "sessions_today": sess,
        }
        if limits:
            # Additive key — existing consumers (kaku.lua status bar) read
            # tokens_today/sessions_today only and are unaffected.
            out[name]["limits"] = limits
        if by_project:
            out[name]["by_project"] = by_project
        if context:
            out[name]["context"] = context
    # compact, no spaces — small payload for run_child_process
    sys.stdout.write(json.dumps(out, separators=(",", ":")))
    sys.stdout.write("\n")


def emit_table():
    # human table uses the 'claude-code' label for clarity
    rows = collect()
    label = {"claude": "claude-code"}
    print("Helm Quota Status")
    print("=================")
    print(f"{'harness':<14} {'sessions_today':<16} {'tokens_today':<13} {'last_active'}")
    print(f"{'-'*14} {'-'*14} {'-'*11} {'-'*12}")
    for name, sess, tok, last, limits, _bp, _ctx in rows:
        extra = ""
        if limits:
            fh = limits.get("five_hour_used_percent")
            sd = limits.get("seven_day_used_percent")
            bits = []
            if fh is not None:
                bits.append(f"5h {fh:.0f}%")
            if sd is not None:
                bits.append(f"wk {sd:.0f}%")
            if bits:
                extra = "  used " + " · ".join(bits) + (f" ({limits['plan']})" if limits.get("plan") else "")
        print(f"{label.get(name, name):<14} {str(sess):<16} {fmt_tokens(tok):<13} {fmt_last(last)}{extra}")
    print()
    print("Note: claude-code tokens summed from message.usage (today only).")
    print("      opencode tokens summed from storage/message/*.json (today).")
    print("      codex tokens = last token_count per session (cumulative), today's UTC dir;")
    print("            quota %% from rate_limits in the freshest session.")
    print("      kiro session files store no token counts (sessions only).")


def main():
    if "--json" in sys.argv[1:]:
        emit_json()
    else:
        emit_table()


if __name__ == "__main__":
    main()
