"""dictate.daemon — always-on capture/transcription daemon.

Push-to-talk: `dictate start-capture` opens the mic, `stop-capture` closes it
and finalizes. Energy VAD cuts segments on silence while held. Each finalized
segment is transcribed with OpenVINO GenAI's WhisperPipeline on the NPU, then
appended to ~/dictation/YYYY-MM-DD.md, copied to the clipboard (wl-copy) and
typed at the keyboard-focused cursor (wtype), with a spinner at the cursor
while the NPU is generating.
"""

from __future__ import annotations

import json
import logging
import os
import queue
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import sounddevice as sd

log = logging.getLogger("dictate")

MODEL = os.environ.get("DICTATE_MODEL", "OpenVINO/whisper-medium-int8-ov")
CACHE_DIR = Path(os.environ.get("DICTATE_CACHE_DIR", os.path.expanduser("~/.cache/dictation")))
MODEL_CACHE = CACHE_DIR / "models"   # HF snapshot dir (kept out of the nix store)
NPU_CACHE = CACHE_DIR / "npu-cache"  # NPU compiled-model cache (first compile ~70 s)
OUT_DIR = Path(os.environ.get("DICTATE_OUT_DIR", os.path.expanduser("~/dictation")))
SOCK_PATH = Path(os.environ.get("DICTATE_SOCKET", os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "dictate.sock")))

SAMPLE_RATE = 16000
BLOCK = 512                                # callback block: 32 ms
PRE_ROLL = 0.3                             # s of audio kept before speech onset
SILENCE_CUT = 0.6                          # s of silence that ends a segment
MIN_SPEECH = 1.2                           # s of speech required before a silence cut
MAX_SEGMENT = 25.0                         # hard cap per segment (GenAI Whisper handles <=30 s)
FINALIZE_MIN = 0.3                         # min speech to transcribe on manual stop
VAD_FLOOR = float(os.environ.get("DICTATE_VAD_FLOOR", "0.004"))
VAD_CEIL = float(os.environ.get("DICTATE_VAD_CEIL", "0.05"))  # threshold cap: below normal speech level
VAD_CALIBRATION = 0.5                      # s of quiet sampling at capture start
VAD_CALIB_SKIP = 0.1                       # s of press-time handling transients ignored

# Dim overlay while the mic is hot: a resident quickshell instance (dim/shell.qml,
# compositor overlay layer, click-through) toggled via `qs ipc`. Empty disables.
# DDC/CI backlight was tried first and rejected (~0.3 s/call + monitor lag) — NOTES.md § dictate
DIM_QS = os.environ.get("DICTATE_DIM_QS", "")
PRE_ROLL_BLOCKS = int(PRE_ROLL * SAMPLE_RATE / BLOCK)
TAIL_BLOCKS = int(0.2 * SAMPLE_RATE / BLOCK)

# Live waveform feed for the dim overlay ("dictating" label replaced by the mic
# trace): min/max of every BLOCK of the actual mic signal, streamed by rewriting
# a tiny tmpfs file each block (~31 Hz). dim/shell.qml FileView-watchChanges it.
# cava rejected: it would re-grab the mic on its own capture path and only
# renders to a terminal. Path+format must match dim/shell.qml.
WAVE_COLS = 150                              # last ~4.8 s of blocks on screen
WAVE_PATH = Path(os.environ.get("DICTATE_WAVE", os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "dictate-wave.txt")))

# Focused-window rect for the dim overlay (window-only dim + centered wave):
# written from `hyprctl activewindow -j` on every dim_on; dim/shell.qml
# FileView-watches it and sizes an unanchored layer surface to the rect.
# "null" (no window / hyprctl failed / hyprctl not on PATH) = full-screen dim.
FOCUS_PATH = Path(os.environ.get("DICTATE_FOCUS", os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "dictate-focus.json")))

# Insert transcribed text at the keyboard-focused cursor with wtype (zwp
# virtual-keyboard; lands in terminals too, unlike a faked Ctrl+V paste).
# "none" disables (clipboard-only). Clipboard is set before inserting either way.
INSERT_MODE = os.environ.get("DICTATE_INSERT", "type")

# Spinner typed at the cursor while the NPU is generating, then BackSpace-d
# (wtype -k BackSpace per codepoint) right before the real text is typed — so
# the cursor shows progress instead of a dead pause after release. Only
# correct while focus doesn't move; cleared on transcription failure and on
# empty results too, so a stray spinner never lingers. "" disables.
PLACEHOLDER = os.environ.get("DICTATE_PLACEHOLDER", "\u2026")  # … rounded ellipsis: 1 codepoint, 1 backspace


_wave_warned = False


def write_focus() -> None:
    """Write the focused-window rect for the overlay (window-only dim).

    activewindow -j gives absolute layout coords; the monitor name is the
    `monitors -j` entry containing the window center (hint for the QML when a
    window straddles screens). No window (activewindow -> {}) or hyprctl
    missing -> file says null and the overlay falls back to full-screen dim.
    """
    if not FOCUS_PATH:
        return
    rect = None
    try:
        hyprctl = shutil.which("hyprctl") or "hyprctl"
        w = json.loads(subprocess.run([hyprctl, "activewindow", "-j"], capture_output=True,
                                      text=True, timeout=5, check=True).stdout)
        x, y = w["at"]
        ww, wh = w["size"]
        mon = ""
        try:
            mons = json.loads(subprocess.run([hyprctl, "monitors", "-j"], capture_output=True,
                                             text=True, timeout=5, check=True).stdout)
            cx, cy = x + ww / 2, y + wh / 2
            mon = next((m["name"] for m in mons
                        if m["x"] <= cx < m["x"] + m["width"]
                        and m["y"] <= cy < m["y"] + m["height"]), "")
        except Exception as e:  # noqa: BLE001 - name is only a straddling hint
            log.debug("monitor lookup failed: %s", e)
        rect = {"x": x, "y": y, "w": ww, "h": wh, "mon": mon}
    except Exception as e:  # noqa: BLE001 - overlay falls back to full-screen
        log.debug("focus rect unavailable: %s", e)
    try:
        FOCUS_PATH.write_text(json.dumps(rect))
    except OSError as e:  # noqa: BLE001
        log.warning("could not write %s: %s", FOCUS_PATH, e)


def write_wave(maxes, mins) -> None:
    """Rewrite the overlay wave file in place (same inode: FileView watches it)."""
    global _wave_warned
    if not DIM_QS or not WAVE_PATH:
        return  # the wave feed exists for the overlay alone: no overlay, no writes
    try:
        WAVE_PATH.write_text(
            " ".join(f"{v:.3f}" for v in maxes) + "\n"
            + " ".join(f"{v:.3f}" for v in mins) + "\n")
    except OSError as e:  # noqa: BLE001 - waveform is cosmetic, never break capture
        if not _wave_warned:  # one warning, not one per block
            log.warning("wave write to %s failed: %s", WAVE_PATH, e)
            _wave_warned = True


class Capture:
    """One push-to-talk hold: stream blocks + energy-VAD state machine.

    Called from the PortAudio callback thread; state is guarded by `lock`
    shared with start/stop from the socket thread.
    """

    def __init__(self, lock, enqueue):
        self.lock = lock
        self.enqueue = enqueue  # callable(audio: np.ndarray, dur: float, spoken: datetime)
        self.blocks: list[np.ndarray] = []
        self.cal_samples: list[float] = []
        self.threshold = VAD_FLOOR
        self.calibrating = True
        self.in_speech = False
        self.seg_start_idx = 0
        self.seg_start_t = 0.0
        self.speech_run = 0.0
        self.silence_run = 0.0
        self.stream: sd.InputStream | None = None
        self.active = False
        self.wave_max = np.zeros(WAVE_COLS, dtype=np.float32)
        self.wave_min = np.zeros(WAVE_COLS, dtype=np.float32)

    def open(self):
        self.wave_max[:] = 0.0
        self.wave_min[:] = 0.0
        write_wave(self.wave_max, self.wave_min)  # clear last session's trace
        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="float32",
            blocksize=BLOCK,
            callback=self._callback,
        )
        self.stream.start()
        self.active = True

    def close_and_finalize(self):
        self.active = False
        if self.stream is not None:
            self.stream.stop()
            self.stream.close()
            self.stream = None
        # Manual stop: take the open segment even though no silence cut fired.
        with self.lock:
            if self.in_speech and self.speech_run >= FINALIZE_MIN:
                self._finalize(len(self.blocks))
                return "finalizing"
            return "discarded (no speech)"

    def _rms(self, block: np.ndarray) -> float:
        return float(np.sqrt(np.mean(np.square(block))))

    def _callback(self, indata, frames, time_info, status):
        if status:
            log.warning("audio status: %s", status)
        x = np.asarray(indata[:, 0], dtype=np.float32).copy()
        dt = frames / SAMPLE_RATE
        with self.lock:
            if not self.active:
                return
            self.blocks.append(x)
            rms = self._rms(x)

            # overlay waveform (also during calibration: shows the mic is live).
            # In-place shift, not np.append: two array allocations per 32 ms
            # block inside an audio callback is avoidable churn.
            self.wave_max[:-1] = self.wave_max[1:]
            self.wave_max[-1] = float(np.max(x))
            self.wave_min[:-1] = self.wave_min[1:]
            self.wave_min[-1] = float(np.min(x))
            write_wave(self.wave_max, self.wave_min)

            if self.calibrating:
                self.cal_samples.append(rms)
                if len(self.cal_samples) * dt >= VAD_CALIBRATION + VAD_CALIB_SKIP:
                    # Noise floor from the LOW end of the window (30th pct): speech
                    # leaking into calibration can't drag it up. Multiplier 4x, hard
                    # cap at VAD_CEIL so calibration can never out-shout normal speech
                    # (a 0.12+ threshold made whole utterances read as silence).
                    noise = np.asarray(self.cal_samples[int(VAD_CALIB_SKIP * SAMPLE_RATE / BLOCK):])
                    p30 = float(np.percentile(noise, 30))
                    self.threshold = min(max(VAD_FLOOR, 4.0 * p30), VAD_CEIL)
                    self.calibrating = False
                    log.info("vad calibrated: threshold=%.4f (p30=%.4f ceil=%.4f)",
                             self.threshold, p30, VAD_CEIL)
                return

            # A hold that never starts speaking fires no cut, so blocks would
            # grow without bound (a 25 min hold is ~60 MB); when idle, keep only
            # what a future onset needs (pre-roll) — the cut path trims the rest.
            if not self.in_speech and len(self.blocks) > PRE_ROLL_BLOCKS:
                self.blocks = self.blocks[-PRE_ROLL_BLOCKS:]

            if rms > self.threshold:
                if not self.in_speech:
                    self.in_speech = True
                    self.seg_start_idx = max(0, len(self.blocks) - 1 - PRE_ROLL_BLOCKS)
                    self.seg_start_t = time.monotonic()
                self.speech_run += dt
                self.silence_run = 0.0
            else:
                self.silence_run += dt

            cut = False
            if self.in_speech:
                if self.silence_run >= SILENCE_CUT and self.speech_run >= MIN_SPEECH:
                    cut = True
                elif time.monotonic() - self.seg_start_t >= MAX_SEGMENT:
                    cut = True
            if cut:
                self._finalize(len(self.blocks) - int(self.silence_run * SAMPLE_RATE / BLOCK) + TAIL_BLOCKS)

    def _finalize(self, end_idx: int):
        """Slice [seg_start_idx, end_idx) and hand it to the worker. Caller holds the lock."""
        end_idx = max(self.seg_start_idx, min(end_idx, len(self.blocks)))
        audio = np.concatenate(self.blocks[self.seg_start_idx:end_idx]) if end_idx > self.seg_start_idx else None
        dur = audio.size / SAMPLE_RATE if audio is not None else 0.0
        # Stamp at capture time, not transcription completion: publish() writes
        # it as the note heading, and a backed-up queue would otherwise push
        # headings past the moment the words were spoken.
        self.enqueue(audio, dur, datetime.now())
        # Start the next segment after the cut; drop consumed prefix to bound memory.
        keep_from = min(self.seg_start_idx, len(self.blocks) - PRE_ROLL_BLOCKS)
        if keep_from > 0:
            self.blocks = self.blocks[keep_from:]
            self.seg_start_idx = 0
        self.in_speech = False
        self.speech_run = 0.0
        self.silence_run = 0.0


class Daemon:
    def __init__(self):
        # Reentrant: serve()'s SIGTERM handler runs on this thread while it may
        # already hold the lock (inside handle()) — a plain Lock would deadlock
        # there, wedge the daemon, and leave the socket file behind.
        self.lock = threading.RLock()
        self.state = "loading"
        self.pipe = None
        self.segments = 0
        self.busy = False  # worker is mid-transcription (shutdown drain, see serve())
        self.error: str | None = None  # set by load_model on failure
        self.q: queue.Queue = queue.Queue()
        self.capture: Capture | None = None
        self.qs: subprocess.Popen | None = None  # dim overlay instance (dim/shell.qml)
        self.dim_lock = threading.RLock()  # qs spawn + IPC; shared with the dim-warm thread
        self.placeholder_on = False  # spinner is sitting at the cursor (worker thread only)

    # ── model ──────────────────────────────────────────────────────────────
    def load_model(self):
        """Runs on its own thread; a failure must not wedge the daemon as 'loading'."""
        try:
            self._load_model()
        except Exception:
            log.exception("model load failed")
            self.state = "error"
            self.error = "model load failed — see daemon log; restarting the daemon may help"

    def _load_model(self):
        from huggingface_hub import snapshot_download
        import openvino_genai as ov_genai

        t0 = time.monotonic()
        log.info("fetching model %s into %s", MODEL, MODEL_CACHE)
        path = snapshot_download(MODEL, cache_dir=str(MODEL_CACHE))
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
        self.pipe = ov_genai.WhisperPipeline(path, "NPU", CACHE_DIR=str(NPU_CACHE))
        task = os.environ.get("DICTATE_TASK", "").strip()
        lang = os.environ.get("DICTATE_LANGUAGE", "").strip()
        if task or lang:
            gen = self.pipe.get_generation_config()
            if task:
                # NOTE: task=translate is IGNORED by whisper-*-turbo-*-ov exports in
                # GenAI 2026.4 (int8 and fp16, NPU and CPU). whisper-medium-int8-ov
                # handles it correctly -> model default in configuration.nix is medium.
                gen.task = task
            if lang:
                gen.language = lang
            self.pipe.set_generation_config(gen)
            log.info("generation config: task=%s language=%s", gen.task, gen.language or "auto")
        self.state = "ready"
        log.info("model ready in %.1f s", time.monotonic() - t0)

    # ── transcription ──────────────────────────────────────────────────────
    def enqueue(self, audio, dur, spoken: datetime):
        if audio is None or audio.size == 0:
            return
        self.q.put((audio, dur, spoken))

    def worker(self):
        while True:
            audio, dur, spoken = self.q.get()
            self.busy = True
            try:
                t0 = time.monotonic()
                self.show_placeholder()
                try:
                    result = self.pipe.generate(audio)
                    text = result.texts[0].strip()
                except Exception:
                    log.exception("transcription failed")
                    self.clear_placeholder()
                    continue
                log.info("segment %.1fs transcribed in %.2fs", dur, time.monotonic() - t0)
                if text:
                    with self.lock:
                        self.segments += 1
                    self.publish(text, dur, spoken)
                else:
                    self.clear_placeholder()  # noise-only segment: don't strand the spinner
                if not self.q.empty():
                    self.show_placeholder()  # more segments queued: spinner between texts
            finally:
                # task_done + busy flag: serve()'s shutdown drain uses both to
                # wait out in-flight finalizations instead of dropping them.
                self.q.task_done()
                self.busy = False

    # ── cursor spinner while the NPU generates ─────────────────────────────
    # Types PLACEHOLDER at the cursor when generation starts; publish()
    # backspaces it right before the real text. Single worker thread, so
    # placeholder_on needs no lock.
    def _wtype(self, *args: str) -> bool:
        """wtype with these args; False on any failure (inserts are best-effort)."""
        wtype = shutil.which("wtype")
        if wtype is None:
            log.warning("DICTATE_INSERT=type but wtype is not on PATH")
            return False
        try:
            r = subprocess.run([wtype, *args], timeout=30, check=False,
                               capture_output=True, text=True)
        except Exception as e:  # noqa: BLE001 - no focus/no input = clipboard only
            log.warning("wtype insert failed: %s", e)
            return False
        if r.returncode != 0:
            log.warning("wtype %r failed: %s", args[0], (r.stderr or r.stdout).strip())
            return False
        return True

    def show_placeholder(self):
        if INSERT_MODE != "type" or not PLACEHOLDER or self.placeholder_on:
            return
        self.placeholder_on = self._wtype("--", PLACEHOLDER)

    def clear_placeholder(self):
        if not self.placeholder_on:
            return
        self.placeholder_on = False
        for _ in PLACEHOLDER:  # one BackSpace per codepoint
            self._wtype("-k", "BackSpace")

    def publish(self, text: str, dur: float, spoken: datetime):
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        now = spoken
        md = OUT_DIR / f"{now:%Y-%m-%d}.md"
        new = not md.exists()
        with md.open("a", encoding="utf-8") as f:
            if new:
                f.write(f"# Dictation {now:%Y-%m-%d}\n")
            f.write(f"\n## {now:%H:%M} ({dur:.1f}s)\n\n{text}\n")
        log.info("appended to %s", md)

        # Clipboard first: insertion needs focus, so this is what makes the text
        # unlosable. (notify-send popup retired 2026-11-14: the text appearing at
        # the cursor IS the feedback.)
        try:
            subprocess.run([shutil.which("wl-copy") or "wl-copy"],
                           input=text.encode("utf-8"), timeout=10, check=False)
        except Exception as e:  # noqa: BLE001 - clipboard is best-effort
            log.warning("wl-copy failed: %s", e)

        if INSERT_MODE == "type":
            # Swap the cursor spinner for the real text. (Re-shown by worker()
            # if more segments are still queued.)
            self.clear_placeholder()
            self._wtype("--", text)

    # ── dim overlay (compositor-side; see dim/shell.qml) ───────────────────
    # A resident quickshell instance (spawned lazily, kept warm) toggled via
    # `qs ipc call dim show|hide`. Chosen over DDC/CI backlight: instant, no
    # per-monitor I2C round trips — NOTES.md § dictate
    def ensure_qs(self) -> bool:
        """Make sure the overlay instance is running; returns False if unusable."""
        if not DIM_QS:
            return False
        with self.dim_lock:  # also spawnable from the dim-warm thread during model load
            if self.qs is not None and self.qs.poll() is None:
                return True
            qs = shutil.which("qs") or "qs"
            try:
                self.qs = subprocess.Popen([qs, "-p", DIM_QS],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                write_wave(np.zeros(WAVE_COLS), np.zeros(WAVE_COLS))  # file exists before first press
            except OSError as e:  # noqa: BLE001 - dim is cosmetic, never block capture
                log.warning("could not spawn dim overlay (qs -p %s): %s", DIM_QS, e)
                return False
            return True

    def dim_on(self):
        """Show the dim overlay, respawning the qs instance once if its ipc is dead.

        Never runs under self.lock: the audio callback needs it every 32 ms block
        and blocking it there drops frames right at press time — the qs spawn and
        IPC share dim_lock instead. A show that lands after dim_off (signal
        handler racing the start path) is undone by the recheck below.
        """
        if not self.ensure_qs():
            return
        write_focus()  # window-targeted dim: geometry first, then show
        qs = shutil.which("qs") or "qs"

        def call(cmd: str) -> subprocess.CompletedProcess:
            return subprocess.run([qs, "-p", DIM_QS, "ipc", "call", "dim", "--", cmd],
                                  capture_output=True, text=True, timeout=5, check=False)

        try:
            with self.dim_lock:
                r = call("show")
                if r.returncode != 0:
                    # instance not up (cold spawn or crash): wait briefly, retry once
                    if self.qs is not None and self.qs.poll() is None:
                        deadline = time.monotonic() + 3.0
                        while time.monotonic() < deadline:
                            time.sleep(0.2)
                            r = call("show")
                            if r.returncode == 0:
                                break
                    if r.returncode != 0:
                        log.warning("dim show failed: %s", r.stderr.strip() or r.stdout.strip())
                        return
                if not (self.capture is not None and self.capture.active):
                    call("hide")  # capture already stopped: best-effort corrective hide
        except Exception as e:  # noqa: BLE001
            log.warning("dim show failed: %s", e)

    def dim_off(self):
        if not DIM_QS or self.qs is None or self.qs.poll() is not None:
            return
        qs = shutil.which("qs") or "qs"
        try:
            with self.dim_lock:
                subprocess.run([qs, "-p", DIM_QS, "ipc", "call", "dim", "--", "hide"],
                               capture_output=True, timeout=5, check=False)
        except Exception as e:  # noqa: BLE001
            log.warning("dim hide failed: %s", e)

    # ── capture control ────────────────────────────────────────────────────
    def start_capture(self) -> str:
        with self.lock:
            if self.state == "loading":
                return "ERR model is still loading"
            if self.state == "error":
                return f"ERR {self.error}"
            if self.state != "ready":
                return f"ERR daemon state is {self.state}"
            if self.capture is not None and self.capture.active:
                return "ERR already capturing"
            self.capture = Capture(self.lock, self.enqueue)
            try:
                self.capture.open()
            except Exception as e:  # noqa: BLE001 - report a clean error over the socket
                self.capture = None
                log.exception("could not open microphone")
                return f"ERR audio: {e}"
            self.state = "capturing"
            # dim_on below (5 s IPC timeouts, ~3 s retry loop) must NOT run under
            # the lock: the audio callback needs it every 32 ms block, and blocking
            # it there drops frames right at press time.
        self.dim_on()
        return "OK capturing"

    def stop_capture(self) -> str:
        with self.lock:
            if self.capture is None or not self.capture.active:
                return "ERR not capturing"
            cap, self.capture = self.capture, None
            # Flip state under the lock, before the dim/finalize work below: a
            # start that slips in during dim_off/finalize would otherwise be
            # clobbered back to "ready" while the new capture is live.
            self.state = "ready"
        self.dim_off()
        # close_and_finalize re-acquires the lock; call it outside.
        outcome = cap.close_and_finalize()
        return f"OK {outcome}"

    # ── socket protocol ────────────────────────────────────────────────────
    def handle(self, line: str) -> str:
        cmd = line.strip()
        if cmd == "start":
            return self.start_capture()
        if cmd == "stop":
            return self.stop_capture()
        if cmd == "status":
            with self.lock:
                cap_active = self.capture is not None and self.capture.active
                segments = self.segments
            return json.dumps({
                "state": "capturing" if cap_active else self.state,
                "model": MODEL,
                "segments": segments,
                "error": self.error,
                "socket": str(SOCK_PATH),
            })
        return "ERR unknown command"

    def serve(self):
        if SOCK_PATH.exists():
            try:
                # stale socket from a dead daemon? ping it first.
                probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                probe.settimeout(1)
                probe.connect(str(SOCK_PATH))
                probe.close()
                log.error("another daemon is already answering on %s", SOCK_PATH)
                sys.exit(1)
            except OSError:
                SOCK_PATH.unlink()
        # bind() creates the socket with umask-default perms and there is a
        # window before the chmod below; bind under a restrictive umask instead
        # (XDG_RUNTIME_DIR is already 0700, but the /tmp fallback is 1777).
        old_umask = os.umask(0o077)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(str(SOCK_PATH))
        os.umask(old_umask)
        os.chmod(str(SOCK_PATH), 0o600)
        srv.listen(8)

        if DIM_QS:  # warm the overlay instance during model load so the first press is instant
            threading.Thread(target=self.ensure_qs, name="dim-warm", daemon=True).start()

        def shutdown(*_):
            try:
                self.stop_capture()
            except Exception:  # noqa: BLE001
                pass
            # Drain queued finalizations before exiting: the worker is a daemon
            # thread and exit() would otherwise drop the user's last utterances.
            # Bounded — a segment transcribes in seconds, so hang no longer than
            # 10 s even if the NPU stalls.
            deadline = time.monotonic() + 10.0
            while (not self.q.empty() or self.busy) and time.monotonic() < deadline:
                time.sleep(0.2)
            if self.qs is not None:  # synchronous: leaving it orphaned would keep the dim up
                self.qs.terminate()
                try:
                    self.qs.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.qs.kill()
                self.qs = None
            SOCK_PATH.unlink(missing_ok=True)
            sys.exit(0)

        signal.signal(signal.SIGTERM, shutdown)
        signal.signal(signal.SIGINT, shutdown)

        log.info("listening on %s (model=%s)", SOCK_PATH, MODEL)
        while True:
            conn, _ = srv.accept()
            try:
                # The CLIs send the whole one-line command immediately; a client
                # that connects and stalls must not hold the accept loop for 5 s.
                conn.settimeout(2)
                data = conn.recv(4096)
                if data:
                    reply = self.handle(data.decode("utf-8", "replace"))
                    conn.sendall(reply.encode("utf-8") + b"\n")
            except OSError as e:
                log.warning("socket error: %s", e)
            finally:
                conn.close()


def run():
    logging.basicConfig(level=logging.INFO, stream=sys.stdout,
                        format="%(asctime)s %(levelname)s %(message)s")
    d = Daemon()
    threading.Thread(target=d.load_model, name="model", daemon=True).start()
    threading.Thread(target=d.worker, name="transcribe", daemon=True).start()
    d.serve()
