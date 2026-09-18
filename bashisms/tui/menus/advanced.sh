#!/usr/bin/env bash
set -Eeuo pipefail

tui_keyfile_security_warning() {
    local boot_mode
    boot_mode="$(state_get ARTIX_BOOT_MODE uefi)"

    [[ "${boot_mode}" == "uefi" ]] || return 0

    tui_msg "Security Warning — Keyfile on UEFI" \
"On UEFI installs, the ESP must be unencrypted so the firmware
can read the bootloader. The keyfile is embedded in the UKI,
which lives on the ESP.

This means the keyfile is on UNENCRYPTED storage.

Anyone with physical access to this disk can:
  • Mount the ESP from another system (FAT32, no encryption)
  • Extract the keyfile from the UKI
  • Unlock your LUKS container

Secure Boot prevents tampering with the UKI, but NOT extraction
of the keyfile. Full-disk encryption does not protect against a
physical attacker when the keyfile is on the ESP.

On BIOS installs, /boot is inside the encrypted container and the
keyfile is protected by LUKS. On UEFI, it is not.

If you want protection against physical disk theft, DECLINE the
keyfile and type your passphrase at each boot instead."

    if ! tui_yesno "Proceed with Keyfile" \
"Use a keyfile anyway? (declining means typing your passphrase at each boot)"; then
        state_set LUKS_KEYFILE no
        log_info "LUKS keyfile declined — passphrase will be required at boot"
        return 1
    fi
    return 0
}

tui_select_luks() {
    if tui_yesno "Disk Encryption" "Enable LUKS full disk encryption?"; then
        state_set USE_LUKS "yes"
        local pass
        if ! pass=$(tui_password_confirm "LUKS Passphrase" "Enter passphrase:" "Confirm passphrase:"); then
            tui_msg_quick "LUKS Cancelled" "No encryption will be applied."
            state_set USE_LUKS "no"
            state_set LUKS_PASS ""
            state_set LUKS_KEYFILE "no"
            state_set LUKS_KEYFILE_PATH ""
            log_warn "LUKS setup cancelled — continuing without encryption"
            return 0
        fi
        state_set LUKS_PASS "${pass}"

        if tui_yesno "LUKS Keyfile" "Use a keyfile to avoid typing your password twice at boot?"; then
            if tui_keyfile_security_warning; then
                state_set LUKS_KEYFILE "yes"
            fi
        else
            state_set LUKS_KEYFILE "no"
        fi
    else
        state_set USE_LUKS "no"
        state_set LUKS_PASS ""
        state_set LUKS_KEYFILE "no"
        state_set LUKS_KEYFILE_PATH ""
    fi

    if tui_yesno "LVM" "Enable Logical Volume Management (LVM)?"; then
        state_set USE_LVM "yes"
        local vg_name
        vg_name=$(tui_input "LVM Volume Group" "Volume group name:" "vg0") || vg_name="vg0"
        [[ -n "${vg_name}" ]] || vg_name="vg0"
        state_set LVM_VG_NAME "${vg_name}"
    else
        state_set USE_LVM "no"
        state_set LVM_VG_NAME "vg0"
    fi
}

tui_select_auris() {
    if tui_yesno "AURIS" "Enable the Artix User Repository of Init Scripts (AURIS)?

AURIS provides community-submitted init scripts for all
supported init systems."; then
        state_set ENABLE_AURIS "yes"
    else
        state_set ENABLE_AURIS "no"
    fi
}

tui_select_arch_repos() {
    local kernel fs_type wm_de required='no' reasons=()
    kernel="$(state_get KERNEL_CHOICE linux)"
    fs_type="$(state_get FS_TYPE ext4)"
    wm_de="$(state_get WM_DE none)"

    case "${kernel}" in
        linux-bazzite-bin|linux-cachyos-bore|xanmod) required='yes'; reasons+=("Kernel ${kernel}") ;;
    esac
    case "${fs_type}" in
        zfs) required='yes'; reasons+=("ZFS filesystem") ;;
    esac
    case "${wm_de}" in
        hyprland|niri|mango) required='yes'; reasons+=("${wm_de} requires Arch repositories") ;;
    esac

    if [[ "${required}" == "yes" ]]; then
        local reason_list
        reason_list=$(printf ' - %s\n' "${reasons[@]}")
        tui_msg_quick "Arch Repositories Required" $'Enabling official Arch repositories because:\n\n'"${reason_list}"
        state_set ENABLE_ARCH_REPOS "yes"
        return 0
    fi

    if tui_yesno "Arch Repositories" "Enable official Arch repositories?"; then
        state_set ENABLE_ARCH_REPOS "yes"
    else
        state_set ENABLE_ARCH_REPOS "no"
    fi
}

tui_select_offline_mode() {
    local off
    off=$(tui_menu "Offline Installation" "Allow offline installation?" "No (require internet)" "Yes (cached install)") || return 1
    case "${off}" in
        Yes*) state_set ALLOW_OFFLINE "yes" ;;
        *)     state_set ALLOW_OFFLINE "no" ;;
    esac
}

tui_select_btrfs_layout() {
    local fs_type
    fs_type="$(state_get FS_TYPE ext4)"
    [[ "${fs_type}" == "btrfs" ]] || return 0
    local layout
    layout=$(tui_menu "BTRFS Layout" "Select subvolume layout:" "standard" "flat" "snapshot") || return 1
    state_set BTRFS_LAYOUT "${layout}"
}