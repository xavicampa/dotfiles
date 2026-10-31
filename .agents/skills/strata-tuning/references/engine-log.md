# The Strata engine log

Both containers append to one file:

```
/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state/strata/launch/docker.engine.log
```

Inside the container it is `/data/state/strata/launch/docker.engine.log`. llama-swap's `cmdStop` runs `strata-log-stop` (archives, then `podman stop -t 120`), which writes an archive per stop under `/home/javi/.local/state/strata-logs/<UTC>-<model-id>/` (`docker.engine.log`, `launch-docker*.server.log`, `context.txt`, `docker.choices.json`); `index.txt` and `samples*.csv` (10 s host/GPU/request samples from `strata-toksample`) live beside it. Those `strata-*` helpers are on the *service's* PATH, not an interactive shell's — from here, stop with plain `podman stop -t 120 <container>`. `unloadTimeout = 40` in the llama-swap config bounds only the hook, so an unload timeout logged there while the engine flushes its KV cache is normal.

## An era = one boot

```bash
L=/home/javi/.local/share/containers/storage/volumes/strata-data/_data/state/strata/launch/docker.engine.log
n=$(grep -an "engine started:.*pack /data/Strata-data/packs/coder-iq1_m" "$L" | tail -1 | cut -d: -f1)
tail -n +$n "$L" | grep -aE "<pattern>"
```

Pick the pack path for the tree (`coder-iq1_m`, `iq3_s`); `engine started:` carries the **effective** command line — read it first, it is the merged truth (preset `extra` + env + run config). Pin the era by that command line when the knob under test is in it (e.g. end the grep with `--batch 3$`) — but keep it a range like `--batch [0-9]+$` if the knob is *what you are changing*, and assert afterwards that the matched line carries the value the preset now holds:

```bash
sed -n "${n}p" "$L" | grep -oE -- '--batch [0-9]+'      # boot argv == the arm you think you booted?
```

A grep pinned to a stale value (`--batch 4$` after the arm moved to 3) silently returns the **previous** era — every
stat below it then describes a different boot. The runner had that bug; `slots=` now drives both the preset and the grep.

**Timestamps are not comparable across sources.** The engine log's `engine started:` stamp is **UTC**; `podman inspect`
`.Created` / `.State.StartedAt` are **local**. A container that restarted 3 s ago can look "an hour old" next to the log
(+0100 CET). To tell whether a boot line belongs to the current era, compare the **log line number** (era start line,
from the grep above) to the file's length, or convert: `date -u -d "$(podman inspect -f '{{.State.StartedAt}}' $C)"`.

## Boot lines that decide an arm

| grep -E pattern | what it tells you |
|---|---|
| `layer split across 2 GPUs` / `layer split: layers` | stage order + split boundary (labels follow `--gpu` order) |
| `of the experts resident` | residency; `<100%` = RAM/paged expert path in the critical path |
| `expert cache auto:` / `expert cache [0-9]` | how many slots each stage took, `+0 MiB for the draft head`, the `1024 MiB reserved` |
| `MiB of VRAM free with everything loaded` | per-stage headroom; a second such line prefixed `CUDA1:` is the other stage |
| `LOW` | a stage under the window-graph floor (~512 MiB) — reject the arm |
| `slot sessions on CUDA` | KV per slot per stage, grows with the stage's layer span |
| `batch-mtp:` | where the slot drafters sit |
| `strata mtp: draft layer loaded` | the draft layer's VRAM (experts + dense split) |
| `strata-vision:` | `on the CPU, N threads, no warm-up` vs `warmed up at N image tokens in X s` |
| `PCIe probe:` / `CUDA0 link` | host→device transfer, prices expert misses only (0 when 100% resident) |
| `CPU pool:` / `resident RAM mode:` | CPU expert workers, page-locked GiB (memory-wall arm) |
| `pipeline-windows` / `adaptive overlap` | stage overlap — present only without `--batch` |
| `WARNING` / `not enough room` / `out of memory` / `exited: 1` | reject |
| `parallel override conflicts with --batch/--slots` | preset `parallel`/`gpus` fighting `--batch` in run-config args |

## Per-request lines

`erastats.py --pack <tree-pack>` parses; the shape is:

```
strata serve: prompt <N> tokens = <R> reused + <N-R> read in <ms> (<prefill tok/s>), <gen> generated in <ms> (<decode tok/s>), drafts accepted <A> of <O>
```

Read decode only from requests with `gen>=150` (400 is better); prefill only from `reused = 0` cold reads. `reused` is the conversation-cache hit. Acceptance is aggregated over the era (`accept`, `drafts/step = fed/(fed-accepted)`, `yield gen/fed`).

## Prefill / image prompts

- `strata prefill: layer-major off for this prompt: an image prompt` — image prompts take a different prefill path.
- `mtmd_helper_bitmap_init_from_buf: failed to decode buffer` = the client sent an undecodable image, not an engine fault.
- `load_hparams: if you encounter problems with accuracy, try adding --image-min-tokens 1024` = the vision token cap is limiting spatial sampling (`vision.max_tokens` in the run config).

## Decode-window stress

```
WARNING: a decode window ...
```
appears when KV/graph room runs out mid-generation; also watch `capturing the N-token window (... MiB of VRAM free)` lines — the free number there is what each window graph needed.
