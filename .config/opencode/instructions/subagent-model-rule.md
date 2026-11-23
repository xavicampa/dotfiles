# Sub-agent model rule

## Hard limit: 3 concurrent requests total

- The multi-agent backend serves **at most 3 requests in parallel**. This is a
  hard capacity limit, not a soft preference. It counts concurrent **inference
  requests**, not sessions — an idle session holds no slot.
- The budget is **shared across parent and children combined**: any request
  in flight counts, whoever issued it.
- **Up to 3 sub-agents can run at once** when the parent dispatches them and
  then simply waits for results — while waiting, the parent holds no slot, so
  all 3 are available to children.
- **Only 2 sub-agents** alongside the parent when the parent is *itself
  generating at the same time* (its request occupies the 3rd slot).
- Never exceed 3 in-flight requests in total. Queue the rest and launch them
  as earlier ones finish. Exceeding 3 overflows the batch slots and degrades
  or stalls every request sharing the backend.

## Model identity

- The multi-agent model is `local/qwen3.8-flash-next` — llama-swap's
  multi-slot entry: parent and child requests share its batch slots. A
  different model ID in the same session would make llama-swap swap backends
  under load (model-swap thrash).
- Subagents carry no model pin: they inherit the session model. Therefore the
  session itself must be on `local/qwen3.8-flash-next` before any subagent is
  fired, so parent and children hit the same backend.
- Before firing ANY subagent: if the main session's model is not
  `local/qwen3.8-flash-next`, STOP and ask (question tool) whether the user
  wants to /model-switch the session to it first. Respect a refusal and
  proceed as-is.
- Never pass a `model` param on subagent calls unless the user explicitly
  names that model.
- The `subagent → ask` permission gate fires on every launch; answer it
  "once", never "always" — "always" durably disables the gate for the project.
