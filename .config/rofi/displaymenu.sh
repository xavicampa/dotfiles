op=$( echo -e "󰶐 󰍹 DisplayPort\n󰍹 󰶐 HDMI\n󰍹 󰍹 Both" | rofi -i -dmenu | awk '{print tolower($3)}' )

case $op in 
  displayport)
    hyprctl dispatch dpms off HDMI-A-1
    hyprctl dispatch dpms on DP-1
    ;;
  hdmi)
    hyprctl dispatch dpms on HDMI-A-1
    hyprctl dispatch dpms off DP-1
    ;;
  both)
    hyprctl dispatch dpms on HDMI-A-1
    hyprctl dispatch dpms on DP-1
    ;;
esac
