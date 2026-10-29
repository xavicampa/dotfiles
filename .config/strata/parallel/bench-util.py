#!/usr/bin/env python3
"""Concurrency curve + per-card utilization sampler for a strata batch engine.

bench-cc-curve.py's shape (temperature 0, streaming, medians of ROUNDS) plus,
per level, what the two cards and the CPU were actually doing while it ran:
per-card nvidia-smi utilization/power/memory, and the engine process's ALL-THREAD
CPU time (its expert pool is threads of the engine process, so /proc/<pid>/stat
alone reads as ~1 core and hides the pool).

  python3 bench-util.py --url http://127.0.0.1:5803 --model qwen3.8-flash-next-iq3_s \
      --levels 1 2 3 4 --rounds 3 --max-tokens 300 --container <podman name> [--csv rows.csv]

Rows are written next to the run so a `strata gpu monitor` / engine-log window
can be lined up against them afterwards.
"""
import argparse
import json
import os
import statistics
import subprocess
import threading
import time
import urllib.request

TOPICS = [
    "the Pacific war", "the Napoleonic wars", "the American Civil War",
    "the Thirty Years' War", "the Punic Wars", "the War of Spanish Succession",
    "the Seven Years' War", "the Wars of the Roses", "the Hundred Years' War",
    "the Crusades", "the Mongol conquests", "the War of the Austrian Succession",
    "the Italo-Ethiopian wars", "the Boxer Rebellion", "the Taiping Rebellion",
    "the Zulu Wars", "the Russo-Japanese War", "the Winter War",
]
PROMPTS = [f"Enumerate the 12 most important battles of {t}, one per line, with a year."
           for t in TOPICS]


def engine_cpu_time(pid):
    """Centiseconds of ALL threads of the engine process."""
    tot = 0
    try:
        for t in os.listdir(f"/proc/{pid}/task"):
            try:
                st = open(f"/proc/{pid}/task/{t}/stat").read().split(")")[1].split()
                tot += int(st[11]) + int(st[12])   # utime + ktime
            except (ProcessLookupError, PermissionError, IndexError, ValueError):
                pass
    except (FileNotFoundError, PermissionError):
        return None
    return tot / 100.0


def gpu_state():
    out = subprocess.run(
        ["nvidia-smi", "--query-gpu=utilization.gpu,power.draw,memory.used",
         "--format=csv,noheader,nounits"], capture_output=True, text=True).stdout
    rows = []
    for line in out.strip().split("\n"):
        u, p, m = [float(x) for x in line.split(",")]
        rows.append((u, p, m))
    return rows


def find_engine_pid(container):
    """Host pid of the strata engine: walk the container's process tree from
    State.Pid (podman top's pid column is the NAMESPACED pid - not host)."""
    out = subprocess.run(["podman", "inspect", "-f", "{{.State.Pid}}", container],
                         capture_output=True, text=True).stdout.strip()
    if not out.isdigit():
        return None
    seen, queue = set(), [int(out)]
    while queue:
        pid = queue.pop()
        if pid in seen:
            continue
        seen.add(pid)
        try:
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode()
        except OSError:
            cmd = ""
        if "components/engine" in cmd and "--serve" in cmd:
            return pid
        try:
            kids = subprocess.run(["pgrep", "-P", str(pid)],
                                  capture_output=True, text=True).stdout.split()
            queue.extend(int(k) for k in kids)
        except Exception:
            pass
    return None


class Sampler:
    def __init__(self, container, interval=0.5):
        self.rows = []
        self.container = container
        self.pid = find_engine_pid(container)
        self.interval = interval
        self._stop = False
        self._prev = None
        self.t = None

    def start(self):
        self.t = threading.Thread(target=self._run, daemon=True)
        self.t.start()

    def _run(self):
        while not self._stop:
            t = time.time()
            cpu = engine_cpu_time(self.pid) if self.pid else None
            if cpu is None and self.container:
                self.pid = find_engine_pid(self.container)   # engine restarted
                cpu = engine_cpu_time(self.pid) if self.pid else None
            cores = None
            if cpu is not None and self._prev and self._prev[2] == self.pid:
                dt = t - self._prev[0]
                if dt > 0 and cpu >= self._prev[1]:
                    cores = (cpu - self._prev[1]) / dt
            self._prev = (t, cpu, self.pid)
            self.rows.append((t, cpu, cores) + sum(gpu_state(), ()))
            time.sleep(self.interval)

    def stop(self):
        self._stop = True
        self.t.join()

    def window(self, t0, t1):
        return [r for r in self.rows if t0 <= r[0] <= t1]


def stream_chat(url, model, prompt, max_tokens):
    endpoint = url.rstrip("/") + "/v1/chat/completions"
    body = {"model": model, "max_tokens": max_tokens, "temperature": 0, "stream": True,
            "messages": [{"role": "user", "content": prompt}]}
    t0 = time.time()
    ttft = None
    toks = 0
    with urllib.request.urlopen(urllib.request.Request(
        endpoint, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}), timeout=900) as r:
        for raw in r:
            if ttft is None:
                ttft = time.time() - t0
            line = raw.decode("utf-8", "replace").strip()
            if line.startswith("data:"):
                payload = line[5:].strip()
                if payload and payload != "[DONE]":
                    try:
                        d = json.loads(payload)
                    except ValueError:
                        continue
                    for ch in d.get("choices") or []:
                        delta = ch.get("delta", {})
                        if delta.get("content") or delta.get("reasoning_content"):
                            toks += 1
    return ttft or 0.0, time.time() - t0, toks


def run_level(k, url, model, max_tokens, sampler):
    res = []
    lock = threading.Lock()

    def worker(i):
        out = stream_chat(url, model, PROMPTS[i % len(PROMPTS)], max_tokens)
        with lock:
            res.append(out)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(k)]
    t0 = time.time()
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    wall = time.time() - t0
    toks = sum(r[2] for r in res)
    leg = {"wall": wall, "agg_tok_s": toks / wall,
           "per_stream": [r[2] / r[1] for r in res],
           "ttft": [r[0] for r in res], "lat": [r[1] for r in res], "toks": [r[2] for r in res],
           "t0": t0, "t1": time.time()}
    if sampler:
        leg["util"] = sampler.window(t0, time.time())
    return leg


def med(a):
    return statistics.median(a) if a else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:5803")
    ap.add_argument("--model", default="qwen3.8-flash-next-iq3_s")
    ap.add_argument("--levels", type=int, nargs="+", default=[1, 2, 3, 4])
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--max-tokens", type=int, default=300)
    ap.add_argument("--container", default=None)
    ap.add_argument("--csv", default=None)
    a = ap.parse_args()

    sampler = Sampler(a.container) if a.container else None
    if sampler:
        sampler.start()
        print(f"sampling engine (container {a.container}) every {sampler.interval}s")
    print(f"url={a.url} model={a.model} max_tokens={a.max_tokens} rounds={a.rounds}")
    print(f"{'streams':>7} {'agg tok/s':>10} {'med/stream':>10} {'min/stream':>10} "
          f"{'med TTFT':>9} {'max TTFT':>9} {'wall s':>7}", flush=True)
    legs = {}
    for k in a.levels:
        runs = [run_level(k, a.url, a.model, a.max_tokens, sampler) for _ in range(a.rounds)]
        legs[k] = runs
        per = [x for l in runs for x in l["per_stream"]]
        tt = [x for l in runs for x in l["ttft"]]
        if not per:
            print(f"{k:>7} no successful stream at this level", flush=True)
            continue
        print(f"{k:>7} {med([l['agg_tok_s'] for l in runs]):>10.1f} {med(per):>10.1f} "
              f"{min(per):>10.1f} {med(tt):>9.2f} {max(tt):>9.2f} "
              f"{med([l['wall'] for l in runs]):>7.2f}", flush=True)
        print(f"        per-stream runs: {', '.join(f'{x:.0f}' for x in sorted(per))}", flush=True)
        if sampler:
            rows = [r for l in runs for r in l.get("util", [])]
            n = len(rows) or 1
            for gi in range(len(gpu_state())):
                u = [r[3 + gi * 3] for r in rows]
                p = [r[4 + gi * 3] for r in rows]
                m = [r[5 + gi * 3] for r in rows]
                if u:
                    print(f"        GPU{gi}: util mean {sum(u)/n:.0f}% max {max(u):.0f}% "
                          f"power {sum(p)/n:.0f}W max {max(p):.0f} mem {sum(m)/n:.0f} MiB", flush=True)
            c = [r[2] for r in rows if r[2] is not None]
            if c:
                print(f"        engine CPU mean {sum(c)/len(c):.2f} max {max(c):.2f} cores (all threads)", flush=True)
        time.sleep(1.0)
    if sampler:
        sampler.stop()
    if a.csv:
        with open(a.csv, "w") as fh:
            fh.write("level,t,cpu_s,cores,util0,pow0,mem0,util1,pow1,mem1\n")
            for k, runs in legs.items():
                for l in runs:
                    for r in l.get("util", []):
                        c = f"{r[1]:.3f}" if r[1] is not None else ""
                        cs = f"{r[2]:.3f}" if r[2] is not None else ""
                        fh.write(f"{k},{r[0]:.3f},{c},{cs},"
                                 f"{r[3]:.0f},{r[4]:.0f},{r[5]:.0f},"
                                 f"{r[6]:.0f},{r[7]:.0f},{r[8]:.0f}\n")
        print(f"rows -> {a.csv}")


if __name__ == "__main__":
    main()
