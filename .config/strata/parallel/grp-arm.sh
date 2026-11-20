#!/usr/bin/env bash
# grp-arm.sh (parallel tree, qwen3.8-flash-next-iq3_s) — one arm of the batch-slot-pipeline sweep
# (engine 0.1.62 / image 0.2.16). See PARALLEL-SWEEP-PLAN.md.
#
# Same shape as tune-ctx.sh (edit -> stop -> reload -> era archive -> assert -> bench) but every knob
# is written into the PRESET's `extra` map, because the run config (strata-iq3_s.json) is regenerated
# from the preset on each start and its own `env` map does not survive a relaunch on this tree
# (the 1slot tree hit exactly this on 2026-11-19; ab-arm.sh now asserts it too).
#
#   ./grp-arm.sh <label> [envk=NAME=VAL,...] [flag=--name=VAL,...] [unset=NAME,...]
#                  [want=RE,...] [forbid=RE,...] [levels="1 2 3"] [rounds=3] [--no-bench]
#
#   envk=  bare STRATA_* keys -> preset extra (this is how the live pins ADAPT_LAG/SPLIT_RING/
#          PF_FUSED/EXCHANGE_ROTATE get to the engine; `env=` in the run config does NOT).
#          Never write "off"/"false"/"no": strata_cli reads those as "remove the pin". Write "0".
#   flag=  engine argv flags -> preset extra ("--batch-groups" "3").
#   unset= drop those keys from preset extra (back to control).
#   want=  regexes that MUST appear in the era's boot log (default: the async tier line, which the
#          notes say --batch-groups can refuse -> an arm that loses it is confounded).
#   forbid=regexes that must NOT appear.
#
# Artifacts: .tune/<label>.{era,boot.txt,assert.txt,bench.txt,csv}
set -u
TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=$TREE/strata/launch-presets/docker.json
C=qwen3.8-flash-next-iq3_s-parallel
ENGINE_ID=qwen3.8-flash-next-iq3_s
L=/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state/strata/launch/docker.engine.log
OUT=$TREE/.tune
PORT=5802
LEVELS="1 2 3"
ROUNDS=3
mkdir -p "$OUT"

LABEL=${1:?label required}; shift || true
ENVSET=(); FLAGS=(); UNSET=(); WANT=(); FORBID=(); BENCH=1
for a in "$@"; do
  case "$a" in
    envk=*)   IFS=',' read -ra t <<< "${a#envk=}"; ENVSET+=("${t[@]}");;
    flag=*)   IFS=',' read -ra t <<< "${a#flag=}"; FLAGS+=("${t[@]}");;
    unset=*)  IFS=',' read -ra t <<< "${a#unset=}"; UNSET+=("${t[@]}");;
    want=*)   IFS=',' read -ra t <<< "${a#want=}"; WANT+=("${t[@]}");;
    forbid=*) IFS=',' read -ra t <<< "${a#forbid=}"; FORBID+=("${t[@]}");;
    levels=*) LEVELS=${a#levels=};;
    rounds=*) ROUNDS=${a#rounds=};;
    --no-bench) BENCH=0;;
    *) echo "unknown arg: $a" >&2; exit 2;;
  esac
done
[ -f "$P.bak-20261119-pre-grpsweep" ] || cp -a "$P" "$P.bak-20261119-pre-grpsweep"

# 1. edit the preset
KEYS=() VALS=()
for kv in "${ENVSET[@]+"${ENVSET[@]}"}"; do KEYS+=("${kv%%=*}"); VALS+=("${kv#*=}"); done
for kv in "${FLAGS[@]+"${FLAGS[@]}"}"; do KEYS+=("${kv%%=*}"); VALS+=("${kv#*=}"); done
KEYS_S=$(printf '%s\n' "${KEYS[@]+"${KEYS[@]}"}") VALS_S=$(printf '%s\n' "${VALS[@]+"${VALS[@]}"}") \
UNSET_S=$(printf '%s\n' "${UNSET[@]+"${UNSET[@]}"}")
KEYS="$KEYS_S" VALS="$VALS_S" UNSET="$UNSET_S" python3 - "$P" <<'PY'
import json, os, sys
P = sys.argv[1]
keys = [x for x in os.environ.get('KEYS', '').split('\n') if x]
vals = [x for x in os.environ.get('VALS', '').split('\n') if x]
drop = [x for x in os.environ.get('UNSET', '').split('\n') if x]
d = json.load(open(P))
for k, v in zip(keys, vals):
    d['extra'][k] = v
for k in drop:
    d['extra'].pop(k, None)
json.dump(d, open(P, 'w'), indent=2, sort_keys=True); open(P, 'a').write('\n')
print('  preset extra now: %s' % ' '.join('%s=%s' % i for i in sorted(d['extra'].items())))
PY
# the edit must be on disk BEFORE the restart, or the boot is a control wearing the arm's label
KEYS="$KEYS_S" VALS="$VALS_S" UNSET="$UNSET_S" python3 - "$P" <<'PY' || exit 1
import json, os, sys
d = json.load(open(sys.argv[1]))['extra']
bad = []
for k, v in zip([x for x in os.environ.get('KEYS','').split('\n') if x],
                [x for x in os.environ.get('VALS','').split('\n') if x]):
    if d.get(k) != v: bad.append('%s should be %r, preset has %r' % (k, v, d.get(k)))
for k in [x for x in os.environ.get('UNSET','').split('\n') if x]:
    if k in d: bad.append('%s should be gone, preset has %r' % (k, d[k]))
if bad:
    print('  PRESET EDIT FAILED: ' + '; '.join(bad), file=sys.stderr); sys.exit(1)
PY

# 2. stop + reload
echo "--- stop/reload ($C) ---"
podman stop -t 120 "$C" >/dev/null; sleep 2
curl -s -m 190 http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d "{\"model\":\"$C\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
  -o /dev/null -w 'reload=%{http_code} t=%{time_total}\n'

# 3. era slice (pin --batch N from the preset, never a hardcoded slot count)
EXP=$(python3 -c "import json;print(json.load(open('$P')).get('parallel',''))")
N=$(grep -an "engine started:.*pack /data/Strata-data/packs/iq3_s.*--batch [0-9]\+$" "$L" | tail -1 | cut -d: -f1)
ACT=$(sed -n "${N}p" "$L" | grep -oE -- '--batch [0-9]+' | grep -oE '[0-9]+')
echo "  era line $N boots --batch ${ACT:-?} (preset parallel=$EXP)"
{ [ -n "$EXP" ] && [ "$EXP" = "${ACT:-}" ]; } || { echo "  ERA MISMATCH - STOP" >&2; exit 1; }
echo "$N" > "$OUT/$LABEL.era"
tail -n +$N "$L" > "$OUT/$LABEL.boot.txt"

# 4. assertions: the knob must reach the engine process AND change the boot log
PID=$(podman inspect -f '{{.State.Pid}}' "$C")
EPID=""
for p in $(pgrep -f 'components/engine/.*--serve'); do
  a0=$(tr '\0' '\n' < /proc/$p/cmdline 2>/dev/null | head -1) || continue
  [ "${a0##*/}" = strata ] && EPID=$p && break
done
{
  echo "engine pid=${EPID:-none}"
  for k in "${KEYS[@]+"${KEYS[@]}"}"; do
    case "$k" in --*) continue;; esac   # argv flags land in the cmdline, checked below
    if [ -n "$EPID" ] && tr '\0' '\n' < /proc/$EPID/environ | grep -qxF -- "$k=$(python3 -c "import json;print(json.load(open('$P'))['extra']['$k'])")"; then
      echo "  extra-env LIVE   $k"
    else
      echo "  extra-env MISSING $k   <-- arm did not reach the engine"
    fi
  done
  for k in "${UNSET[@]+"${UNSET[@]}"}"; do
    case "$k" in
      --*) if tr '\0' '\n' < /proc/${EPID:-0}/cmdline 2>/dev/null | grep -qxF -- "$k"; then
             echo "  should-be-gone STILL IN ARGV $k"
           else
             echo "  gone as asked      $k (argv)"
           fi ;;
      *)   if [ -n "$EPID" ] && tr '\0' '\n' < /proc/$EPID/environ | grep -qE "^$k="; then
             echo "  should-be-gone STILL SET $k"
           else
             echo "  gone as asked      $k"
           fi ;;
    esac
  done
  echo "  argv: $(tr '\0' ' ' < /proc/${EPID:-0}/cmdline | grep -oE -- '--(batch|batch-groups|batch-mtp|pipeline-windows|spec|spec-min-p|layer-split)[ =][^ ]*' | tr '\n' ' ')"
  echo "  argv has batch-groups: $(tr '\0' '\n' < /proc/${EPID:-0}/cmdline | grep -c -- '--batch-groups')"
  # What the boot log must / must not show, derived from the PRESET (the authority) rather than this
  # call's edit list, so a re-run of the same config boots under the same assertions.
  # --batch-groups refuses --adapt-async ("adapt-async 1 is off (not with --batch-groups (the pipelined
  # slot groups)): the blocking adaptive tier"), so a groups boot must show the blocking tier instead.
  PG=$(python3 -c "import json;print(json.load(open('$P'))['extra'].get('--batch-groups',''))")
  PM=$(python3 -c "import json;print(json.load(open('$P'))['extra'].get('STRATA_PIPED_MTP',''))")
  if [ -n "$PG" ] && [ "$PG" != 1 ]; then
    WANT+=( 'the blocking adaptive tier' )
    FORBID+=( 'adaptive tier asynchronous' 'WARNING: --batch-groups' )
    if [ -n "$PM" ]; then
      WANT+=( 'STRATA_PIPED_MTP: [0-9]+ pipelined group' )
      FORBID+=( 'WARNING: STRATA_PIPED_MTP is off' )
    fi
  else
    WANT+=( 'adaptive tier asynchronous \(--adapt-async 1\)' )
    FORBID+=( 'adapt-async 1 is off' 'WARNING: --batch-groups' )
  fi
  FORBID+=( 'LOW:' 'not enough room' 'out of memory' 'exited: 1' 'more than [0-9]+ rows per window' )
  for re in "${WANT[@]}"; do
    c=$(sed -n "${N},\$p" "$L" | grep -acE -- "$re" || true)
    [ "$c" -gt 0 ] && echo "  log OK    $re" || echo "  log MISS  $re   <-- confounded arm"
  done
  for re in "${FORBID[@]}"; do
    c=$(sed -n "${N},\$p" "$L" | grep -acE -- "$re" || true)
    [ "$c" -eq 0 ] && echo "  clean     $re" || echo "  log BAD   $re ($c)"
  done
  echo "  batch-window lines:"
  sed -n "${N},\$p" "$L" | grep -aE 'batch-groups|pipelined batch windows|STRATA_PIPED|pipeline-windows|batch \(pipelined|strata batch: [0-9]+ windows|prompt kernels' | cut -c1-200 | sed 's/^/    /' | head -12
} | tee "$OUT/$LABEL.assert.txt"

BAD=$(grep -cE 'MISSING|MISS|BAD|STILL SET|confounded' "$OUT/$LABEL.assert.txt" || true)
[ "$BAD" = 0 ] || echo "!!! $BAD assertion problem(s) — read $OUT/$LABEL.assert.txt before trusting any number"

if [ "$BENCH" = 0 ]; then exit 0; fi
echo "--- bench ($ROUNDS rounds, levels $LEVELS, 400 tok) ---"
python3 "$TREE/bench-util.py" --url "http://127.0.0.1:$PORT" --model "$ENGINE_ID" --container "$C" \
  --levels $LEVELS --rounds "$ROUNDS" --max-tokens 400 --csv "$OUT/$LABEL.csv" 2>&1 | tee "$OUT/$LABEL.bench.txt"

echo "--- engine-side window accounting for this era ---"
python3 - "$L" "$N" <<'PY'
import re, sys, statistics as st
L, n = sys.argv[1], int(sys.argv[2])
lines = open(L, errors="replace").readlines()[n:]
for pat, tag in ((r"strata batch: (\d+) windows, avg ([\d.]+) rows, ([\d.]+) ms/window = run [\d.]+ \(CUDA0 GPU-reach wait ([\d.]+) \+ CPU experts ([\d.]+)", "serial windows"),
                 (r"strata batch \(pipelined, (\d+) groups of (\d+)\): (\d+) group-steps, (\d+) rows in (\d+) ms = ([\d.]+) rows/s", "pipelined groups"),
                 (r"strata verify: pipelined batch windows commit after the verdict \(layers \[(-?\d+), (-?\d+)\), (\d+) rows, ([\d.]+) MiB saved rows\)", "saved rows"),
                 (r"suffix drafts: (\d+) windows, (\d+) of (\d+) drafts accepted", "suffix drafts"),
                 (r"decode expert cache hit rate: ([\d.]+)%", "cache hit %")):
    ms = [m for m in (re.search(pat, l) for l in lines) if m]
    if not ms:
        print("  %-16s none in this era" % tag); continue
    last = ms[-1]
    print("  %-16s n=%d  last: %s" % (tag, len(ms), " ".join(g if g is not None else "?" for g in last.groups())))
cap = [int(c.group(1)) for c in (re.search(r"capturing the \d+-token window \((\d+) MiB", l) for l in lines) if c]
if cap: print("  window capture: n=%d min %d MiB free (floor 512)" % (len(cap), min(cap)))
PY
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader
