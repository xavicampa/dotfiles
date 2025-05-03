op=$( echo -e "󰶐 󰍹 Only32\n󰍹 󰶐 Only27\n󰍹 󰶐 Only27Rotated\n󰍹 󰍹 Both\n󰍹 󰍹 BothRotate27" | rofi -i -dmenu | awk '{print tolower($3)}' )

case $op in 
  only32)
    hyprctl keyword monitor "HDMI-A-1,disable"
    hyprctl keyword monitor "DP-1,3840x2160@120,0x0,1.5,vrr,0"
    ;;
  only27)
    hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1.25"
    hyprctl keyword monitor "DP-1,disable"
    ;;
  only27rotated)
    hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1.25,transform,3"
    hyprctl keyword monitor "DP-1,disable"
    ;;
  both)
    hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1"
    hyprctl keyword monitor "DP-1,3840x2160@120,2048x0,1.5,vrr,0"
    ;;
  bothrotate27)
    hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1.25,transform,3"
    hyprctl keyword monitor "DP-1,3840x2160@120,1152x384,1.5,vrr,0"
    ;;
esac
