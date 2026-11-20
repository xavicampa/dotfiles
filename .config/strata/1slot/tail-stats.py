#!/usr/bin/env python3
"""tail-stats.py — route-tail-skip mechanism counters for one or more 1slot eras.

    ./tail-stats.py                 # every .tune/*.era, oldest first
    ./tail-stats.py <era-line> ...  # specific era start lines (the number in .tune/<label>.era)

Decode medians on this tree drift +-11 %, so speed alone cannot price STRATA_ROUTE_TAIL_SKIP.
These counters are in-era and near-noise-free. Read them as a set:

  skip on/off  the boot line: `STRATA_ROUTE_TAIL_SKIP=N is ON (default)` vs the off line
  skipped      `route tail skip: N missed experts skipped (M entries) since the start`, last of
               the era ("since the start" resets at each boot, so it is the era total)
  skip/1k gen  that total over the era's generated tokens: the mechanism, independent of speed
  hit rate     `decode expert cache hit rate: X%` lines, median of the era
  decode       `N generated in M ms (X tok/s)` lines, median of the era (the drift-prone column)
  cold read    `prompt N tokens = 0 reused` lines, median tok/s (the +-0.1 % column)
"""
import json
import os
import re
import statistics as st
import sys

TREE = os.path.dirname(os.path.abspath(__file__))
LOG = ("/home/javi/.local/share/containers/storage/volumes/strata-data/_data"
       "/state/strata/launch/docker.engine.log")
ERA = re.compile(r"engine started:.*packs/iq3_s.*--max-context 262144")
RE_SKIP = re.compile(r"route tail skip: (\d+) missed experts skipped \((\d+) entries\)")
RE_ON = re.compile(r"STRATA_ROUTE_TAIL_SKIP=(\d+) is ON")
RE_OFF = re.compile(r"route tail skip[^.]{0,40}(is off|disabled|OFF)")
RE_GEN = re.compile(r"(\d+) generated in (\d+) ms \(([\d.]+) tok/s\)")
RE_HIT = re.compile(r"decode expert cache hit rate: ([\d.]+)%")
RE_COLD = re.compile(r"prompt (\d+) tokens = 0 reused \+ \d+ read in \d+ ms \(([\d.]+) tok/s\)")


def era_starts(lines):
    return [i + 1 for i, ln in enumerate(lines) if ERA.search(ln)]


def labels_by_era():
    out = {}
    d = os.path.join(TREE, ".tune")
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith(".era"):
                try:
                    out[int(open(os.path.join(d, f)).read().strip())] = f[:-4]
                except ValueError:
                    pass
    return out


def report(lines, start, end, name):
    seg = lines[start - 1:end - 1]
    on = [m.group(1) for ln in seg for m in [RE_ON.search(ln)] if m]
    offs = [ln for ln in seg if RE_OFF.search(ln)]
    skips = [m for ln in seg for m in [RE_SKIP.search(ln)] if m]
    gens = [m for ln in seg for m in [RE_GEN.search(ln)] if m]
    hits = [float(m.group(1)) for ln in seg for m in [RE_HIT.search(ln)] if m]
    colds = [float(m.group(2)) for ln in seg for m in [RE_COLD.search(ln)] if m]
    gen_tok = sum(int(g.group(1)) for g in gens)
    dec = [float(g.group(3)) for g in gens]
    skipped, entries = (int(skips[-1].group(1)), int(skips[-1].group(2))) if skips else (0, 0)
    state = ("ON rank " + on[-1]) if on else ("OFF" if offs else "no line")
    per1k = 1000.0 * skipped / gen_tok if gen_tok else 0.0
    med = lambda v: ("%.1f" % st.median(v)) if v else "-"
    print("%-14s era %-7d gen %7d  skip=%-11s skipped %7d/%-7d (%4.1f%% of entries)  "
          "skip/1k gen %6.1f  hit %5s%%  decode %5s tok/s  cold %7s tok/s"
          % (name, start, gen_tok, state, skipped, entries,
             (100.0 * skipped / entries if entries else 0.0), per1k,
             med(hits), med(dec), med(colds)))
    return dict(era=start, name=name, gen_tok=gen_tok, skipped=skipped, entries=entries,
                per1k=per1k, decode_med=st.median(dec) if dec else None,
                cold_med=st.median(colds) if colds else None,
                hit_med=st.median(hits) if hits else None, state=state)


def main():
    lines = open(LOG, errors="replace").read().splitlines()
    starts = era_starts(lines)
    by_label = labels_by_era()
    if len(sys.argv) > 1:
        wanted = [int(a) for a in sys.argv[1:]]
    else:
        wanted = sorted(int(open(os.path.join(TREE, ".tune", f)).read().strip())
                        for f in os.listdir(os.path.join(TREE, ".tune")) if f.endswith(".era")) \
            if os.path.isdir(os.path.join(TREE, ".tune")) else []
    if not wanted:
        print("no eras given and no .tune/*.era files", file=sys.stderr)
        return 1
    rows = []
    for e in sorted(wanted):
        if e not in starts:
            print("%d is not a 1slot era start line" % e, file=sys.stderr)
            continue
        nxt = next((s for s in starts if s > e), len(lines) + 1)
        rows.append(report(lines, e, nxt, by_label.get(e, "(unlabeled)")))
    json.dump(rows, open(os.path.join(TREE, ".tune", "tailsweep-stats.json"), "w"), indent=1)
    print("wrote .tune/tailsweep-stats.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
