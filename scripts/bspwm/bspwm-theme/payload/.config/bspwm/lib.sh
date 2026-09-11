# Shared helpers for the touch desktop. Source this; do not run it.
CFG="$HOME/.config/bspwm/settings.conf"
cfg_get() { # cfg_get KEY DEFAULT
  v=$(grep -s "^$1=" "$CFG" | tail -1 | cut -d= -f2-)
  [ -n "$v" ] && { printf '%s\n' "$v"; return; }
  case "$1" in   # legacy single-value files from earlier versions
    SCALE) v=$(cat "$HOME/.config/bspwm/scale" 2>/dev/null) ;;
    FOCUS) v=$(cat "$HOME/.config/bspwm/focus" 2>/dev/null) ;;
  esac
  printf '%s\n' "${v:-$2}"
}
cfg_set() { # cfg_set KEY VALUE
  touch "$CFG"; grep -v "^$1=" "$CFG" > "$CFG.tmp"; printf '%s=%s\n' "$1" "$2" >> "$CFG.tmp"; mv "$CFG.tmp" "$CFG"
}
accent_hex() { # accent_hex NAME
  case "$1" in
    rosewater) echo '#f5e0dc';; flamingo) echo '#f2cdcd';; pink) echo '#f5c2e7';; mauve) echo '#cba6f7';;
    red) echo '#f38ba8';; maroon) echo '#eba0ac';; peach) echo '#fab387';; yellow) echo '#f9e2af';;
    green) echo '#a6e3a1';; teal) echo '#94e2d5';; sky) echo '#89dceb';; sapphire) echo '#74c7ec';;
    blue) echo '#89b4fa';; *) echo '#b4befe';;
  esac
}
# menu PROMPT MESG ACTIVE_INDEX  (menu lines on stdin; prints the chosen line; fails on cancel)
menu() {
  p="$1"; m="$2"; a="$3"
  if [ -n "$a" ]; then rofi -dmenu -i -p "$p" ${m:+-mesg "$m"} -a "$a" -theme "$HOME/.config/rofi/settings.rasi"
  else rofi -dmenu -i -p "$p" ${m:+-mesg "$m"} -theme "$HOME/.config/rofi/settings.rasi"; fi
}
# pick PROMPT CURRENT "opt1 opt2 ..."  -> prints chosen option (current row highlighted)
pick() {
  p="$1"; cur="$2"; i=0; act=""
  for o in $3; do [ "$o" = "$cur" ] && act=$i; i=$((i+1)); done
  printf '%s\n' $3 | menu "$p" "" "$act"
}
notify() { notify-send -a Settings "$@"; }
