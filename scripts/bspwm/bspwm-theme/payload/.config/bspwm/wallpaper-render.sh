#!/bin/sh
# Render the wallpaper to the root pixmap and remember the screen size it was rendered for.
# The screen watcher only re-renders when the screen grows beyond this size (shrinking is free).
sz=$(xdpyinfo | awk '/dimensions/{print $2}')
feh --no-fehbg --bg-fill "$HOME/.config/bspwm/wallpaper" && printf '%s\n' "$sz" > "$HOME/.cache/wallpaper-size"
