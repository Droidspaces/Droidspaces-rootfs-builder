#!/bin/sh
# Screenshot applet (ideas from adi1090x/rofi applets). Saves to ~/Pictures/Screenshots.
. "$HOME/.config/bspwm/lib.sh"
dir="$HOME/Pictures/Screenshots"; mkdir -p "$dir"
f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
countdown() { n=$1; while [ "$n" -gt 0 ]; do notify-send -r 699 -t 1000 "Screenshot in $n"; sleep 1; n=$((n-1)); done; }
done_msg() { [ -f "$f" ] && notify-send -i "$f" "Screenshot saved" "$(basename "$f")"; }
c=$(printf '%s\n' "  Now" "  In 5 seconds" "  Drag an area" "  Focused window" "  Open folder" "  Back" | menu "Screenshot" "Saved to ~/Pictures/Screenshots" "") || exit 0
case "$c" in
  *Now)            sleep 0.4; scrot -o "$f"; done_msg ;;
  *"5 seconds")    countdown 5; scrot -o "$f"; done_msg ;;
  *area)           notify-send -t 2500 "Drag to select an area"; sleep 0.4; scrot -s -f -o "$f" && done_msg ;;
  *window)         sleep 0.4; scrot -u -b -o "$f"; done_msg ;;
  *folder)         thunar "$dir" & ;;
esac
