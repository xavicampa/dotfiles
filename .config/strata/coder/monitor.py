#!/usr/bin/env python3
"""monitor.py — the signals that bite on this box, one line per interval.

Nothing here is a fix; it is the read-out TUNING_NOTES.md § "The queue 429" says to watch:
  1. the wrapper's inference queue (pi 429s past queue_timeout 90),
  2. the conversation-cache limits (12288 MiB budget AND 10 slots — both ride their edge, so either one
     fires an eviction; § Parked-conversation counters),
  3. CUDA0 free VRAM vs the 512 MiB paging cliff (#2065),
  4. host MemAvailable vs the RAM-admission guard (min-free-mib 1536).

It also answers the question the counters alone cannot: **is the parked tier earning its RAM?** Cost =
the ms spent copying snapshots in; value = tokens brought back, priced against measured prefill speed
(~2.45k tok/s: 13819 tokens read in 5.641 s to first token).

Log counters are scoped to the CURRENT boot only, and the remote side filters with grep so the transfer
stays tiny: older boots in the same file carry 178 RAM-admission skips from a 2560 MiB floor era (§
Reading the engine log per boot).

Usage: ./monitor.py            # 30 s
       ./monitor.py 60         # 60 s
       ./monitor.py once       # one line, then exit
"""
import json, os, subprocess, sys, time

CONTAINER = "qwen3.8-flash-next-coder-iq1_m-parallel"
LOG = "/data/state/strata/launch/docker.engine.log"
URL = "http://127.0.0.1:5801/metrics"
PREFILL_TOK_S = 2450.0          # measured: 13819 tokens read, first engine token 5.641 s
PAGING_CLIFF_MIB = 512          # #2065
QUEUE_TIMEOUT_S = 90            # strata-coder-iq1_m.json: "queue_timeout"
BUDGET_MIB = 12288              # --conversation-cache-mib
SLOTS = 10                    # --conversation-cache-slots
INTENDED_KV_RES = 86016       # what the config files say; the live engine must match after a restart


def sh(cmd):
    return subprocess.run(["podman", "exec", CONTAINER, "sh", "-c", cmd],
                          capture_output=True, text=True).stdout


def boot_start():
    out = sh(f"grep -n 'engine started:' {LOG} | tail -1 | cut -d: -f1").strip()
    return out or "1"


def log_counters(start):
    """Counters for the current boot: guards (cheap greps) and the park/restore economics (filtered output).
    The sed program MUST stay single-quoted: in double quotes `$p` expands to nothing and the read comes back
    empty, which silently reads as '0 events' — that is how the notes' cache section first got written wrong."""
    sed = f"sed -n '{start},$p' {LOG}"
    guards = sh(f"{sed} | grep -c 'physical RAM admission'; "
                f"{sed} | grep -c 'superseded copy'; "
                f"{sed} | grep -cE 'LOW|paging'").split()
    events = sh(f"{sed} | grep -oE '(parked|restored) [0-9]+ tokens( \\((live|checkpoint)\\))? in [0-9.]+ ms'")
    parks = restores = 0
    park_tok = rest_tok = 0
    park_ms = rest_ms = 0.0
    for line in events.splitlines():
        kind, tok, *_ = line.split()
        ms = float(line.rsplit(" ", 2)[1])
        if kind == "parked":
            parks += 1; park_tok += int(tok); park_ms += ms
        else:
            restores += 1; rest_tok += int(tok); rest_ms += ms
    summary = sh(f"{sed} | grep -oE 'parked=[0-9]+ bytes=[0-9]+ evictions=[0-9]+ snapshot_bytes=[0-9]+' | tail -1")
    return {"ram_skip": int(guards[0]) if len(guards) > 0 else -1,
            "superseded": int(guards[1]) if len(guards) > 1 else -1,
            "paging": int(guards[2]) if len(guards) > 2 else -1,
            "parks": parks, "restores": restores, "park_ms": park_ms, "rest_ms": rest_ms,
            "park_tok": park_tok, "rest_tok": rest_tok, "last_park": summary}


def row():
    try:
        raw = subprocess.run(["curl", "-s", "--max-time", "6", URL], capture_output=True, text=True).stdout
        d = json.loads(raw)
    except Exception:
        return False
    live, cache, eng = d["live"], d["conversation_cache"], d["engine"]
    mem = int(open("/proc/meminfo").read().split("MemAvailable:")[1].split()[0]) // 1048576  # GiB
    lg = log_counters(boot_start())
    budget = cache.get("budget_mib", BUDGET_MIB)
    pct = 100 * cache["bytes"] / (budget * 1048576)
    saved = lg["rest_tok"] / PREFILL_TOK_S
    net = saved - lg["park_ms"] / 1000.0
    print("%s %-9s r%s q%s w%s | cache %d/%d slots %5d/%dMiB %5.1f%% ev%-4d park%-4d res%-4d | "
          "vram %4d MiB kv_res %6d | RAM avail %3d GiB | log ram-skip %d superseded %d paging %d" % (
              time.strftime("%H:%M"), live["state"], live["running"], live["queued"], live["waiting"],
              cache["parked"], cache.get("slots", SLOTS), cache["bytes"] // 1048576, budget, pct,
              cache["evictions"], cache["parks"], cache["restores"],
              eng["vram_free_mib"], eng["kv_resident"], mem,
              lg["ram_skip"], lg["superseded"], lg["paging"]), flush=True)
    print("     cache economics: park %d tokens in %5.1f s, restore %d tokens in %4.2f s "
          "-> %5.0f s of prefill saved, net %+5.0f s (ratio %.1f:1)" % (
              lg["park_tok"], lg["park_ms"] / 1000.0, lg["rest_tok"], lg["rest_ms"] / 1000.0, saved, net,
              saved / max(lg["park_ms"] / 1000.0, 0.01)), flush=True)
    if lg["last_park"]:
        print("     last park: %s" % lg["last_park"], flush=True)
    if live["queued"] > 0:
        print("     ^ %d calls queued behind the slots: past queue_timeout %d the WRAPPER 429s "
              "(the inference queue deadline, not an engine fault)" % (live["queued"], QUEUE_TIMEOUT_S), flush=True)
    if pct >= 95:
        print("     ^ budget at %.1f%% full (parked %d of %s slots): the BUDGET fired this time — but both limits "
              "ride their edge, so raising only one of them is a no-op (§ Parked-conversation counters)" % (
                  pct, cache["parked"], cache.get("slots", SLOTS)), flush=True)
    if eng["vram_free_mib"] < PAGING_CLIFF_MIB:
        print("     ^ CUDA0 %d MiB under the %d MiB paging cliff (#2065): step --kv-resident down (86016 -> 65536),"
              " which per § Decode throughput usually raises decode too" % (eng["vram_free_mib"], PAGING_CLIFF_MIB), flush=True)
    if eng.get("kv_resident") not in (None, INTENDED_KV_RES):
        print("     ^ live engine kv_resident %s but the config files say %s: this edit is not restarted in yet"
              " (restart-only, § Applying changes)" % (eng["kv_resident"], INTENDED_KV_RES), flush=True)
    if lg["ram_skip"] > 0:
        print("     ^ %d RAM-admission skips this boot: min-free-mib 1536 is flushing snapshots "
              "— cut --conversation-cache-mib (12288 -> 8192)" % lg["ram_skip"], flush=True)
    return True


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "30"
    if arg == "once":
        sys.exit(0 if row() else 1)
    step = int(arg)
    print("   time  state running queued waiting | cache parked/slots MiB(of budget %) evictions parks restores | "
          "vram kv_res | RAM avail | log guards")
    while True:
        if not row():
            print("(no /metrics — is the engine restarting?)", flush=True)
        time.sleep(step)
