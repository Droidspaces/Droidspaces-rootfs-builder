#!/bin/sh
# Battery for polybar: reads Android's /sys/class/power_supply/battery
d=/sys/class/power_supply/battery
cap=$(cat $d/capacity 2>/dev/null || echo 0)
st=$(cat $d/status 2>/dev/null)
if [ $cap -ge 90 ]; then i=""; c="#a6e3a1"
elif [ $cap -ge 65 ]; then i=""; c="#a6e3a1"
elif [ $cap -ge 40 ]; then i=""; c="#f9e2af"
elif [ $cap -ge 15 ]; then i=""; c="#fab387"
else i=""; c="#f38ba8"; fi
case "$st" in Charging|Full) i=""; c="#a6e3a1";; esac
printf '%%{F%s}%%{T2}%s%%{T-}%%{F-} %s%%\n' "$c" "$i" "$cap"
