#!/usr/bin/env python3
"""cc-counters.py — conversation-cache health for one Strata era (1slot tree).

    ./cc-counters.py                 # every iq3_s era in the engine log, most recent last
    ./cc-counters.py <era-line> ...  # specific era start lines (the number in .tune/<label>.era)

Decides conversation-cache arms. Decode medians on this tree drift +-11 %; these counters are
in-era and near-noise-free. Read them as a set:

  refusals   `skip parking (snapshot N MiB exceeds available budget)` -> the POOL is too small
  small      parks under --conversation-cache-min-tokens' threshold... i.e. parks of conversations
             below 8192 tokens -> churn eating GiB that a giant needs
  restores   `restored N tokens (live)` -> the payoff; 100-197K tokens costs ~100-330 ms, against
             a 21-30 s cold re-read of the same conversation
  evict max  LRU victims at park time; if this climbs and the same era shows a giant request with
             `0 reused`, the pool cannot hold the long conversations that are actually live

Windows are not traffic-matched, so the `cold s` column is context, not the verdict.
"""
import re
import sys

LOG = ("/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state"
       "/strata/launch/docker.engine.log")
REQ = re.compile(r"strata serve: prompt (\d+) tokens = (\d+) reused \+ (\d+) read in ([\d.]+) ms")
PARK = re.compile(r"parked (\d+) tokens in ([\d.]+) ms; parked=(\d+) bytes=(\d+) evictions=(\d+) "
                  r"snapshot_bytes=(\d+)")
REST = re.compile(r"restored (\d+) tokens \(live\) in ([\d.]+) ms")
SMALL_TOKENS = 8192  # the min-tokens the arm was accepted at; labels the churn parks


def eras(lines, pack="iq3_s"):
    """(start_line, effective_argv) for every engine boot of `pack`."""
    out = []
    for i, l in enumerate(lines, 1):
        if "engine started:" in l and f"packs/{pack}" in l:
            out.append((i, l))
    return out


def argv_of(boot_line, flags):
    got = {}
    for f in flags:
        m = re.search(re.escape(f) + r" (\S+)", boot_line)
        got[f] = m.group(1) if m else "(default)"
    return " ".join(f"{f[len('--conversation-cache-'):]}={v}" for f, v in got.items())


def report(lines, start, stop):
    window = lines[start - 1:stop]
    req = [m for l in window for m in [REQ.search(l)] if m]
    cold = [(int(m.group(1)), float(m.group(4)) / 1000) for m in req
            if m.group(2) == "0" and int(m.group(1)) >= 4000]
    parks = [m for l in window for m in [PARK.search(l)] if m]
    rests = [m for l in window for m in [REST.search(l)] if m]
    # group numbers: 1 tokens, 2 ms, 3 parked slots, 4 POOL bytes, 5 evictions, 6 SNAPSHOT bytes
    refusals = sorted({int(m.group(1)) for l in window
                       for m in [re.search(r"skip parking \(snapshot (\d+) MiB exceeds", l)] if m})
    print(f"  requests {len(req):4} | cold reads >=4000 tok: n={len(cold)} "
          f"total {sum(x[1] for x in cold):6.1f}s  {[c[0] for c in cold]}")
    print(f"  refusals {len(refusals):3} (MiB {refusals[:6]}{'...' if len(refusals) > 6 else ''})"
          f" | parks {len(parks):3} (of which <{SMALL_TOKENS} tok: "
          f"{len([m for m in parks if int(m.group(1)) < SMALL_TOKENS])})"
          f" | evictions max {max((int(m.group(5)) for m in parks), default=0)}")
    if parks:
        big = max(parks, key=lambda m: int(m.group(6)))
        print(f"  parked: biggest snapshot {int(big.group(1)):7} tok in {float(big.group(2)):6.1f} ms "
              f"-> {int(big.group(6)) / 2**30:.2f} GiB "
              f"({int(big.group(6)) / 2**10 / int(big.group(1)):.1f} KiB/token); "
              f"pool peak {max(int(m.group(4)) for m in parks) / 2**30:.2f} GiB "
              f"in {max(int(m.group(3)) for m in parks)} slots")
    if rests:
        best = max(rests, key=lambda m: int(m.group(1)))
        print(f"  LIVE RESTORES {len(rests)}: best {int(best.group(1)):7} tokens in "
              f"{float(best.group(2)):6.1f} ms   <- the payoff line")
    else:
        print("  live restores  0  <- a parked conversation never came back: the cache is not paying")


def main():
    lines = open(LOG, errors="replace").read().splitlines()
    all_eras = eras(lines)
    want = [int(a) for a in sys.argv[1:]] or [s for s, _ in all_eras[-3:]]
    bounds = [s for s, _ in all_eras]
    for start in want:
        boot = next((b for s, b in all_eras if s == start), "")
        stop = min([s for s in bounds if s > start], default=len(lines)) - 1
        print(f"\nera {start}..{stop}  {argv_of(boot, ['--conversation-cache-mib', '--conversation-cache-slots', '--conversation-cache-min-tokens', '--conversation-cache-park-gain', '--conversation-cache-min-free-mib'])}")
        report(lines, start, stop)


if __name__ == "__main__":
    main()
