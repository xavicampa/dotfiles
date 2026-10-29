#!/usr/bin/env python3
"""Per-request decode stats for one engine era (one boot) of the shared Strata engine log.

The coder and iq3_s containers append to the SAME log file, so an era is a boot line
plus everything after it -- and the boot you want is the one whose --pack path matches
the tree under test.  Without --pack the newest boot is used, which is the other
model's whenever it reloaded last.

  erastats.py                     # newest boot in the log
  erastats.py --pack coder-iq1_m  # newest boot for that pack (recommended)
  erastats.py --pack coder-iq1_m --boots 3   # stats over the last 3 such eras
"""
import argparse, re, statistics as st

LOG = '/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state/strata/launch/docker.engine.log'
REQ = re.compile(r'prompt (\d+) tokens = (\d+) reused \+ (\d+) read in ([\d.]+) ms \(([\d.]+) tok/s\), '
                 r'(\d+) generated in ([\d.]+) ms \(([\d.]+) tok/s\), drafts accepted (\d+) of (\d+)')

ap = argparse.ArgumentParser()
ap.add_argument('--pack', default=None, help='substring of the --pack path (coder-iq1_m, iq3_s, ...)')
ap.add_argument('--boots', type=int, default=1, help='how many matching eras to pool')
ap.add_argument('--log', default=LOG)
a = ap.parse_args()

data = open(a.log, 'rb').read()[-8_000_000:].decode('utf-8', 'replace')
lines = data.splitlines()
boots = [i for i, l in enumerate(lines) if 'engine started:' in l]
if a.pack:
    boots = [i for i in boots if a.pack in lines[i]]
if not boots:
    raise SystemExit(f'no {"engine started:" if not a.pack else "boot matching " + a.pack!r} in the tail of the log')
starts = boots[-a.boots:]
ends = starts[1:] + [len(lines)]

rows = []
for s, e in zip(starts, ends):
    for m in REQ.finditer('\n'.join(lines[s:e])):
        rows.append(dict(gen=int(m.group(6)), ms=float(m.group(7)), tps=float(m.group(8)),
                         acc=int(m.group(9)), off=int(m.group(10)),
                         prompt=int(m.group(1)), reused=int(m.group(2)),
                         read_ms=float(m.group(4)), read_tps=float(m.group(5))))
if not rows:
    raise SystemExit('no per-request lines in that era (boot only, no completions yet)')

tps = [r['tps'] for r in rows]
fed = sum(r['off'] for r in rows) or 1
acc = sum(r['acc'] for r in rows)
gen = sum(r['gen'] for r in rows)
print(f"era{'s' if a.boots > 1 else ''}{': ' + (a.pack or 'newest boot')}  n={len(rows)}"
      f"  tok/s med {st.median(tps):.1f} p25 {sorted(tps)[len(tps)//4]:.1f} p75 {sorted(tps)[3*len(tps)//4]:.1f} mean {st.mean(tps):.1f}")
print(f'accept {100*acc/fed:.1f}%  drafts/step {fed/max(1, fed-acc):.2f}  yield gen/fed {gen/fed:.3f}')
for lo in (150, 400):
    big = [r['tps'] for r in rows if r['gen'] >= lo]
    if len(big) >= 2:
        print(f'  long requests (gen>={lo}): n={len(big)} med {st.median(big):.1f} tok/s')
pref = [r['read_tps'] for r in rows if r['reused'] == 0 and r['read_ms'] > 200]
if pref:
    print(f'  fresh prefill (cold reads): n={len(pref)} med {st.median(pref):.1f} tok/s')
cached = [r['reused'] for r in rows if r['reused']]
if cached:
    print(f'  conversation cache hits: n={len(cached)} med reused {st.median(cached):.0f} tokens')
