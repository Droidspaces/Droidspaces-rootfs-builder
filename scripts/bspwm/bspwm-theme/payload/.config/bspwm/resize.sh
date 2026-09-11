#!/bin/sh
step=${2:-80}
case "$1" in
  grow)   bspc node -z right  "$step" 0 2>/dev/null || bspc node -z left  "-$step" 0 2>/dev/null
          bspc node -z bottom 0 "$step" 2>/dev/null || bspc node -z top   0 "-$step" 2>/dev/null ;;
  shrink) bspc node -z right  "-$step" 0 2>/dev/null || bspc node -z left  "$step" 0 2>/dev/null
          bspc node -z bottom 0 "-$step" 2>/dev/null || bspc node -z top   0 "$step" 2>/dev/null ;;
esac
