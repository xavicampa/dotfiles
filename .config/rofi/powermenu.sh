op=$( echo -e " Suspend\n Poweroff\n󰜉 Reboot\n Logout\n󱄅 Reboot-to-Linux\n Reboot-to-Windows\n Reboot-to-UEFI" | rofi -i -dmenu | awk '{print tolower($2)}' )

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
  reboot-to-linux)
    pkexec efibootmgr -n 0000 && reboot
    ;;
  reboot-to-windows)
    pkexec efibootmgr -n 0002 && reboot
    ;;
  reboot-to-uefi)
    systemctl reboot --firmware-setup
    ;;
esac
