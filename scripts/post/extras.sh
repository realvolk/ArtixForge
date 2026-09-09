#!/usr/bin/env bash
set -Eeuo pipefail

install_extras() {
    local selected=" ${EXTRAS:-} " pkgs=() init="${INIT:-openrc}"

    local -a CURATED_NAMES=(
        git flatpak firewalld bluez zram-tools usb_modeswitch
        nano vim neovim micro helix
        firefox chromium qutebrowser
        ranger lf nnn thunar
        alacritty kitty foot
        fastfetch fzf zoxide starship eza tmux
        btop htop nvtop
        mpv feh
        rsvc swaybg swaylock waybar wofi fuzzel hyprpaper
    )

    local curated_str=" ${CURATED_NAMES[*]} "

    [[ "${selected}" == *" git "* ]] && pkgs+=(git base-devel)

    [[ "${selected}" == *" flatpak "* ]] && pkgs+=(flatpak)
    [[ "${selected}" == *" firewalld "* ]] && pkgs+=(firewalld "firewalld-${init}")
    [[ "${selected}" == *" bluez "* ]] && pkgs+=(bluez bluez-utils "bluez-${init}")
    [[ "${selected}" == *" zram-tools "* ]] && pkgs+=(zramen "zramen-${init}")
    [[ "${selected}" == *" usb_modeswitch "* ]] && pkgs+=(usb_modeswitch)

    local -a SIMPLE=(
        nano vim neovim micro helix
        firefox chromium qutebrowser
        ranger lf nnn thunar
        alacritty kitty foot
        fastfetch fzf zoxide starship eza tmux
        btop htop nvtop
        mpv feh
    )
    for pkg in "${SIMPLE[@]}"; do
        [[ "${selected}" == *" ${pkg} "* ]] && pkgs+=("${pkg}")
    done

    if [[ "${selected}" == *" rsvc "* ]]; then
        if [[ "${init}" != 'runit' ]]; then
            log_warn "rsvc only supported on runit systems. Skipping."
        else
            [[ "${selected}" == *" git "* ]] || pkgs+=(git base-devel)
        fi
    fi

    local -a extra_tokens
    read -ra extra_tokens <<< "${EXTRAS:-}"
    for token in "${extra_tokens[@]}"; do
        [[ -z "${token}" || " ${curated_str} " == *" ${token} "* ]] && continue
        pkgs+=("${token}")
    done

    if [[ ${#pkgs[@]} -eq 0 ]]; then return 0; fi

    local -a deduped
    mapfile -t deduped < <(printf '%s\n' "${pkgs[@]}" | sort -u)

    log_info "Installing extras..."
    if ! retry_command "extras install" pacman -S --noconfirm --needed "${deduped[@]}"; then
        log_warn "Some extras failed to install — continuing with what succeeded"
    fi

    [[ "${selected}" == *" firewalld "* ]] && enable_service firewalld || warn_collect "firewalld service could not be enabled"
    [[ "${selected}" == *" bluez "* ]] && enable_service bluetoothd || warn_collect "bluetoothd service could not be enabled"
    [[ "${selected}" == *" zram-tools "* ]] && enable_service zramen || warn_collect "zramen service could not be enabled"

    if [[ "${selected}" == *" rsvc "* && "${init}" == 'runit' ]]; then
        log_info "Installing rsvc..."
        git clone https://github.com/SashexSRB/rsvc /tmp/rsvc || true
        ( cd /tmp/rsvc && make && make install )
    fi

    log_info "Extras installation complete."
}