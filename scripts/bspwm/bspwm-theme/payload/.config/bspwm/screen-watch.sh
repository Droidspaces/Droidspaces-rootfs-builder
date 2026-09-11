#!/bin/sh
# Keeps the desktop responsive when Termux:X11 resizes the screen (keyboard, keys row, rotation).
# Critical path is a single xdotool move of the dock; everything else runs afterwards in the background.
. "$HOME/.config/bspwm/lib.sh"
mkdir -p "$HOME/.cache"
dock=""; DW=0; DH=0; DX=0
cache_dock() {   # look the dock up once; refreshed when the bars are relaunched
    dock=$(xdotool search --name polybar-dock_builtin 2>/dev/null | head -1)
    [ -n "$dock" ] && eval "$(xdotool getwindowgeometry --shell "$dock" | sed 's/^/D/')" && DW=$DWIDTH; DH=$DHEIGHT; DX=$DX
}
bspc subscribe monitor_geometry | while read -r _ev _mon geom; do
    W=${geom%%x*}; rest=${geom#*x}; Hh=${rest%%+*}
    . "$HOME/.config/bspwm/scale-env.sh"; off=${UI_BAR_OFFSET_Y:-0}
    [ -n "$dock" ] && xdotool getwindowname "$dock" >/dev/null 2>&1 || cache_dock
    want_w=$((W - 2 * ${UI_BAR_MARGIN:-0}))
    if [ -z "$dock" ] || [ "$DW" -ne "$want_w" ]; then
        "$HOME/.config/polybar/launch.sh"; sleep 0.5; cache_dock     # width changed: bars need a relayout
    else
        xdotool windowmove "$dock" "$DX" $((Hh - off - DH))
    fi
    # popups position themselves only when they open: re-centre any open rofi menu / prompt
    for r in $(xdotool search --class Rofi 2>/dev/null); do
        eval "$(xdotool getwindowgeometry --shell "$r" | sed 's/^/R/')"
        xdotool windowmove "$r" $(( (W - RWIDTH) / 2 )) $(( (Hh - RHEIGHT) / 2 ))
    done
    (   # background: wallpaper only if the screen grew, then clamp floating windows
        read -r lw_lh < "$HOME/.cache/wallpaper-size" 2>/dev/null || lw_lh=0x0
        lw=${lw_lh%x*}; lh=${lw_lh#*x}
        if [ "$W" -gt "${lw:-0}" ] || [ "$Hh" -gt "${lh:-0}" ]; then "$HOME/.config/bspwm/wallpaper-render.sh"; fi
        bspc query -T -d | python3 -c '
import json,sys,subprocess
W,H=int(sys.argv[1]),int(sys.argv[2])
def walk(n):
    if not n: return
    c=n.get("client")
    if c and c["state"]=="floating":
        r=c["floatingRectangle"]; dx=dy=0
        if c.get("className","").lower()=="gsimplecal":        # calendar popup: keep it centred
            dx=(W-r["width"])//2-r["x"]; dy=(H-r["height"])//2-r["y"]
            if dx or dy: subprocess.run(["bspc","node",str(n["id"]),"-v",str(dx),str(dy)])
            walk(n.get("firstChild")); walk(n.get("secondChild")); return
        if r["x"]+r["width"]>W: dx=W-(r["x"]+r["width"])
        if r["y"]+r["height"]>H: dy=H-(r["y"]+r["height"])
        if r["x"]+dx<0: dx=-r["x"]
        if r["y"]+dy<0: dy=-r["y"]
        if dx or dy: subprocess.run(["bspc","node",str(n["id"]),"-v",str(dx),str(dy)])
    walk(n.get("firstChild")); walk(n.get("secondChild"))
walk(json.load(sys.stdin)["root"])' "$W" "$Hh"
    ) &
done
