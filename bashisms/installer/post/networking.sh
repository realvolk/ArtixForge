#!/usr/bin/env bash
set -Eeuo pipefail

setup_networking() {
    local network_stack="${NETWORK_STACK:-dhcpcd+iwd}"
    local init="${INIT:-openrc}"

    [[ "${network_stack}" == "none" ]] && return 0

    local -a conflict_stacks=()
    case "${network_stack}" in
        networkmanager) conflict_stacks=(dhcpcd+iwd connman) ;;
        connman)        conflict_stacks=(networkmanager dhcpcd+iwd) ;;
        dhcpcd+iwd)     conflict_stacks=(networkmanager connman) ;;
    esac

    local stack
    for stack in "${conflict_stacks[@]}"; do
        local -a other_pkgs=()
        mapfile -t other_pkgs < <(resolve_network_packages "${stack}" "${init}")
        local pkg
        local -a found=()
        for pkg in "${other_pkgs[@]}"; do
            pacman -Q "${pkg}" &>/dev/null && found+=("${pkg}")
        done
        if [[ ${#found[@]} -gt 0 ]]; then
            log_warn "${stack} packages are installed but ${network_stack} was selected. Remove manually if conflicts arise."
        fi
    done

    local -a pkgs=()
    mapfile -t pkgs < <(resolve_network_packages "${network_stack}" "${init}")

    local -a to_install=()
    local pkg
    for pkg in "${pkgs[@]}"; do
        pacman -Q "${pkg}" &>/dev/null || to_install+=("${pkg}")
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        pkg_install "${to_install[@]}"
    else
        log_info "Network packages already installed — skipping."
    fi

    local raw_services
    raw_services="$(resolve_network_services "${network_stack}")"
    [[ -n "${raw_services}" ]] || return 0
    local svc
    for svc in ${raw_services}; do
        enable_service "${svc}" || log_warn "Failed to enable ${svc}"
    done
}