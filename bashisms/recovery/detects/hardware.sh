#!/usr/bin/env bash
set -Eeuo pipefail

detect_disk() {
    local source pkname disk candidate
    source="$(findmnt -no SOURCE "${ROOT}" 2>/dev/null || true)"
    [[ -n "${source}" ]] || return 0

    if [[ "${source}" == /dev/mapper/* ]]; then
        pkname="$(lsblk -no PKNAME "${source}" 2>/dev/null || true)"
        [[ -n "${pkname}" ]] && source="/dev/${pkname}"
    fi

    candidate="${source}"
    while [[ -n "${candidate}" ]]; do
        disk="$(lsblk -no PKNAME "${candidate}" 2>/dev/null || true)"
        if [[ -z "${disk}" ]]; then
            break
        fi
        candidate="/dev/${disk}"
    done

    if [[ -b "${candidate}" ]]; then
        state_set DISK "${candidate}"
        log_info "Detected installation disk: ${candidate}"
        return 0
    fi

    local fstab_root
    fstab_root="$(awk '$2 == "/" {print $1}' "${ROOT}/etc/fstab" 2>/dev/null | head -n1)"
    if [[ "${fstab_root}" == UUID=* ]]; then
        candidate="$(blkid -U "${fstab_root#UUID=}" 2>/dev/null || true)"
        [[ -b "${candidate}" ]] && { state_set DISK "${candidate}"; log_info "Detected disk from fstab UUID: ${candidate}"; return 0; }
    fi

    log_warn "Could not auto-detect installation disk."
    if tui_yesno "Disk Detection" "Automatic disk detection failed. Would you like to select the installation disk manually?"; then
        tui_select_disk
    else
        die "Cannot continue without a valid installation disk."
    fi
}

detect_luks() {
    local source parent
    source="$(findmnt -no SOURCE "${ROOT}" 2>/dev/null || true)"
    [[ -n "${source}" ]] || return 0
    
    local check_dev="${source}"
    while [[ -n "${check_dev}" ]]; do
        if cryptsetup isLuks "${check_dev}" &>/dev/null; then
            state_set USE_LUKS yes
            return 0
        fi
        parent="$(lsblk -no PKNAME "${check_dev}" 2>/dev/null || true)"
        [[ -n "${parent}" ]] && check_dev="/dev/${parent}" || break
    done
    
    local mapper_dev
    for mapper_dev in /dev/mapper/*; do
        [[ -b "${mapper_dev}" ]] || continue
        if cryptsetup isLuks "${mapper_dev}" &>/dev/null; then
            state_set USE_LUKS yes
            return 0
        fi
    done
    
    state_set USE_LUKS no
}

detect_nvidia() {
    if pacman_root_has nvidia || pacman_root_has nvidia-dkms || pacman_root_has nvidia-open; then
        state_set GPU_DRIVER nvidia
    fi
}

detect_virtualization() {
    if pacman_root_has qemu-guest-agent; then
        state_set VM_GUEST qemu
    elif pacman_root_has virtualbox-guest-utils; then
        state_set VM_GUEST virtualbox
    elif pacman_root_has open-vm-tools; then
        state_set VM_GUEST vmware
    else
        state_set VM_GUEST none
    fi
}

detect_display_protocol() {
    if [[ -d "${ROOT}/usr/share/wayland-sessions" ]]; then
        state_set DISPLAY_PROTOCOL wayland
    elif [[ -d "${ROOT}/usr/share/xsessions" ]]; then
        state_set DISPLAY_PROTOCOL x11
    fi
}

detect_username() {
    local user
    user="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' "${ROOT}/etc/passwd" 2>/dev/null || true)"
    [[ -n "${user}" ]] || user='artix'
    state_set USER_NAME "${user}"
}