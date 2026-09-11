#!/usr/bin/env bash
set -Eeuo pipefail

_quick_profile_baseline() {
    local init="$1"
    state_set INIT "${init}"
    state_set FS_TYPE "ext4"
    state_set BOOTLOADER "grub"
    state_set KERNEL_CHOICE "linux"
    state_set PRIV_ESCALATION "sudo"
    state_set USE_LUKS "no"
    state_set USE_LVM "no"
    state_set GENERATE_UKI "no"
    state_set ALLOW_OFFLINE "no"
    state_set ENABLE_ARCH_REPOS "no"
    state_set MICROCODE_OVERRIDE "auto"
    state_set KEEP_BINARY_KERNEL "yes"
    state_set COREUTILS "gnu"
    state_set KERNEL_CONFIG_DEPTH "auto"
    state_set NETWORK_STACK "networkmanager"
    state_set AUDIO_STACK "pipewire"
    state_set USER_SHELL "bash"
    state_set EXTRAS ""
}

_quick_profile_infer_de() {
    local profile="$1"
    case "${profile}" in
        base|minimal|server)
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set X_STACK "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            ;;
        plasma|community-qt)
            state_set WM_DE "kde"
            state_set KDE_PROFILE "desktop"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            ;;
        lxqt)
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        xfce)
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        cinnamon)
            state_set WM_DE "cinnamon"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        mate)
            state_set WM_DE "mate"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        community-gtk|lxde)
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        *)
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set X_STACK "none"
            state_set KDE_PROFILE "none"
            ;;
    esac
}

_quick_profile_select_init() {
    local title="$1"
    tui_menu "${title}" "Select init system:" "dinit" "openrc" "runit" "s6"
}

_quick_profile_finalize() {
    local display_name="$1"

    tui_select_hostname
    tui_select_timezone
    tui_select_locale
    tui_select_keyboard_layout
    tui_configure_users

    tui_show_summary || return 1

    if tui_yesno "Customize" "Would you like to customize any settings before installing?"; then
        state_set QUICK_INSTALL "no"
        return 1
    fi

    state_set QUICK_INSTALL "yes"
    return 0
}

_quick_profile_from_yaml() {
    local -a profiles=()
    mapfile -t profiles < <(iso_profiles_list)
    if [[ "${#profiles[@]}" -eq 0 ]]; then
        log_warn "iso-profiles list empty — falling back"
        return 1
    fi

    local -a menu_items=()
    local p
    for p in "${profiles[@]}"; do
        menu_items+=("${p} — ${p}")
    done

    local choice
    choice=$(tui_menu "Quick Profile" "Select an iso-profiles profile:" "${menu_items[@]}") || return 1
    local profile="${choice%% — *}"

    local init
    init=$(_quick_profile_select_init "${profile^} Init") || return 1

    _quick_profile_baseline "${init}"
    _quick_profile_infer_de "${profile}"

    state_set QUICK_PROFILE "${profile}"
    state_set QUICK_INSTALL "yes"

    if ! quick_profile_load "${profile}"; then
        log_warn "Failed to load profile packages for '${profile}'"
        state_set PROFILE_PACKAGES ""
    fi

    _quick_profile_finalize "${profile}"
}

_quick_profile_hardcoded() {
    local profile
    profile=$(tui_menu "Quick Profile" "Select a preset:" \
        "Base – no desktop, minimal system" \
        "Plasma – KDE Plasma desktop" \
        "XFCE – XFCE4 desktop" \
        "Cinnamon – Cinnamon desktop" \
        "LXQt – LXQt desktop" \
        "MATE – MATE desktop" \
        "Community GTK – community GTK ISO package set" \
        "Community Qt – community Qt ISO package set" \
        "Gaming – Plasma, linux-zen, Steam, Lutris, DOSBox" \
        "Server – no desktop, firewalld, tmux" \
        "Minimal – bare system, no extras") || return 1

    state_set PROFILE_PACKAGES ""

    case "${profile}" in
        *Base*)
            state_set QUICK_PROFILE "Base"
            local base_init
            base_init=$(_quick_profile_select_init "Base Init") || return 1
            _quick_profile_baseline "${base_init}"
            state_set PRIV_ESCALATION "doas"
            state_set ENABLE_ARCH_REPOS "no"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            ;;
        *Plasma*)
            state_set QUICK_PROFILE "Plasma"
            local plasma_init
            plasma_init=$(_quick_profile_select_init "Plasma Init") || return 1
            _quick_profile_baseline "${plasma_init}"
            state_set WM_DE "kde"
            state_set KDE_PROFILE "desktop"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git flatpak fastfetch firewalld bluez zram-tools firefox neovim alacritty fzf zoxide starship eza btop htop tmux mpv"
            ;;
        *XFCE*)
            state_set QUICK_PROFILE "XFCE"
            local xfce_init
            xfce_init=$(_quick_profile_select_init "XFCE Init") || return 1
            _quick_profile_baseline "${xfce_init}"
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox neovim alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *Cinnamon*)
            state_set QUICK_PROFILE "Cinnamon"
            local cinnamon_init
            cinnamon_init=$(_quick_profile_select_init "Cinnamon Init") || return 1
            _quick_profile_baseline "${cinnamon_init}"
            state_set WM_DE "cinnamon"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *LXQt*)
            state_set QUICK_PROFILE "LXQt"
            local lxqt_init
            lxqt_init=$(_quick_profile_select_init "LXQt Init") || return 1
            _quick_profile_baseline "${lxqt_init}"
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux"
            ;;
        *MATE*)
            state_set QUICK_PROFILE "MATE"
            local mate_init
            mate_init=$(_quick_profile_select_init "MATE Init") || return 1
            _quick_profile_baseline "${mate_init}"
            state_set WM_DE "mate"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *"Community GTK"*)
            state_set QUICK_PROFILE "Community GTK"
            local cgtk_init
            cgtk_init=$(_quick_profile_select_init "Community GTK Init") || return 1
            _quick_profile_baseline "${cgtk_init}"
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox thunderbird libreoffice gimp inkscape vlc alacritty fzf zoxide starship eza btop tmux flatpak"
            ;;
        *"Community Qt"*)
            state_set QUICK_PROFILE "Community Qt"
            local cqt_init
            cqt_init=$(_quick_profile_select_init "Community Qt Init") || return 1
            _quick_profile_baseline "${cqt_init}"
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox thunderbird libreoffice gimp inkscape vlc alacritty fzf zoxide starship eza btop tmux flatpak"
            ;;
        *Gaming*)
            state_set QUICK_PROFILE "Gaming"
            local gaming_init
            gaming_init=$(_quick_profile_select_init "Gaming Init") || return 1
            _quick_profile_baseline "${gaming_init}"
            state_set KERNEL_CHOICE "linux-zen"
            state_set WM_DE "kde"
            state_set KDE_PROFILE "minimal"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git flatpak fastfetch firewalld firefox alacritty fzf zoxide starship eza btop tmux mpv steam lutris dosbox lact goverlay mangohud gamemode piper solaar"
            ;;
        *Server*)
            state_set QUICK_PROFILE "Server"
            local server_init
            server_init=$(_quick_profile_select_init "Server Init") || return 1
            _quick_profile_baseline "${server_init}"
            state_set PRIV_ESCALATION "doas"
            state_set ENABLE_ARCH_REPOS "no"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            state_set EXTRAS "git firewalld tmux"
            ;;
        *Minimal*)
            state_set QUICK_PROFILE "Minimal"
            local minimal_init
            minimal_init=$(_quick_profile_select_init "Minimal Init") || return 1
            _quick_profile_baseline "${minimal_init}"
            state_set PRIV_ESCALATION "doas"
            state_set ENABLE_ARCH_REPOS "no"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            ;;
        *)
            return 1
            ;;
    esac

    _quick_profile_finalize "${profile}"
}

tui_quick_install() {
    if ! tui_yesno "Quick Install" "Use a pre-configured profile?"; then
        return 1
    fi

    if iso_profiles_ensure; then
        if tui_yesno "Profile Source" "Use upstream iso-profiles (recommended)?"; then
            if _quick_profile_from_yaml; then
                return 0
            fi
            log_warn "iso-profiles path failed — falling back to built-in presets"
        fi
    fi

    _quick_profile_hardcoded
}