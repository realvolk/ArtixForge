#!/usr/bin/env bash
set -Eeuo pipefail

tui_select_luks() {
    if tui_yesno "Disk Encryption" "Enable LUKS full disk encryption?"; then
        state_set USE_LUKS "yes"
        local pass
        pass=$(tui_password_confirm "LUKS Passphrase" "Enter passphrase:" "Confirm passphrase:") || return 1
        state_set LUKS_PASS "${pass}"
        
        if tui_yesno "LUKS Keyfile" "Use a keyfile to avoid typing your password twice at boot?"; then
            state_set LUKS_KEYFILE "yes"
        fi
    else
        state_set USE_LUKS "no"
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