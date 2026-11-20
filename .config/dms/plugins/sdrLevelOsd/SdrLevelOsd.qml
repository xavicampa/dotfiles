// sdrLevelOsd — DMS-styled slider OSD for Hyprland's SDR white-level keybinds.
// SHIFT+F11/F12 in hyprland.lua reprograms sdr_max_luminance, then calls:
//   dms ipc call sdrLevelOsd show <value> <min> <max> <label>
// (the Go IPC layer is strict on arity — all 4 args are required).
// This reuses DMS's OWN OSD chrome (qs.Modules.OSD LevelOSD -> qs.Widgets DOSD,
// the exact widget the brightness/volume OSDs are), so it matches the stock OSD
// pixel-for-pixel and follows the user's OSD position setting (osdKind
// "brightness" inherits the brightness OSD's position).
//
// DMS 2.1.2 (dux-shell). The Variants pattern mirrors DMSShell.qml's per-screen
// BrightnessOSD instantiation; modelData (the Screen) is injected by name into
// DOSD's `modelData` property.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.OSD
import qs.Modules.Plugins

PluginComponent {
    id: root

    pluginId: "sdrLevelOsd"

    property int level: 0
    property int minimum: 0
    property int maximum: 100
    property string unit: " nits"
    property string label: "SDR white"

    // Quickshell Variants has no stable public items accessor, so each
    // per-screen LevelOSD registers itself here on completion.
    property var osds: []

    function registerOsd(osd) {
        root.osds.push(osd);
    }

    function unregisterOsd(osd) {
        const i = root.osds.indexOf(osd);
        if (i >= 0)
            root.osds.splice(i, 1);
    }

    Variants {
        id: osdVariants
        model: SettingsData.getFilteredScreens("osd")

        delegate: LevelOSD {
            id: osd

            Component.onCompleted: root.registerOsd(osd)
            Component.onDestruction: root.unregisterOsd(osd)

            // Inherit the brightness OSD's on-screen position; keeps the SDR
            // slider in the same spot as the panel-brightness one.
            osdKind: "brightness"

            iconName: "lightbulb"
            insetIconName: "lightbulb"
            endIconName: "monitor"
            endIconLabel: root.label

            value: root.level
            minimum: root.minimum
            maximum: root.maximum
            unit: root.unit
            available: true
        }
    }

    IpcHandler {
        target: "sdrLevelOsd"

        function show(value: int, min: int, max: int, label: string): string {
            root.minimum = min;
            root.maximum = max;
            root.level = value;
            if (label.length > 0)
                root.label = label;
            for (const osd of root.osds) {
                osd.show();
            }
            return "OSD " + value;
        }
    }
}
