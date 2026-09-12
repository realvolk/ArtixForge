#!/usr/bin/env bash
set -Eeuo pipefail

detect_extras() {
    local extras=()
    local -a pkg_list=(
        git flatpak fastfetch firewalld bluez
        fzf zoxide starship eza btop htop nvtop tmux usb_modeswitch rsvc
        nano vim neovim micro helix
        firefox chromium qutebrowser
        ranger lf nnn thunar
        alacritty kitty foot
        mpv feh
    )

    for pkg in "${pkg_list[@]}"; do
        pacman_root_has "${pkg}" && extras+=("${pkg}")
    done

    if pacman_root_has zram-generator || pacman_root_has zramen; then
        extras+=(zram-tools)
    fi

    state_set EXTRAS "${extras[*]}"
}

detect_repositories() {
    if grep -Eq '^\[(core|extra|multilib)\]' "${ROOT}/etc/pacman.conf" 2>/dev/null; then
        state_set ENABLE_ARCH_REPOS yes
    else
        state_set ENABLE_ARCH_REPOS no
    fi
    if grep -q '^\[chaotic-aur\]' "${ROOT}/etc/pacman.conf" 2>/dev/null; then
        state_set HAS_CHAOTIC yes
    else
        state_set HAS_CHAOTIC no
    fi
}

detect_coreutils() {
    if pacman_root_has busybox; then
        if [[ "$(readlink "${ROOT}/usr/bin/ls" 2>/dev/null)" == *"busybox"* ]] || \
           [[ "$(readlink "${ROOT}/usr/bin/cp" 2>/dev/null)" == *"busybox"* ]]; then
            state_set COREUTILS busybox
            return 0
        fi
    fi
    if pacman_root_has uutils-coreutils; then
        state_set COREUTILS uutils
    elif [[ -f "${ROOT}/etc/artix-poweruser/world.txt" ]] && grep -q 'artix-coreutils' "${ROOT}/etc/artix-poweruser/world.txt" 2>/dev/null; then
        state_set COREUTILS artix
    else
        state_set COREUTILS gnu
    fi
}

detect_poweruser() {
    if [[ -f "${ROOT}/etc/artix-poweruser/world.txt" ]] || [[ -f "${ROOT}/usr/local/bin/gartix" ]]; then
        state_set POWER_USER yes
        if [[ -f "${ROOT}/etc/artix-poweruser/world.txt" ]]; then
            local pkgs
            pkgs=$(tr '\n' ' ' < "${ROOT}/etc/artix-poweruser/world.txt")
            state_set POWERUSER_PACKAGES "${pkgs}"
        fi
        if [[ -f "${ROOT}/usr/share/artix-poweruser/profile/active" ]]; then
            state_set POWERUSER_PROFILE "$(tr -d '[:space:]' < "${ROOT}/usr/share/artix-poweruser/profile/active")"
        fi
    else
        state_set POWER_USER no
    fi
}

detect_priv_escalation() {
    if pacman_root_has doas && [[ -f "${ROOT}/etc/doas.conf" ]]; then
        state_set PRIV_ESCALATION doas
    elif pacman_root_has sudo; then
        state_set PRIV_ESCALATION sudo
    else
        state_set PRIV_ESCALATION none
    fi
}