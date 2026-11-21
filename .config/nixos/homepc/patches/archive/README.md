# Archived patches

Patches kept here are **not applied** by `configuration.nix` — they are retained as
history (superseded versions, or experiments worth keeping). Nothing under this
directory is referenced from any `.nix` file; move patches back up to `../` to apply them.

- `hyprland-reference-luminance-0.57.2.patch` (2026-11-21) — v1 of the Hyprland
  `reference_luminance` patch (upstream issue #16329, PR rebased to tag v0.57.2).
  It put the rule's reference into the monitor description everywhere, so driving
  it from the SHIFT+F11/F12 slider crushed HDR-video shadows
  (`getCMSettings` scales every HDR tonemap by `dstRef/srcRef`). Superseded the
  same day by v2, `../hyprland-reference-luminance-advertise-0.57.2.patch`, which
  applies the override only at the advertise sites. Full backstory in
  `homepc/NOTES.md` (§ hyprland).
