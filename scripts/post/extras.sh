#!/usr/bin/env bash
set -Eeuo pipefail

install_extras() {
    local selected=" ${EXTRAS:-} " pkgs=() init="${INIT:-openrc}"

    [[ -z "${EXTRAS:-}" ]] && return 0

    read -ra pkgs <<< "${EXTRAS}"

    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    log_info "Installing extras: ${pkgs[*]}"
    pacman -S --noconfirm --needed "${pkgs[@]}"

    # Enable services for known packages
    [[ " ${EXTRAS} " == *" firewalld "* ]] && enable_service firewalld
    [[ " ${EXTRAS} " == *" bluez "* ]] && { enable_service bluetoothd; pacman -S --noconfirm --needed bluez-utils "bluez-${init}"; }
    [[ " ${EXTRAS} " == *" zram-tools "* || " ${EXTRAS} " == *" zramen "* ]] && { enable_service zramen; pacman -S --noconfirm --needed "zramen-${init}"; }

    log_info "Extras installation complete."
}