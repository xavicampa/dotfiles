#!/usr/bin/env python3
"""Fixed A/B benchmark for --batch-mtp on the batch (parallel) install.

Run it once with --batch-mtp in the engine argv, once without (restart between).
It drives one solo request then 2, 3, 4 and 5 conversations concurrently, 3 rounds,
and prints per-stream and aggregate medians plus the engine's own batch-window
accounting.
"""
import json, re, statistics, subprocess, sys, threading, time, urllib.request

URL = "http://127.0.0.1:5802/v1/chat/completions"
LOG = ("/home/javi/.local/share/containers/storage/volumes/strata-data/_data/"
       "state/strata/launch/docker.engine.log")
ROUNDS = 3
MAX_TOKENS = 200
PROMPTS = [
    "Enumerate the 12 most important battles of the Pacific war, one per line, with a year.",
    "Enumerate the 12 most important battles of the Napoleonic wars, one per line, with a year.",
    "Enumerate the 12 most important battles of the American Civil War, one per line, with a year.",
    "Enumerate the 12 most important battles of the Napoleonic era in Europe, one per line, with a year.",
    "Enumerate the 12 most important battles of the Thirty Years' War, one per line, with a year.",
]


def engine_state():
    out = subprocess.run(["bash", "-c",
        "pid=$(pgrep -f 'components/engine/.*--serve' | head -1); tr '\\0' '\\n' < /proc/$pid/cmdline"],
        capture_output=True, text=True).stdout.split("\n")
    flag = "--batch-mtp" in out
    batch = out[out.index("--batch") + 1] if "--batch" in out else "?"
    return flag, batch


def chat(prompt, n=MAX_TOKENS):
    body = {"model": "qwen3.8-flash-next-iq3_s", "max_tokens": n, "temperature": 0,
            "messages": [{"role": "user", "content": prompt}]}
    t0 = time.time()
    d = json.load(urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}), timeout=900))
    el = time.time() - t0
    return d["usage"]["completion_tokens"] / el


def concurrent(k):
    res = []
    th = [threading.Thread(target=lambda k=k, i=i: res.append(chat(PROMPTS[i]))) for i in range(k)]
    [t.start() for t in th]
    [t.join() for t in th]
    return sum(res), res


def main():
    flag, batch = engine_state()
    print(f"engine: --batch-mtp={'ON' if flag else 'off'}  --batch={batch}")
    if "--batch-mtp" in sys.argv and not flag:
        print("  WARNING: expected --batch-mtp ON in the running engine")
    if "--no-mtp" in sys.argv and flag:
        print("  WARNING: expected --batch-mtp OFF in the running engine")

    log_start = sum(1 for _ in open(LOG, errors="replace"))
    solo, two, three, four, five = [], [], [], [], []
    for _ in range(ROUNDS):
        solo.append(max(chat(PROMPTS[0]), 1e-9)); time.sleep(2)
        two.append(concurrent(2)[0]); time.sleep(2)
        three.append(concurrent(3)[0]); time.sleep(2)
        four.append(concurrent(4)[0]); time.sleep(2)
        five.append(concurrent(5)[0]); time.sleep(2)

    med = lambda a: statistics.median(a)
    print(f"solo      : {med(solo):6.1f} tok/s   runs: {', '.join(f'{x:.0f}' for x in solo)}")
    print(f"2 streams : {med(two):6.1f} tok/s   runs: {', '.join(f'{x:.0f}' for x in two)}")
    print(f"3 streams : {med(three):6.1f} tok/s   runs: {', '.join(f'{x:.0f}' for x in three)}")
    print(f"4 streams : {med(four):6.1f} tok/s   runs: {', '.join(f'{x:.0f}' for x in four)}")
    print(f"5 streams : {med(five):6.1f} tok/s   runs: {', '.join(f'{x:.0f}' for x in five)}")

    pat = re.compile(r"strata batch: (\d+) windows, avg ([0-9.]+) rows, ([0-9.]+) ms/window")
    mtp = re.compile(r"MTP proposals accepted (\d+) of (\d+)")
    lines = open(LOG, errors="replace").read().split("\n")[log_start:]
    print("batch windows this run:")
    for i, l in enumerate(lines):
        m = pat.search(l)
        if not m:
            continue
        w, rows, ms = (float(x) for x in m.groups())
        nxt = mtp.search("\n".join(lines[i:i + 4]))
        acc = int(nxt.group(1)) / int(nxt.group(2)) if nxt else 0.0
        per_slot = 1.0 + (int(nxt.group(1)) / w / rows if nxt else 0.0)
        print(f"  {int(w):5d} windows rows={rows:4.2f} {ms:5.2f} ms/win"
              f"  accepted={acc:5.1%}  tok/s/slot~{1000/ms*per_slot:5.1f}")


if __name__ == "__main__":
    main()
