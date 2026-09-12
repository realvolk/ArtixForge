#!/usr/bin/env bash
set -Eeuo pipefail

pkg_install() {
    local -a pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    local -a uniq=()
    local -A seen=()
    local p
    for p in "${pkgs[@]}"; do
        [[ -n "${p}" ]] || continue
        [[ -z "${seen[${p}]:-}" ]] || continue
        seen["${p}"]=1
        uniq+=("${p}")
    done
    [[ ${#uniq[@]} -gt 0 ]] || return 0
    retry_command "package install" pacman --color=never --noconfirm --needed -S "${uniq[@]}"
}

pkg_install_from() {
    local -a pkgs=()
    mapfile -t pkgs
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    pkg_install "${pkgs[@]}"
}

pkg_remove() {
    local -a pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    pacman --color=never --noconfirm -Rdd "${pkgs[@]}" 2>/dev/null || true
}

pkg_query_installed() {
    pacman -Qq 2>/dev/null
}

pkg_exists() {
    pacman -Si "$1" >/dev/null 2>&1
}

pkg_verify_list() {
    local -a missing=()
    local p
    for p in "$@"; do
        [[ -n "${p}" ]] || continue
        pkg_exists "${p}" || missing+=("${p}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Packages not found in configured repos: ${missing[*]}"
        return 1
    fi
    return 0
}