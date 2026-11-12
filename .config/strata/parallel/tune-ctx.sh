#!/usr/bin/env bash
# tune-arm.sh (parallel tree, qwen3.8-flash-next-iq3_s) — one arm, switched identically: edit -> stop ->
# reload -> boot archive -> gate -> bench. Same shape as coder/tune-arm.sh; the knob lives in the run
# config's `env` map:#
#   * 0.2.9's speed knobs are all STRATA_* env, and 0.1.55's serve/server.py applies the run
#     config's `env` map to the engine child (child_env, line ~3759) BEFORE parallel_stack_env/
#     gdn_stack_env, both of which setdefault. So an `env` entry in strata-iq3_s.json
#     wins over the 0.2.9 defaults and needs NO nixos-rebuild — only this script's stop+reload.
#   * the 1slot tree uses the SAME pack (packs/iq3_s) and the same native GGUF, so the era grep pins --batch N,
#     which only this tree's arm carries. N is now read from the preset (slots=), NOT hardcoded — a grep pinned to
#     an old value returns the PREVIOUS era and every stat after it describes a different boot (that bug lived
#     here until 2026-10-31; it pinned `--batch 4$` after the arm had moved to 3).
#     (TUNING_NOTES.md said "no env layer": that was verified on 0.1.54. Re-verified here on 0.1.55.)
#   * the container name is the PROXY id (…-parallel): the reload curl uses it. The bench uses
#     the ENGINE id qwen3.8-flash-next-iq3_s on the ENGINE port from `-e PORT` (5803).
#
#   ./tune-arm.sh <label> [gdn=on|off] [par=on|off] [env=NAME=VAL,...] [split=N] [kv=N] [frac=X] [slots=N]
#                   [spec=N] [specminp=X] [workers=N] [--no-bench]
#
#   gdn=off  -> env STRATA_GDN_TC=0 STRATA_GDN_CONVL2=0        (pre-0.2.9 Gated DeltaNet prompt path)
#   gdn=on   -> those two removed, wrapper re-applies 1 / 2
#   par=off  -> the nine PARALLEL_STACK_ENV vars set to 0       (pre-0.2.9 slot/ckpt path)
#   par=on   -> those nine removed
#   env=NAME=VAL,...  extra config env (e.g. env=STRATA_COALESCE_PREFILL=1)
#   env-clear -> drop every 0.2.9-stack key from the config
#   levels=1,3  which concurrency levels to bench (default "1 3"; this arm's queue is 3 slots)
#   slots=N    preset top-level `parallel` (== engine --batch): the KV slots, i.e. the batch-row ceiling
#              (N slots x 2 draft positions). A/B'd 2026-10-31: rows/s is flat (~185-190) across 3 and 4, so a 4th
#              slot buys NO engine speed — only queue avoidance (+10.5% agg at 4 real clients), for CUDA1 -290 MiB,
#              -4.2% CUDA0 expert cache and ~250-300 MiB less window-capture margin. Bench `--levels 3 4` with it.
#   spec=N      preset extra `--spec N`     — drafts offered per step (drafting depth)
#   specminp=X  preset extra `--spec-min-p X` — the acceptance gate a draft must clear to be offered
#               Both live ONLY in preset `extra` on this tree (the run config has no user_args; its `args`
#               are regenerated each start, so they are cosmetic). Assert the boot argv carries them.
#   workers=N   preset extra `--pool-workers N`. Default here is 15 = 8 P-cores (logicals 0-7,
#               5.4-5.5 GHz) + half the E-cores (logicals 8-15, 4.7 GHz), host pinned on a P-core
#               (logical 4); logicals 16-23 are the aux CPUs. Raise it and WATCH the boot's
#               `N pool workers on logical processors ...` + `strata aux cpus:` lines — the extra
#               workers land on E-cores, which are ~13 % slower per task, and they steal aux CPUs.
#   probe=TOKENS  also send a unique long prompt of ~TOKENS tokens per round (GDN/prefill arms: the
#                 bench prompts are ~30 tokens, which is fixed overhead and shows nothing; the vendor
#                 numbers are at 4K-32K). Judge from the era's cold reads, which the runner prints.
#
#   ROUNDS=2 ./tune-arm.sh ...   # bench rounds per boot (default 1)
# Artifacts: .tune/<label>.{boot.txt,bench.txt,csv,era}. A failed gate costs one reload, not a bench.
set -u
TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=$TREE/strata/launch-presets/docker.json
R=$TREE/strata-iq3_s.json
C=qwen3.8-flash-next-iq3_s-parallel          # container == proxy id
ENGINE_ID=qwen3.8-flash-next-iq3_s
PORT=$(podman inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$C" 2>/dev/null | sed -n 's/^PORT=//p')
L=/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state/strata/launch/docker.engine.log
OUT=$TREE/.tune
ROUNDS=${ROUNDS:-1}
mkdir -p "$OUT"
[ -n "${PORT:-}" ] || { echo "PORT not readable from podman inspect of $C" >&2; exit 2; }

LABEL=${1:?label required}; shift || true
BENCH=1; PAIRS=(); ENVSET=(); ENVDEL=(); CLEAR=0; LEVELS="1 4"; PROBE=0; SLOTS=""; CTX=""
GDN=(STRATA_GDN_TC STRATA_GDN_CONVL2)
PAR=(STRATA_CKPT_POOL STRATA_CKPT_POOL_READY STRATA_SLOT_CKPT_MOVE STRATA_SLOT_COPY_DIRECT \
     STRATA_SLOT_COPY_BATCHSYNC STRATA_BATCH_GDN_GROUPS STRATA_BATCH_ATTN_ROWS STRATA_BATCH_SELF_COMMIT STRATA_QSA_SLOTS)
for a in "$@"; do
  case "$a" in
    gdn=off)  for k in "${GDN[@]}"; do ENVSET+=("$k=0"); done;;
    gdn=on)   for k in "${GDN[@]}"; do ENVDEL+=("$k"); done;;
    par=off)  for k in "${PAR[@]}"; do ENVSET+=("$k=0"); done;;
    par=on)   for k in "${PAR[@]}"; do ENVDEL+=("$k"); done;;
    env-clear) CLEAR=1;;
    env=*)    ENVSET+=("${a#env=}");;
    split=*)  PAIRS+=("--layer-split|${a#split=}");;
    ctx=*)    PAIRS+=("--max-context|${a#ctx=}"); CTX=${a#ctx=};;
    kv=*)     PAIRS+=("--kv-resident|${a#kv=}");;
    frac=*)   PAIRS+=("--pcie-frac|${a#frac=}");;
    spec=*)   PAIRS+=("--spec|${a#spec=}");;
    specminp=*) PAIRS+=("--spec-min-p|${a#specminp=}");;
    workers=*) PAIRS+=("--pool-workers|${a#workers=}");;
    levels=*) LEVELS=${a#levels=};;
    slots=*)  SLOTS=${a#slots=};;
    probe=*)  PROBE=${a#probe=};;
    --no-bench) BENCH=0;;
    *) echo "unknown arg: $a" >&2; exit 2;;
  esac
done

SLOTS="$SLOTS" CTX="$CTX" python3 - "$P" "$R" $(printf '%s\n' "${PAIRS[@]+"${PAIRS[@]}"}") -- $(printf '%s\n' "${ENVSET[@]+"${ENVSET[@]}"}") -- $(printf '%s\n' "${ENVDEL[@]+"${ENVDEL[@]}"}") "$CLEAR" <<'PY'
import json, os, sys
P, R = sys.argv[1:3]
rest = sys.argv[3:]
cuts = [i for i, x in enumerate(rest) if x == "--"]
pairs = rest[:cuts[0]] if cuts else rest
after = rest[cuts[0] + 1:] if cuts else []
envset = after[:after.index("--")] if "--" in after else after
envdel = after[after.index("--") + 1:] if "--" in after else []
clear = (envdel and envdel[-1] == "1")

d = json.load(open(P))
for p in pairs:
    k, v = p.split("|", 1)
    d["extra"][k] = v
ctx = os.environ.get("CTX")
if ctx:
    d["context"] = int(ctx)   # keep the reuse-test half in step
if os.environ.get("SLOTS"):
    d["parallel"] = int(os.environ["SLOTS"])   # top-level, NOT extra: serve --parallel / --max-queue follow it
json.dump(d, open(P, "w"), indent=2, sort_keys=True); open(P, "a").write("\n")

r = json.load(open(R))
env = dict(r.get("env") or {})
for kv in envset:
    k, v = kv.split("=", 1)
    env[k] = v
for k in envdel:
    if k != "1":
        env.pop(k, None)
if clear:
    env = {}
if env:
    r["env"] = env
else:
    r.pop("env", None)
json.dump(r, open(R, "w"), indent=1); open(R, "a").write("\n")
print("  preset: split=%s kv=%s frac=%s spec=%s spec-min-p=%s pool-workers=%s parallel(slots)=%s" % (d["extra"].get("--layer-split"), d["extra"].get("--kv-resident"), d["extra"].get("--pcie-frac"), d["extra"].get("--spec"), d["extra"].get("--spec-min-p"), d["extra"].get("--pool-workers"), d.get("parallel")))
print("  run-config env (%d): %s" % (len(env), " ".join("%s=%s" % i for i in sorted(env.items())) or "(none - 0.2.9 defaults win)"))
PY

echo "--- stop/reload (container $C, proxy id) ---"
podman stop -t 120 "$C" >/dev/null; sleep 2
curl -s -m 190 http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d "{\"model\":\"$C\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
  -o /dev/null -w 'reload=%{http_code} t=%{time_total}\n'

# Any --batch, then assert the matched boot carries the value the preset now holds (see the header note).
EXP=$(python3 -c "import json;print(json.load(open('$P')).get('parallel',''))" 2>/dev/null)
N=$(grep -an "engine started:.*pack /data/Strata-data/packs/iq3_s.*--batch [0-9]\+$" "$L" | tail -1 | cut -d: -f1)
ACT=$(sed -n "${N}p" "$L" | grep -oE -- '--batch [0-9]+' | grep -oE '[0-9]+')
echo "  era line $N boots --batch ${ACT:-?} (preset parallel=$EXP)"
[ -z "$EXP" ] || [ "$EXP" = "${ACT:-}" ] || { echo "  ERA MISMATCH: boot argv says ${ACT:-?}, preset says $EXP — the grep matched an older boot. STOP." >&2; exit 1; }
echo "$N" > "$OUT/$LABEL.era"
tail -n +$N "$L" > "$OUT/$LABEL.boot.txt"
sed 's/^\[strata\] [0-9 :-]*//' "$OUT/$LABEL.boot.txt" | grep -aE "layer split: CUDA1 runs|of the experts resident|MiB of VRAM free with everything loaded|strata-vision|prompt experts|file tier \(Linux defaults|KV streaming: [0-9]+ of" | cut -c1-190

echo "--- engine child env (what the arm ACTUALLY runs; config env is not in podman inspect) ---"
podman exec "$C" sh -c '
for p in $(ls /proc 2>/dev/null | grep -E "^[0-9]+$"); do
  if grep -qa "components/engine" "/proc/$p/cmdline" 2>/dev/null; then
    tr "\0" "\n" < "/proc/$p/environ" 2>/dev/null | grep -E "STRATA_(GDN_TC|GDN_CONVL2|GDN_CHUNKED|CKPT_POOL|CKPT_POOL_READY|SLOT_CKPT_MOVE|SLOT_COPY_DIRECT|SLOT_COPY_BATCHSYNC|BATCH_GDN_GROUPS|BATCH_ATTN_ROWS|BATCH_SELF_COMMIT|QSA_SLOTS|COALESCE_PREFILL|PAR_COUNTERS|DEFAULTS)=" | sort | sed "s/^/    /"
    break
  fi
done'

python3 - "$OUT/$LABEL.boot.txt" <<'PY' || { echo "--- bench skipped (boot gate) ---"; exit 1; }
import re, sys
t = open(sys.argv[1], errors="replace").read()
p = re.search(r"expert cache (\d+) slots \(([\d.]+) GiB\), (\d+) of its (\d+) profiled pairs", t)
f = [re.search(r"serve: (\d+) MiB of VRAM free", t), re.search(r"serve: CUDA1: (\d+) MiB of VRAM free", t)]
bad = re.findall(r"LOW:|not enough room|out of memory|exited: 1|parallel override conflicts", t)
ok = bool(p) and p.group(3) == p.group(4) and all(x and int(x.group(1)) >= 512 for x in f) and not bad
print("  stage1 %s/%s  free %s/%s  GATE %s%s" % (p.group(3) if p else "?", p.group(4) if p else "?",
      f[0].group(1) if f[0] else "?", f[1].group(1) if f[1] else "?", "PASS" if ok else "FAIL",
      "" if not bad else " " + ",".join(sorted(set(bad)))))
sys.exit(0 if ok else 1)
PY

if [ "$BENCH" = 0 ]; then echo "--- bench skipped (--no-bench) ---"; exit 0; fi
if [ "$PROBE" -gt 0 ]; then
  echo "--- long cold-read probe (~$PROBE tokens x $ROUNDS, unique per round) ---"
  python3 - "http://127.0.0.1:$PORT" "$ENGINE_ID" "$PROBE" "$ROUNDS" <<'PY'
import urllib.request, json, random, time, sys
url, model, target, rounds = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
for r in range(rounds):
    rnd, nonce = random.Random(r * 7919 + time.time_ns()), f"n{r}-{random.Random(r).randint(10**8,10**9)}"
    words = [" ".join(rnd.choice(["alpha","bravo","charlie","delta","echo","foxtrot","golf","kilo",
                                    "lima","november","tango","sierra","uniform","victor","whiskey",
                                    "xray","yankee","zulu"]) for _ in range(6)) for _ in range(max(1, target // 12))]
    body = {"model": model, "max_tokens": 1, "temperature": 0, "stream": True,
            "messages": [{"role": "user", "content": nonce + "\n" + "\n".join(words) +
                         f"\n\nAnswer with the single word: {nonce}"}]}
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(url.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}), timeout=900) as resp:
        for _ in resp: pass
    print(f"  round {r}: wall {time.time() - t0:6.2f} s  (chars {len(body['messages'][0]['content'])})", flush=True)
PY
fi

echo "--- cold prompt read, live log from this era (the stable +-1% control; unique probes only) ---"
python3 - "$L" "$N" <<'PY'
import re, sys, statistics as st
L, n = sys.argv[1], int(sys.argv[2])
lines = open(L, errors="replace").readlines()[n:]
rows = [(int(m.group(1)), int(m.group(2)), float(m.group(5))) for line in lines for m in
        [re.search(r"prompt (\d+) tokens = (\d+) reused \+ (\d+) read in (\d+) ms \(([\d.]+) tok/s\)", line)]
        if m and int(m.group(2)) == 0 and int(m.group(1)) >= 1500]
for lo, hi in ((1500, 6000), (10000, 20000)):
    b = [r for r in rows if lo <= r[0] < hi]
    if b: print("  %5d-%5d n=%d  %s | med %.0f tok/s" % (lo, hi, len(b),
          " ".join("%d->%.0f" % (r[0], r[2]) for r in b), st.median(r[2] for r in b)))
PY

echo "--- bench ($ROUNDS round(s), levels $LEVELS, 400 tok) ---"
python3 /home/javi/.config/strata/parallel/bench-util.py \
  --url "http://127.0.0.1:$PORT" --model "$ENGINE_ID" --container "$C" \
  --levels $LEVELS --rounds "$ROUNDS" --max-tokens 400 \
  --csv "$OUT/$LABEL.csv" 2>&1 | tee "$OUT/$LABEL.bench.txt"

echo "--- engine-side stats for this era ---"
timeout 180 python3 /home/javi/.config/strata/parallel/erastats.py --pack iq3_s 2>&1 | sed -n '1,4p'
echo "--- window accounting + window-capture margin for this era (the slot-knob instruments) ---"
python3 - "$L" "$N" <<'PY'
import re, sys, statistics as st
L, n = sys.argv[1], int(sys.argv[2])
lines = open(L, errors="replace").readlines()[n:]
w = [m for m in (re.search(r"strata batch: (\d+) windows, avg ([\d.]+) rows, ([\d.]+) ms/window = run [\d.]+ \(CUDA0 GPU-reach wait ([\d.]+) \+ CPU experts ([\d.]+)", l) for l in lines) if m]
if w:
    rows, ms = st.median([float(x.group(2)) for x in w]), st.median([float(x.group(3)) for x in w])
    print("  rows %s ms/window %s -> rows/s %.0f | GPU-reach %s ms  CPU-experts %s ms (rows/s, not rows/window,"
          " is what a slot adds or costs)" % (rows, ms, 1000 * rows / ms,
          st.median([float(x.group(4)) for x in w]), st.median([float(x.group(5)) for x in w])))
else:
    print("  no window lines yet in this era")
cap = [int(c.group(1)) for c in (re.search(r"capturing the \d+-token window \((\d+) MiB", l) for l in lines) if c]
if cap:
    print("  window capture: n=%d min %d MiB free (floor 512; this pool is what context growth eats)" % (len(cap), min(cap)))
PY
nvidia-smi --query-gpu=index,memory.used,memory.total,utilization.gpu --format=csv,noheader
