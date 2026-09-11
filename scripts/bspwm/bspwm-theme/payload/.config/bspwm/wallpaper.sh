#!/bin/sh
# Wallpaper picker. Images live in ~/Pictures/wallpapers; "Browse" opens a file browser for anything else.
dir="$HOME/Pictures/wallpapers"; link="$HOME/.config/bspwm/wallpaper"
if [ "$1" = "set" ]; then
  f="$2"; [ -f "$f" ] || exit 1
  case "$(file -b --mime-type "$f")" in image/*) ;; *) notify-send "Wallpaper" "Not an image: $(basename "$f")"; exit 1;; esac
  ln -sfn "$(readlink -f "$f")" "$link"
  "$HOME/.config/bspwm/wallpaper-render.sh"
  notify-send "Wallpaper" "$(basename "$f")"
  exit 0
fi
choice=$( { for f in "$dir"/*.png "$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.webp; do
      [ -f "$f" ] || continue; printf '%s\000icon\037%s\n' "$(basename "$f")" "$f"; done
    printf '  Browse for an image…\n'; } \
  | rofi -dmenu -i -p "Wallpaper" -show-icons -theme "$HOME/.config/rofi/wallpaper.rasi") || exit 0
case "$choice" in
  *"Browse for an image"*) rofi -show filebrowser -theme "$HOME/.config/rofi/filebrowser.rasi" ;;
  "") ;;
  *) "$0" set "$dir/$choice" ;;
esac
