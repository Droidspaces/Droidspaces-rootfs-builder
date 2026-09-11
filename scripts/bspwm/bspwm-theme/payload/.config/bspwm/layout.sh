#!/bin/sh
l=$(bspc query -T -d | grep -o '"layout":"[a-z]*"' | head -1 | cut -d'"' -f4)
[ "$l" = "monocle" ] && printf '%s\n' '' || printf '%s\n' ''
