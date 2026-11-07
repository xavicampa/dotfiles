#!/usr/bin/env bash
# ab-arm.sh (1slot tree, qwen3.8-flash-next-iq3_s @ ctx 262144, engine 0.1.58) — one arm per call:
# edit -> stop -> reload -> assert the boot really carries the knob -> gate -> probes.
#
# WHY A DIFFERENT RUNNER FROM parallel/tune-arm.sh: this tree is launched by the image entrypoint's `run`
# (llama-swap nix entry qwen3.8-flash-next-iq3_s -> podman run ... :latest-cuda13 run), so the config the
# serve layer reads is the volume's state file, NOT the tree copy:
#     python3 -m serve.server --engine strata --config /data/state/strata/launch/docker.json
# and the arg layer that survives a relaunch is the PRESET (strata/launch-presets/docker.json `extra`,
# plus the top-level `drafting` / `parallel` / `context` keys), which flows preset -> docker.choices.json
# -> docker.json. ~/.config/strata/1slot/strata-iq3_s.json is a stale Nov-4 copy (no --kv-resident,
# --pcie-frac 0.00 while the live boot runs 0.20/32768) — never edit it as if it were live.
#
#   ./ab-arm.sh <label> [--measure-only] [extra=--flag|value[,...]] [extra-del=--flag]
#                     [drafting=auto|mtp|dflash2|off] [env=NAME=VAL[,...]] [env-clear]
#                     [want=substr[,...]] [p40k=N] [p120k=N]
#
#   extra=      writes preset extra (durable: the preset is the source for engine args on this tree)
#   drafting=   preset top-level drafting (0.2.10+: one drafter per run; the engine sees --draft <name>)
#   env=        writes an `env` map into the CONFIG THE ENGINE IS STARTED FROM (state docker.json).
#               serve/server.py:4344 child_env applies cfg["env"]; the /proc audit below is what proves
#               it survived the relaunch — if the launch regenerated docker.json the value is gone and
#               the arm is dead, so the script STOPS rather than benching a no-op.
#   want=       substring(s) the boot argv must carry (assertion), e.g. want=--pipeline-windows 0
#   p40k / p120k  probe rounds (default 2 and 1)
# Artifacts: .tune/<label>.{era,boot.txt,probes.txt}. pi is served by this engine: no background sweeps.
set -u
TREE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P=$TREE/strata/launch-presets/docker.json
VOL=/home/javi/.local/share/containers/storage/volumes/strata-data/_data
DCON=$VOL/state/strata/launch/docker.json
L=$VOL/state/strata/launch/docker.engine.log
C=qwen3.8-flash-next-iq3_s          # container name == llama-swap proxy id == PI_MODEL
OUT=$TREE/.tune; mkdir -p "$OUT"
MEASURE=0; EXTRA=(); EDEL=(); DRAFT=""; ENVSET=(); ENVCLEAR=0; WANT=(); N40=2; N120=1

LABEL=${1:?label required}; shift || true
WL=${WL:-11500}   # long-probe words ~ tokens for this word list (calibrated: 11500 words -> 11602 tokens)
for a in "$@"; do
  case "$a" in
    wl=*)        WL=${a#wl=};;
    --measure-only) MEASURE=1;;
    extra=*)     EXTRA+=("${a#extra=}");;
    extra-del=*) EDEL+=("${a#extra-del=}");;
    drafting=*)  DRAFT=${a#drafting=};;
    env-clear)   ENVCLEAR=1;;
    env=*)       ENVSET+=("${a#env=}");;
    want=*)      WANT+=("${a#want=}");;
    p40k=*)      N40=${a#p40k=};;
    p120k=*)     N120=${a#p120k=};;
    *) echo "unknown arg: $a" >&2; exit 2;;
  esac
done

if [ "$MEASURE" != 1 ]; then
  EXTRA="${EXTRA[*]}" EDEL="${EDEL[*]}" DRAFT="$DRAFT" ENVSET="${ENVSET[*]}" ENVCLEAR="$ENVCLEAR" python3 - "$P" "$DCON" <<'PY'
import json, os, sys
P, DCON = sys.argv[1:3]
extra = [x for x in os.environ.get("EXTRA", "").split(",") if x.strip()]
edel  = [x for x in os.environ.get("EDEL", "").split(",") if x.strip()]
draft = os.environ.get("DRAFT", "")
envset = [x for x in os.environ.get("ENVSET", "").split(",") if x.strip()]
clear  = os.environ.get("ENVCLEAR") == "1"

d = json.load(open(P))
for kv in extra:
    k, v = kv.split("|", 1); d["extra"][k.strip()] = v
for k in edel: d["extra"].pop(k.strip(), None)
if draft: d["drafting"] = draft
json.dump(d, open(P, "w"), indent=2, sort_keys=True); open(P, "a").write("\n")
print("  preset: drafting=%s extra=%s" % (d.get("drafting"), json.dumps(d["extra"], sort_keys=True)))

if envset or clear:
    c = json.load(open(DCON))
    env = {} if clear else dict(c.get("env") or {})
    for kv in envset:
        k, v = kv.split("=", 1); env[k.strip()] = v
    if env: c["env"] = env
    else: c.pop("env", None)
    json.dump(c, open(DCON, "w"), indent=2); open(DCON, "a").write("\n")
    print("  state-config env (%d): %s" % (len(env), " ".join("%s=%s" % i for i in sorted(env.items())) or "(none)"))
PY
  echo "--- stop/reload (container $C) ---"
  podman stop -t 120 "$C" >/dev/null; sleep 2
  curl -s -m 240 http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' \
    -d "{\"model\":\"$C\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
    -o /dev/null -w 'reload=%{http_code} t=%{time_total}\n'
fi

# era = the newest 1slot boot; --max-context 262144 is this tree's marker (parallel/iq3_s runs 131072 and
# the 1slot tree shares packs/iq3_s with it, so a pack-only grep can land on the other tree's boot).
N=$(grep -an "engine started:.*packs/iq3_s.*--max-context 262144" "$L" | tail -1 | cut -d: -f1)
LINE=$(sed -n "${N}p" "$L")
echo "  era line $N: $(printf '%s' "$LINE" | grep -oE '\-\-(pipeline-windows|max-context|draft|max-tokens|pcie-frac|kv-resident|layer-split|mtp|batch)( [^ ]+)?' | tr '\n' ' ')"
for w in "${WANT[@]+"${WANT[@]}"}"; do
  case "$LINE" in *"$w"*) echo "  want ok: $w";; *) echo "  WANT MISSING: '$w' not in the boot argv — arm is dead, STOP." >&2; exit 1;; esac
done
echo "$N" > "$OUT/$LABEL.era"; tail -n +$N "$L" > "$OUT/$LABEL.boot.txt"
sed 's/^\[strata\] [0-9 :-]*//' "$OUT/$LABEL.boot.txt" | grep -aE "layer split: CUDA1 runs|of the experts resident|MiB of VRAM free with everything loaded|draft layer|dflash2|drafter|mtp:|LOW |WARNING|out of memory" | cut -c1-190

echo "--- engine child argv+env (what the arm ACTUALLY runs) ---"
podman exec "$C" sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do grep -qa components/engine /proc/$p/cmdline 2>/dev/null && grep -av vision /proc/$p/cmdline >/dev/null 2>/dev/null && { echo "  argv:"; tr "\0" "\n" < /proc/$p/cmdline | grep -E "^--(draft|mtp|pipeline-windows|spec|spec-min-p)$|^--(draft|mtp|pipeline-windows|spec|spec-min-p) " | tr "\n" " "; echo; echo "  env:"; tr "\0" "\n" < /proc/$p/environ | grep -E "^STRATA_(ADAPT_FETCH|SELECT_TWO_PASS|GDN|CKPT_POOL|PF_FUSED|SPLIT_RING|ADAPT_LAG|EXCHANGE_ROTATE)" | sort | tr "\n" " "; echo; }; done' 2>/dev/null

if [ "${#ENVSET[@]}" -gt 0 ] || [ "$ENVCLEAR" = 1 ]; then
  for kv in "${ENVSET[@]+"${ENVSET[@]}"}"; do
    k=${kv%%=*}
    if podman exec "$C" sh -c 'for p in $(ls /proc | grep -E "^[0-9]+$"); do grep -qa components/engine/0.1.58[^/]*/strata /proc/$p/cmdline 2>/dev/null && tr "\0" "\n" < /proc/$p/environ | grep -qxF "$1" && echo yes; done' _ "$kv" | grep -q yes; then
      echo "  env LIVE: $kv"
    else
      echo "  env NOT LIVE: $kv — the relaunch did not carry it (launch regenerates the state config). Arm dead, STOP." >&2; exit 1
    fi
  done
fi

echo "--- probes: greedy, unique prefix (nonce first, so no reuse); long probe words=$WL ---"
python3 - "$LABEL" "$N40" "$N120" "$WL" <<'PY' > "$OUT/$LABEL.probes.txt" 2>&1
import json, random, sys, time, urllib.request
label, n40, n120, wl = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
def send(prompt, maxtok):
    body = json.dumps({"model": "qwen3.8-flash-next-iq3_s", "max_tokens": maxtok, "temperature": 0,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    t = time.time()
    r = json.load(urllib.request.urlopen(urllib.request.Request("http://localhost:8080/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"}), timeout=600))
    u = r.get("usage", {})
    print("%-8s wall %6.2f s  prompt_tokens %-7s completion_tokens %s" % (label, time.time()-t,
          u.get("prompt_tokens"), u.get("completion_tokens")), flush=True)
words = "cache store expert layer token window stream weight matrix batch kernel copy stage buffer offset row block dense gate query key value head norm scale shift reduce fold patch tile rank stride depth width plane sweep".split()
for i in range(n40):
    n = random.randint(10**9, 10**10)
    p = "NONCE-%d-%d " % (n, i) + " ".join(random.choice(words) for _ in range(3900)) + \
        "\nNow write a detailed technical explanation of how a two-GPU expert cache with adaptive swaps works. " \
        "Aim for at least 400 words and do not stop early."
    send(p, 600)
for i in range(n120):
    n = random.randint(10**9, 10**10)
    p = "NONCE-%d-L%d " % (n, i) + " ".join(random.choice(words) for _ in range(wl)) + \
        "\nNow write a detailed technical explanation of how a two-GPU expert cache with adaptive swaps works. " \
        "Aim for at least 150 words and do not stop early."
    send(p, 200)
PY
cat "$OUT/$LABEL.probes.txt"

M0=$(date +%s)
echo "--- engine lines for this era (cold reads / decode / drafts) ---"
tail -n +$N "$L" | grep -aE "prompt [0-9]+ tokens = 0 reused|[0-9]+ generated in [0-9]+ ms" | tail -8 | sed 's/^\[strata\] [0-9 :-]*//' | cut -c1-170
echo "--- host RAM (MemAvailable) ---"; awk '/MemAvailable/{printf "  %.0f MiB\n",$2/1024}' /proc/meminfo
