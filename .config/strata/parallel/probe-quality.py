#!/usr/bin/env python3
"""Quality smoke for an arm on this tree (parallel, qwen3.8-flash-next-iq3_s).

The house rule for an arm that touches the draft/commit path is a look at the actual
output, not only tok/s. Speculative decoding is verified token-by-token, so the point of
this probe is not "did the drafts change the answer" but: does the model still hold
together at temperature 0 — code that parses, JSON that parses, a needle found at 4k
tokens, and no degeneration (loops) in a long continuation.

  ./probe-quality.py [--url http://127.0.0.1:5802] [--model qwen3.8-flash-next-iq3_s]
                     [--out .tune/smoke-<label>.txt]

Every output is hashed; run the same probe under two configs and diff the hashes plus the
flag lines. A hash difference alone is not a failure (batched matmuls are not bit-identical
to separate ones); a failed flag is.
"""
import argparse, hashlib, json, re, statistics, urllib.request

NEEDLE = "The maintenance window for the Kessler-9 vault is 2026-03-14 at 04:30 UTC, code ORCHID-4471."


def fill(nchars, seed):
    words = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima november "
             "oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu") .split()
    out, i, h = [], 0, seed
    while sum(len(w) + 1 for w in out) < nchars:
        h = (h * 1103515245 + 12345) & 0x7FFFFFFF
        out.append(words[h % len(words)])
        i += 1
        if i % 37 == 0:
            out.append(f"line{i}={h % 9973}")
    return " ".join(out)


PROMPTS = [
    ("code", 1400, "Write a Python function parse_duration(iso: str) -> float that parses an ISO-8601 "
                   "duration like 'P1DT2H3M4.5S' and returns seconds. Then give five pytest cases that "
                   "cover days, hours, minutes, fractions and a malformed input."),
    ("json", 900, "Return ONLY a JSON object, no prose, with keys: name (string), version (string), "
                  "deps (array of 4 strings each 'pkg@semver'), licenses (array of the same length)."),
    ("needle", 800, "Read the passage and answer with the exact code that appears in it, nothing else.\n\n"
                    + fill(20000, 7919) + "\n\nPassage continues: " + NEEDLE + "\n\nCode:"),
    ("long", 1600, "Explain, in order and with the numbers, how a two-GPU layer split with a streaming "
                   "expert cache decides which experts to keep in VRAM, and what happens on a miss. "
                   "Be concrete about sizes and bandwidth."),
]


def ask(url, model, prompt, max_tokens):
    """Non-streaming, but this model answers in reasoning_content as well as content: keep both."""
    body = {"model": model, "max_tokens": max_tokens, "temperature": 0, "stream": False,
            "messages": [{"role": "user", "content": prompt}]}
    with urllib.request.urlopen(urllib.request.Request(url.rstrip("/") + "/v1/chat/completions",
                                                       data=json.dumps(body).encode(),
                                                       headers={"Content-Type": "application/json"}),
                                timeout=600) as r:
        d = json.loads(r.read().decode())
    m = d["choices"][0]["message"]
    return (m.get("content") or ""), (m.get("reasoning_content") or "")


def degeneration(text):
    """Cheap loop detector: repeated identical lines, and the longest repeated 8-gram."""
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    dup = len(lines) - len(set(lines))
    grams = {}
    w = text.split()
    for i in range(len(w) - 7):
        grams[" ".join(w[i:i + 8])] = grams.get(" ".join(w[i:i + 8]), 0) + 1
    worst = max(grams.values()) if grams else 0
    return dup, worst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:5802")
    ap.add_argument("--model", default="qwen3.8-flash-next-iq3_s")
    ap.add_argument("--out", default=".tune/smoke.txt")
    a = ap.parse_args()
    flags, lines = [], []
    for name, mt, p in PROMPTS:
        content, reasoning = ask(a.url, a.model, p, mt)
        t = content + "\n" + reasoning
        ans = content.strip() or reasoning          # flags are judged on the answer, not the thinking
        h = hashlib.sha256(t.encode()).hexdigest()[:16]
        dup, worst = degeneration(t)
        ok = True
        if name == "json":
            try:
                o = json.loads(re.search(r"\{.*\}", ans, re.S).group(0))
                ok = (isinstance(o.get("deps"), list) and len(o["deps"]) == len(o.get("licenses", [])) == 4)
            except Exception:
                ok = False
        if name == "needle":
            ok = bool(re.search(r"ORCHID[- ]?4471", ans))
        if name == "code":
            ok = "def parse_duration" in ans and "P1DT2H3M4.5S" in ans
        flags.append(f"{name:7} sha={h} chars={len(t):5} dup_lines={dup:2} max_8gram_repeat={worst:2} flag={'OK' if ok else 'FAIL'}")
        lines.append(f"===== {name} (sha {h}, flag {'OK' if ok else 'FAIL'}) =====\n{t}\n")
    report = "\n".join(flags) + "\n\n" + "\n".join(lines)
    open(a.out, "w").write(report)
    print(report.split("\n\n")[0])
    print(f"full text -> {a.out}")
    print("FAILS: " + (", ".join(f.split()[0] for f in flags if "FAIL" in f) or "none"))


main()
