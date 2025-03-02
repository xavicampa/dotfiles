op=$( echo -e "󰛧 󰍹 Only32\n󰌢 󰶐 OnlyLaptop\n󰌢 󰍹 Both" | rofi -i -dmenu | awk '{print tolower($3)}' )

case $op in 
  only32)
    hyprctl keyword monitor "eDP-1,disable"
    hyprctl keyword monitor "DP-1,preferred,0x0,1.5"
    ;;
  onlylaptop)
    hyprctl keyword monitor "eDP-1,preferred,0x0,1"
    hyprctl keyword monitor "DP-1,disable"
    ;;
  both)
    hyprctl keyword monitor "eDP-1,preferred,0x0,1"
    hyprctl keyword monitor "DP-1,preferred,1920x0,1.5"
    ;;
esac
