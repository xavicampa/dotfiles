#!/usr/bin/env bash
# tune-arm.sh — one arm, switched identically: edit -> stop -> reload -> boot archive -> gate -> bench.
#
#   ./tune-arm.sh <label> [split=N] [kv=N] [frac=X] [mtp=on|off] [vision=gpu|cpu]
#                          [cc=MIB] [ccslots=N] [ccmin=N] [gain=N] [minfree=N] [--no-bench]
#
# cc = --conversation-cache-mib (RAM pool for parked conversations; 0 = off), ccslots = -slots,
# ccmin = -min-tokens, gain = -park-gain, minfree = -min-free-mib. These five are kept in step in
# BOTH carriers (preset extra and the run config args) - see TUNING_NOTES.md "merge order".
#   ROUNDS=2 ./tune-arm.sh ...        # bench rounds per boot (default 1)
#
# Anything you do not pass stays as-is. Artifacts land in <tree>/.tune/ (boot.txt, bench.txt, era line no.).
# The gate decides whether a bench is worth running: stage-1 must hold every profiled pair it owns, both
# stages must keep >=512 MiB free, and no LOW/WARNING/OOM in the boot. A failed gate costs one reload only.
set -u
TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=$TREE/strata/launch-presets/docker.json
R=$TREE/strata-iq3_s.json
C=qwen3.8-flash-next-iq3_s
L=/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state/strata/launch/docker.engine.log
OUT=$TREE/.tune
ROUNDS=${ROUNDS:-1}
mkdir -p "$OUT"

LABEL=${1:?label required}; shift || true
BENCH=1; PAIRS=()
for a in "$@"; do
  case "$a" in
    split=*)  PAIRS+=("--layer-split|${a#split=}");;
    kv=*)     PAIRS+=("--kv-resident|${a#kv=}");;
    frac=*)   PAIRS+=("--pcie-frac|${a#frac=}");;
    mtp=on)   PAIRS+=("STRATA_MTP_STAGE0|1");;
    mtp=off)  PAIRS+=("STRATA_MTP_STAGE0|");;
    vision=*) VISION=${a#vision=};;
    cc=*)      PAIRS+=("--conversation-cache-mib|${a#cc=}");;
    ccslots=*) PAIRS+=("--conversation-cache-slots|${a#ccslots=}");;
    ccmin=*)   PAIRS+=("--conversation-cache-min-tokens|${a#ccmin=}");;
    gain=*)    PAIRS+=("--conversation-cache-park-gain|${a#gain=}");;
    minfree=*) PAIRS+=("--conversation-cache-min-free-mib|${a#minfree=}");;
    --no-bench) BENCH=0;;
    *) echo "unknown arg: $a" >&2; exit 2;;
  esac
done

python3 - "$P" "$R" "${VISION:-keep}" $(printf '%s\n' "${PAIRS[@]+"${PAIRS[@]}"}") <<'PY'
import json, sys
P, R, vis, *pairs = sys.argv[1:]
d = json.load(open(P))
for p in pairs:
    k, v = p.split("|", 1)
    if v: d["extra"][k] = v
    else: d["extra"].pop(k, None)
json.dump(d, open(P, "w"), indent=2, sort_keys=True); open(P, "a").write("\n")
r = json.load(open(R))
if vis != "keep":
    r["vision"]["gpu"] = (vis == "gpu")
# conversation-cache flags live in the run config args too; the preset wins on the merge, but the
# manual run-iq3_s.sh path reads the run config alone, so mirror the value there (notes: "both carriers").
a, synced = r["args"], []
for p in pairs:
    k, v = p.split("|", 1)
    if k in a:
        i = a.index(k)
        if v: a[i + 1] = v
        else: del a[i:i + 2]
        synced.append(k)
r_changed = vis != "keep" or synced
if r_changed:
    json.dump(r, open(R, "w"), indent=1); open(R, "a").write("\n")
print("  split=%s kv=%s frac=%s mtp_stage0=%s vision.gpu=%s" % (
    d["extra"].get("--layer-split"), d["extra"].get("--kv-resident"), d["extra"].get("--pcie-frac"),
    d["extra"].get("STRATA_MTP_STAGE0", "(absent)"), r["vision"]["gpu"]))
print("  cc: " + " ".join("%s=%s" % (k.replace("--conversation-cache-", ""),
      d["extra"].get(k, "(default)")) for k in ("--conversation-cache-mib", "--conversation-cache-slots",
      "--conversation-cache-min-tokens", "--conversation-cache-park-gain", "--conversation-cache-min-free-mib")))
if synced: print("  also synced in run config args:", ",".join(synced))
PY

echo "--- stop/reload ---"
podman stop -t 120 $C >/dev/null; sleep 2
curl -s -m 190 http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d "{\"model\":\"$C\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
  -o /dev/null -w 'reload=%{http_code} t=%{time_total}\n'

N=$(grep -an "engine started:.*packs/iq3_s" "$L" | tail -1 | cut -d: -f1)
echo "$N" > "$OUT/$LABEL.era"
tail -n +$N "$L" > "$OUT/$LABEL.boot.txt"
grep -aE "layer split: CUDA1 runs|of the experts resident|expert cache auto:|MiB of VRAM free with everything loaded|KV streaming: [0-9]+ of [0-9]+ cells|resident RAM mode:|strata mtp: draft layer" "$OUT/$LABEL.boot.txt" | sed 's/^\[strata\] [0-9 :-]*//' | cut -c1-190

python3 - "$OUT/$LABEL.boot.txt" <<'PY' || { echo "--- bench skipped (boot gate) ---"; exit 1; }
import re, sys
t = open(sys.argv[1], errors="replace").read()
p = re.search(r"expert cache (\d+) slots \(([\d.]+) GiB\), (\d+) of its (\d+) profiled pairs", t)
f = [re.search(r"serve: (\d+) MiB of VRAM free", t), re.search(r"serve: CUDA1: (\d+) MiB of VRAM free", t)]
bad = re.findall(r"LOW:|not enough room|out of memory|exited: 1", t)
ok = bool(p) and p.group(3) == p.group(4) and all(x and int(x.group(1)) >= 512 for x in f) and not bad
print("  stage1 %s/%s  free %s/%s  GATE %s%s" % (p.group(3) if p else "?", p.group(4) if p else "?",
      f[0].group(1) if f[0] else "?", f[1].group(1) if f[1] else "?", "PASS" if ok else "FAIL",
      "" if not bad else " " + ",".join(sorted(set(bad)))))
sys.exit(0 if ok else 1)
PY

cc_counters() {
  echo "--- conversation cache counters (this era) ---"
  python3 "$TREE/cc-counters.py" "$N" | tail -n +2
}
cc_counters
if [ "$BENCH" = 0 ]; then echo "--- bench skipped (--no-bench) ---"; exit 0; fi
echo "--- bench ($ROUNDS round(s)) ---"
cd "$TREE" && python3 bench-1slot.py "$ROUNDS" 2>&1 | tee "$OUT/$LABEL.bench.txt" | grep -aE "^ +[ABCD] |memory during"

echo "--- KV VRAM hit rate by context size (this era only) ---"
python3 - "$L" "$N" <<'PY'
import re, sys, statistics as st
L, n = sys.argv[1], int(sys.argv[2])
req = re.compile(r"strata serve: prompt (\d+) tokens")
kvl = re.compile(r"KV streaming: ([\d.]+)% of (\d+) block reads hit VRAM, ([\d.]+) MiB read from RAM")
prompt, rows = None, []
for i, line in enumerate(open(L, errors="replace"), 1):
    if i < n: continue
    m = req.search(line)
    if m: prompt = int(m.group(1)); continue
    m = kvl.search(line)
    if m and prompt: rows.append((prompt, float(m.group(1)), int(m.group(2)), float(m.group(3))))
for lo, hi, lab in ((1500, 40000, "<40K"), (40000, 110000, "40-110K"), (110000, 180000, "110-180K"), (180000, 400000, ">180K")):
    b = [r for r in rows if lo <= r[0] < hi and r[2] > 50000]
    if b: print("  %-9s n=%-3d hit med %6.2f%% worst %6.2f%%  MiB from RAM med %7.1f max %8.1f" % (
        lab, len(b), st.median(r[1] for r in b), min(r[1] for r in b), st.median(r[3] for r in b), max(r[3] for r in b)))
PY
timeout 180 python3 /home/javi/.config/strata/parallel/erastats.py --pack iq3_s 2>&1 | sed -n '1,3p'
cc_counters
