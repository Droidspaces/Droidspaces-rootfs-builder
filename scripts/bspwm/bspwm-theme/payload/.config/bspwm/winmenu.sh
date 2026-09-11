#!/bin/sh
# Labelled window actions for the focused window.
. "$HOME/.config/bspwm/lib.sh"
n=$(bspc query -N -n focused) || { notify-send "Window actions" "No window is focused"; exit 0; }
title=$(xdotool getwindowname "$n" 2>/dev/null | cut -c1-40)
c=$(printf '%s\n' "  Swap with previous" "  Swap with next" "  Grow" "  Shrink" "  Rotate layout" "  Balance sizes" "  Flip layout" "  Toggle monocle" "  Float / tile" "  Fullscreen" "  Send to next desktop" "  Send to desktop…" "  Close" "  Force kill" "  Back" \
   | menu "Window" "$title" "") || exit 0
case "$c" in
  *previous)  bspc node -s prev.local.window ;;
  *"with next") bspc node -s next.local.window ;;
  *Grow)      "$HOME/.config/bspwm/resize.sh" grow ;;
  *Shrink)    "$HOME/.config/bspwm/resize.sh" shrink ;;
  *Rotate*)   bspc node @/ -R 90 ;;
  *Balance*)  bspc node @/ -B ;;
  *Flip*)     bspc node @/ -F horizontal ;;
  *monocle)   bspc desktop -l next ;;
  *Float*)    bspc node -t ~floating ;;
  *Fullscreen) bspc node -t ~fullscreen ;;
  *"next desktop") bspc node -d next --follow ;;
  *"desktop…") d=$(printf '%s\n' 1 2 3 4 | menu "Send to desktop" "" "") && [ -n "$d" ] && bspc node -d "^$d" --follow ;;
  *Close)     bspc node -c ;;
  *kill)      bspc node -k ;;
esac
