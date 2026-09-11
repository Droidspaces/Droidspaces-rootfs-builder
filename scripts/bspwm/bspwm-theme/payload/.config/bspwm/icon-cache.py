#!/usr/bin/env python3
"""Pre-render launcher icons to PNG so rofi can load them instantly.

Rofi resolves each app icon through the (huge) Papirus theme and rasterises the SVG on every launch.
This renders every visible app's icon once to ~/.cache/app-icons/<name>.png and writes/updates a local
desktop-entry override pointing Icon= at that file. Safe to run any time; only re-renders missing icons.
"""
import os, glob, configparser, gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GdkPixbuf

SIZE = 96
cache = os.path.expanduser("~/.cache/app-icons"); os.makedirs(cache, exist_ok=True)
local = os.path.expanduser("~/.local/share/applications"); os.makedirs(local, exist_ok=True)
theme = Gtk.IconTheme.new(); theme.set_custom_theme("Papirus-Dark")

def render(icon):
    if not icon: return None
    base = os.path.basename(icon)
    if os.path.isabs(icon): base = base.rsplit('.', 1)[0]     # theme names keep their dots: org.xfce.thunar
    out = os.path.join(cache, base + '.png')
    if os.path.exists(out): return out
    try:
        if os.path.isabs(icon):
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon, SIZE, SIZE, True)
        else:
            info = theme.lookup_icon(icon, SIZE, Gtk.IconLookupFlags.FORCE_SIZE)
            if info is None: return None
            pb = info.load_icon()
        pb.savev(out, "png", [], []); return out
    except Exception:
        return None

seen = set(); made = 0
for d in (local, "/usr/share/applications"):
    for f in sorted(glob.glob(d + "/*.desktop")):
        name = os.path.basename(f)
        if name in seen: continue
        seen.add(name)
        c = configparser.RawConfigParser(strict=False, interpolation=None)
        try: c.read(f, encoding="utf-8")
        except Exception: continue
        if "Desktop Entry" not in c: continue
        e = c["Desktop Entry"]
        if e.get("type", "Application") != "Application" or e.get("nodisplay", "false").lower() == "true": continue
        icon = e.get("icon", "")
        if icon.startswith(cache + "/"):                                   # our own override: re-read the original icon name
            sysf = os.path.join("/usr/share/applications", name)
            if os.path.exists(sysf):
                c2 = configparser.RawConfigParser(strict=False, interpolation=None); c2.read(sysf, encoding="utf-8")
                icon = c2["Desktop Entry"].get("icon", "") if "Desktop Entry" in c2 else ""
            else: continue
        elif icon.endswith(".png") and os.path.isabs(icon): continue     # already a direct PNG
        png = render(icon)
        if not png: continue
        src = open(f, encoding="utf-8").read().splitlines()
        out = []; replaced = False
        for ln in src:
            if ln.startswith("Icon=") and not replaced:
                out.append("Icon=" + png); replaced = True
            elif ln.startswith("Icon=") and replaced:
                out.append(ln)                                          # action groups keep their own icons
            else: out.append(ln)
        if not replaced: out.insert(1, "Icon=" + png)
        dst = os.path.join(local, name)
        new = "\n".join(out) + "\n"
        if not os.path.exists(dst) or open(dst, encoding="utf-8").read() != new:
            open(dst, "w", encoding="utf-8").write(new); made += 1
print(f"icons cached in {cache}, {made} desktop overrides updated")
