#!/bin/sh
# Unified settings hub (gear icon on the top bar). Everything is saved to ~/.config/bspwm/settings.conf
# and re-applied on every start by apply.sh.
. "$HOME/.config/bspwm/lib.sh"
B="$HOME/.config/bspwm"
apply() { "$B/apply.sh"; }
bars()  { "$HOME/.config/polybar/launch.sh"; }
term()  { xfce4-terminal -e "sh -c '$1'" & }

appearance() { while :; do
  sc=$(cfg_get SCALE 1.25); pct=$(awk "BEGIN{printf \"%d\", $sc*100}")
  c=$(printf '%s\n' "  UI scale: ${pct}%" "  Wallpaper" "  Accent colour: $(cfg_get ACCENT lavender)" "  Gaps: $(cfg_get GAPS comfy)" "  Border width: $(cfg_get BORDER 2)" "  Bar style: $(cfg_get BAR_STYLE floating)" "  Animations: $(cfg_get ANIM subtle)" "  Shadows: $(cfg_get SHADOWS off)" "  Font: $(cfg_get FONT Inter)" "  Icons: $(cfg_get ICONS Papirus-Dark)" "  Cursor: $(cfg_get CURSOR Adwaita)" "  Back" \
      | menu "Appearance" "" "") || return
  case "$c" in
    *"UI scale"*) n=$(pick "UI scale" "$pct%" "100% 125% 150% 175% 200%") && [ -n "$n" ] && { cfg_set SCALE "$(awk "BEGIN{print ${n%\%}/100}")"; apply; bars; notify "UI scale $n" "Reopen running apps to resize them."; } ;;
    *Wallpaper)   "$B/wallpaper.sh" ;;
    *Accent*)     n=$(pick "Accent colour" "$(cfg_get ACCENT lavender)" "lavender blue sapphire sky teal green yellow peach maroon red mauve pink flamingo rosewater") && [ -n "$n" ] && { cfg_set ACCENT "$n"; apply; bars; } ;;
    *Gaps*)       n=$(pick "Gaps" "$(cfg_get GAPS comfy)" "none compact comfy spacious") && [ -n "$n" ] && { cfg_set GAPS "$n"; apply; } ;;
    *Border*)     n=$(pick "Border width" "$(cfg_get BORDER 2)" "0 1 2 3 4") && [ -n "$n" ] && { cfg_set BORDER "$n"; apply; } ;;
    *Animations*) n=$(pick "Animations" "$(cfg_get ANIM subtle)" "off subtle smooth") && [ -n "$n" ] && { cfg_set ANIM "$n"; apply; } ;;
    *Shadows*)    n=$(pick "Shadows" "$(cfg_get SHADOWS off)" "off on") && [ -n "$n" ] && { cfg_set SHADOWS "$n"; apply; } ;;
    *Font*)   n=$(printf '%s\n' Inter "Noto Sans" "JetBrains Mono" | menu "Font" "Current: $(cfg_get FONT Inter)" "") && [ -n "$n" ] && { cfg_set FONT "$n"; apply; } ;;
    *Icons*)  n=$(printf '%s\n' Papirus-Dark Papirus-Light Papirus Adwaita Humanity-Dark | menu "Icons" "Current: $(cfg_get ICONS Papirus-Dark)" "") && [ -n "$n" ] && { cfg_set ICONS "$n"; apply; } ;;
    *Cursor*) n=$(printf '%s\n' Adwaita whiteglass redglass handhelds | menu "Cursor" "Current: $(cfg_get CURSOR Adwaita)" "") && [ -n "$n" ] && { cfg_set CURSOR "$n"; apply; } ;;
    *"Bar style"*) n=$(pick "Bar style" "$(cfg_get BAR_STYLE floating)" "floating attached") && [ -n "$n" ] && { cfg_set BAR_STYLE "$n"; apply; bars; } ;;
    *Back) return ;;
  esac; done; }

windows() { while :; do
  c=$(printf '%s\n' "  Focus: $(cfg_get FOCUS tap)" "  Tiling scheme: $(cfg_get SCHEME alternate)" "  Split ratio: $(cfg_get SPLIT 0.5)" "  Single window fills screen: $(cfg_get SINGLE_MONOCLE false)" "  Gapless monocle: $(cfg_get GAPLESS_MONOCLE false)" "  Borderless monocle: $(cfg_get BORDERLESS_MONOCLE true)" "  Back" \
      | menu "Windows" "" "") || return
  case "$c" in
    *"Minimum desktops"*) n=$(pick "Minimum desktops" "$(cfg_get DESKTOPS 2)" "1 2 3 4 5 6") && [ -n "$n" ] && { cfg_set DESKTOPS "$n"; "$B/desktops.sh"; } ;;
    *Focus*)  n=$(pick "Focus" "$(cfg_get FOCUS tap)" "tap hover") && [ -n "$n" ] && { cfg_set FOCUS "$n"; apply; } ;;
    *Tiling*) n=$(pick "Tiling scheme" "$(cfg_get SCHEME alternate)" "alternate longest_side spiral") && [ -n "$n" ] && { cfg_set SCHEME "$n"; apply; } ;;
    *Split*)  n=$(pick "Split ratio" "$(cfg_get SPLIT 0.5)" "0.4 0.5 0.6 0.66") && [ -n "$n" ] && { cfg_set SPLIT "$n"; apply; } ;;
    *"Single window"*) cfg_set SINGLE_MONOCLE "$([ "$(cfg_get SINGLE_MONOCLE false)" = true ] && echo false || echo true)"; apply ;;
    *Gapless*)         cfg_set GAPLESS_MONOCLE "$([ "$(cfg_get GAPLESS_MONOCLE false)" = true ] && echo false || echo true)"; apply ;;
    *Borderless*)      cfg_set BORDERLESS_MONOCLE "$([ "$(cfg_get BORDERLESS_MONOCLE true)" = true ] && echo false || echo true)"; apply ;;
    *Back) return ;;
  esac; done; }

barsmenu() { while :; do
  c=$(printf '%s\n' "  Top bar: $(cfg_get BAR_TOP on)" "  Dock: $(cfg_get BAR_DOCK on)" "  Reload bars" "  Back" | menu "Bars" "" "") || return
  case "$c" in
    *"Top bar"*) cfg_set BAR_TOP "$([ "$(cfg_get BAR_TOP on)" = on ] && echo off || echo on)"; bars ;;
    *Dock*)      cfg_set BAR_DOCK "$([ "$(cfg_get BAR_DOCK on)" = on ] && echo off || echo on)"; bars ;;
    *"Dock layout"*) n=$(pick "Dock layout" "$(cfg_get DOCK full)" "full compact") && [ -n "$n" ] && { cfg_set DOCK "$n"; bars; } ;;
    *Reload*)    bars ;;
    *Back) return ;;
  esac; done; }

system() { while :; do
  c=$(printf '%s\n' "  System info" "  Screenshot" "  Task manager" "  Update packages" "  Notifications: $(cfg_get NOTIFY on)" "  Compositor: $(cfg_get COMPOSITOR on)" "  Kill a window" "  Edit bspwm config" "  Edit bar config" "  Restart bspwm" "  Reset all settings" "  Back" \
      | menu "System" "" "") || return
  case "$c" in
    *"System info")   "$B/sysinfo.sh" ;;
    *Screenshot)      "$B/screenshot.sh" ;;
    *"Task manager")  term "htop || top" ;;
    *Update*)         term "sudo apt update && sudo apt upgrade; echo; echo Done. Press Enter.; read x" ;;
    *Notifications*)  cfg_set NOTIFY "$([ "$(cfg_get NOTIFY on)" = on ] && echo off || echo on)"; apply ;;
    *Compositor*)     cfg_set COMPOSITOR "$([ "$(cfg_get COMPOSITOR on)" = on ] && echo off || echo on)"; apply ;;
    *"Kill a window") notify "Kill a window" "Tap the window to force-close"; xkill >/dev/null 2>&1 & ;;
    *"Edit bspwm"*)   term "\${EDITOR:-micro} $B/bspwmrc" ;;
    *"Edit bar"*)     term "\${EDITOR:-micro} $HOME/.config/polybar/config.ini" ;;
    *"Restart bspwm") bspc wm -r; exit 0 ;;
    *Reset*)          r=$(printf '%s\n' "  Yes, reset everything" "  Cancel" | menu "Reset" "Restores default scale, accent, gaps, focus and bars" "") && case "$r" in *Yes*) rm -f "$CFG" "$B/scale" "$B/focus"; bspc wm -r; exit 0;; esac ;;
    *Back) return ;;
  esac; done; }

autostart() { d="$B/autostart.d"; mkdir -p "$d"; while :; do
  list=""; for f in "$d"/*; do [ -f "$f" ] || continue; [ -x "$f" ] && list="$list  $(basename "$f")\n" || list="$list  $(basename "$f")\n"; done
  c=$(printf "${list}  New script\n  Open folder\n  Back\n" | menu "Autostart" "Runs at login. Tap to enable/disable." "") || return
  case "$c" in
    *"New script") n=$(printf '' | rofi -dmenu -p "Script name" -theme "$HOME/.config/rofi/prompt.rasi") && [ -n "$n" ] && { f="$d/${n%.sh}.sh"; [ -f "$f" ] || printf '#!/bin/sh\n# Started by bspwm at login.\n\n' > "$f"; chmod +x "$f"; term "\${EDITOR:-micro} $f"; } ;;
    *"Open folder") thunar "$d" & ;;
    *Back) return ;;
    *) f="$d/$(printf '%s' "$c" | sed 's/^..//')"; [ -f "$f" ] && { [ -x "$f" ] && chmod -x "$f" || chmod +x "$f"; } ;;
  esac; done; }

section="$1"
while :; do
  case "$section" in
    appearance) appearance ;; windows) windows ;; audio) pavucontrol & ;; bars) barsmenu ;; system) system ;; autostart) autostart ;; power) exec "$B/power.sh" ;;
  esac
  section=$(printf '%s\n' "  Appearance" "  Windows" "  Audio" "  Bars" "  System" "  Autostart" "  Power" | menu "Settings" "" "") || exit 0
  case "$section" in *Appearance) section=appearance;; *Windows) section=windows;; *Audio) section=audio;; *Bars) section=bars;; *System) section=system;; *Autostart) section=autostart;; *Power) section=power;; *) exit 0;; esac
done
