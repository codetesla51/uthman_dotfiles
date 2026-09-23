#!/bin/sh
# pkg-sizes.sh — batch download-size lookup for PkgManager
# Usage: pkg-sizes.sh off pkg1 pkg2...  -> pacman -Si (single call, fast)
#        pkg-sizes.sh aur pkg1 pkg2...  -> yay -Si (single call)
# Output: "name|size" per line, e.g. "firefox|84.78 MiB"
# AUR source packages have no size — they are simply omitted.
mode="$1"; shift
[ $# -eq 0 ] && exit 0
case "$mode" in
  off)
    pacman -Si "$@" 2>/dev/null | awk '
      /^Name/ { n=$3 }
      /^Download Size/ { d=$4" "$5 }
      /^$/ { if (n && d) { print n"|"d; n=0; d=0 } }
      END { if (n && d) print n"|"d }
    '
    ;;
  aur)
    yay -Si "$@" 2>/dev/null | awk '
      /^Name/ { if (n && d) print n"|"d; n=$3; d=0 }
      /^Download Size/ { d=$4" "$5 }
      /^Installed Size/ { if (!d) d=$4" "$5 }
      END { if (n && d) print n"|"d }
    '
    ;;
esac
