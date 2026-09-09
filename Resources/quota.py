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


def _claude_project_roots():
    """Every directory Claude Code may write session JSONL into.

    Claude Code honours CODEX-style config relocation via CLAUDE_CONFIG_DIR
    (comma-separated, as ccusage supports), and older/XDG installs use
    ~/.config/claude. Reading only ~/.claude/projects silently reports 0 tokens
    for anyone with a relocated config dir.
    """
    roots, seen = [], set()

    def add(base):
        p = (Path(base).expanduser() / "projects").resolve()
        key = str(p)
        if key in seen:
            return
        seen.add(key)
        if p.is_dir():
            roots.append(p)

    override = os.environ.get("HELM_CLAUDE_PROJECTS")
    if override:
        for part in override.split(","):
            if part.strip():
                p = Path(part.strip()).expanduser().resolve()
                if str(p) not in seen:
                    seen.add(str(p))
                    if p.is_dir():
                        roots.append(p)
        return roots

    cfg = os.environ.get("CLAUDE_CONFIG_DIR")
    if cfg:
        for part in cfg.split(","):
            if part.strip():
                add(part.strip())
    add(HOME / ".claude")
    add(HOME / ".config" / "claude")
    return roots
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
# LOCAL midnight, not UTC. "Today" must mean the user's day: at UTC+8 a UTC
# boundary starts today at 08:00 local and silently discards the whole morning
# (and at UTC-5 it counts part of yesterday evening). ccusage buckets by local
# date for the same reason.
TODAY_START = datetime.now().astimezone().replace(
    hour=0, minute=0, second=0, microsecond=0).timestamp()


def _int(value):
    """A token count as int. Missing/None/garbage -> 0 (bool is not a count)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value)


def ago(ts: float) -> str:
    d = NOW - ts
    if d < 60: return f"{int(d)}s ago"
    if d < 3600: return f"{int(d/60)}m ago"
    if d < 86400: return f"{int(d/3600)}h ago"
    return f"{int(d/86400)}d ago"


# ── live account limits (claude oauth endpoint / codex app-server) ──────────
# Both report SERVER-side window utilization: five_hour + seven_day, 0-100.
# Cached on disk to avoid polling provider endpoints on every 30-second UI
# refresh. Fetch failures serve stale data; HTTP Retry-After is persisted so
# app restarts do not keep a rate-limited OAuth token in a retry loop.
CACHE_DIR = HOME / ".helm" / "sessions"
LIMITS_TTL = 180
CLAUDE_LIMITS_TTL = 3600


def _cache_is_current(data):
    """A cached snapshot is only valid until its own windows reset. Claude's
    TTL is an hour but its 5-hour window can reset inside that hour; serving
    the cached payload then means `_scrub_expired` drops the percentage and the
    provider reports nothing until the TTL lapses. Treat a passed reset as a
    cache miss so the next poll refetches."""
    if not isinstance(data, dict):
        return False
    for win in ("five_hour", "seven_day"):
        reset = _reset_epoch(data.get(win + "_resets_at"))
        if reset is not None and reset <= time.time():
            return False
    return True


def _limits_cached(name, fetch, ttl=LIMITS_TTL):
    path = CACHE_DIR / name
    retry_path = path.with_name(path.name + ".retry-at")
    try:
        if time.time() - path.stat().st_mtime < ttl:
            cached = json.loads(path.read_text())
            if _cache_is_current(cached):
                return cached
    except Exception:
        pass
    retry_at = 0
    try:
        retry_at = float(retry_path.read_text())
    except Exception:
        pass
    data = None
    if not os.environ.get("HELM_QUOTA_OFFLINE") and time.time() >= retry_at:
        try:
            data = fetch()
            retry_path.unlink(missing_ok=True)
        except Exception as exc:
            retry_after = None
            try:
                retry_after = float(exc.headers.get("Retry-After"))
            except Exception:
                pass
            if retry_after is not None:
                try:
                    CACHE_DIR.mkdir(parents=True, exist_ok=True)
                    retry_path.write_text(str(time.time() + max(retry_after, ttl)))
                except Exception:
                    pass
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


def _usable_claude_token(credentials):
    """Return an unexpired access token from a Claude credential object."""
    try:
        oauth = credentials["claudeAiOauth"]
        expires_at = float(oauth.get("expiresAt") or 0) / 1000.0
        if expires_at <= time.time() + 60:
            return None
        return oauth.get("accessToken") or None
    except Exception:
        return None


def _claude_oauth_token():
    """Prefer the first unexpired credential; legacy files can linger for months."""
    try:
        d = json.loads((HOME / ".claude" / ".credentials.json").read_text())
        token = _usable_claude_token(d)
        if token:
            return token
    except Exception:
        pass
    try:
        pr = subprocess.run(
            ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
            capture_output=True, text=True, timeout=5)
        if pr.returncode == 0 and pr.stdout.strip():
            return _usable_claude_token(json.loads(pr.stdout))
    except Exception:
        pass
    return None


def _claude_user_agent():
    """Match the installed Claude Code version; stale versions are rate-limited."""
    candidates = [
        HOME / ".local" / "bin" / "claude",
        HOME / ".claude" / "local" / "claude",
        Path("/opt/homebrew/bin/claude"),
        Path("/usr/local/bin/claude"),
    ]
    for executable in candidates:
        if not executable.is_file():
            continue
        try:
            pr = subprocess.run(
                [str(executable), "--version"],
                capture_output=True, text=True, timeout=5)
            version = pr.stdout.strip().split()[0]
            if pr.returncode == 0 and version:
                return "claude-code/" + version
        except Exception:
            pass
    return "claude-code/2.1.241"


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
            # Anthropic rate-limits stale or missing claude-code user agents.
            "User-Agent": _claude_user_agent(),
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
    return _limits_cached(
        "claude-limits-cache.json",
        _fetch_claude_limits,
        ttl=CLAUDE_LIMITS_TTL,
    )


# ── Cursor account period usage (unofficial DashboardService) ───────────────
# No local 5h/7d files. Token from Cursor's state.vscdb; percentages are a
# monthly billing pool (api / auto), mapped onto Kaji's five_hour / seven_day
# slots: outer=API, inner=Auto. Spec: 2026-07-24-cursor-quota.md.


def _cursor_token():
    """Read cursorAuth/accessToken from Cursor's globalStorage sqlite DB."""
    path = (HOME / "Library" / "Application Support" / "Cursor"
            / "User" / "globalStorage" / "state.vscdb")
    if not path.is_file():
        return None
    try:
        import sqlite3
        conn = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=2)
        try:
            row = conn.execute(
                "SELECT value FROM ItemTable WHERE key = ?",
                ("cursorAuth/accessToken",),
            ).fetchone()
        finally:
            conn.close()
        if row and row[0]:
            return str(row[0])
    except Exception:
        return None
    return None


def _clamp_pct(value):
    try:
        x = float(value)
    except (TypeError, ValueError):
        return None
    if x != x:  # NaN
        return None
    return max(0.0, min(100.0, x))


def _ms_to_iso(ms):
    """Cursor billingCycleEnd is epoch milliseconds (number or digit string) → ISO-8601 UTC."""
    if isinstance(ms, str):
        ms = ms.strip()
        if not ms:
            return None
    try:
        ms = float(ms)
    except (TypeError, ValueError):
        return None
    if ms <= 0:
        return None
    from datetime import datetime, timezone
    dt = datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(dt.microsecond / 1000):03d}Z"


def _map_cursor_payload(d):
    """Outer five_hour←apiPercentUsed; inner seven_day←autoPercentUsed.

    Observed shapes:
    - flat: apiPercentUsed / autoPercentUsed on the root
    - nested (2026-07): planUsage.{api,auto}PercentUsed; billingCycleEnd as string ms
    """
    if not isinstance(d, dict):
        return None
    plan = d.get("planUsage") if isinstance(d.get("planUsage"), dict) else {}
    out = {}
    reset = _ms_to_iso(d.get("billingCycleEnd"))
    api = _clamp_pct(plan.get("apiPercentUsed", d.get("apiPercentUsed")))
    auto = _clamp_pct(plan.get("autoPercentUsed", d.get("autoPercentUsed")))
    if api is not None:
        out["five_hour_used_percent"] = api
        if reset:
            out["five_hour_resets_at"] = reset
    if auto is not None:
        out["seven_day_used_percent"] = auto
        if reset:
            out["seven_day_resets_at"] = reset
    return out or None


def _fetch_cursor_limits():
    token = _cursor_token()
    if not token:
        return None
    import urllib.request
    req = urllib.request.Request(
        "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
        data=b"{}",
        method="POST",
        headers={
            "Authorization": "Bearer " + token,
            "Connect-Protocol-Version": "1",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        d = json.loads(r.read().decode("utf-8"))
    return _map_cursor_payload(d)


def cursor_limits():
    return _limits_cached("cursor-limits-cache.json", _fetch_cursor_limits)


def _codex_map_rate_limits(rl, pct_key, reset_key, window_key, plan_key):
    """A codex rateLimits object -> Kaji's {five_hour,seven_day} limits dict.

    Mapped by WINDOW LENGTH, never by the `primary`/`secondary` slot name.
    Codex reuses `primary` for whichever window is currently authoritative: on
    a plan with only a weekly cap, `primary.window_minutes == 10080` and
    `secondary` is null. Trusting the slot name paints a 7-day figure onto the
    5-hour ring — that is the "codex ring is wrong" bug. ≤ 24h counts as the
    5-hour window, anything longer as the 7-day window.
    """
    if not isinstance(rl, dict):
        return None
    out = {}
    for slot in ("primary", "secondary"):
        w = rl.get(slot)
        if not isinstance(w, dict) or w.get(pct_key) is None:
            continue
        mins = w.get(window_key)
        if isinstance(mins, (int, float)) and not isinstance(mins, bool):
            key = "five_hour" if mins <= 1440 else "seven_day"
        else:
            # No window length: fall back to the slot's conventional meaning.
            key = "five_hour" if slot == "primary" else "seven_day"
        # First writer wins so a genuine 5h window is not overwritten by a
        # second short window reported in the other slot.
        if key + "_used_percent" in out:
            continue
        out[key + "_used_percent"] = w[pct_key]
        if w.get(reset_key) is not None:
            out[key + "_resets_at"] = w[reset_key]
    if rl.get(plan_key):
        out["plan"] = rl[plan_key]
    # A dict carrying only a plan label is not a usable limits reading.
    if not any(k.endswith("_used_percent") for k in out):
        return None
    return out


def _fetch_codex_limits():
    """codex app-server JSON-RPC account/rateLimits/read (official path)."""
    import queue as _queue
    import threading
    # `-a untrusted` was REMOVED from codex's approval policy enum (0.153.x
    # accepts only on-request|never); passing it makes the CLI exit before
    # serving any JSON-RPC, so the live path silently never worked and every
    # reading came from the stale session-file fallback. `never` is the
    # non-interactive choice, paired with read-only sandboxing.
    proc = subprocess.Popen(
        ["codex", "-s", "read-only", "-a", "never", "app-server"],
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
                return _codex_map_rate_limits(
                    rl, "usedPercent", "resetsAt", "windowDurationMins", "planType")
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

    Counting rules (aligned with ccusage):
      * tokens = input + output + cache_creation + cache_read. Cache reads are
        ~99% of real traffic; input+output alone tracks almost nothing.
      * every usage record is de-duplicated on (message.id, requestId). Resumed,
        branched and compacted sessions REWRITE earlier turns into new files, so
        a naive sum counts the same API call several times.
      * `model == "<synthetic>"` rows are local error placeholders, not billed.
      * subagent/sidechain files are real billed usage and must be included.
    """
    roots = _claude_project_roots()
    if not roots:
        return 0, 0, None, {}, {}
    tokens_today, last = 0, None
    session_ids_today = set()
    by_project = {}
    context = {}        # proj -> {"used": n, "window": w, "ts": newest-seen}
    seen_usage = set()  # (message.id, requestId) across ALL files
    for base in roots:
      for jsonl in base.rglob("*.jsonl"):
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
                        msg = d.get("message") if isinstance(d.get("message"), dict) else None
                        usage = msg.get("usage") if msg else None
                        if not isinstance(usage, dict) or not usage:
                            continue
                        if msg.get("model") == "<synthetic>":
                            continue
                        used = (_int(usage.get("input_tokens"))
                                + _int(usage.get("cache_read_input_tokens"))
                                + _int(usage.get("cache_creation_input_tokens")))
                        # Context is a point-in-time snapshot of the newest
                        # prompt, so it is read BEFORE the dedup gate (a
                        # duplicated record still describes the real context).
                        cur = context.get(proj)
                        if used and (cur is None or ts > cur["ts"]):
                            model = msg.get("model") or ""
                            window = 1_000_000 if ("[1m]" in model or "fable" in model) else 200_000
                            if used > window:
                                window = 1_000_000
                            context[proj] = {"used": used, "window": window, "ts": ts}
                        key = (msg.get("id"), d.get("requestId"))
                        if key[0] and key[1]:
                            if key in seen_usage:
                                continue
                            seen_usage.add(key)
                        n = used + _int(usage.get("output_tokens"))
                        tokens_today += n
                        by_project[proj] = by_project.get(proj, 0) + n
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


def _codex_scan_rollout(path):
    """Scan one rollout file: (info, rate_limits, cwd, tokens_today).

    `info`/`rate_limits` are the LAST seen (freshest snapshot in this session).

    `tokens_today` needs care. A token_count event carries a session-CUMULATIVE
    `total_token_usage` plus the per-turn `last_token_usage`. Summing the final
    cumulative value attributes a session's ENTIRE lifetime to today — a
    long-lived session started three weeks ago (10.6M tokens here) lands wholly
    in today's total. So we sum `last_token_usage` over events TIMESTAMPED today
    instead, skipping events whose cumulative snapshot is byte-identical to the
    previous one (the TUI re-emits the same token_count on redraw//status, which
    would otherwise double-count the last turn).
    """
    info, rl, cwd = None, None, None
    tokens_today = 0
    prev_total = None
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
                cur = payload.get("info")
                rl = payload.get("rate_limits") or rl
                if not isinstance(cur, dict):
                    continue
                info = cur
                total = cur.get("total_token_usage")
                if total == prev_total:
                    continue
                prev_total = total
                ts = _reset_epoch(rec.get("timestamp"))
                if ts is None or ts < TODAY_START:
                    continue
                last = cur.get("last_token_usage") or {}
                tokens_today += _int(last.get("total_tokens"))
    except OSError:
        pass
    return info, rl, cwd, tokens_today


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

    tokens: per-turn `last_token_usage` summed over events timestamped today
    (see _codex_scan_rollout) across sessions touched in the last 24h.
    limits: from the freshest session overall (account-level, not today-bound):
    {five_hour_*, seven_day_*, plan?} — mapped by WINDOW LENGTH, not by the
    primary/secondary slot name.
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
        info, _, cwd, n = _codex_scan_rollout(p)
        try:
            m = p.stat().st_mtime
        except OSError:
            m = 0
        if n:
            tokens_today += n
            if cwd:
                by_project[cwd] = by_project.get(cwd, 0) + n
        if info and cwd:
            lt = info.get("last_token_usage") or {}
            used = _int(lt.get("input_tokens")) + _int(lt.get("cached_input_tokens"))
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
        _, rl, _, _ = _codex_scan_rollout(p)
        if not rl:
            continue
        limits = _codex_map_rate_limits(rl, "used_percent", "resets_at",
                                        "window_minutes", "plan_type")
        break

    return len(files_recent), (tokens_today or None), last, limits, by_project, context




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
    file fallback), cursor via DashboardService period usage, minimax via the
    `mmx` CLI; all cached on disk with the same TTL.
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
    # Cursor is limits-only (no local today-token scan). Emit only when we have
    # a usable limits dict (live or cached). tokens/sessions stay unset in JSON.
    c_lim = cursor_limits()
    if c_lim:
        rows.append(("cursor", None, None, None, c_lim, {}, {}))
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
        if name == "cursor":
            # Spec §5.6: limits-only — omit tokens_today / sessions_today so the
            # app does not treat missing usage as zero.
            out[name] = {}
            if limits:
                out[name]["limits"] = limits
            continue
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
        limits = _scrub_expired(limits)
        extra = ""
        if limits:
            fh = limits.get("five_hour_used_percent")
            sd = limits.get("seven_day_used_percent")
            bits = []
            if fh is not None:
                label5 = "API" if name == "cursor" else "5h"
                bits.append(f"{label5} {fh:.0f}%")
            if sd is not None:
                label7 = "Auto" if name == "cursor" else "wk"
                bits.append(f"{label7} {sd:.0f}%")
            if bits:
                extra = "  used " + " · ".join(bits) + (f" ({limits['plan']})" if limits.get("plan") else "")
        sess_s = "—" if sess is None else str(sess)
        tok_s = "—" if tok is None else fmt_tokens(tok)
        print(f"{label.get(name, name):<14} {sess_s:<16} {tok_s:<13} {fmt_last(last)}{extra}")
    print()
    print("Note: claude-code tokens = input+output+cache from message.usage, de-duplicated")
    print("            on (message.id, requestId), local day only.")
    print("      opencode tokens summed from storage/message/*.json (today).")
    print("      codex tokens = per-turn last_token_usage over today's token_count events;")
    print("            quota %% from app-server, mapped by window length.")
    print("      cursor limits from DashboardService period usage (API/Auto); no today tokens.")
    print("      kiro session files store no token counts (sessions only).")


def main():
    if "--json" in sys.argv[1:]:
        emit_json()
    else:
        emit_table()


if __name__ == "__main__":
    main()
