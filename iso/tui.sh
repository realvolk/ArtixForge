#!/usr/bin/env bash
set -Eeuo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ISO_DIR}/.." && pwd)}"

ISO_TARGET_STATE_FILE="/tmp/artix-installer/iso-target-state.conf"

iso_target_state_get() {
    local key="${1}" default="${2:-}"
    if [[ -f "${ISO_TARGET_STATE_FILE}" ]]; then
        source "${ISO_TARGET_STATE_FILE}" 2>/dev/null || true
    fi
    printf '%s\n' "${!key:-${default}}"
}

iso_target_state_set() {
    local key="${1}" value="${2}"
    local tmpfile="${ISO_TARGET_STATE_FILE}.tmp.$$"
    if [[ -f "${ISO_TARGET_STATE_FILE}" ]]; then
        while IFS= read -r line; do
            [[ "${line}" =~ ^${key}= ]] || printf '%s\n' "${line}" >> "${tmpfile}"
        done < "${ISO_TARGET_STATE_FILE}"
    else
        mkdir -p "$(dirname "${ISO_TARGET_STATE_FILE}")"
    fi
    printf '%s=%q\n' "${key}" "${value}" >> "${tmpfile}"
    mv "${tmpfile}" "${ISO_TARGET_STATE_FILE}"
}

iso_target_state_init() {
    mkdir -p "$(dirname "${ISO_TARGET_STATE_FILE}")"
    : > "${ISO_TARGET_STATE_FILE}"
}

tui_iso_live_config() {
    local base_profile
    if iso_profiles_available; then
        local -a profiles=()
        mapfile -t profiles < <(iso_profiles_list)
        if [[ "${#profiles[@]}" -gt 0 ]]; then
            base_profile=$(tui_menu "Base Profile" "Select an upstream iso-profiles base:" "${profiles[@]}") || return 1
        fi
    fi
    if [[ -z "${base_profile:-}" ]]; then
        tui_select_desktop
        base_profile="$(iso_profile_for_de "$(state_get WM_DE none)")"
    else
        tui_select_desktop
    fi
    state_set ISO_BASE_PROFILE "${base_profile}"

    tui_select_display_manager
    tui_select_xstack
    tui_select_init
    local iso_kernel
    iso_kernel=$(tui_menu "Kernel" "Select kernel for the live ISO:" \
        "linux" "linux-zen" "linux-lts" "linux-hardened") || return 1
    state_set KERNEL_CHOICE "${iso_kernel}"
    tui_select_network_stack
    tui_select_audio_stack
    tui_select_extras
    state_set DISK ""
    state_set FS_TYPE "ext4"
    state_set BOOTLOADER ""
    state_set USE_LUKS "no"
    state_set USE_LVM "no"
    state_set GENERATE_UKI "no"
    state_set HOSTNAME "artixforge"
    state_set TIMEZONE "UTC"
    state_set LOCALE "en_US.UTF-8"
    state_set KEYMAP "us"
    state_set USER_NAME "artix"
    state_set USER_PASS ""
    state_set ROOT_PASS ""
    state_set USER_SHELL "bash"
    state_set PRIV_ESCALATION "sudo"
    state_set QUICK_PROFILE "Custom"
}

tui_iso_target_config() {
    tui_msg_quick "Offline Configuration" "Configure the system you will later install.\nThese packages will be bundled for offline installation."

    cp /tmp/artix-installer/state.conf /tmp/artix-installer/live-state-temp.conf 2>/dev/null || true

    tui_select_init
    tui_select_filesystem
    tui_select_btrfs_layout
    tui_select_bootloader
    tui_select_uki
    tui_select_kernel
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
    tui_select_arch_repos
    tui_select_hostname
    tui_select_timezone
    tui_select_locale
    tui_select_keyboard_layout
    tui_select_username
    tui_select_user_password
    tui_select_root_password
    tui_show_sanity_warnings
    state_set DISK ""

    cp /tmp/artix-installer/state.conf /tmp/artix-installer/iso-target-state.conf
    cp /tmp/artix-installer/live-state-temp.conf /tmp/artix-installer/state.conf
    rm -f /tmp/artix-installer/live-state-temp.conf
}

start_iso_build() {
    if [[ -d /run/artix/sfs/rootfs ]]; then
        tui_msg_quick "Not Supported" "ISO building from a live environment is not supported due to overlayfs limitations in artools.\n\nPlease build ISOs from an installed Artix system."
        return 0
    fi

    if ! command -v buildiso &>/dev/null; then
        if tui_yesno "Missing Tools" "artools is not installed. Install now?"; then
            pacman -S --noconfirm artools iso-profiles || die "Failed to install artools"
            modprobe loop
        else
            die "artools is required for ISO generation"
        fi
    fi

    local boot_mode
    boot_mode=$(tui_menu "ISO Type" "What kind of ISO do you want to build?" \
        "Live Desktop – full graphical environment, installer available manually" \
        "Installer – boots directly into ArtixForge installer") || return 1

    case "${boot_mode}" in
        "Live Desktop"*) boot_mode="live" ;;
        "Installer"*)    boot_mode="installer" ;;
    esac

    if [[ "${boot_mode}" == "live" ]]; then
        local config_method
        config_method=$(tui_menu "ISO Configuration" "How would you like to configure the ISO?" \
            "Full Customization – choose every option" \
            "Load Profile – from saved configuration file") || return 1

        case "${config_method}" in
            "Full Customization"*)
                tui_iso_live_config
                ;;
            "Load Profile"*)
                local profile_file
                profile_file=$(tui_input "Load Profile" "Enter path to profile file:" "/etc/artixforge-profile.conf") || return 1
                if [[ -f "${profile_file}" ]]; then
                    source "${profile_file}"
                    for var in FS_TYPE BOOTLOADER KERNEL_CHOICE INIT PRIV_ESCALATION USE_LUKS USE_LVM GENERATE_UKI ALLOW_OFFLINE ENABLE_ARCH_REPOS MICROCODE_OVERRIDE KEEP_BINARY_KERNEL COREUTILS KERNEL_CONFIG_DEPTH WM_DE KDE_PROFILE DISPLAY_MANAGER NETWORK_STACK AUDIO_STACK X_STACK USER_SHELL EXTRAS POWER_USER POWERUSER_PACKAGES POWERUSER_PROFILE; do
                        [[ -n "${!var:-}" ]] && state_set "${var}" "${!var}"
                    done
                    tui_msg_quick "Profile Loaded" "Configuration loaded from ${profile_file}"
                else
                    tui_msg_quick "Error" "Profile file not found: ${profile_file}"
                    return 1
                fi
                ;;
        esac
    else
        local inst_init inst_kernel
        inst_init=$(tui_menu "Init System" "Select init system for the installer ISO:" \
            "openrc" "runit" "dinit" "s6") || return 1
        state_set INIT "${inst_init}"

        inst_kernel=$(tui_menu "Kernel" "Select kernel for the installer ISO:" \
            "linux" "linux-zen" "linux-lts" "linux-hardened") || return 1
        state_set KERNEL_CHOICE "${inst_kernel}"

        state_set WM_DE "none"
        state_set DISPLAY_MANAGER "none"
        state_set X_STACK "none"
        state_set AUDIO_STACK "none"
        state_set NETWORK_STACK "networkmanager"
        state_set QUICK_PROFILE "Installer"
        state_set ISO_BASE_PROFILE "base"
    fi

    if tui_yesno "Additional Packages" "Would you like to add extra packages to the ISO?"; then
        local extra_pkgs
        extra_pkgs=$(tui_checklist "Extra Packages" "Select additional packages to include:" \
            "git" "flatpak" "fastfetch" "firewalld" "bluez" "zram-tools" \
            "fzf" "zoxide" "starship" "eza" "btop" "htop" "nvtop" "tmux" \
            "neovim" "micro" "helix" "firefox" "chromium" "qutebrowser" \
            "ranger" "lf" "nnn" "thunar" "alacritty" "kitty" "foot" "mpv" "feh") || true
        extra_pkgs=$(echo "${extra_pkgs}" | tr '\n' ' ')
        if [[ -n "${extra_pkgs}" ]]; then
            state_set ISO_EXTRA_PACKAGES "${extra_pkgs}"
        fi
    fi

    local iso_output_dir
    iso_output_dir=$(tui_input "Output Directory" "Where should the ISO be saved?" "${HOME}/ArtixForge-ISO") || return 1
    mkdir -p "${iso_output_dir}"
    state_set ISO_OUTPUT_DIR "${iso_output_dir}"

    local profile_name init kernel offline base_profile
    profile_name="$(state_get QUICK_PROFILE "Custom")"
    init="$(state_get INIT "openrc")"
    kernel="$(state_get KERNEL_CHOICE "linux")"
    base_profile="$(state_get ISO_BASE_PROFILE "base")"

    offline="no"
    if tui_yesno "Offline ISO" "Include all packages for offline installation?"; then
        offline="yes"
        if [[ "${boot_mode}" == "live" ]]; then
            tui_iso_target_config
        else
            log_info "Installer ISO offline mode: using existing package list (no target configuration needed)"
        fi
    fi

    source "${ISO_DIR}/build.sh"
    build_artix_iso "${profile_name}" "${init}" "${kernel}" "${offline}" "${boot_mode}" "${iso_output_dir}" "${base_profile}"
}