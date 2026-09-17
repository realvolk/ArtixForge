#!/usr/bin/env bash
set -Eeuo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ISO_DIR}/../.." && pwd)}"

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

lint_iso_state() {
    local errors=""

    local init
    init="$(state_get INIT openrc)"
    case "${init}" in
        openrc|runit|dinit|s6) ;;
        *) errors+="INIT '${init}' is not supported"$'\n' ;;
    esac

    local kernel
    kernel="$(state_get KERNEL_CHOICE linux)"
    local valid_kernel=0
    local k
    for k in "${ISO_KERNEL_CHOICES[@]}"; do
        [[ "${kernel}" == "${k}" ]] && valid_kernel=1
    done
    [[ ${valid_kernel} -eq 1 ]] || errors+="KERNEL_CHOICE '${kernel}' is not in ISO_KERNEL_CHOICES"$'\n'

    local wm_de
    wm_de="$(state_get WM_DE none)"
    if [[ "${wm_de}" != "none" ]]; then
        local x_stack
        x_stack="$(state_get X_STACK xorg)"
        if [[ "${wm_de}" =~ ^(hyprland|niri|sway|mango|cosmic)$ ]] && [[ "${x_stack}" == "xorg" ]]; then
            errors+="Wayland compositor '${wm_de}' with X_STACK=xorg — likely misconfigured"$'\n'
        fi
    fi

    local base_profile
    base_profile="$(state_get ISO_BASE_PROFILE "")"
    if [[ -n "${base_profile}" ]]; then
        if ! iso_profiles_available; then
            errors+="ISO_BASE_PROFILE '${base_profile}' requested but iso-profiles unavailable"$'\n'
        fi
    fi

    if [[ -n "${errors}" ]]; then
        printf '%s' "${errors}"
        return 1
    fi
    return 0
}

tui_iso_live_config() {
    iso_profiles_ensure || true

    local build_mode
    build_mode=$(tui_menu "ISO Base" \
        "How do you want to build the live system?" \
        "Upstream profile – extend an existing Artix profile (recommended for most users)" \
        "Custom – build from scratch, use my DE and config choices only") || return 1

    tui_select_init
    tui_select_desktop
    tui_select_display_manager
    tui_select_xstack

    case "${build_mode}" in
        "Upstream"*)
            local wm_de suggested
            wm_de="$(state_get WM_DE none)"
            suggested="$(resolve_de_profile "${wm_de}")"

            local base_profile="${suggested}"
            if iso_profiles_available; then
                local -a profiles=()
                mapfile -t profiles < <(iso_profiles_list)
                if [[ "${#profiles[@]}" -gt 0 ]]; then
                    local -a profile_menu=()
                    local p
                    for p in "${profiles[@]}"; do
                        if [[ "${p}" == "${suggested}" ]]; then
                            profile_menu+=("${p} (recommended for ${wm_de})")
                        else
                            profile_menu+=("${p}")
                        fi
                    done
                    local choice
                    choice=$(tui_menu "Base Profile" \
                        "Selected DE: ${wm_de}
Recommended upstream base: ${suggested}" \
                        "${profile_menu[@]}") || return 1
                    case "${choice}" in
                        *"(recommended for "*) base_profile="${suggested}" ;;
                        *) base_profile="${choice}" ;;
                    esac
                fi
            fi
            state_set ISO_BASE_PROFILE "${base_profile}"
            ;;
        "Custom"*)
            state_set ISO_BASE_PROFILE ""
            ;;
    esac

    local iso_kernel
    iso_kernel=$(tui_menu "Kernel" "Select kernel for the live ISO:" "${ISO_KERNEL_CHOICES[@]}") || return 1
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
    tui_msg "Offline Target Configuration" \
"Now configure the TARGET system — the system that will be
installed from this ISO without internet access.

The packages selected here will be bundled onto the ISO so that
offline installation works.

This is separate from the LIVE environment configuration you
just completed. The live environment stays as you set it."

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

    iso_profiles_ensure || true

    local iso_stage_file="/tmp/artix-installer/iso-build-stage.conf"
    if [[ -f "${iso_stage_file}" ]]; then
        local saved_stage resume_summary
        saved_stage="$(cat "${iso_stage_file}" 2>/dev/null || echo "init")"

        resume_summary=""
        resume_summary+="An ISO build is in progress (stage: ${saved_stage})."$'\n\n'
        resume_summary+="- **Init:** $(state_get INIT openrc)"$'\n'
        resume_summary+="- **Kernel:** $(state_get KERNEL_CHOICE linux)"$'\n'
        resume_summary+="- **Base profile:** $(state_get ISO_BASE_PROFILE 'base')"$'\n'
        resume_summary+="- **Boot mode:** $(state_get ISO_BOOT_MODE live)"$'\n'
        resume_summary+="- **Offline:** $(state_get ALLOW_OFFLINE no)"$'\n'
        resume_summary+="- **Output:** $(state_get ISO_OUTPUT_DIR "${HOME}/ArtixForge-ISO")"$'\n\n'
        resume_summary+="Resume with these settings?"

        if tui_yesno "Resume ISO Build" "${resume_summary}"; then
            source "${ISO_DIR}/build.sh"
            build_artix_iso \
                "$(state_get QUICK_PROFILE Custom)" \
                "$(state_get INIT openrc)" \
                "$(state_get KERNEL_CHOICE linux)" \
                "$(state_get ALLOW_OFFLINE no)" \
                "$(state_get ISO_BOOT_MODE live)" \
                "$(state_get ISO_OUTPUT_DIR "${HOME}/ArtixForge-ISO")" \
                "$(state_get ISO_BASE_PROFILE '')"
            return $?
        fi

        rm -f "${iso_stage_file}"
        log_info "Starting fresh ISO build"
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

        inst_kernel=$(tui_menu "Kernel" "Select kernel for the installer ISO:" "${ISO_KERNEL_CHOICES[@]}") || return 1
        state_set KERNEL_CHOICE "${inst_kernel}"

        state_set WM_DE "none"
        state_set DISPLAY_MANAGER "none"
        state_set X_STACK "none"
        state_set AUDIO_STACK "none"
        state_set NETWORK_STACK "networkmanager"
        state_set QUICK_PROFILE "Installer"
        state_set ISO_BASE_PROFILE "base"
    fi

    state_set ISO_BOOT_MODE "${boot_mode}"

    local lint_errors
    lint_errors=$(lint_iso_state 2>/dev/null || true)
    if [[ -n "${lint_errors}" ]]; then
        tui_msg "ISO Configuration Invalid" "$(printf 'The ISO configuration has errors:\n\n%s\n\nCannot proceed.' "${lint_errors}")"
        return 1
    fi

    local iso_output_dir
    iso_output_dir=$(tui_input "Output Directory" "Where should the ISO be saved?" "${HOME}/ArtixForge-ISO") || return 1
    mkdir -p "${iso_output_dir}"
    state_set ISO_OUTPUT_DIR "${iso_output_dir}"

    local profile_name init kernel offline base_profile
    profile_name="$(state_get QUICK_PROFILE "Custom")"
    init="$(state_get INIT "openrc")"
    kernel="$(state_get KERNEL_CHOICE "linux")"
    base_profile="$(state_get ISO_BASE_PROFILE "")"

    offline="no"
    if tui_yesno "Offline ISO" "Include all packages for offline installation?"; then
        offline="yes"
        state_set ALLOW_OFFLINE "yes"
        if [[ "${boot_mode}" == "live" ]]; then
            tui_iso_target_config
        else
            log_info "Installer ISO offline mode: using existing package list (no target configuration needed)"
        fi
    else
        state_set ALLOW_OFFLINE "no"
    fi

    if tui_yesno "Additional Packages" "Would you like to add extra packages to the ISO?"; then
        tui_select_extras
        local iso_extras existing
        iso_extras="$(state_get EXTRAS '')"
        existing="$(state_get ISO_EXTRA_PACKAGES '')"
        if [[ -n "${iso_extras}" ]]; then
            state_set ISO_EXTRA_PACKAGES "${existing} ${iso_extras}"
        fi
    fi

    local summary=""
    summary+="Ready to build the ISO."$'\n\n'
    summary+="- **Init:** ${init}"$'\n'
    summary+="- **Kernel:** ${kernel}"$'\n'
    summary+="- **Base profile:** ${base_profile:-custom}"$'\n'
    summary+="- **Boot mode:** ${boot_mode}"$'\n'
    summary+="- **Offline:** ${offline}"$'\n'
    summary+="- **Output:** ${iso_output_dir}"$'\n\n'
    summary+="Proceed?"

    if ! tui_yesno "Start Build" "${summary}"; then
        return 1
    fi

    source "${ISO_DIR}/build.sh"
    build_artix_iso "${profile_name}" "${init}" "${kernel}" "${offline}" "${boot_mode}" "${iso_output_dir}" "${base_profile}"
}