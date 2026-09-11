#!/bin/sh
. "$HOME/.config/bspwm/scale-env.sh"
killall -q polybar
while pgrep -u "$(id -u)" -x polybar >/dev/null; do sleep 0.2; done
polybar -q top  >"$HOME/.config/polybar/top.log"  2>&1 &
polybar -q dock >"$HOME/.config/polybar/dock.log" 2>&1 &
sleep 0.6
[ "$(cfg_get BAR_TOP on)"  = off ] && polybar-msg -p "$(pgrep -f 'polybar -q top')"  cmd hide >/dev/null 2>&1
[ "$(cfg_get BAR_DOCK on)" = off ] && polybar-msg -p "$(pgrep -f 'polybar -q dock')" cmd hide >/dev/null 2>&1
exit 0
