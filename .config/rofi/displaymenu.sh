op=$( echo -e "󰶐 󰍹 Only32\n󰍹 󰶐 Only27\n󰍹 󰍹 Both" | rofi -i -dmenu | awk '{print tolower($3)}' )

case $op in 
  only32)
    hyprctl keyword monitor "HDMI-A-1,disable"
    hyprctl keyword monitor "DP-2,highrr,2560x0,1.2,vrr,1"
    ;;
  only27)
    hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1"
    hyprctl keyword monitor "DP-2,disable"
    ;;
  both)
    hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1"
    hyprctl keyword monitor "DP-2,highrr,2560x0,1.2,vrr,1"
    ;;
esac
