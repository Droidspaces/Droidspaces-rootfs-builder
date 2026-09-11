#!/bin/sh
# Touch power menu. Power off / Restart ask for your password (sudo) in a rofi prompt.
# POWER_DRY_RUN=1 makes systemctl only print what it would do (used by tests).
theme="$HOME/.config/rofi/powermenu.rasi"
choice=$(printf '%s\n' "  Power off" "  Restart" "  Cancel" \
  | rofi -dmenu -i -p "" -theme "$theme") || exit 0
run_root() {
  [ "${POWER_DRY_RUN:-0}" = 1 ] && set -- "$@" --dry-run
  # Already root (the default DESKTOP_USER): no sudo, no password, ever.
  if [ "$(id -u)" = 0 ]; then
    "$@"; [ "${POWER_DRY_RUN:-0}" = 1 ] && notify-send "Power (dry run)" "$*"
    return
  fi
  # Passwordless sudo (NOPASSWD): try non-interactively before asking for anything.
  if sudo -n true 2>/dev/null; then
    sudo "$@"; [ "${POWER_DRY_RUN:-0}" = 1 ] && notify-send "Power (dry run)" "$*"
    return
  fi
  pw=$(printf '' | rofi -dmenu -password -p "Password for $(id -un)" -theme "$HOME/.config/rofi/prompt.rasi"); rc=$?
  [ $rc -eq 1 ] && exit 0                      # Escape / cancelled
  [ $rc -ne 0 ] && { notify-send -u critical "Power" "Password prompt failed (rofi exit $rc)"; exit 1; }
  err=$(printf '%s\n' "$pw" | sudo -S -p '' "$@" 2>&1 >/dev/null) && { [ "${POWER_DRY_RUN:-0}" = 1 ] && notify-send "Power (dry run)" "$*"; return 0; }
  case "$err" in
    *"incorrect password"*|*"Sorry"*|*"try again"*) notify-send -u critical "Power" "Wrong password" ;;
    *) notify-send -u critical "Power" "Failed: ${err:-unknown error}" ;;
  esac
}
case "$choice" in
  *"Power off")       run_root systemctl poweroff ;;
  *"Restart")         run_root systemctl reboot ;;
esac
