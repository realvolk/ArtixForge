#!/usr/bin/env bash
set -Eeuo pipefail

detect_network_stack() {
    if pacman_root_has networkmanager; then
        state_set NETWORK_STACK networkmanager
    elif pacman_root_has connman; then
        state_set NETWORK_STACK connman
    elif pacman_root_has dhcpcd || pacman_root_has iwd; then
        state_set NETWORK_STACK dhcpcd+iwd
    else
        state_set NETWORK_STACK none
    fi
}

detect_audio_stack() {
    if pacman_root_has pipewire; then
        state_set AUDIO_STACK pipewire
    elif pacman_root_has pulseaudio; then
        state_set AUDIO_STACK pulseaudio
    else
        state_set AUDIO_STACK none
    fi
}

detect_hostname() {
    local hostname='artix'
    [[ -f "${ROOT}/etc/hostname" ]] && hostname="$(tr -d '[:space:]' < "${ROOT}/etc/hostname")"
    state_set HOSTNAME "${hostname}"
}

detect_user_shell() {
    local shell
    shell="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $7; exit}' "${ROOT}/etc/passwd" 2>/dev/null || true)"
    shell="${shell##*/}"
    case "${shell}" in
        bash|zsh|fish) ;;
        *) shell='bash' ;;
    esac
    state_set USER_SHELL "${shell}"
}

detect_ucode() {
    if pacman_root_has intel-ucode; then
        state_set CPU_UCODE intel
    elif pacman_root_has amd-ucode; then
        state_set CPU_UCODE amd
    else
        state_set CPU_UCODE none
    fi
}