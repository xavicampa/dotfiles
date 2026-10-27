#!/usr/bin/env python3
"""Steady-state concurrency curve for the batch `parallel` engine (port 5802).

Complements `strata bench run --suite parallel-mixed-v1`, whose mixed phase caps
each request at 32/96 tokens: with a 5-request fan-out released at once the phase
wall time is set by the longest stream, so its output_tok_s understates the
steady-state decode rate. This script holds each stream at MAX_TOKENS so the
decode loop is the thing being measured, and reports per-stream and aggregate
tok/s plus client-side TTFT at each concurrency level.

Same shape as bench-batch-mtp.py (temperature 0, N rounds, medians) but adds
levels above --batch (oversubscription) and TTFT via streaming.
"""
import json
import statistics
import time
import urllib.request

URL = "http://127.0.0.1:5802/v1/chat/completions"
MODEL = "qwen3.8-flash-next-iq3_s"
ROUNDS = 3
MAX_TOKENS = 300
LEVELS = [1, 2, 3, 4, 5, 6, 7]   # pass levels as argv to override; keep max <= admission_limit
# (= slots + max_queue) or a level is answered with HTTP 429 instead of a measurement.

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


def chat(prompt, n=MAX_TOKENS):
    """One streaming request -> (ttft_s, latency_s, completion_tokens)."""
    body = {"model": MODEL, "max_tokens": n, "temperature": 0, "stream": True,
            "messages": [{"role": "user", "content": prompt}]}
    t0 = time.time()
    ttft = None
    tokens = 0
    with urllib.request.urlopen(urllib.request.Request(
            URL, data=json.dumps(body).encode(),
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
                        if ch.get("delta", {}).get("content") or ch.get("delta", {}).get("reasoning_content"):
                            tokens += 1
    return ttft or 0.0, time.time() - t0, tokens


def run_level(k):
    res = []
    lock = __import__("threading").Lock()

    def worker(i):
        out = chat(PROMPTS[i % len(PROMPTS)])
        with lock:
            res.append(out)

    threads = [__import__("threading").Thread(target=worker, args=(i,)) for i in range(k)]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    wall = time.time() - t0
    toks = sum(r[2] for r in res)
    return {"wall": wall, "agg_tok_s": toks / wall,
            "per_stream": [r[2] / r[1] for r in res],
            "ttft": [r[0] for r in res],
            "lat": [r[1] for r in res],
            "toks": [r[2] for r in res]}


def med(a):
    return statistics.median(a) if a else float("nan")


def main():
    import sys
    if len(sys.argv) > 1:
        LEVELS[:] = [int(x) for x in sys.argv[1:]]
    print(f"engine model={MODEL} max_tokens={MAX_TOKENS} rounds={ROUNDS} "
          f"(temperature 0, streaming, host loopback)")
    print(f"{'streams':>7} {'agg tok/s':>10} {'med/stream':>10} {'min/stream':>10} "
          f"{'med TTFT':>9} {'max TTFT':>9} {'med latency':>12} {'wall s':>7}")
    for k in LEVELS:
        legs = [run_level(k) for _ in range(ROUNDS)]
        agg = med([l["agg_tok_s"] for l in legs])
        per = [x for l in legs for x in l["per_stream"]]
        tt = [x for l in legs for x in l["ttft"]]
        lat = [x for l in legs for x in l["lat"]]
        print(f"{k:>7} {agg:>10.1f} {med(per):>10.1f} {min(per):>10.1f} "
              f"{med(tt):>9.2f} {max(tt):>9.2f} {med(lat):>12.2f} "
              f"{med([l['wall'] for l in legs]):>7.2f}")
        print(f"        per-stream runs: {', '.join(f'{x:.0f}' for x in sorted(per))}")
        time.sleep(1.0)


if __name__ == "__main__":
    main()
