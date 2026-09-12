# Source this. Exports everything that depends on the saved UI scale and accent.
. "$HOME/.config/bspwm/lib.sh"
UI_SCALE=$(cfg_get SCALE 1.25)
case "$UI_SCALE" in 1|1.25|1.5|1.75|2) ;; *) UI_SCALE=1.25 ;; esac
export UI_SCALE
export POLYBAR_DPI=$(awk "BEGIN{printf \"%d\", 96*$UI_SCALE}")
export GDK_SCALE=$(awk "BEGIN{print ($UI_SCALE>=1.5)?2:1}")
export GDK_DPI_SCALE=$(awk "BEGIN{print 1/$GDK_SCALE}")
export QT_SCALE_FACTOR="$UI_SCALE"
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export XCURSOR_SIZE=$(awk "BEGIN{printf \"%d\", 24*$UI_SCALE}")
case "$(cfg_get GAPS comfy)" in none) g=0;; compact) g=10;; spacious) g=28;; *) g=18;; esac
export UI_GAP=$(awk "BEGIN{printf \"%d\", $g*$UI_SCALE}")
export UI_BORDER=$(awk "BEGIN{printf \"%d\", $(cfg_get BORDER 2)*$UI_SCALE}")
export UI_ACCENT=$(accent_hex "$(cfg_get ACCENT lavender)")
if [ "$(cfg_get BAR_STYLE floating)" = attached ]; then
  export UI_BAR_WIDTH=100% UI_BAR_OFFSET_X=0 UI_BAR_OFFSET_Y=0 UI_BAR_RADIUS=0 UI_BAR_MARGIN=0
else
  # floating bars line up with the visible edge of a tiled window: gap minus border
  # bspwm tiles a lone window from (gap - border) to (width - gap - border): match that span exactly
  g=$UI_GAP; [ "$g" -lt 10 ] && g=10; m=$((g - UI_BORDER)); [ "$m" -lt 6 ] && m=6
  export UI_BAR_WIDTH="100%:-$((2 * g))px" UI_BAR_OFFSET_X="$m" UI_BAR_OFFSET_Y="$m" UI_BAR_RADIUS=18 UI_BAR_MARGIN="$g"
fi
# Top-bar distro logo (Nerd Font "Linux Logos" block, shipped with the theme). ID_LIKE is
# tried after ID so derivatives fall in the right place for free: archarm/artix -> arch,
# kali -> its own dragon. Anything unrecognised gets Tux rather than a wrong distro's mark.
# Sourced in a subshell so os-release's NAME/VERSION/... do not leak into the session.
for _id in $(. /etc/os-release 2>/dev/null; echo "$ID $ID_LIKE"); do
  case "$_id" in
    ubuntu)  UI_LOGO=""; UI_LOGO_FG="#fab387"; break ;;
    kali)    UI_LOGO=""; UI_LOGO_FG="#89b4fa"; break ;;
    debian)  UI_LOGO=""; UI_LOGO_FG="#f38ba8"; break ;;
    arch|artix) UI_LOGO=""; UI_LOGO_FG="#89dceb"; break ;;
    alpine)  UI_LOGO=""; UI_LOGO_FG="#89b4fa"; break ;;
    fedora)  UI_LOGO=""; UI_LOGO_FG="#89b4fa"; break ;;
  esac
done
export UI_LOGO="${UI_LOGO:-}" UI_LOGO_FG="${UI_LOGO_FG:-#cdd6f4}"
# polybar fakes transparency by copying the root pixmap, and gets it wrong outside the bars'
# rounded corners - the bottom dock ends up with a grey wedge in each corner. Only turn it on
# when no compositor is running to do it properly; without either, the corners render black.
if [ "$(cfg_get COMPOSITOR on)" = on ]; then export UI_PSEUDO_TRANS=false; else export UI_PSEUDO_TRANS=true; fi
case "$(cfg_get DOCK full)" in
  compact) export UI_DOCK_LEFT="apps terminal files windows" UI_DOCK_CENTER="sep winmenu layout float fullscreen sep" UI_DOCK_RIGHT="send close" ;;
  *)       export UI_DOCK_LEFT="apps terminal files windows" UI_DOCK_CENTER="sep swap-prev swap-next shrink grow sep rotate balance layout sep float fullscreen send sep" UI_DOCK_RIGHT="close" ;;
esac
# A dead/unreachable PulseAudio server (host bridge not connected, or the container
# started without audio) makes polybar's internal/pulseaudio module fail to connect,
# which stalls the whole top bar's render loop instead of just disabling that module.
# Drop it from the bar rather than lose the gear/power buttons behind it.
if timeout 1 pactl info >/dev/null 2>&1; then
  export UI_TOP_RIGHT="volume battery scale power"
else
  export UI_TOP_RIGHT="battery scale power"
fi
