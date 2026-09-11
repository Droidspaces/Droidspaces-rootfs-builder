#!/bin/sh
# Start the bspwm touch desktop on the Termux:X11 display. Open the Termux:X11 app first.
# Optional: SCALE=1.5 ~/start-desktop.sh   (seeds the saved UI scale; change it later from the top bar)
export DISPLAY="${DISPLAY:-:5}"
unset XAUTHORITY
. "$HOME/.config/bspwm/lib.sh"
[ -n "$SCALE" ] && cfg_set SCALE "$SCALE"
. "$HOME/.config/bspwm/scale-env.sh"
export XDG_CURRENT_DESKTOP=bspwm
export GTK_THEME=catppuccin-mocha-lavender-standard+default
export _JAVA_AWT_WM_NONREPARENTING=1
export TERMINAL=xfce4-terminal

if ! xdpyinfo >/dev/null 2>&1; then
  echo "No X server on $DISPLAY. Open the Termux:X11 app, then run this again." >&2
  exit 1
fi
if bspc wm -g >/dev/null 2>&1; then echo "bspwm is already running on $DISPLAY (desktop-autostart.service?)" >&2; exit 1; fi
exec dbus-launch --exit-with-session bspwm
