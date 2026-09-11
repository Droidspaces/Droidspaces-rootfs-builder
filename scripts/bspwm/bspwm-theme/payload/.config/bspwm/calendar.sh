#!/bin/sh
# Tap the clock to open the calendar, tap it again or tap anywhere else to close it.
if pgrep -x gsimplecal >/dev/null; then pkill -x gsimplecal; exit 0; fi
. "$HOME/.config/bspwm/scale-env.sh"
# Boost only the calendar's fonts so it reads like a popup, whatever the UI scale is.
export GDK_DPI_SCALE=$(awk "BEGIN{print $GDK_DPI_SCALE*1.6}")
gsimplecal &
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.1; n=$(bspc query -N -n .window | while read -r id; do xprop -id "$id" WM_CLASS 2>/dev/null | grep -q gsimplecal && echo "$id"; done | head -1)
  [ -n "$n" ] && { bspc node "$n" -f; break; }
done
