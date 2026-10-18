-- DMS user keybind overrides (edit via Control Center or dms; do not remove this header)

hl.unbind("F11")
hl.bind("F11", hl.dsp.exec_cmd("dms ipc call brightness decrement 5 \"ddc:i2c-11\""), { locked = true, repeating = true })
hl.unbind("F12")
hl.bind("F12", hl.dsp.exec_cmd("dms ipc call brightness increment 5 \"ddc:i2c-11\""), { locked = true, repeating = true })
hl.unbind("SUPER + B")
hl.bind("SUPER + B", hl.dsp.exec_cmd("dms ipc call bar toggle index 0"), { description = "toggle DMS bar" })
hl.unbind("SUPER + SHIFT + B")
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("dms ipc call bar toggleAutoHide index 0"), { description = "toggle DMS bar auto-hide" })
hl.unbind("SUPER + Y")
hl.bind("SUPER + Y", hl.dsp.exec_cmd("dms ipc call dash toggle overview"), { description = "dash -> overview tab" })
hl.unbind("SUPER + Z")
hl.bind("SUPER + Z", hl.dsp.exec_cmd("dms ipc call keybinds toggle hyprland"))
hl.unbind("XF86MonBrightnessDown")
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("dms ipc call brightness decrement 5 \"ddc:i2c-11\""), { locked = true, repeating = true })
hl.unbind("XF86MonBrightnessUp")
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("dms ipc call brightness increment 5 \"ddc:i2c-11\""), { locked = true, repeating = true })
hl.unbind("SUPER + S")
hl.unbind("SUPER + SHIFT + S")
hl.unbind("SUPER + E")
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus --new-window"), { description = "Files (Nautilus)" })
hl.unbind("SUPER + CTRL + Return")
hl.bind("SUPER + CTRL + Return", hl.dsp.exec_cmd("kitty pi"), { description = "kitty running pi" })
hl.unbind("SUPER + Return")
hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"), { description = "kitty terminal" })
hl.unbind("CTRL + SHIFT + R")
hl.unbind("SUPER + CTRL + SHIFT + grave")
hl.unbind("SUPER + SHIFT + Slash")
hl.unbind("SUPER + T")
hl.unbind("SUPER + code:61")
hl.unbind("SUPER + grave")

-- SUPER + minus → scratch workspace. DMS's default here was
-- resizeactive -100 0; keysym `minus` is only ever the printed `-` key on kb_layout=no
-- (<AB10>, unshifted only), and width resize survives on the printed `+` (SUPER+code:20 =
-- resizeactive -100 0) and printed `\` (SUPER+code:21 = resizeactive 100 0).
hl.unbind("SUPER + minus")
hl.bind("SUPER + minus", hl.dsp.workspace.toggle_special("magic"), { description = "toggle scratch (special:magic)" })

-- SUPER + SHIFT + minus → window → scratch. (SUPER+S / SUPER+SHIFT+S are both unbound now, so
-- this is the only window→scratch key; toggling scratch is SUPER+minus.)
-- Keycode form is mandatory: on kb_layout=no the printed `-` key (<AB10>) emits keysym
-- `underscore` with Shift down, so a `SUPER + SHIFT + minus` keysym bind can never fire;
-- `code:61` matches the physical key and shift state is irrelevant to it.
-- The unbind clears DMS's unaddressable default here (resizeactive 0 -100) and keeps that
-- keysym slot dead across DMS updates.
hl.unbind("SUPER + SHIFT + minus")
hl.bind("SUPER + SHIFT + code:61", hl.dsp.window.move({ workspace = "special:magic" }), { description = "move window to scratch" })
