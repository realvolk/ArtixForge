#!/usr/bin/env bash
set -Eeuo pipefail

detect_network_stack() {
    local stack pkg
    local -a found=()

    for stack in networkmanager connman "dhcpcd+iwd"; do
        local -a pkgs
        mapfile -t pkgs < <(resolve_network_packages "${stack}" 2>/dev/null || true)
        [[ ${#pkgs[@]} -gt 0 ]] || continue

        local matched=0
        for pkg in "${pkgs[@]}"; do
            if pacman_root_has "${pkg}"; then
                matched=1
                break
            fi
        done
        [[ ${matched} -eq 1 ]] && found+=("${stack}")
    done

    case "${#found[@]}" in
        0) state_set NETWORK_STACK none ;;
        1) state_set NETWORK_STACK "${found[0]}" ;;
        *)
            state_set NETWORK_STACK "${found[0]}"
            local issues
            issues="$(state_get BOOT_ISSUES none)"
            [[ "${issues}" == "none" ]] && issues=""
            issues+="network-conflict:${found[*]} "
            state_set BOOT_ISSUES "${issues}"
            log_warn "Multiple network stacks detected: ${found[*]}"
            ;;
    esac
}

detect_audio_stack() {
    local stack pkg
    local -a found=()

    for stack in pipewire pulseaudio; do
        local -a pkgs
        mapfile -t pkgs < <(resolve_audio_packages "${stack}" 2>/dev/null || true)
        [[ ${#pkgs[@]} -gt 0 ]] || continue

        for pkg in "${pkgs[@]}"; do
            if pacman_root_has "${pkg}"; then
                found+=("${stack}")
                break
            fi
        done
    done

    case "${#found[@]}" in
        0) state_set AUDIO_STACK none ;;
        1) state_set AUDIO_STACK "${found[0]}" ;;
        *)
            state_set AUDIO_STACK "${found[0]}"
            local issues
            issues="$(state_get BOOT_ISSUES none)"
            [[ "${issues}" == "none" ]] && issues=""
            issues+="audio-conflict:${found[*]} "
            state_set BOOT_ISSUES "${issues}"
            log_warn "Multiple audio stacks detected: ${found[*]}"
            ;;
    esac
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