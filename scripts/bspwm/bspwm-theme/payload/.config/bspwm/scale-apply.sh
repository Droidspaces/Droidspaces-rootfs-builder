#!/bin/sh
# Push the current UI scale into X resources, rofi and bspwm. Safe to run any time.
. "$HOME/.config/bspwm/scale-env.sh"
printf 'Xft.dpi: %s\nXft.antialias: 1\nXft.hinting: 1\nXft.hintstyle: hintslight\nXft.rgba: rgb\nXcursor.size: %s\n' "$POLYBAR_DPI" "$XCURSOR_SIZE" | xrdb -merge
printf 'configuration { dpi: %s; }\n' "$POLYBAR_DPI" > "$HOME/.config/rofi/dpi.rasi"
xsetroot -cursor_name left_ptr
bspc config window_gap   "$UI_GAP"   2>/dev/null
bspc config border_width "$UI_BORDER" 2>/dev/null
