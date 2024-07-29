op=$( echo -e "  Poweroff\n  Reboot\n  Suspend\n  Logout" | rofi -i -dmenu --width 300 --height 200 | awk '{print tolower($2)}' )

case $op in 
  poweroff)
    ;&
  reboot)
    ;&
  suspend)
    systemctl $op
    ;;
  logout)
    hyprctl dispatch exit 1
    ;;
esac
