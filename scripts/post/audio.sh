#!/usr/bin/env bash
set -Eeuo pipefail

setup_audio() {
    local audio_stack="${AUDIO_STACK:-pipewire}" pkgs=()
    
    if [[ "${audio_stack}" == "pipewire" ]]; then
        if pacman -Q jack2 &>/dev/null; then
            log_info "Removing jack2 (replaced by pipewire-jack)..."
            pacman -Rdd --noconfirm jack2 2>/dev/null || log_warn "Failed to remove jack2"
        fi
        if pacman -Q pulseaudio &>/dev/null; then
            log_info "Removing pulseaudio (replaced by pipewire-pulse)..."
            pacman -Rdd --noconfirm pulseaudio pulseaudio-alsa 2>/dev/null || log_warn "Failed to remove pulseaudio"
        fi
        pkgs+=(pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pavucontrol rtkit pipewire-jack)
    elif [[ "${audio_stack}" == "pulseaudio" ]]; then
        if pacman -Q pipewire &>/dev/null; then
            log_info "Removing pipewire (replaced by pulseaudio)..."
            pacman -Rdd --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber 2>/dev/null || log_warn "Failed to remove pipewire"
        fi
        pkgs+=(pulseaudio pulseaudio-alsa alsa-utils pavucontrol)
    else
        return 0
    fi

    local -a to_install=()
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Q "${pkg}" &>/dev/null; then
            to_install+=("${pkg}")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_info "Audio packages already installed — skipping."
        return 0
    fi

    log_info "Installing audio packages..."
    if ! retry_command "audio install" pacman -S --noconfirm --needed "${to_install[@]}"; then
        log_warn "Failed to install ${audio_stack} packages. Audio may not work. Install manually after boot."
    fi
}