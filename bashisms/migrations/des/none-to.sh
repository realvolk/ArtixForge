#!/usr/bin/env bash
set -Eeuo pipefail
MIGRATIONS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${MIGRATIONS_DIR}/common.sh"
target=$(tui_menu "Target Desktop" "Select desktop to install:" \
    "kde" "xfce" "lxqt" "lxde" "hyprland" "sway" "niri" \
    "i3wm" "dwm" "vxwm" "icewm" "mango") || exit 1
run_de_migration "none" "$target"