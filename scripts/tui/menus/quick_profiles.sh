#!/usr/bin/env bash
set -Eeuo pipefail

tui_quick_install() {
    if ! tui_yesno "Quick Install" "Use a pre-configured profile?"; then
        return 1
    fi

    local profile
    profile=$(tui_menu "Quick Profile" "Select a preset:" \
        "Base – no desktop, minimal system" \
        "Plasma – KDE Plasma desktop" \
        "XFCE – XFCE4 desktop" \
        "Cinnamon – Cinnamon desktop" \
        "LXQt – LXQt desktop" \
        "Community GTK – community GTK ISO package set" \
        "Community Qt – community Qt ISO package set" \
        "Gaming – Plasma, linux-zen, Steam, Lutris, DOSBox" \
        "Server – no desktop, firewalld, tmux" \
        "Minimal – bare system, no extras") || return 1

    case "${profile}" in
        *Base*)
            state_set QUICK_PROFILE "Base"
            local base_init
            base_init=$(tui_menu "Base Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${base_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "doas"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "no"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            state_set USER_SHELL "bash"
            state_set EXTRAS ""
            ;;
        *Plasma*)
            state_set QUICK_PROFILE "Plasma"
            local plasma_init
            plasma_init=$(tui_menu "Plasma Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${plasma_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "kde"
            state_set KDE_PROFILE "desktop"
            state_set DISPLAY_MANAGER "sddm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git flatpak fastfetch firewalld bluez zram-tools firefox neovim alacritty fzf zoxide starship eza btop htop tmux mpv"
            ;;
        *XFCE*)
            state_set QUICK_PROFILE "XFCE"
            local xfce_init
            xfce_init=$(tui_menu "XFCE Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${xfce_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git firefox neovim alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *Cinnamon*)
            state_set QUICK_PROFILE "Cinnamon"
            local cinnamon_init
            cinnamon_init=$(tui_menu "Cinnamon Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${cinnamon_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "cinnamon"
            state_set DISPLAY_MANAGER "lightdm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *LXQt*)
            state_set QUICK_PROFILE "LXQt"
            local lxqt_init
            lxqt_init=$(tui_menu "LXQt Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${lxqt_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux"
            ;;
        *Community GTK*)
            state_set QUICK_PROFILE "Community GTK"
            local cgtk_init
            cgtk_init=$(tui_menu "Community GTK Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${cgtk_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git firefox thunderbird libreoffice gimp inkscape vlc alacritty fzf zoxide starship eza btop tmux flatpak"
            ;;
        *Community Qt*)
            state_set QUICK_PROFILE "Community Qt"
            local cqt_init
            cqt_init=$(tui_menu "Community Qt Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${cqt_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git firefox thunderbird libreoffice gimp inkscape vlc alacritty fzf zoxide starship eza btop tmux flatpak"
            ;;
        *Gaming*)
            state_set QUICK_PROFILE "Gaming"
            local gaming_init
            gaming_init=$(tui_menu "Gaming Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${gaming_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux-zen"
            state_set PRIV_ESCALATION "sudo"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "yes"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "kde"
            state_set KDE_PROFILE "minimal"
            state_set DISPLAY_MANAGER "sddm"
            state_set NETWORK_STACK "networkmanager"
            state_set AUDIO_STACK "pipewire"
            state_set X_STACK "xorg"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git flatpak fastfetch firewalld firefox alacritty fzf zoxide starship eza btop tmux mpv steam lutris dosbox lact goverlay mangohud gamemode piper solaar"
            ;;
        *Server*)
            state_set QUICK_PROFILE "Server"
            local server_init
            server_init=$(tui_menu "Server Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${server_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "doas"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "no"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            state_set USER_SHELL "bash"
            state_set EXTRAS "git firewalld tmux"
            ;;
        *Minimal*)
            state_set QUICK_PROFILE "Minimal"
            local minimal_init
            minimal_init=$(tui_menu "Minimal Init" "Select init system:" "dinit" "openrc" "runit" "s6") || return 1
            state_set INIT "${minimal_init}"
            state_set FS_TYPE "ext4"
            state_set BOOTLOADER "grub"
            state_set KERNEL_CHOICE "linux"
            state_set PRIV_ESCALATION "doas"
            state_set USE_LUKS "no"
            state_set USE_LVM "no"
            state_set GENERATE_UKI "no"
            state_set ALLOW_OFFLINE "no"
            state_set ENABLE_ARCH_REPOS "no"
            state_set MICROCODE_OVERRIDE "auto"
            state_set KEEP_BINARY_KERNEL "yes"
            state_set COREUTILS "gnu"
            state_set KERNEL_CONFIG_DEPTH "auto"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            state_set USER_SHELL "bash"
            state_set EXTRAS ""
            ;;
    esac

    tui_select_hostname
    tui_select_timezone
    tui_select_locale
    tui_select_keyboard_layout
    tui_select_username
    tui_select_user_password
    tui_select_root_password

    local summary=""
    summary+="Profile: ${profile}"$'\n\n'
    summary+="Filesystem: $(state_get FS_TYPE ext4)"$'\n'
    summary+="Bootloader: $(state_get BOOTLOADER grub)"$'\n'
    summary+="Kernel: $(state_get KERNEL_CHOICE linux)"$'\n'
    summary+="Init: $(state_get INIT openrc)"$'\n'
    summary+="Desktop: $(state_get WM_DE none)"$'\n'
    summary+="Display Manager: $(state_get DISPLAY_MANAGER none)"$'\n'
    summary+="Network: $(state_get NETWORK_STACK none)"$'\n'
    summary+="Audio: $(state_get AUDIO_STACK none)"$'\n'
    summary+="X Stack: $(state_get X_STACK none)"$'\n'
    summary+="Privilege Escalation: $(state_get PRIV_ESCALATION sudo)"$'\n'
    summary+="LUKS: $(state_get USE_LUKS no)"$'\n'
    summary+="LVM: $(state_get USE_LVM no)"$'\n'
    summary+="UKI: $(state_get GENERATE_UKI no)"$'\n'
    summary+="Extras: $(state_get EXTRAS)"

    if ! tui_yesno "Confirm Profile" "${summary}"$'\n\n'"Proceed with this profile?"; then
        return 1
    fi

    if tui_yesno "Customize" "Would you like to customize any settings before installing?"; then
        state_set QUICK_INSTALL "no"
        return 1
    fi

    state_set QUICK_INSTALL "yes"
    return 0
}