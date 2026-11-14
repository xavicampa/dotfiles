# TODO — homepc

1. **dictate: stream long utterances (trough-aware mid-hold cuts)** — continuous
   speech with no >=0.6 s pause only ends at `MAX_SEGMENT` (25 s), so an 8-10 s
   sentence waits for release + ~1.2 s. True incremental Whisper isn't a thing
   (GenAI's pipeline is whole-buffer; stitching partial transcriptions risks
   eaten/duped words at seams) — but chunks cut mid-hold already transcribe in
   parallel with ongoing speech (worker queue + paste path exist; measured
   2026-11-14: 1.4 s chunk -> 0.85 s, 6.0 s -> 0.94 s, 7.3 s -> 1.22 s).
   Plan: once a segment is armed at ~3 s, cut at the next short energy *trough*
   (rms dropping toward the noise floor ~0.2 s) instead of a clock tick, so
   boundaries land between words; lower `MAX_SEGMENT` 25 -> 8-10 s as the
   monotone-speech safety valve. Effect: text starts inserting under the cursor
   while still speaking; each chunk = its own timestamped md entry, pasted in
   order (existing behavior). Cheaper fallback if it misbehaves: just set
   `MAX_SEGMENT` ~3.5 (arbitrary mid-word cuts).
   Where: `dictate/daemon.py` in this folder (constants ~L42-59, VAD loop +
   `_finalize` ~L240-280) — NOTES.md § dictate.
