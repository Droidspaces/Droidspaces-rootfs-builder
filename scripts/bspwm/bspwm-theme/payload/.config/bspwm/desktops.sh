#!/bin/sh
# GNOME-style dynamic desktops: there is always exactly one empty desktop at the end,
# never fewer than DESKTOPS (default 2). Run once to reconcile, or "watch" to follow bspwm events.
. "$HOME/.config/bspwm/lib.sh"
reconcile() {
    min=$(cfg_get DESKTOPS 2); [ "$min" -lt 1 ] && min=1
    set -- $(bspc query -D --names); n=$#
    while [ "$n" -lt "$min" ]; do n=$((n + 1)); bspc monitor -a "$n"; done
    set -- $(bspc query -D --names); n=$#
    last=$(eval "echo \$$n")
    if [ -n "$(bspc query -N -d "$last" -n .window)" ]; then      # last desktop in use: open a fresh one
        bspc monitor -a "$((n + 1))"; return
    fi
    focused=$(bspc query -D -d focused --names)
    while [ "$n" -gt "$min" ]; do                                 # trim trailing empties down to one
        last=$(eval "echo \$$n"); prev=$(eval "echo \$$((n - 1))")
        [ -z "$(bspc query -N -d "$last" -n .window)" ] || break
        [ -z "$(bspc query -N -d "$prev" -n .window)" ] || break
        [ "$focused" = "$last" ] && break                            # keep the one the user is standing on
        bspc desktop "$last" -r; n=$((n - 1))
        set -- $(bspc query -D --names)
    done
}
if [ "$1" = watch ]; then
    reconcile
    bspc subscribe node_add node_remove node_transfer node_state desktop_focus desktop_remove | while read -r _; do reconcile; done
else
    reconcile
fi
