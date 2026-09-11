#!/usr/bin/env python3
"""Modifier-free edge dragging for bspwm (touch friendly).

Passively grabs button 1 on the root window in synchronous mode. A press that lands on the
gap/border between tiled windows starts a fence drag; a press on the top strip of a floating
window moves it; anything else is replayed untouched to the app underneath.
A press outside the calendar popup closes it.
"""
import json, subprocess, time
from Xlib import X, display, Xcursorfont
from Xlib.ext import xtest

INNER = 12          # px inside a window edge that still counts as the edge
FLOAT_GRIP = 28     # px strip at the top of a floating window that moves it
MODS = (0, X.LockMask, X.Mod2Mask, X.LockMask | X.Mod2Mask)
# Presses on a bar with Ctrl/Alt/Shift held are never intentional on a phone: Termux:X11's latching
# CTRL key can get stuck when a window closes mid-sequence. Grab those too and release the modifiers.
STUCK = (X.ControlMask, X.Mod1Mask, X.ShiftMask)
STUCK_MODS = tuple(m | base for m in STUCK for base in MODS) + tuple(X.ControlMask | X.ShiftMask | base for base in MODS)

d = display.Display()
root = d.screen().root
font = d.open_font("cursor")
def cur(g): return font.create_glyph_cursor(font, g, g + 1, (0, 0, 0), (65535, 65535, 65535))
CUR = {"h": cur(Xcursorfont.sb_h_double_arrow), "v": cur(Xcursorfont.sb_v_double_arrow), "c": cur(Xcursorfont.fleur)}
EVMASK = X.ButtonPressMask | X.ButtonReleaseMask | X.PointerMotionMask

def bspc(*a):
    return subprocess.run(["bspc", *a], capture_output=True, text=True)

_cfg = {"t": 0}
def cfg():
    if time.time() - _cfg["t"] > 3:
        _cfg["gap"] = int(bspc("config", "window_gap").stdout.strip() or 0)
        _cfg["bw"] = int(bspc("config", "border_width").stdout.strip() or 0)
        _cfg["t"] = time.time()
    return _cfg["gap"], _cfg["bw"]

def leaves():
    out = bspc("query", "-T", "-d").stdout
    if not out: return []
    res = []
    def walk(n):
        if not n: return
        c = n.get("client")
        if c:
            r = c["tiledRectangle"] if c["state"] in ("tiled", "pseudo_tiled") else c["floatingRectangle"]
            res.append((str(n["id"]), c["state"], r, c.get("className", "")))
        walk(n.get("firstChild")); walk(n.get("secondChild"))
    walk(json.loads(out)["root"])
    return res

NEIGH = {"left": "west", "right": "east", "top": "north", "bottom": "south"}
def has_neighbour(wid, side):
    return bool(bspc("query", "-N", "-n", f"{wid}#{NEIGH[side]}.local.!hidden.window").stdout.strip())

POPUP_CLASSES = ("gsimplecal", "pavucontrol")
def dismiss_popups(px, py, ls):
    for wid, state, r, cls in ls:
        if cls.lower() in POPUP_CLASSES and not (r["x"] <= px <= r["x"] + r["width"] and r["y"] <= py <= r["y"] + r["height"]):
            subprocess.Popen(["bspc", "node", wid, "-c"])      # polite close request to the popup window

def hit(px, py):
    gap, bw = cfg()
    outer = gap + bw + 4
    ls = leaves()
    dismiss_popups(px, py, ls)
    floating = [l for l in ls if l[1] == "floating"]
    tiled = [l for l in ls if l[1] in ("tiled", "pseudo_tiled")]
    for wid, _, r, _cls in floating:              # floating windows are on top: their top strip moves them
        x0, y0, x1, y1 = r["x"] - bw, r["y"] - bw, r["x"] + r["width"] + bw, r["y"] + r["height"] + bw
        if x0 <= px <= x1 and y0 - outer <= py <= y0 + FLOAT_GRIP:
            return ("move", wid, "", "")
    for wid, _, r, _cls in tiled:
        x0, y0, x1, y1 = r["x"] - bw, r["y"] - bw, r["x"] + r["width"] + bw, r["y"] + r["height"] + bw
        if not (x0 - outer <= px <= x1 + outer and y0 - outer <= py <= y1 + outer): continue
        v = "left" if px <= x0 + INNER else "right" if px >= x1 - INNER else ""
        h = "top" if py <= y0 + INNER else "bottom" if py >= y1 - INNER else ""
        if v and not has_neighbour(wid, v): v = ""
        if h and not has_neighbour(wid, h): h = ""
        if not v and not h: continue
        return ("resize", wid, v, h)
    return None

for m in MODS + STUCK_MODS:
    root.grab_button(1, m, False, EVMASK, X.GrabModeSync, X.GrabModeAsync, X.NONE, X.NONE)
d.flush()

def bar_ids():
    out = subprocess.run(["xdotool", "search", "--class", "Polybar"], capture_output=True, text=True).stdout.split()
    return {int(x) for x in out}
def release_stuck_modifiers():
    mm = d.get_modifier_mapping()      # rows: shift, lock, control, mod1..mod5
    for row in (mm[0], mm[2], mm[3]):
        for kc in row:
            if kc: xtest.fake_input(d, X.KeyRelease, kc)
    d.flush()

drag = None
while True:
    e = d.next_event()
    if e.type == X.ButtonPress:
        if e.state & (X.ControlMask | X.Mod1Mask | X.ShiftMask) and e.child.id in bar_ids():
            release_stuck_modifiers()                       # unfreeze a latched Ctrl/Alt/Shift
            d.allow_events(X.ReplayPointer, e.time); d.flush(); continue
        h = None
        try: h = hit(e.root_x, e.root_y)
        except Exception: h = None
        if not h:
            d.allow_events(X.ReplayPointer, e.time); d.flush(); continue
        d.allow_events(X.AsyncPointer, e.time)
        kind, wid, v, hz = h
        c = CUR["c"] if kind == "move" or (v and hz) else CUR["h"] if v else CUR["v"]
        d.change_active_pointer_grab(EVMASK, c, e.time); d.flush()
        drag = {"kind": kind, "wid": wid, "v": v, "h": hz, "x": e.root_x, "y": e.root_y}
    elif e.type == X.MotionNotify and drag:
        while d.pending_events():                       # compress motion, stop at release
            e2 = d.next_event()
            if e2.type == X.MotionNotify: e = e2
            elif e2.type == X.ButtonRelease: e = e2; break
        if e.type == X.ButtonRelease:
            drag = None; continue
        dx, dy = e.root_x - drag["x"], e.root_y - drag["y"]
        if dx == 0 and dy == 0: continue
        if drag["kind"] == "move":
            bspc("node", drag["wid"], "-v", str(dx), str(dy))
        else:
            if drag["v"]: bspc("node", drag["wid"], "-z", drag["v"], str(dx), "0")
            if drag["h"]: bspc("node", drag["wid"], "-z", drag["h"], "0", str(dy))
        drag["x"], drag["y"] = e.root_x, e.root_y
    elif e.type == X.ButtonRelease:
        drag = None
