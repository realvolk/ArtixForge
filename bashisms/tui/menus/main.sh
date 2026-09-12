#!/usr/bin/env bash
set -Eeuo pipefail

tui_select_disk() {
    local disk disks=()
    while IFS=' ' read -r name size model; do
        disks+=("${name} - ${size} (${model:-Unknown})")
    done < <(lsblk -dpno NAME,SIZE,MODEL -e 7)

    disk=$(tui_menu "Disk Selection" "Choose target drive:" "${disks[@]}") || return 1
    disk="${disk%% *}"
    state_set DISK "${disk}"
}

tui_select_init() {
    local init
    init=$(tui_menu "Init System" "Select init system:" \
        "OpenRC" "runit" "dinit" "s6") || return 1
    state_set INIT "${init,,}"
}

tui_select_filesystem() {
    local fs
    local fs_options=("ext4" "btrfs" "xfs" "f2fs")

    fs=$(tui_menu "Filesystem" "Select filesystem:" "${fs_options[@]}") || return 1

    state_set FS_TYPE "${fs}"
}

tui_select_bootloader() {
    local bl
    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        bl="grub"
        tui_msg_quick "BIOS Bootloader" "BIOS/Legacy boot detected. Only GRUB is supported."
    else
        bl=$(tui_menu "Bootloader" "Select bootloader:" \
            "GRUB" "rEFInd" "EFIStub" "Limine") || return 1
        bl="${bl,,}"
    fi
    state_set BOOTLOADER "${bl}"
}

tui_select_uki() {
    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        state_set GENERATE_UKI "no"
        return 0
    fi
    if tui_yesno "UKI" "Generate a Unified Kernel Image (UKI)?"; then
        state_set GENERATE_UKI "yes"
    else
        state_set GENERATE_UKI "no"
    fi
}

tui_select_kernel() {
    local k
    k=$(tui_menu "Kernel" "Select kernel:" \
        "linux-* (standard)" "linux-cachyos-*" "linux-bazzite-bin" "xanmod" "tkg" \
        "linux-libre") || return 1

    case "${k}" in
        "linux-* (standard)")
            local variant
            variant=$(tui_menu "Standard Kernel" "Select variant:" \
                "linux" \
                "linux-zen" \
                "linux-lts" \
                "linux-hardened") || return 1
            state_set KERNEL_CHOICE "${variant}"
            ;;
        "linux-cachyos-*")
            local variant
            variant=$(tui_menu "CachyOS Kernel" "Select variant:" \
                "linux-cachyos (EEVDF)" \
                "linux-cachyos-bore (BORE)" \
                "linux-cachyos-eevdf" \
                "linux-cachyos-bmq (BMQ)" \
                "linux-cachyos-rt-bore (RT + BORE)" \
                "linux-cachyos-hardened (BORE + hardening)" \
                "linux-cachyos-lts (EEVDF, long-term)" \
                "linux-cachyos-server (EEVDF, server)" \
                "linux-cachyos-deckify (BORE, Steam Deck)") || return 1
            variant="${variant%% *}"
            state_set KERNEL_CHOICE "${variant}"
            ;;
        *)
            state_set KERNEL_CHOICE "${k}"
            ;;
    esac
}

tui_select_theme() {
    local theme
    while true; do
        theme=$(tui_menu "Theme" "Select colour scheme:" \
            "Forge (default)" \
            "Artix" \
            "Jet Black" \
            "Mono" \
            "Retro") || break
        case "${theme}" in
            "Forge (default)")
                GUM_TITLE_COLOR=212; GUM_ACCENT_COLOR=34 ;;
            Artix*)
                GUM_TITLE_COLOR=39; GUM_ACCENT_COLOR=117 ;;
            "Jet Black")
                GUM_TITLE_COLOR=245; GUM_ACCENT_COLOR=196 ;;
            Mono*)
                GUM_TITLE_COLOR=250; GUM_ACCENT_COLOR=255 ;;
            Retro*)
                GUM_TITLE_COLOR=3; GUM_ACCENT_COLOR=11 ;;
        esac

        state_set GUM_TITLE_COLOR "${GUM_TITLE_COLOR}"
        state_set GUM_ACCENT_COLOR "${GUM_ACCENT_COLOR}"

        tui_msg "Theme Preview" "This is how titles and messages will look."
        if tui_yesno "Keep Theme?" "Keep this theme?"; then
            break
        fi
    done
}

tui_select_swap() {
    local enabled
    enabled=$(tui_menu "Swap" "Configure swap?" \
        "Partition (dedicated swap partition)" \
        "Swapfile (file in root filesystem)" \
        "ZRAM (compressed RAM)" \
        "Zswap (compressed cache in front of a swap device)" \
        "None") || return 1

    case "${enabled}" in
        "Partition"*)
            state_set SWAP_ENABLED "partition"
            local size size_mb
            while true; do
                size=$(tui_input "Swap Size" "Enter swap partition size (e.g. 4G, 512M, 1T):" "4G") || return 1
                size_mb=$(parse_size_to_mb "${size}")
                [[ -n "${size_mb}" && "${size_mb}" -ge 64 ]] && break
                tui_msg_quick "Invalid Size" "Enter a size like 4G, 512M, 1T (minimum 64M)."
            done
            state_set SWAP_SIZE "${size_mb}"
            ;;
        "Swapfile"*)
            state_set SWAP_ENABLED "swapfile"
            local size size_mb
            while true; do
                size=$(tui_input "Swapfile Size" "Enter swapfile size (e.g. 4G, 512M):" "4G") || return 1
                size_mb=$(parse_size_to_mb "${size}")
                [[ -n "${size_mb}" && "${size_mb}" -ge 64 ]] && break
                tui_msg_quick "Invalid Size" "Enter a size like 4G, 512M (minimum 64M)."
            done
            state_set SWAP_SIZE "${size_mb}"
            ;;
        "ZRAM"*)
            state_set SWAP_ENABLED "zram"
            local pct
            while true; do
                pct=$(tui_input "ZRAM Percent" "Percent of RAM to allocate to ZRAM (10-100):" "50") || return 1
                [[ "${pct}" =~ ^[0-9]+$ && "${pct}" -ge 10 && "${pct}" -le 100 ]] && break
                tui_msg_quick "Invalid Percent" "Enter a number between 10 and 100."
            done
            state_set ZRAM_PERCENT "${pct}"
            ;;
        "Zswap"*)
            state_set SWAP_ENABLED "zswap"
            ;;
        *)
            state_set SWAP_ENABLED "none"
            state_set SWAP_SIZE "0"
            ;;
    esac
}

tui_collect_install_config() {
    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        tui_msg_quick "BIOS Mode" "Legacy BIOS boot detected. UEFI features (UKI, EFIStub, rEFInd, Limine) are disabled."
    fi
    tui_select_theme
    tui_select_disk
    if tui_quick_install; then
        if [[ "$(state_get POWER_USER no)" == "yes" ]]; then
            tui_select_poweruser
        fi
        return
    fi

    local quick_vars=(
        QUICK_PROFILE FS_TYPE BOOTLOADER KERNEL_CHOICE INIT PRIV_ESCALATION
        USE_LUKS USE_LVM GENERATE_UKI ALLOW_OFFLINE ENABLE_ARCH_REPOS
        MICROCODE_OVERRIDE KEEP_BINARY_KERNEL COREUTILS KERNEL_CONFIG_DEPTH
        WM_DE KDE_PROFILE DISPLAY_MANAGER NETWORK_STACK AUDIO_STACK X_STACK
        USER_SHELL EXTRAS POWER_USER POWERUSER_PACKAGES POWERUSER_PROFILE
        SWAP_ENABLED SWAP_SIZE LUKS_KEYFILE LUKS_KEYFILE_PATH LUKS_PASS
    )
    for var in "${quick_vars[@]}"; do
        state_set "${var}" ""
    done
    state_set QUICK_INSTALL "no"

    tui_select_init
    tui_select_filesystem
    tui_select_btrfs_layout
    tui_select_bootloader
    tui_select_uki
    tui_select_kernel
    tui_select_poweruser
    tui_select_microcode
    tui_select_desktop
    tui_select_display_manager
    tui_select_xstack
    tui_select_network_stack
    tui_select_audio_stack
    tui_select_shell
    tui_select_priv_escalation
    tui_select_extras
    tui_select_luks
    tui_select_swap
    tui_select_auris
    tui_select_arch_repos
    tui_select_offline_mode
    tui_select_hostname
    tui_select_timezone
    tui_select_locale
    tui_select_keyboard_layout
    tui_configure_users
    tui_show_sanity_warnings
    tui_show_summary
}