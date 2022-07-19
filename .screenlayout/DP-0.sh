#!/bin/sh
# xrandr --output HDMI-0 --off --output DP-0 --primary --mode 3840x2160 --rate 119.91 --pos 0x0 --rotate normal --output DP-1 --off --output DP-2 --off --output DP-3 --off --output DP-4 --off --output DP-5 --off --output DP-1-1 --off --output HDMI-1-1 --off --output DP-1-2 --off
# nvidia-settings --assign CurrentMetaMode=(nvidia-settings -q CurrentMetaMode -t|tr '\n' ' '|sed -e 's/.*:: \(.*\)/\1\n/g' -e 's/}/, ForceCompositionPipeline = On}/g')
nvidia-settings --assign CurrentMetaMode="DPY-1: 3840x2160_120 @3840x2160 +0+0 {ViewPortIn=3840x2160, ViewPortOut=3840x2160+0+0, ForceCompositionPipeline=On, ForceCompositionPipeline = On}"
