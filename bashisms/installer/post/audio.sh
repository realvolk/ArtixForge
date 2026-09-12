#!/usr/bin/env bash
set -Eeuo pipefail

setup_audio() {
    local audio_stack="${AUDIO_STACK:-pipewire}"
    local init="${INIT:-openrc}"

    [[ "${audio_stack}" == "none" ]] && return 0

    local -a conflicts=()
    read -ra conflicts <<< "${AUDIO_CONFLICTS[${audio_stack}]:-}"
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        local installed_conflicts=()
        local pkg
        for pkg in "${conflicts[@]}"; do
            pacman -Q "${pkg}" &>/dev/null && installed_conflicts+=("${pkg}")
        done
        if [[ ${#installed_conflicts[@]} -gt 0 ]]; then
            log_info "Removing conflicting audio packages: ${installed_conflicts[*]}"
            pacman -Rdd --noconfirm "${installed_conflicts[@]}" 2>/dev/null || log_warn "Failed to remove some conflicting audio packages"
        fi
    fi

    local -a pkgs=()
    mapfile -t pkgs < <(resolve_audio_packages "${audio_stack}")
    mapfile -t -O "${#pkgs[@]}" pkgs < <(resolve_audio_service_packages "${audio_stack}" "${init}")

    [[ ${#pkgs[@]} -gt 0 ]] || return 0

    local -a to_install=()
    local pkg
    for pkg in "${pkgs[@]}"; do
        pacman -Q "${pkg}" &>/dev/null || to_install+=("${pkg}")
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_info "Audio packages already installed — skipping."
        return 0
    fi

    log_info "Installing audio packages..."
    if ! pkg_install "${to_install[@]}"; then
        log_warn "Failed to install ${audio_stack} packages. Audio may not work. Install manually after boot."
    fi
}