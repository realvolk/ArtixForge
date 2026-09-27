#!/usr/bin/env bash
set -Eeuo pipefail

_generate_fstab() {
    local fstab="/mnt/etc/fstab"

    if [[ -f "${fstab}" ]]; then
        local entry_count
        entry_count=$(grep -cvE '^[[:space:]]*(#|$)' "${fstab}" || true)
        if [[ "${entry_count}" -gt 0 ]]; then
            log_info "fstab already populated — skipping generation"
            return 0
        fi
    fi

    log_info "Generating /etc/fstab..."
    fstabgen -U /mnt > /mnt/etc/fstab
    log_info "fstab generated."
}

stage_chroot() {
    if stage_should_skip chroot; then return 0; fi
    stage_require_chroot || die "chroot environment is not ready"

    local init rc=0 bootloader fs_type
    init="$(state_get INIT openrc)"
    bootloader="$(state_get BOOTLOADER grub)"
    fs_type="$(state_get FS_TYPE ext4)"

    case "${init}" in
        openrc|runit|dinit|s6|busybox) ;;
        *) die "invalid init system: ${init}" ;;
    esac

    log_info "Verifying init system: ${init}"

    log_info "Validating display stack compatibility..."
    if ! validate_display_stack; then
        log_error "Display stack validation failed. Cannot continue."
        return 1
    fi

    if [[ "${init}" != "busybox" ]]; then
        if ! artix-chroot /mnt pacman -Q "${init}" >/dev/null 2>&1; then
            log_info "Installing init system: ${init}"
            artix-chroot /mnt pacman -S --noconfirm "${init}"
            rc=$?
            if [[ ${rc} -ne 0 ]]; then
                log_error "Failed to install init system: ${init}"
                return ${rc}
            fi
        fi
    else
        log_info "BusyBox init is source-built — skipping pacman check"
        if ! artix-chroot /mnt which busybox &>/dev/null; then
            warn_collect "BusyBox binary not found in target — init may have failed to build"
        fi
    fi

    _generate_fstab

    if ! configure_system; then
        log_error "System configuration failed."
        return 1
    fi

    if ! configure_users; then
        log_error "User configuration failed."
        return 1
    fi

    if ! configure_bootloader; then
        log_error "Bootloader configuration failed."
        if [[ "${ARTIX_BOOT_MODE:-uefi}" == "uefi" && "${bootloader}" == 'efistub' ]]; then
            log_error "EFIStub boot entry creation failed."
            log_error "Verify EFI mountpoints and kernel artifacts."
            log_error "Check efibootmgr -v from the live environment."
        fi
        return 1
    fi

    if ! declare -F prepare_handoff &>/dev/null; then
        source "${SCRIPT_DIR}/install/handoff.sh" || die "handoff.sh missing"
    fi

    if ! prepare_handoff; then
        log_error "Handoff preparation failed."
        return 1
    fi

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "uefi" ]]; then
        if [[ "${bootloader}" == 'efistub' ]]; then
            log_info "Validating EFI boot entries..."

            if ! artix-chroot /mnt efibootmgr -v >/tmp/artix-efibootmgr.log 2>&1; then
                log_error "efibootmgr failed to read EFI entries."
                log_error "System may not boot correctly."
                return 1
            fi

            if ! grep -qi 'Artix Linux' /tmp/artix-efibootmgr.log; then
                log_error "No Artix EFI boot entry detected."
                log_error "EFIStub configuration appears incomplete."
                log_error "Review efibootmgr output manually."
                return 1
            fi

            log_info "EFI boot entry validation successful."
        fi
    else
        log_info "BIOS mode – skipping EFI boot entry validation"
    fi

    stage_mark_done chroot
}