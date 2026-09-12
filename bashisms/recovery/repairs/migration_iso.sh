#!/usr/bin/env bash
set -Eeuo pipefail

repair_migration() {
    local issues
    issues=$(state_get MIGRATION_ISSUES none)
    [[ "${issues}" == "none" ]] && return 0

    if [[ "${issues}" =~ multiple-inits ]]; then
        log_warn "Multiple init systems detected. This usually means a migration was interrupted."
        if tui_yesno "Repair Migration" "Reinstall the correct init system and clean up orphaned files?"; then
            local correct_init
            correct_init=$(state_get INIT openrc)
            log_info "Reinstalling ${correct_init}..."
            case "${correct_init}" in
                openrc) artix-chroot /mnt pacman -S --noconfirm openrc ;;
                runit)  artix-chroot /mnt pacman -S --noconfirm runit ;;
                dinit)  artix-chroot /mnt pacman -S --noconfirm dinit dinit-base dinit-rc ;;
                s6)     artix-chroot /mnt pacman -S --noconfirm s6 s6-rc ;;
            esac
            for init in runit dinit.d s6 init.d; do
                if [[ "${init}" != "${correct_init}"* ]] && [[ "${init}" != "init.d" || "${correct_init}" != "openrc" ]]; then
                    [[ -d "/mnt/etc/${init}" ]] && rm -rf "/mnt/etc/${init}" && log_info "Removed /etc/${init}"
                fi
            done
        fi
    fi

    if [[ "${issues}" =~ init-mismatch ]]; then
        log_warn "Init system mismatch between state and installed system."
        if tui_yesno "Fix Init" "Set the detected init as the correct one?"; then
            local actual
            actual=$(detect_init_actual)
            state_set INIT "${actual}"
            log_info "State updated to ${actual}"
        fi
    fi
}

repair_iso() {
    local issues
    issues=$(state_get ISO_ISSUES none)
    [[ "${issues}" == "none" ]] && return 0

    if [[ "${issues}" =~ no-pacman || "${issues}" =~ pacman-db-broken ]]; then
        log_error "Pacman is broken or missing. This ISO is too damaged to repair automatically."
        tui_msg "Cannot Repair" "Pacman is required for all repairs.\n\nReinstall from a working ISO."
        return 1
    fi

    if [[ "${issues}" =~ missing-artixforge ]]; then
        log_warn "ArtixForge installer not found at /root/ArtixForge."
        tui_msg "Missing ArtixForge" "The installer is missing but the system may still be bootable.\n\nRun 'pacman -S artixforge' after boot if available."
    fi

    if [[ "${issues}" =~ base-incomplete ]]; then
        log_warn "Base packages incomplete."
        if tui_yesno "Repair Base" "Reinstall base packages?"; then
            artix-chroot /mnt pacman -S --noconfirm base base-devel
            log_info "Base reinstalled."
        fi
    fi

    if [[ "${issues}" =~ no-kernel-iso ]]; then
        log_warn "No kernel found in /boot."
        if tui_yesno "Install Kernel" "Install linux kernel?"; then
            artix-chroot /mnt pacman -S --noconfirm linux linux-headers
            artix-chroot /mnt mkinitcpio -P
            log_info "Kernel installed."
        fi
    fi
}