"""dictate whisperd — Whisper (OpenVINO GenAI, NPU) as a llama-swap backend.

llama-swap starts this like any `cmd` model and proxies
/v1/audio/transcriptions to it (the request's multipart `model` field routes
it here; the body arrives verbatim). Serving contract:

  GET  /                    -> status json (llama-swap preload hits this)
  GET  /health              -> 200 once the pipeline is loaded (checkEndpoint)
  POST /v1/audio/transcriptions
       multipart: file=<wav>, model=..., task=translate|transcribe,
       language=<whisper code, empty = auto>, response_format=json (only)
       -> {"text": "..."}

Audio contract: PCM16 mono 16 kHz wav — what `dictate daemon` sends; anything
else is a 400 (the GenAI pipeline wants raw 16 kHz float samples; decoding or
resampling other formats isn't worth stdlib-only code when the only client is
our own daemon).

Single-threaded by design: one request at a time, no locks around the
pipeline, and dictation segments arrive one at a time anyway.

Run standalone for testing (llama-swap passes --port itself):
    whisperd --port 5899
"""

from __future__ import annotations

import argparse
import http.server
import io
import json
import logging
import os
import sys
import time
import wave
from email import policy
from email.parser import BytesParser

import numpy as np

from . import engine

log = logging.getLogger("dictate.whisperd")

SAMPLE_RATE = 16000
DEFAULT_PORT = 5899  # standalone only; llama-swap passes its allocated port


class State:
    def __init__(self, task: str, language: str):
        self.pipe = None
        self.error: str | None = None
        self.task = task        # default task (DICTATE_TASK)
        self.language = language  # default language (DICTATE_LANGUAGE); "" = auto
        self.segments = 0


def parse_multipart(content_type: str, body: bytes) -> dict[str, tuple[str, bytes]]:
    """multipart/form-data -> {name: (filename, bytes)}.

    stdlib-only (no `cgi`, gone in 3.13): hand the Content-Type header + body
    to the email MIME parser, which is exactly the parser multipart is defined
    by (RFC 2046/2388).
    """
    head = f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode()
    msg = BytesParser(policy=policy.default).parsebytes(head + body)
    out: dict[str, tuple[str, bytes]] = {}
    if not msg.is_multipart():
        return out
    for part in msg.get_payload():
        name = part.get_param("name", header="content-disposition")
        if not name:
            continue
        data = part.get_payload(decode=True) or b""
        out[name] = (part.get_filename() or "", data)
    return out


def wav_to_samples(data: bytes) -> np.ndarray:
    """PCM16 mono 16 kHz wav -> float32 in [-1, 1) (what pipe.generate takes)."""
    with wave.open(io.BytesIO(data), "rb") as w:
        if w.getnchannels() != 1:
            raise ValueError(f"mono only, got {w.getnchannels()} channels")
        if w.getsampwidth() != 2:
            raise ValueError(f"16-bit PCM only, got {w.getsampwidth() * 8}-bit")
        if w.getframerate() != SAMPLE_RATE:
            raise ValueError(f"16 kHz only, got {w.getframerate()} Hz")
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


class Handler(http.server.BaseHTTPRequestHandler):
    state: State  # set on the class in main()

    def log_message(self, fmt, *args):  # route access logs through logging
        log.info("%s %s", self.address_string(), fmt % args)

    def _send(self, code: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/health"):
            ready = self.state.pipe is not None
            if self.path == "/":
                self._send(200, json.dumps({
                    "status": "ready" if ready else "loading",
                    "model": engine.MODEL,
                    "task": self.state.task or "default",
                    "language": self.state.language or "auto",
                    "segments": self.state.segments,
                }).encode())
            elif ready:
                self._send(200, b"OK", "text/plain")
            else:
                self._send(503, json.dumps({"error": self.state.error or "loading"}).encode())
        else:
            self._send(404, json.dumps({"error": "not found"}).encode())

    def do_POST(self):
        if self.path != "/v1/audio/transcriptions":
            self._send(404, json.dumps({"error": "not found"}).encode())
            return
        if self.state.pipe is None:
            self._send(503, json.dumps({"error": self.state.error or "model not loaded"}).encode())
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            ctype = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in ctype:
                raise ValueError("expected multipart/form-data")
            fields = parse_multipart(ctype, self.rfile.read(length))
            fmt = (fields.get("response_format", ("", b"json"))[1] or b"json").decode()
            if fmt != "json":
                raise ValueError(f"response_format={fmt!r} not supported (json only)")
            if "file" not in fields:
                raise ValueError("missing 'file' part")
            audio = wav_to_samples(fields["file"][1])
            task = (fields.get("task", ("", b""))[1]).decode().strip() or self.state.task
            language = (fields.get("language", ("", b""))[1]).decode().strip() or self.state.language

            t0 = time.monotonic()
            engine.set_task_language(self.state.pipe, task, language)
            result = self.state.pipe.generate(audio)
            text = (result.texts[0] or "").strip()
            self.state.segments += 1
            log.info("segment %.1fs -> %d chars in %.2fs (task=%s language=%s)",
                     audio.size / SAMPLE_RATE, len(text), time.monotonic() - t0,
                     task or "default", language or "auto")
            self._send(200, json.dumps({"text": text}).encode())
        except (ValueError, wave.Error) as e:
            self._send(400, json.dumps({"error": str(e)}).encode())
        except Exception as e:  # noqa: BLE001 - one bad segment must not kill the backend
            log.exception("transcription failed")
            self._send(500, json.dumps({"error": f"transcription failed: {e}"}).encode())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="whisperd", description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", DEFAULT_PORT)),
                    help="listen port (llama-swap passes --port; PORT env also honored)")
    ap.add_argument("--host", default="127.0.0.1",
                    help="bind address; keep local — llama-swap proxies over loopback")
    args = ap.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s: %(message)s")
    state = State(task=os.environ.get("DICTATE_TASK", "").strip(),
                  language=os.environ.get("DICTATE_LANGUAGE", "").strip())

    # Load before serving: llama-swap blocks on /health (healthCheckTimeout)
    # anyway, and a crash during load exits the process, which llama-swap sees.
    try:
        state.pipe = engine.build_pipeline(engine.MODEL, state.task, state.language)
    except Exception:
        log.exception("model load failed")
        state.error = "model load failed — see whisperd log"

    srv = http.server.HTTPServer((args.host, args.port), Handler)
    Handler.state = state
    log.info("whisperd listening on http://%s:%d (model=%s, %s)",
             args.host, args.port, engine.MODEL, "ready" if state.pipe else "load FAILED")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
