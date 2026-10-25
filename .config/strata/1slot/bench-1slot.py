#!/usr/bin/env python3
"""A/B benchmark for the 1slot install (qwen3.8-flash-next-iq3_s, port 5801).

Same requests in both arms (arena vs resident-experts + kv-resident), greedy:

  A  ~24K  ctx, 1200 tokens decode     (below --kv-resident 32768: control stage)
  B  ~72K  ctx, 1200 tokens decode     (above 32768 cells: KV streaming bites)
  C  ~150K ctx, 1200 tokens decode     (deep context)
  D  fresh ~60K cold prompt read, 1 token generated (prompt path / page cache)

Speed numbers are read from the engine's own accounting lines, so they are
directly comparable with the numbers in the engine log.

  python3 bench-1slot.py [ROUNDS]      # default 2 rounds per arm
"""
import json
import os
import re
import statistics
import subprocess
import sys
import threading
import time
import urllib.request

URL = "http://127.0.0.1:5801/v1/chat/completions"
LOG = ("/home/javi/.local/share/containers/storage/volumes/strata-data/_data/"
       "state/strata/launch/docker.engine.log")
MODEL = "qwen3.8-flash-next-iq3_s"
SRC = os.path.expanduser("~/dev/personal/Strata/docs")
GEN = 1200
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
TARGETS = {"A": 24000, "B": 72000, "C": 150000}
COLD_TARGET = 60000

CORPUS = ""
for _name in sorted(os.listdir(SRC)):
    if _name.endswith(".md"):
        CORPUS += open(os.path.join(SRC, _name), errors="replace").read() + "\n\n"
if len(CORPUS) < 20_000_000:
    CORPUS += "zqxv jkqm 0042 lorem ipsum tact delta omega. " * 400_000


def chunk(i, n=4000):
    return CORPUS[(i * n) % len(CORPUS):((i * n) % len(CORPUS)) + n] or CORPUS[:n]


def chat(messages, max_tokens):
    body = {"model": MODEL, "max_tokens": max_tokens, "temperature": 0,
            "messages": messages}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        d = json.load(urllib.request.urlopen(req, timeout=2400))
    except urllib.error.HTTPError as e:
        print("    HTTP", e.code, e.read()[:300])
        return None, time.time() - t0, ""
    el = time.time() - t0
    if not d.get("choices"):
        return None, el, ""
    return d["usage"], el, d["choices"][0]["message"]["content"]


def engine_argv():
    return subprocess.run(
        ["bash", "-c", "pid=$(pgrep -f 'components/engine/.*--serve' | head -1); "
         "tr '\\0' '\\n' < /proc/$pid/cmdline"], capture_output=True, text=True).stdout.split()


def show_state(argv):
    def val(f):
        return argv[argv.index(f) + 1] if f in argv and argv.index(f) + 1 < len(argv) else None
    print("engine arm: resident-experts=%s  kv-resident=%s  adapt-async=%s  "
          "adapt-every=%s  max-context=%s" % (
              "ON" if "--resident-experts" in argv else "off",
              val("--kv-resident") or "off",
              "ON" if "--adapt-async" in argv else "off",
              val("--adapt-every") or "(default)",
              val("--max-context")))


def mem_sample(stop, rec):
    while not stop.is_set():
        mi = {}
        for line in open("/proc/meminfo"):
            k, v = line.split(":", 1)
            mi[k] = int(v.split()[0])
        rss = subprocess.run(
            ["bash", "-c", "a=0; for p in $(pgrep -f 'components/engine'); do "
             "r=$(sed -n 's/^VmRSS:[[:space:]]*\\([0-9]*\\).*/\\1/p' /proc/$p/status 2>/dev/null); "
             "a=$((a + ${r:-0})); done; echo $a"], capture_output=True, text=True).stdout
        rec.append((mi.get("MemAvailable", 0), mi.get("SwapTotal", 0) - mi.get("SwapFree", 0),
                    int(rss or 0)))
        time.sleep(2.0)


def build(target, ratio, n0=0):
    """conversation of about `target` real tokens, deterministic"""
    msgs = [{"role": "system", "content": "You are a careful assistant. Answer in plain prose."}]
    chars = len(msgs[0]["content"])
    i = n0
    while chars / ratio < target:
        msgs.append({"role": "user", "content": chunk(i)})
        msgs.append({"role": "assistant", "content": "Noted. Standing by for the next excerpt."})
        chars += 4000
        i += 1
    return msgs, i


def main():
    show_state(engine_argv())
    log_start = sum(1 for _ in open(LOG, errors="replace"))
    stop, mem = threading.Event(), []
    th = threading.Thread(target=mem_sample, args=(stop, mem))
    th.start()

    # calibrate chars -> tokens once (and warm the engine)
    warm, _, _ = chat([{"role": "user", "content": "".join(chunk(i) for i in range(6))}], 1)
    ratio = warm["prompt_tokens"] / 24000.0 if warm else 0.28
    print(f"tokenizer calibration: {ratio:.3f} tokens/char "
          f"({warm['prompt_tokens'] if warm else '?'} tokens for 24000 chars)\n")

    n = 0
    for r in range(ROUNDS):
        msgs, n = build(TARGETS["A"], ratio, n)
        for stage in ("A", "B", "C"):
            msgs.append({"role": "user", "content": f"Give lesson {r + 1}{stage} from these excerpts, "
                                                    "as a numbered list of 40 items."})
            u, el, txt = chat(msgs, GEN)
            if not u:
                print(f"  round {r + 1} stage {stage}: FAILED")
                continue
            msgs.append({"role": "assistant", "content": txt})
            print(f"  round {r + 1} stage {stage}: ctx {u['prompt_tokens']:>7} -> "
                  f"{u['completion_tokens']:>4} tok in {el:6.1f} s "
                  f"({u['completion_tokens'] / el:6.1f} tok/s wall)", flush=True)
            if stage != "C":
                while len("".join(m["content"] for m in msgs)) * ratio < TARGETS[
                        "B" if stage == "A" else "C"]:
                    msgs.append({"role": "user", "content": chunk(n)})
                    msgs.append({"role": "assistant", "content": "Noted."})
                    n += 1
        cold = [{"role": "user", "content": "".join(chunk(1000 + i) for i in range(
            int(COLD_TARGET / ratio / 4000) + 1))}]
        u, el, _ = chat(cold, 1)
        if u:
            print(f"  round {r + 1} stage D: cold read {u['prompt_tokens']:>7} tok in "
                  f"{el:6.1f} s ({u['prompt_tokens'] / el:7.1f} tok/s wall)", flush=True)

    stop.set()
    th.join()

    lines = open(LOG, errors="replace").read().split("\n")[log_start:]
    pat = re.compile(r"prompt (\d+) tokens = (\d+) reused \+ (\d+) read in ([0-9.]+) ms "
                     r"\(([0-9.]+) tok/s\), (\d+) generated in ([0-9.]+) ms \(([0-9.]+) tok/s\)")
    rows = [m.groups() for m in (pat.search(l) for l in lines) if m]
    print(f"\nengine accounting ({len(rows)} requests):")
    print(f"  {'ctx':>7} {'reused':>7} {'read':>6} {'read tok/s':>11} {'gen':>5} {'gen ms':>7} "
          f"{'decode tok/s':>12} accepted")
    for p, reused, read, rms, rps, gen, gms, gps in rows:
        print(f"  {int(p):>7} {int(reused):>7} {int(read):>6} {float(rps):>11.1f} "
              f"{int(gen):>5} {float(gms):>7.0f} {float(gps):>12.1f}")

    def bucket(stage, row):
        ctx, read, gen = int(row[0]), int(row[2]), int(row[5])
        if stage == "D":
            return gen <= 2 and read > 30000
        if gen <= 2:
            return False
        return {"A": ctx < 40000, "B": 40000 <= ctx < 100000, "C": ctx >= 100000}[stage]

    print("\nmedians (engine-side):")
    for stage, desc in (("A", "<40K ctx, 1200 tok decode"),
                        ("B", "40-100K ctx, 1200 tok decode"),
                        ("C", ">100K ctx, 1200 tok decode"),
                        ("D", "cold prompt read")):
        sel = [r for r in rows if bucket(stage, r)]
        if not sel:
            continue
        idx = 5 if stage == "D" else 7
        v = statistics.median(float(r[idx]) for r in sel)
        rd = statistics.median(float(r[4]) for r in sel)
        print(f"  {stage}  {desc:28s} " + (f"read {rd:8.1f} tok/s" if stage == "D"
                                           else f"decode {v:6.1f} tok/s  (read {rd:7.1f})"))

    if mem:
        print(f"\nmemory during run: min MemAvailable {min(m[0] for m in mem) / 1048576:.1f} GiB"
              f" | max swap used {max(m[1] for m in mem) / 1048576:.1f} GiB"
              f" | engine RSS ~{max(m[2] for m in mem) / 1048576:.1f} GiB")

    stats = [l.strip() for l in lines if re.search(
        r"expert cache|VRAM free with everything|adapt-async|resident RAM|arena|hit rate|slot save", l)]
    if stats:
        print("\nengine stat lines in this window:")
        for l in stats[-14:]:
            print("  " + l[:170])


if __name__ == "__main__":
    main()
