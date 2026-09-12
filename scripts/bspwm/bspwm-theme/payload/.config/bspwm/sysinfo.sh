#!/bin/sh
. "$HOME/.config/bspwm/lib.sh"
mem=$(free -h | awk '/Mem:/{print $3" / "$2}'); swp=$(free -h | awk '/Swap:/{print $3" / "$2}')
disk=$(df -h / | awk 'NR==2{print $3" / "$2"  ("$5")"}'); load=$(cut -d' ' -f1-3 /proc/loadavg)
bat="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)% $(cat /sys/class/power_supply/battery/status 2>/dev/null)"
ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1); up=$(uptime -p | sed 's/^up //')
printf '%s\n' "  $(. /etc/os-release; echo "$PRETTY_NAME")  ·  $(uname -m)" "  $(uname -r)" "  Uptime $up" "  Load $load" "  Memory $mem" "  Swap $swp" "  Disk $disk" "  Battery $bat" "  IP ${ip:-none}" "  Screen $(xdpyinfo | awk '/dimensions/{print $2}')  ·  scale $(cfg_get SCALE 1.25)x" "  Back" \
  | menu "System" "" "" >/dev/null
