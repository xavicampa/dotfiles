// Dim overlay + live mic waveform while dictate is capturing — driven by the
// dictate daemon: `qs ipc call dim show|hide` (IpcHandler below) toggles it,
// the daemon streams the waveform via FileView (see below).
// Design notes — NOTES.md § dictate:
// - dim targets the FOCUSED WINDOW only: on press the daemon writes the
//   active window's absolute rect from `hyprctl activewindow -j` to
//   $XDG_RUNTIME_DIR/dictate-focus.json; each per-monitor surface (Instantiator
//   over Quickshell.screens — 0.3.2 has no `Screens`/`Vars`) stays
//   full-screen-transparent and draws the dim as an inner Rectangle at the
//   window's local coords (robust; straddling windows clip per monitor for
//   free) with the waveform centered on it. No rect (no window / hyprctl
//   failed) -> the Rectangle fills the surface = full-screen dim fallback.
//   Geometry is sampled at press; a window dragged mid-sentence keeps the
//   stale rectangle.
// - exclusiveZone -1: no area reserved (windows keep their geometry);
//   empty Region mask: surface has no input region -> clicks fall through;
//   focusable false (default): keyboard never lands on the overlay.
// - waveform: the capture callback in dictate/daemon.py appends min/max of
//   every 32 ms block of the *actual mic signal* and rewrites
//   $XDG_RUNTIME_DIR/dictate-wave.txt at ~31 Hz; FileView watches it and the
//   Canvas draws one vertical slice per block (150 cols = last ~4.8 s,
//   newest at right). cava considered and rejected: it grabs the mic through
//   its own capture path and only renders to a terminal.
// - colors follow the Dux Shell (DMS) theme: trace = palette role `primary`,
//   baseline = `outline`. Palette comes from the active theme's theme.json
//   (path = customThemeFile in ~/.config/dms/settings.json, both FileView-
//   watched → a theme switch re-skins live); light/dark mode is asked of the
//   *running* shell via `qs -p $XDG_RUNTIME_DIR/dms-shell/* ipc call theme
//   -- getMode` at load and on every show. Not custom-themed (stock/dynamic)
//   or no DMS running -> fall back to the plain white trace.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // repaint signals for the per-screen delegates (ids inside a Repeater
    // are not reachable from root-scope FileViews)
    signal waveTick
    signal paletteTick

    // QML has no env access; resolve $XDG_RUNTIME_DIR/$HOME once.
    // NOTE: quickshell Process does NOT auto-start — running: true is required.
    property string wavePath: ""
    property string focusPath: ""
    property string dmsSettingsPath: ""
    Process {
        running: true
        command: ["sh", "-c", "printf '%s %s' \"$XDG_RUNTIME_DIR\" \"$HOME\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var tok = text.trim().split(" ")
                if (tok.length === 2 && tok[0] !== "") {
                    root.wavePath = tok[0] + "/dictate-wave.txt"
                    root.focusPath = tok[0] + "/dictate-focus.json"
                    root.dmsSettingsPath = tok[1] + "/.config/dms/settings.json"
                }
            }
        }
    }

    // ── DMS theme colors ───────────────────────────────────────────────────
    property string themeMode: "dark" // dms boot default until getMode answers
    property var themeDoc: null       // parsed active theme.json
    property var themeRole: null      // mode block of themeDoc (empty block = absent)
    function resolveTheme(): void {
        var t = root.themeDoc
        if (!t) { root.themeRole = null; return }
        var m = t[root.themeMode]
        if (!m || !Object.keys(m).length)
            m = t[root.themeMode === "light" ? "dark" : "light"]
        root.themeRole = (m && Object.keys(m).length) ? m : null
        root.paletteTick()
    }
    function roleHex(role, fallback) {
        return (root.themeRole && root.themeRole[role]) ? root.themeRole[role] : fallback
    }
    Process {
        id: modeProc
        command: ["sh", "-c", "d=$(ls -d \"$XDG_RUNTIME_DIR\"/dms-shell/* 2>/dev/null | head -1); [ -n \"$d\" ] && qs -p \"$d\" ipc call theme -- getMode"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = text.trim()
                if (m === "light" || m === "dark") { root.themeMode = m; root.resolveTheme() }
            }
        }
    }
    FileView {
        id: dmsSettings
        path: root.dmsSettingsPath
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: {
            // dms only applies customThemeFile when the theme is "custom"
            try {
                var s = JSON.parse(this.text())
                root.themeFilePath = (s.currentThemeName === "custom" && s.customThemeFile) ? s.customThemeFile : ""
            } catch (e) { root.themeFilePath = "" }
        }
    }
    property string themeFilePath: ""
    FileView {
        path: root.themeFilePath
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: {
            try { root.themeDoc = JSON.parse(this.text()) } catch (e) { root.themeDoc = null }
            root.resolveTheme()
        }
    }

    // ── focused-window rect for the dim (daemon writes on press; null = full-screen)
    property var focusRect: null   // {x, y, w, h, mon} absolute hyprland coords
    property bool shown: false     // last show()/hide() from the daemon
    FileView {
        path: root.focusPath
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: {
            try {
                var j = JSON.parse(this.text())
                root.focusRect = (j && j.w > 0 && j.h > 0) ? j : null
            } catch (e) { root.focusRect = null }
        }
    }

    // ── mic waveform feed (daemon streams; newest column at right) ─────────
    property var waveMax: []
    property var waveMin: []
    FileView {
        path: root.wavePath
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: {
            var lines = this.text().split("\n")
            if (lines.length < 2) return
            root.waveMax = lines[0].split(" ")
            root.waveMin = lines[1].split(" ")
            root.waveTick()
        }
    }

    // One full-screen surface per monitor (anchors: proven mapping); the dim
    // is a Rectangle drawn INSIDE the surface at the focused window's local
    // coords — far more robust than positioning/sizing layer surfaces via
    // margins, and a window straddling screens gets its dim clipped per
    // monitor automatically.
    // Instantiator, NOT Repeater: Repeater delegates must be visual Items and
    // PanelWindow is a window — with Repeater the delegates are silently never
    // created (nothing renders, zero warnings).
    Instantiator {
        model: Quickshell.screens   // 0.3.2 name (Screens.all is a later API)
        delegate: PanelWindow {
            id: dim
            required property ShellScreen modelData
            screen: modelData
            anchors.left: true
            anchors.right: true
            anchors.top: true
            anchors.bottom: true
            exclusiveZone: -1
            focusable: false
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"
            mask: Region {} // empty input region: fully click-through

            readonly property var j: root.focusRect
            readonly property bool full: j === null
            // window coords relative to this screen (hyprland layout coords
            // == Qt logical geometry at scale 1 — both monitors run 1:1)
            readonly property real rx: full ? 0 : j.x - modelData.x
            readonly property real ry: full ? 0 : j.y - modelData.y
            readonly property bool overlap: full
                || (rx < modelData.width && ry < modelData.height
                    && rx + j.w > 0 && ry + j.h > 0)

            visible: root.shown && overlap

            Connections {
                target: root
                function onWaveTick() { wave.requestPaint() }
                function onPaletteTick() { wave.requestPaint() }
            }

            Rectangle {
                id: spot
                x: Math.round(dim.rx)
                y: Math.round(dim.ry)
                width: Math.round(dim.full ? dim.width : j.w)
                height: Math.round(dim.full ? dim.height : j.h)
                color: "#66000000" // 40% black dim (was #bf = 75%; lowered now that the waveform carries the "listening" signal)
            }

            Canvas {
                id: wave
                anchors.centerIn: spot
                width: Math.min(spot.width * 0.5, 900)
                height: Math.min(240, Math.max(80, spot.height - 40))
                antialiasing: true

                function amp(v) { // fixed gain + hard clip; ~0.4 raw fills the view
                    return Math.max(-1, Math.min(1, Number(v) * 2.5))
                }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var mid = height / 2
                    // faint baseline (theme outline) so a silent mic reads as a flat trace
                    ctx.strokeStyle = root.roleHex("outline", "#ffffff")
                    ctx.globalAlpha = 0.25
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(0, mid)
                    ctx.lineTo(width, mid)
                    ctx.stroke()
                    var n = Math.min(root.waveMax.length, root.waveMin.length)
                    if (n === 0) return
                    var half = mid - 4
                    var colw = width / n
                    ctx.strokeStyle = root.roleHex("primary", "#ccffffff")
                    ctx.globalAlpha = 0.95
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var i = 0; i < n; i++) {
                        var hi = root.waveMax[i]
                        var lo = root.waveMin[i]
                        if (isNaN(hi) || isNaN(lo)) continue
                        var x = i * colw + colw / 2
                        ctx.moveTo(x, mid - amp(hi) * half)
                        ctx.lineTo(x, mid - amp(lo) * half)
                    }
                    ctx.stroke()
                }
            }
        }
    }

    IpcHandler {
        target: "dim"
        function show(): void {
            root.shown = true
            // refresh the light/dark mode on every press (async; repaint follows)
            modeProc.exec(modeProc.command)
        }
        function hide(): void { root.shown = false }
    }
}
