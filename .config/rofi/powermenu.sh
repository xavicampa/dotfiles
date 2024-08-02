op=$( echo -e " Suspend\n Poweroff\n󰜉 Reboot\n Logout" | rofi -i -dmenu | awk '{print tolower($2)}' )

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
