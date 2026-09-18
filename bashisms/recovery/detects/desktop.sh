#!/usr/bin/env bash
set -Eeuo pipefail

detect_desktop() {
    local de pattern
    for de in "${DE_DETECT_ORDER[@]}"; do
        pattern="${DE_DETECT_PATTERN[$de]:-}"
        [[ -n "${pattern}" ]] || continue
        if pacman_root_has "${pattern}"; then
            state_set WM_DE "${de}"
            if [[ "${de}" == "kde" ]]; then
                if pacman_root_has kde-applications; then
                    state_set KDE_PROFILE full
                elif pacman_root_has dolphin; then
                    state_set KDE_PROFILE minimal
                else
                    state_set KDE_PROFILE desktop
                fi
            fi
            return 0
        fi
    done

    if pacman_root_has lxde-common || pacman_root_has lxde; then
        state_set WM_DE lxde
    elif [[ -f "${ROOT}/usr/local/bin/vxwm" ]]; then
        state_set WM_DE vxwm
    else
        state_set WM_DE none
    fi
}

detect_display_manager() {
    if pacman_root_has sonic-login-manager; then
        state_set DISPLAY_MANAGER soniclogin
    elif pacman_root_has sddm; then
        state_set DISPLAY_MANAGER sddm
    elif pacman_root_has lightdm; then
        state_set DISPLAY_MANAGER lightdm
    else
        state_set DISPLAY_MANAGER none
    fi
}

detect_xstack() {
    if pacman_root_has xlibre-xserver; then
        state_set X_STACK xlibre
    elif pacman_root_has xorg-server-tearfree; then
        state_set X_STACK xorg-tearfree
    elif pacman_root_has xorg-server; then
        state_set X_STACK xorg
    else
        state_set X_STACK none
    fi
}

detect_seat_manager() {
    if pacman_root_has seatd; then
        state_set SEAT_MANAGER seatd
    else
        state_set SEAT_MANAGER elogind
    fi
}