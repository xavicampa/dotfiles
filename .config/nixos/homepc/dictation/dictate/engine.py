"""dictate.engine — the Whisper pipeline both entrypoints share.

daemon.py loads this in-process; whisperd.py serves it over HTTP (llama-swap
backend). Same model dir, same NPU compile cache, same generation_config
workaround, so whichever one runs warms the same on-disk caches
(~/.cache/dictation).
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path

log = logging.getLogger("dictate.engine")

MODEL = os.environ.get("DICTATE_MODEL", "OpenVINO/whisper-medium-int8-ov")
CACHE_DIR = Path(os.environ.get("DICTATE_CACHE_DIR", os.path.expanduser("~/.cache/dictation")))
MODEL_CACHE = CACHE_DIR / "models"   # HF snapshot dir (kept out of the nix store)
NPU_CACHE = CACHE_DIR / "npu-cache"  # NPU compiled-model cache (first compile ~70 s)


def build_pipeline(model: str = MODEL, task: str = "", language: str = ""):
    """Download/patch/compile; returns a ready ov_genai.WhisperPipeline (NPU).

    Blocking (~10 s with warm caches, minutes on the first NPU compile); callers
    own the threading story.
    """
    import resource

    from huggingface_hub import snapshot_download
    import openvino_genai as ov_genai

    # The NPU compiler (level-zero) mlocks its DMA/weight buffers and marks them
    # PROT_READ|WRITE — "can't protect" under a small RLIMIT_MEMLOCK. The user
    # manager chain gives infinity (NOTES.md § memlock) but **system** services
    # start from the 8 MiB default, which is what llama-swap spawns whisperd with.
    # Hard limit is unlimited here, so raising the soft limit is allowed; if the
    # hard limit ever drops below infinity, keep it and log instead of dying.
    soft, hard = resource.getrlimit(resource.RLIMIT_MEMLOCK)
    if soft != resource.RLIM_INFINITY:
        try:
            resource.setrlimit(resource.RLIMIT_MEMLOCK, (resource.RLIM_INFINITY, hard))
            log.info("raised RLIMIT_MEMLOCK %s -> infinity (hard %s)", soft, hard)
        except (ValueError, OSError) as e:
            log.warning("could not raise RLIMIT_MEMLOCK (soft %s hard %s): %s", soft, hard, e)

    log.info("fetching model %s into %s", model, MODEL_CACHE)
    path = snapshot_download(model, cache_dir=str(MODEL_CACHE))
    # The OpenVINO export ships forced_decoder_ids=[[1,null],[2,50360]] which hard-pins
    # the <|transcribe|> token; GenAI honors it over WhisperGenerationConfig.task, so
    # translate silently never fires. Drop it and let the config own the prefix.
    gc_path = Path(path) / "generation_config.json"
    if gc_path.exists():
        gc = json.loads(gc_path.read_text())
        if "forced_decoder_ids" in gc:
            del gc["forced_decoder_ids"]
            gc_path.chmod(0o644)
            gc_path.write_text(json.dumps(gc, indent=2))
            log.info("patched %s: dropped forced_decoder_ids (was forcing <|transcribe|>)", gc_path)
    log.info("compiling pipeline on NPU (first compile may take ~1 minute)...")
    pipe = ov_genai.WhisperPipeline(path, "NPU", CACHE_DIR=str(NPU_CACHE))
    if task or language:
        gen = pipe.get_generation_config()
        if task:
            # NOTE: task=translate is IGNORED by whisper-*-turbo-*-ov exports in
            # GenAI 2026.4 (int8 and fp16, NPU and CPU). whisper-medium-int8-ov
            # handles it correctly -> model default in configuration.nix is medium.
            gen.task = task
        if language:
            gen.language = language
        pipe.set_generation_config(gen)
        log.info("generation config: task=%s language=%s", gen.task, gen.language or "auto")
    return pipe


def set_task_language(pipe, task: str, language: str) -> None:
    """Per-request task/language override on an already-built pipeline.

    Safe without a lock only where one worker thread serves all requests
    (daemon worker, whisperd's single-threaded server).
    """
    gen = pipe.get_generation_config()
    if task and gen.task != task:
        gen.task = task
    if language and (gen.language or "") != language:
        gen.language = language
    pipe.set_generation_config(gen)
