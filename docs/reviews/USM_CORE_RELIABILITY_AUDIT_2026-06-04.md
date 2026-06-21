# USM Core Reliability Audit and Hand-off

**Date:** 2026-06-04
**Component:** `server/usm-core` (the "Una Server Manager", Rust)
**Scope:** Process-supervision reliability of usm-core and the local service fleet it manages.
**Method:** Live inspection of the running system on the host machine, plus source review of `crates/usm-core` at the current checkout. No code or system configuration was changed.
**Audience:** The server project team. This report is self-contained and assumes no knowledge of the iOS client.

---

## 1. Executive summary

usm-core and the fleet it manages were **up and healthy** at the time of inspection. The manager process had been running continuously for ~1 day 15 hours, was responding on its API, and had successfully started the core services (management-api on 8766, web-client on 3001) alongside ollama and piper-tts.

However, the audit found one architectural gap and several hygiene issues that undermine the "enterprise-grade, crash-proof, self-healing" goal:

1. **No crash-supervision of managed services (primary finding).** usm-core starts `auto_start` instances once at load and exposes a manual `/restart` endpoint, but it runs **no background watchdog** that detects a crashed managed service and respawns it. The only process kept alive automatically is the manager itself, via the launchd `KeepAlive` on its LaunchAgent. If a managed service (for example the management-api or ollama) crashes, it stays down until a human or an external caller restarts it.
2. **Stale-PID handling produces error noise and proves silent crashes happen.** `usm-core-error.log` contains repeated `kill: <pid>: No such process`. The stop path shells out `kill {pid}` against PIDs that have already exited, which is direct evidence that managed processes do exit unattended and the manager only notices later, when it tries to stop an already-dead PID.
3. **A perpetually-failing leftover LaunchAgent** (`com.voicelearn.logserver`) points at a script path that no longer exists after a repo rename, and loops forever under `KeepAlive`.
4. **Error-log pollution:** unrelated Homebrew output is landing in `usm-core-error.log`, mixed with shell `kill` stderr, which makes the error log hard to trust as a signal.

The good news: the building blocks for self-healing and self-reporting already exist (a process-monitor backend, an event bus, a `/ws` event stream, and a `/api/metrics` endpoint). What is missing is the supervision loop that ties them together. Section 5 proposes that design.

---

## 2. Observed state (evidence)

Collected on 2026-06-04 from the running system.

### 2.1 Manager process

```
launchctl: com.unamentis.usm-core  -> PID 2292, last exit 0
ps:        /Users/.../server/usm-core/target/release/usm server --port 8787   (ELAPSED 01-15:44:56)
GET http://localhost:8787/api/health -> 200 {"service":"USM Core","status":"ok","version":"0.1.0"}
```

LaunchAgent `~/Library/LaunchAgents/com.unamentis.usm-core.plist`: `RunAtLoad=true`, `KeepAlive=true`, logs to `~/Library/Logs/usm-core.log` and `usm-core-error.log`.

### 2.2 Fleet, per the manager's own `/api/instances`

| Instance | Port | Status | auto_start |
|---|---|---|---|
| management-api-primary | 8766 | running (pid 20524) | true |
| web-client | 3001 | running (pid 3785) | false |
| web-server-primary | 3000 | stopped | false |
| postgresql | 5432 | stopped | false |

Independently confirmed listening: ollama on 11434, piper-tts on 11402, usm-core on 8787, management-api on 8766 (`/health` → 200, all other routes require `Authorization: Bearer`, realm `unamentis`), web dashboard on 3001 (→ 200). ollama reports models `llama3.2:3b`, `qwen2.5:32b`, `mistral:7b`, `ministral-3:14b`.

The startup config is `config/services.toml` (6 templates, 6 instances).

---

## 3. Architecture as built (relevant pieces)

`crates/usm-core/src`:

- `server/mod.rs` exposes the HTTP API: `/api/health`, `/api/templates` (+ `:id`, POST), `/api/instances` (+ `:id`, POST), `/api/instances/:id/{start,stop,restart}`, `/api/metrics`, and `/ws`.
- `monitor/` is a platform process-monitor backend (`macos.rs`, `linux.rs`): port discovery (`lsof`/`ss`), process metrics, `start_process_with_port`, `kill_process`, `execute_command`. It is an on-demand backend, not a supervisor.
- `events/` provides an event bus; `/ws` (`server/mod.rs:629`) forwards bus events to subscribers and handles ping/pong. This is the only long-lived loop in the server.
- `service/` holds `instance.rs`, `registry.rs`, `template.rs`. Templates may define `stop_command` (default `"kill {pid}"`, `template.rs:145`).
- `lib.rs` is the orchestrator: at startup it creates the monitor and starts `auto_start` instances once (`auto_start_instances()` filtered in `registry.rs:188`, started around `lib.rs:342`). `restart_instance` (`lib.rs:302`) is a stop-then-start and is only invoked via the HTTP route.

What is absent: there is no `tokio::spawn` of a periodic supervision/reconcile task anywhere in the crate. `auto_start` governs start-at-load only; restart is manual.

---

## 4. Findings

### F1. No crash-supervision of managed services (High)

**What:** Nothing detects that a managed service died and brings it back. `auto_start` runs once at load; `/restart` is manual. Only the manager process is auto-restarted, by launchd `KeepAlive`.

**Impact:** This is the most likely cause of "it was running before and now it is not": launchd quietly restarts the *manager*, but the *fleet it manages* is not supervised, so any crashed service stays down silently. For a component that is meant to own all server infrastructure, this is the core reliability gap.

**Evidence:** No background loop in the crate other than the `/ws` forwarder (`server/mod.rs:629`); restart is reachable only through `restart_instance` via the HTTP route.

### F2. Stale-PID handling and error-log noise (Medium)

**What:** The stop path shells `kill {pid}` (`template.rs:145`, `monitor/macos.rs:223`) without first checking liveness, and the error log shows repeated `kill: <pid>: No such process`.

**Impact:** Two problems. First, it is concrete proof that services exit unattended (F1). Second, the manager can hold a stale `pid` while reporting an instance as `running`, so `/api/instances` can misrepresent reality until a stop/restart is attempted.

**Evidence (`~/Library/Logs/usm-core-error.log`):**
```
kill: 51328: No such process
kill: 98193: No such process
kill: 86547: No such process
...
```

### F3. Stale, perpetually-failing LaunchAgent `com.voicelearn.logserver` (Medium)

**What:** `~/Library/LaunchAgents/com.voicelearn.logserver.plist` runs `python3 /Users/ramerman/dev/voicelearn-ios/scripts/log_server.py`. That path no longer exists (the repo was renamed from `voicelearn-ios`). With `KeepAlive=true`, launchd retries forever and the job sits at `launchctl` last-exit status `78` (`EX_CONFIG`).

**Impact:** A permanently-failing daemon, ongoing wasted relaunch attempts, and confusing status. Note this LaunchAgent is **not** a usm-core component; it is a system-level leftover, but it is part of the same reliability picture. The `com.voicelearn.ollama` and `com.voicelearn.piper-tts` agents still point at valid binaries and run, but carry the old `com.voicelearn.*` label.

**Evidence:** `ls /Users/ramerman/dev/voicelearn-ios/scripts/log_server.py` → `No such file or directory`; `launchctl list` shows `-	78	com.voicelearn.logserver`.

### F4. Foreign output polluting the error log (Low)

**What:** `usm-core-error.log` contains Homebrew output, for example `✔︎ JSON API formula.jws.json`, interleaved with the `kill` stderr.

**Impact:** Some managed command or template shells out (and something triggered `brew`), and that subprocess stderr is not separated from usm-core's own logging, which devalues the error log as a monitoring signal.

---

## 5. Recommended remediation

### 5.1 Add a supervision loop (addresses F1, the priority)

Spawn one background task at startup (`tokio::spawn` in `lib.rs` after `auto_start_instances`) that runs on a short interval (2 to 5 seconds) and, for each instance the registry believes is `running`:

1. **Check liveness.** Confirm the PID is still alive (signal 0 / process-exists check through the monitor backend). Optionally add a per-instance health probe (TCP connect or HTTP `/health` on the instance port) for "running but wedged" cases.
2. **On unexpected exit, capture diagnostics:** exit status or terminating signal if obtainable, the last N lines of the instance's stdout/stderr, the timestamp, the uptime, and the running restart count.
3. **Emit a structured event** on the existing event bus so `/ws` subscribers and `/api/metrics` observe the crash and its captured reason. This is the "figure out what happened and report it on its own" behavior.
4. **Apply a restart policy** per template/instance: `never | on-failure | always`, with exponential backoff and a crash-loop breaker (for example, more than 5 restarts in 60 seconds marks the instance `failed`, stops retrying, and raises a louder alert rather than thrashing).
5. **Record** restart counts and last-crash reason into metrics.

Add a `restart_policy` (and optional `health_check`) field to the template/instance schema in `services.toml`, defaulting to `on-failure` for core services.

### 5.2 Fix PID lifecycle (addresses F2)

- Before issuing a stop/kill, verify the process is alive; treat "no such process" as already-stopped (success), not an error.
- Reap and clear the stored PID when an instance exits, and reconcile `status` so `/api/instances` never reports `running` for a dead PID.

### 5.3 Operational hygiene (addresses F3, F4)

- Remove or repoint the stale `com.voicelearn.logserver` LaunchAgent, and audit the remaining `com.voicelearn.*` agents (`ollama`, `piper-tts`) for renaming to `com.unamentis.*` for consistency after the repo rename.
- Separate subprocess stderr from usm-core's own structured logging, and keep Homebrew (and any other shell-out) output out of `usm-core-error.log`.

### 5.4 Optional, for true "enterprise" posture

- An external alerting hook (webhook or similar) fired on `failed` / crash-loop, so an unattended host can report outward.
- A self-health endpoint that summarizes per-instance restart counts, last-crash reasons, and crash-loop state, for dashboards and for the manager to report on itself.

---

## 6. Priority and effort

| Item | Severity | Effort | Note |
|---|---|---|---|
| F1 supervision loop (5.1) | High | Medium (Rust feature: build + test) | The real fix for crash-proofing |
| F2 PID lifecycle (5.2) | Medium | Small | Pairs naturally with F1 |
| F3 stale LaunchAgent (5.3) | Medium | Trivial | System config, not usm-core code |
| F4 log separation (5.3) | Low | Small | Improves signal quality |

No regression risk was introduced by this audit; nothing was changed. The fleet was healthy at inspection time, so this work can be scheduled rather than treated as an active outage.

---

## Appendix A. Related infrastructure finding: ollama is running CPU-only (High)

This surfaced during the same session while validating an end-to-end inference round trip against the local stack. It is not a usm-core defect, but it is a server-infrastructure reliability issue that makes local inference effectively unusable, so it is recorded here for the same team.

**Symptom:** A real completion request to ollama (`llama3.2:3b`, OpenAI-compatible `v1/chat/completions`) is correct but pathologically slow: ~88 seconds for a 7-token answer, roughly 5 to 6 seconds per token. A client with a normal request timeout (60s) gets no first token before timing out.

**Root cause:** The model is loaded with zero GPU offload despite an available GPU.

Evidence from `~/Library/Logs/voicelearn-ollama.error.log`:
```
llama_model_load_from_file_impl: using device Metal (Apple M4 Max) (unknown id) - 110100 MiB free
load_tensors: offloading 0 repeating layers to GPU
load_tensors: offloaded 0/29 layers to GPU
... load request="{... GPULayers:[] ... MainGPU:0 ...}"
```
`ollama ps` confirms: `llama3.2:3b ... 100% CPU`. Metal initializes fine and 110 GB of GPU memory is free, yet 0 of 29 layers are offloaded, so inference runs entirely on CPU (roughly 100x slower than Metal).

**Prime suspect:** The ollama LaunchAgent `~/Library/LaunchAgents/com.voicelearn.ollama.plist` sets `ProcessType=Background`. Background QoS throttles scheduling and is a known cause of degraded or denied GPU usage for launchd-managed processes. (There is no `OLLAMA_NUM_GPU=0` or CPU-forcing env var in the agent, so the throttling context is the most likely cause.)

**Recommended fix:**
1. Change `ProcessType` from `Background` to `Standard` (or `Interactive`) in the ollama LaunchAgent and reload it.
2. Confirm `ollama ps` then shows `100% GPU` and that `offloaded N/29 layers to GPU` is non-zero in the server log.
3. Verify no `num_gpu: 0` override exists in the model params or in the request path.
4. As with F3, this agent still carries the legacy `com.voicelearn.*` label; consider renaming to `com.unamentis.*`.

Until this is fixed, any real-time client path (the 500ms-class latency targets) cannot be met by the local inference backend, regardless of usm-core.

### Resolution (2026-06-05)

Fixed. The ollama LaunchAgent (`~/Library/LaunchAgents/com.voicelearn.ollama.plist`) was changed from `ProcessType=Background` to `Standard`, and three environment variables were added to keep the model resident and fast: `OLLAMA_KEEP_ALIVE=24h`, `OLLAMA_FLASH_ATTENTION=1`, and `OLLAMA_MAX_LOADED_MODELS=1`. After reloading the agent (`launchctl bootout` then `bootstrap`), the server log shows `GPULayers:29[...] FlashAttention:Enabled` and `offloaded 29/29 layers to GPU`, and `ollama ps` reports the loaded model at `100% GPU` with `UNTIL: 24 hours from now`. No `OLLAMA_NUM_GPU=0` or `num_gpu: 0` override exists anywhere in the agent, the model params, or the request path.

The served real-time default is now **`qwen2.5:14b-instruct`** (Q4_K_M), with **`qwen2.5:7b-instruct`** as the faster fallback. Both run fully on the Metal GPU. Candidates were benchmarked warm on this M4 Max (median of multiple runs, all `100% GPU`):

| Model | Warm TTFT | Throughput | Resident |
|---|---|---|---|
| qwen2.5:14b-instruct (chosen) | ~64-74 ms | ~50 tok/s | 9.7 GB |
| qwen2.5:7b-instruct (fallback) | ~54 ms | ~95 tok/s | 4.9 GB |
| ministral-3:14b | ~76 ms | ~53 tok/s | 10 GB |
| mistral:7b | ~19 ms | ~92 tok/s | 5.1 GB |
| llama3.2:3b (old default) | ~64 ms | ~171 tok/s | 2.8 GB |

The 14B clears the real-time bar with wide margin (warm TTFT well under 300 ms, throughput well above 30 tok/s), so it was preferred for its stronger instruction-following on tutoring dialogue. The model is kept warm via `OLLAMA_KEEP_ALIVE=24h` rather than a startup pre-warm, which preserves the idle manager's deliberate "shed the LLM on deep idle" behavior (the TTS-primary resource policy). For comparison, the pre-fix figure was roughly 5 to 6 seconds per token on CPU, so this is about a 100x throughput improvement.

The chosen model name was wired consistently across the stack: `server/management/data/model_config.json` (and the code default in `server/management/server.py`), the ollama template env in `server/usm-core/config/services.toml`, the web client default in `server/web/src/lib/api-client.ts`, and the self-hosted entry in the latency harness (`server/latency_harness/models.py`). Two items are intentionally left as-is and out of scope: the importer/enrichment path still defaults to `qwen2.5:32b` (an offline batch path where latency does not matter and the larger model gives better enrichment), and the iOS client still defaults its `llmModel` UserDefault to `llama3.2:3b` (separate repo; it should be updated to `qwen2.5:14b-instruct` to match). The legacy `com.voicelearn.ollama` agent label was left unchanged; renaming it to `com.unamentis.*` remains an optional hygiene item (F3).

