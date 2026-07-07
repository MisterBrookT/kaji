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
import hashlib, hmac, json, os, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

HOME = Path.home()
# Overridable for tests.
CODEX_SESSIONS = Path(os.environ.get("HELM_CODEX_SESSIONS") or HOME / ".codex" / "sessions")
ARK_AGENT_KEY = Path(os.environ.get("HELM_ARK_AGENT_KEY") or HOME / ".config" / "ark" / "agent-key")


def _read_env_file(path):
    data = {}
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        return data
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key:
            data[key] = value
    return data


_LOCAL_ENV_PATH = os.environ.get("KAJI_VOLCENGINE_ENV") or os.environ.get("KAJI_GAUGE_VOLCENGINE_ENV")
if not _LOCAL_ENV_PATH:
    _KAJI_ENV = HOME / ".config" / "kaji" / "volcengine.env"
    _LEGACY_ENV = HOME / ".config" / "kaji-gauge" / "volcengine.env"
    _LOCAL_ENV_PATH = _KAJI_ENV if _KAJI_ENV.exists() or not _LEGACY_ENV.exists() else _LEGACY_ENV
LOCAL_ENV = _read_env_file(_LOCAL_ENV_PATH)


def _secret(*names):
    for name in names:
        value = os.environ.get(name) or LOCAL_ENV.get(name)
        if value:
            return value
    return ""


VOLC_AK = _secret("VOLCENGINE_ACCESS_KEY_ID", "VOLCENGINE_ACCESS_KEY",
                  "VOLC_ACCESS_KEY_ID", "VOLC_ACCESS_KEY")
VOLC_SK = _secret("VOLCENGINE_SECRET_ACCESS_KEY", "VOLCENGINE_SECRET_KEY",
                  "VOLC_SECRET_ACCESS_KEY", "VOLC_SECRET_KEY")
VOLC_SESSION_TOKEN = _secret("VOLCENGINE_SESSION_TOKEN", "VOLC_SESSION_TOKEN")
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
    import queue as _queue
    import threading
    proc = subprocess.Popen(
        ["codex", "-s", "read-only", "-a", "untrusted", "app-server"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True)
    # Drain stdout on a background thread. select()+text readline() can leave a
    # second JSON-RPC response stranded in the userspace buffer (select reports
    # the fd not-ready while a full line already sits decoded), stalling the
    # whole 10s budget. A blocking line iterator on its own thread never stalls.
    lines = _queue.Queue()

    def _drain():
        try:
            for ln in proc.stdout:
                lines.put(ln)
        except Exception:
            pass
        lines.put(None)

    threading.Thread(target=_drain, daemon=True).start()
    try:
        def send(o):
            proc.stdin.write(json.dumps(o) + "\n")
            proc.stdin.flush()
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "kaji-quota", "version": "1.0"}}})
        send({"jsonrpc": "2.0", "id": 2,
              "method": "account/rateLimits/read", "params": {}})
        deadline = time.time() + 10
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                break
            try:
                line = lines.get(timeout=remaining)
            except _queue.Empty:
                break
            if line is None:
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


def _codex_rollout_files():
    base = CODEX_SESSIONS
    if not base.exists():
        return []
    try:
        return sorted(base.glob("*/*/*/rollout-*.jsonl"), key=lambda p: p.stat().st_mtime)
    except OSError:
        return []


def _codex_recent_rollout_files(hours=24):
    cutoff = time.time() - hours * 3600
    files = []
    for p in _codex_rollout_files():
        try:
            if p.stat().st_mtime >= cutoff:
                files.append(p)
        except OSError:
            pass
    return files


def codex():
    """Returns (sessions_today, tokens_today, last_active_ts, limits|None, by_project, context).

    tokens: token_count events are session-CUMULATIVE — take the LAST event
    per file and sum across sessions active in the last 24h. Directory dates are
    not reliable for a menu bar app because UTC/local day boundaries differ.
    limits: from the freshest session overall (account-level, not today-bound):
    {primary_used_percent?, secondary_used_percent?, *_resets_at?, plan?}.
    """
    base = CODEX_SESSIONS
    if not base.exists():
        return 0, None, None, None, {}, {}
    files_recent = _codex_recent_rollout_files(hours=24)

    tokens_today, last = 0, None
    by_project = {}
    context = {}        # cwd -> {"used", "window"} from the freshest session
    ctx_mtime = {}
    for p in files_recent:
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
    all_files = _codex_rollout_files()
    # Walk sessions freshest-first and take the first that actually carries a
    # rate_limits event. The single newest file may be a brand-new session with
    # no token_count yet (rl=None) — using only all_files[-1] would then drop
    # account limits even though the 2nd-freshest session has fresh ones.
    for p in reversed(all_files):
        _, rl, _ = _codex_last_token_count(p)
        if not rl:
            continue
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
        break

    return len(files_recent), (tokens_today or None), last, limits, by_project, context


def codex_cost_today():
    """Best-effort Codex USD estimate from last-24h token_count totals.

    Codex sessions expose cumulative per-file input/cached/output tokens. Pricing
    uses GPT-5.4 short-context API rates as an estimate; subscriptions remain
    quota-based, not direct per-token billing.
    """
    input_rate = 1.25
    cached_rate = 0.13
    output_rate = 7.50
    total = 0.0
    found = False
    for p in _codex_recent_rollout_files(hours=24):
        info, _, _ = _codex_last_token_count(p)
        usage = (info or {}).get("total_token_usage") or {}
        if not usage:
            continue
        input_tokens = usage.get("input_tokens") or 0
        cached_tokens = usage.get("cached_input_tokens") or 0
        output_tokens = usage.get("output_tokens") or 0
        uncached = max(input_tokens - cached_tokens, 0)
        total += (uncached * input_rate + cached_tokens * cached_rate + output_tokens * output_rate) / 1_000_000
        found = True
    return total if found else None


def fmt_tokens(n):
    if n is None: return "N/A"
    if n == 0: return "N/A"
    return f"~{n//1000}k" if n >= 1000 else str(n)


def fmt_last(ts):
    if ts is None: return "N/A"
    return ago(ts)


def _reset_epoch(value):
    """A reset timestamp as epoch seconds. Accepts unix epoch (codex/minimax)
    or ISO-8601 (claude/ark). None if unparseable."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    return None


def _scrub_expired(limits):
    """Drop a window's used_percent once its reset time has passed.

    The percentage is a point-in-time snapshot (last provider activity / last
    cache fetch). After the window resets the real usage is ~0, but a quiet
    provider keeps reporting the old pre-reset value until it's exercised again
    — that's the stale 'codex shows 80% when it already reset' bug. Dropping the
    value renders '—' (honest unknown) instead of a stale-high number."""
    if not isinstance(limits, dict):
        return limits
    for win in ("five_hour", "seven_day"):
        reset = _reset_epoch(limits.get(win + "_resets_at"))
        if reset is not None and reset <= NOW:
            limits.pop(win + "_used_percent", None)
            limits.pop(win + "_resets_at", None)
    return limits


def _merge_limits(primary, fallback):
    """Merge two limits dicts per-KEY (not whole-dict). `primary` (live) wins
    where present; `fallback` (file) fills the rest. A partial live dict (e.g.
    only five_hour) must not mask a more complete file dict's seven_day."""
    if not primary:
        return fallback
    if not fallback:
        return primary
    out = dict(fallback)
    out.update({k: v for k, v in primary.items() if v is not None})
    return out


def _fetch_minimax_limits():
    """MiniMax Token Plan usage via the `mmx` CLI.

    `mmx quota show --output json` returns a per-model `model_remains[]` array.
    We pick the "general" model (text quota) and read:
      - 5h window:  used% = 100 - current_interval_remaining_percent
      - 7d window:  used% = 100 - current_weekly_remaining_percent
      - resets:     end_time / weekly_end_time (ms unix epoch → seconds float,
                    the ResetTimestamp decoder on the Swift side accepts both)

    On auth failure (no `mmx` creds), unrecognised response, or any subprocess
    error we return None and the store shows the MiniMax ring empty. Same
    stale-cache behavior as the other providers.
    """
    try:
        proc = subprocess.run(
            ["mmx", "quota", "show", "--output", "json", "--quiet"],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    try:
        d = json.loads(proc.stdout)
    except Exception:
        return None
    out = {}
    for entry in (d.get("model_remains") or []):
        if not isinstance(entry, dict) or entry.get("model_name") != "general":
            continue
        iv_remaining = entry.get("current_interval_remaining_percent")
        wk_remaining = entry.get("current_weekly_remaining_percent")
        if iv_remaining is not None:
            out["five_hour_used_percent"] = max(0.0, 100.0 - float(iv_remaining))
            end_ms = entry.get("end_time")
            if isinstance(end_ms, (int, float)):
                out["five_hour_resets_at"] = float(end_ms) / 1000.0
        if wk_remaining is not None:
            out["seven_day_used_percent"] = max(0.0, 100.0 - float(wk_remaining))
            wk_end_ms = entry.get("weekly_end_time")
            if isinstance(wk_end_ms, (int, float)):
                out["seven_day_resets_at"] = float(wk_end_ms) / 1000.0
        break
    return out or None


def minimax_limits():
    return _limits_cached("minimax-limits-cache.json", _fetch_minimax_limits)


def minimax():
    """MiniMax: no local session files; quota lives server-side (mmx CLI).

    Returns (sessions_today=0, tokens_today=None, last_active_ts=None) — the
    ring's `limits` block is filled by `minimax_limits()` (cached) which the
    Swift side surfaces as the 5h/7d percentages.
    """
    return 0, None, None


def _norm_query(params):
    bits = []
    for key in sorted(params):
        value = params[key]
        if isinstance(value, list):
            vals = value
        else:
            vals = [value]
        for val in vals:
            bits.append(quote(str(key), safe="-_.~") + "=" + quote(str(val), safe="-_.~"))
    return "&".join(bits)


def _hmac_sha256(key, content):
    return hmac.new(key, content.encode("utf-8"), hashlib.sha256).digest()


def _hash_sha256(content):
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _volc_openapi(action, query=None, body_obj=None):
    """Signed Volcengine OpenAPI GET request for Ark management-plane APIs."""
    if not VOLC_AK or not VOLC_SK:
        return None

    import urllib.request
    host = "open.volcengineapi.com"
    service = "ark"
    region = "cn-beijing"
    version = "2024-01-01"
    body = ""
    content_type = "application/x-www-form-urlencoded"
    method = "GET"
    if body_obj is not None:
        body = json.dumps(body_obj, separators=(",", ":"))
        content_type = "application/json"
        method = "POST"
    now = datetime.now(timezone.utc)
    x_date = now.strftime("%Y%m%dT%H%M%SZ")
    short_date = x_date[:8]
    x_content_sha256 = _hash_sha256(body)

    params = {"Action": action, "Version": version}
    if query:
        params.update(query)

    headers_to_sign = {
        "content-type": content_type,
        "host": host,
        "x-content-sha256": x_content_sha256,
        "x-date": x_date,
    }
    if VOLC_SESSION_TOKEN:
        headers_to_sign["x-security-token"] = VOLC_SESSION_TOKEN
    signed_headers = ";".join(sorted(headers_to_sign))
    canonical_headers = "".join(f"{k}:{headers_to_sign[k]}\n" for k in sorted(headers_to_sign))
    canonical_request = "\n".join([
        method,
        "/",
        _norm_query(params),
        canonical_headers,
        signed_headers,
        x_content_sha256,
    ])
    credential_scope = "/".join([short_date, region, service, "request"])
    string_to_sign = "\n".join([
        "HMAC-SHA256",
        x_date,
        credential_scope,
        _hash_sha256(canonical_request),
    ])
    k_date = _hmac_sha256(VOLC_SK.encode("utf-8"), short_date)
    k_region = _hmac_sha256(k_date, region)
    k_service = _hmac_sha256(k_region, service)
    k_signing = _hmac_sha256(k_service, "request")
    signature = hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    headers = {
        "Host": host,
        "Content-Type": content_type,
        "X-Content-Sha256": x_content_sha256,
        "X-Date": x_date,
        "Authorization": (
            "HMAC-SHA256 "
            f"Credential={VOLC_AK}/{credential_scope}, "
            f"SignedHeaders={signed_headers}, "
            f"Signature={signature}"
        ),
    }
    if VOLC_SESSION_TOKEN:
        headers["X-Security-Token"] = VOLC_SESSION_TOKEN

    # Use the SAME canonical encoder as the signature (_norm_query). urlencode
    # differs on spaces (+) and list params, which would desync the signed
    # query string from the wire query string and fail signature verification.
    url = "https://" + host + "/?" + _norm_query(params)
    req = urllib.request.Request(url, data=(body.encode("utf-8") if method == "POST" else None),
                                 headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def _walk_values(obj, path=()):
    if isinstance(obj, dict):
        for key, value in obj.items():
            yield from _walk_values(value, path + (str(key),))
    elif isinstance(obj, list):
        for idx, value in enumerate(obj):
            yield from _walk_values(value, path + (str(idx),))
    else:
        yield path, obj


def _coerce_percent(value, ratio_ok=True):
    # bool is an int subclass — True would coerce to 100, False to 0. Reject it.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    v = float(value)
    # Only a value strictly < 1 is unambiguously a fraction (0.44 -> 44%). The
    # value 1 is ambiguous (1% vs 100%); for percent/rate fields treat it as an
    # already-scaled percent, never multiply.
    if ratio_ok and 0 <= v < 1:
        return v * 100.0
    if 0 <= v <= 100:
        return v
    return None


_METRIC_TERMS = ("percent", "ratio", "rate", "utilization")


def _find_percent(data, window_terms):
    for path, value in _walk_values(data):
        key = "_".join(path).lower()
        if not any(term in key for term in window_terms):
            continue
        matched = [term for term in _METRIC_TERMS if term in key]
        if not matched:
            continue
        # A field named "*ratio*" is a 0..1 fraction; percent/rate/utilization
        # fields are already scaled 0..100, so don't re-multiply a bare 1.
        p = _coerce_percent(value, ratio_ok=("ratio" in matched))
        if p is not None:
            return p
    return None


def _iso_from_volc_ms(value):
    if not isinstance(value, (int, float)) or value <= 0:
        return None
    return datetime.fromtimestamp(value / 1000.0, timezone.utc).isoformat().replace("+00:00", "Z")


def _add_ark_window(out, result, source_key, target_key):
    window = result.get(source_key) if isinstance(result, dict) else None
    if not isinstance(window, dict):
        return
    quota = window.get("Quota")
    used = window.get("Used")
    if isinstance(quota, (int, float)) and quota > 0 and isinstance(used, (int, float)):
        out[target_key + "_used_percent"] = max(0.0, min(100.0, float(used) / float(quota) * 100.0))
    reset = _iso_from_volc_ms(window.get("ResetTime"))
    if reset:
        out[target_key + "_resets_at"] = reset


def _ark_usage_limits(action, query=None, post_body=False):
    """Best-effort parser for Ark Agent Plan usage responses."""
    try:
        data = _volc_openapi(action, body_obj=(query if post_body else None))
    except Exception as exc:
        try:
            body = exc.read().decode("utf-8", "replace")
            err = ((json.loads(body).get("ResponseMetadata") or {}).get("Error") or {})
            msg = err.get("Message") or err.get("Code")
            return {"status": msg} if msg else None
        except Exception:
            return None
    if not data or (data.get("ResponseMetadata") or {}).get("Error"):
        return None
    out = {}
    result = data.get("Result") if isinstance(data, dict) else None
    if isinstance(result, dict):
        if result.get("PlanType"):
            out["tier"] = result["PlanType"]
        _add_ark_window(out, result, "AFPFiveHour", "five_hour")
        _add_ark_window(out, result, "AFPWeekly", "seven_day")
    # Heuristic walk is a FALLBACK only — never clobber the exact Quota/Used
    # percentages computed above. Fill a window solely when it's still missing.
    if "five_hour_used_percent" not in out:
        five = _find_percent(data, ("five", "5h", "hour"))
        if five is not None:
            out["five_hour_used_percent"] = five
    if "seven_day_used_percent" not in out:
        week = _find_percent(data, ("week", "weekly", "seven", "7d"))
        if week is not None:
            out["seven_day_used_percent"] = week
    return out or None


def ark_agent_limits():
    return _limits_cached("ark-agent-limits-cache.json", lambda: _ark_usage_limits("GetAFPUsage"))


def _with_plan(plan, limits):
    out = {"plan": plan}
    if limits:
        out.update(limits)
    return out


def _configured_key(path):
    """Whether a provider key exists and is non-empty, without exposing it."""
    try:
        return path.is_file() and path.stat().st_size > 0
    except OSError:
        return False


def ark_agent():
    """Volcengine Ark Agent Plan via Claude Code-compatible wrappers.

    Local wiring lives in fish functions (`claude-ark` / `arkp`) that set
    ANTHROPIC_BASE_URL to /api/plan. The plan usage APIs appear to be
    management-plane APIs, so the first UI slice only reports configured state
    and the plan label; exact quota can be added once signing is implemented.
    """
    return 0, None, None


def collect():
    """Per-harness tuples (name, sessions, tokens, last, limits|None, by_project).

    Limits: live account windows (five_hour/seven_day used_percent) — claude
    via the oauth usage endpoint, codex via app-server (or freshest session
    file fallback), minimax via the `mmx` CLI; all cached on disk with the
    same TTL.
    """
    c_sess, c_tok, c_last, c_proj, c_ctx = claude_code()
    x_sess, x_tok, x_last, x_file_limits, x_proj, x_ctx = codex()
    m_sess, m_tok, m_last = minimax()
    rows = [
        ("claude",  c_sess, c_tok, c_last, claude_limits(), c_proj, c_ctx),
        ("kiro",    *kiro(), None, {}, {}),
        ("opencode", *opencode(), None, {}, {}),
        # Scrub each source BEFORE merging: a live dict may carry a used_percent
        # with no resets_at of its own — merging first would let it inherit the
        # file source's EXPIRED resets_at and then get wrongly scrubbed. Drop
        # each source's stale windows independently, then merge what's fresh.
        ("codex",   x_sess, x_tok, x_last,
         _merge_limits(_scrub_expired(codex_limits()), _scrub_expired(x_file_limits)),
         x_proj, x_ctx),
        ("minimax", m_sess, m_tok, m_last, minimax_limits(), {}, {}),
    ]
    if _configured_key(ARK_AGENT_KEY):
        rows.append(("ark-agent", *ark_agent(), _with_plan("Agent Plan", ark_agent_limits()), {}, {}))
    return rows


def emit_json():
    rows = collect()
    out = {}
    for name, sess, tok, _last, limits, by_project, context in rows:
        # Drop windows whose reset already passed — the cached % is pre-reset
        # stale and would otherwise show a high number for a quiet provider.
        limits = _scrub_expired(limits)
        out[name] = {
            "tokens_today": tok if tok is not None else 0,
            "sessions_today": sess,
        }
        if limits:
            # Additive key — existing consumers (kaku.lua status bar) read
            # tokens_today/sessions_today only and are unaffected.
            out[name]["limits"] = limits
        if name == "codex":
            cost = codex_cost_today()
            if cost is not None:
                out[name]["cost_today_usd"] = round(cost, 4)
                out[name]["cost_is_estimated"] = True
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
        limits = _scrub_expired(limits)
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
