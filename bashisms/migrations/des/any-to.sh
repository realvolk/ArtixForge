#!/usr/bin/env bash
set -Eeuo pipefail
MIGRATIONS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${MIGRATIONS_DIR}/common.sh"
current=$(detect_current_de)
target=$(tui_menu "Target Desktop" "Select new desktop:" \
    "kde" "xfce" "lxqt" "lxde" "hyprland" "sway" "niri" \
    "i3wm" "dwm" "vxwm" "icewm" "mango" "none") || exit 1
run_de_migration "$current" "$target"