#!/bin/sh
# Apply the saved focus mode: "tap" = click to focus (default), "hover" = focus follows the pointer.
mode=$(cat "$HOME/.config/bspwm/focus" 2>/dev/null); [ "$mode" = hover ] || mode=tap
if [ "$mode" = hover ]; then bspc config focus_follows_pointer true; else bspc config focus_follows_pointer false; fi
bspc config click_to_focus any
