#!/bin/sh
xrandr --output HDMI-0 --primary --mode 3840x2160 --pos 0x0 --rotate normal --output DP-0 --mode 3840x2160 --rate 119.91 --pos 3840x0 --rotate normal --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off --output DP-1-1 --off --output HDMI-1-1 --off --output DP-1-2 --off
feh --bg-center "$HOME/.config/i3/background.png" "$HOME/.config/i3/background.png"
pactl set-card-profile alsa_card.pci-0000_01_00.1 output:hdmi-stereo
