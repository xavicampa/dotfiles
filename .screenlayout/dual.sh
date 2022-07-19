#!/bin/sh
# xrandr --output HDMI-0 --mode 3840x2160 --rate 59.94 --pos 0x0 --rotate normal --output DP-0 --primary --mode 3840x2160 --rate 59.94 --pos 3840x0 --rotate normal --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off --output DP-1-1 --off --output HDMI-1-1 --off --output DP-1-2 --off
# feh --bg-center "$HOME/.config/i3/background.png" "$HOME/.config/i3/background.png"
# pactl set-card-profile alsa_card.pci-0000_01_00.1 output:hdmi-stereo-extra1
# nvidia-settings --assign CurrentMetaMode="$(nvidia-settings -q CurrentMetaMode -t|tr '\n' ' '|sed -e 's/.*:: \(.*\)/\1\n/g' -e 's/}/, ForceCompositionPipeline = On}/g')"
nvidia-settings --assign CurrentMetaMode="DPY-1: 3840x2160_60_0 @3840x2160 +3840+0 {ViewPortIn=3840x2160, ViewPortOut=3840x2160+0+0, ForceCompositionPipeline=On, ForceCompositionPipeline = On}, DPY-0: 3840x2160_60_0 @3840x2160 +0+0 {ViewPortIn=3840x2160, ViewPortOut=3840x2160+0+0, ForceCompositionPipeline=On, ForceCompositionPipeline = On}"
