#!/bin/sh
# Wallpaper picker: lists every supported image anywhere under ~/Pictures (subfolders
# included), labeled by their path relative to ~/Pictures so duplicate filenames in
# different folders stay distinguishable.
dir="$HOME/Pictures"; link="$HOME/.config/bspwm/wallpaper"
if [ "$1" = "set" ]; then
  f="$2"; [ -f "$f" ] || exit 1
  case "$(file -b --mime-type "$f")" in image/*) ;; *) notify-send "Wallpaper" "Not an image: $(basename "$f")"; exit 1;; esac
  ln -sfn "$(readlink -f "$f")" "$link"
  "$HOME/.config/bspwm/wallpaper-render.sh"
  notify-send "Wallpaper" "$(basename "$f")"
  exit 0
fi
choice=$(
  find "$dir" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | sort |
  while IFS= read -r f; do printf '%s\000icon\037%s\n' "${f#"$dir"/}" "$f"; done |
  rofi -dmenu -sync -i -p "Wallpaper" -show-icons -theme "$HOME/.config/rofi/wallpaper.rasi"
) || exit 0
[ -n "$choice" ] && "$0" set "$dir/$choice"
