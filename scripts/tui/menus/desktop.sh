#!/usr/bin/env bash
set -Eeuo pipefail

tui_select_desktop() {
    local d
    d=$(tui_menu "Desktop Environment" "Select desktop:" \
        "xfce4" "lxqt" "kde" "lxde" "mango" "hyprland" "niri" "sway" \
        "i3wm" "dwm" "vxwm" "icewm" "cinnamon" "budgie" "moksha" "cosmic" "none") || return 1
    state_set WM_DE "${d}"

    if [[ "${d}" == "kde" ]]; then
        local profile
        profile=$(tui_menu "KDE Profile" "Select KDE Plasma profile:" \
            "minimal" "desktop" "full") || return 1
        state_set KDE_PROFILE "${profile}"
    else
        state_set KDE_PROFILE "none"
    fi
}

tui_select_display_manager() {
    local wm dm
    wm="$(state_get WM_DE none)"
    if [[ "${wm}" =~ ^(none|dwm|i3wm|icewm|hyprland|mango|niri|sway)$ ]]; then
        dm=$(tui_menu "Display Manager" "Select display manager:" "None" "LightDM" "SDDM") || return 1
    else
        dm=$(tui_menu "Display Manager" "Select display manager:" "LightDM" "SDDM") || return 1
    fi
    state_set DISPLAY_MANAGER "${dm,,}"
}

tui_select_xstack() {
    local wm stack
    wm="$(state_get WM_DE none)"
    if [[ "${wm}" == "none" ]]; then
        state_set X_STACK "none"
        return 0
    fi
    stack=$(tui_menu "Display Stack" "Select display stack:" "X.Org" "None") || return 1
    case "${stack}" in
        "X.Org") state_set X_STACK "xorg" ;;
        *)       state_set X_STACK "none" ;;
    esac
}