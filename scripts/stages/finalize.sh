#!/usr/bin/env bash
set -Eeuo pipefail

_finalize_sync() {
    sync
}

_finalize_cleanup_installer_state() {
    if [[ -f /mnt/etc/artix-installer.conf ]]; then
        shred -u /mnt/etc/artix-installer.conf 2>/dev/null || rm -f /mnt/etc/artix-installer.conf
    fi
}

_finalize_unmount() {
    umount -R /mnt 2>/dev/null || true
    if [[ -e /dev/mapper/cryptroot ]]; then
        cryptsetup close cryptroot 2>/dev/null || true
    fi
}

_finalize_validate() {
    local issues=0

    source "${SCRIPT_DIR}/recovery/detect.sh" 2>/dev/null || true
    source "${SCRIPT_DIR}/recovery/core.sh" 2>/dev/null || true

    detect_boot_health 2>/dev/null || true
    detect_pacman_health 2>/dev/null || true
    detect_fstab_health 2>/dev/null || true

    local boot_issues pacman_issues fstab_issues
    boot_issues="$(state_get BOOT_ISSUES none)"
    pacman_issues="$(state_get PACMAN_ISSUES none)"
    fstab_issues="$(state_get FSTAB_ISSUES none)"

    if [[ "${boot_issues}" != "none" ]]; then
        log_warn "Boot issues: ${boot_issues}"
        issues=1
    fi
    if [[ "${pacman_issues}" != "none" ]]; then
        log_warn "Pacman issues: ${pacman_issues}"
        issues=1
    fi
    if [[ "${fstab_issues}" != "none" ]]; then
        log_warn "FSTAB issues: ${fstab_issues}"
        issues=1
    fi

    if [[ ${issues} -eq 1 ]]; then
        if tui_yesno "Post-Install Issues" "Some issues were detected with the installation.\n\nBoot: ${boot_issues}\nPacman: ${pacman_issues}\nFSTAB: ${fstab_issues}\n\nAttempt automatic repair?"; then
            source "${SCRIPT_DIR}/recovery/repair.sh" 2>/dev/null || true
            repair_detected_issues 2>/dev/null || log_warn "Automatic repair could not fix all issues"
        fi
    fi

    return 0
}

_finalize_write_report() {
    local report="/mnt/root/artixforge-install-report.txt"
    mkdir -p /mnt/root
    {
        printf 'ArtixForge Installation Report\n'
        printf '===============================\n'
        printf 'Date: %s\n' "$(date)"
        printf 'Version: %s\n\n' "$(cat "${BASE_DIR}/VERSION" 2>/dev/null || echo unknown)"
        
        printf 'System Configuration:\n'
        printf '  Init: %s\n' "$(state_get INIT)"
        printf '  Bootloader: %s\n' "$(state_get BOOTLOADER)"
        printf '  Kernel: %s\n' "$(state_get KERNEL_CHOICE)"
        printf '  Filesystem: %s\n' "$(state_get FS_TYPE)"
        printf '  Desktop: %s\n' "$(state_get WM_DE)"
        printf '  Display Manager: %s\n' "$(state_get DISPLAY_MANAGER)"
        printf '  Display Stack: %s\n' "$(state_get X_STACK)"
        printf '  Network Stack: %s\n' "$(state_get NETWORK_STACK)"
        printf '  Audio Stack: %s\n\n' "$(state_get AUDIO_STACK)"

        printf 'Hardware:\n'
        printf '  GPU: %s\n' "$(get_gpu_info 2>/dev/null || echo unknown)"
        printf '  GPU Driver: %s\n' "$(state_get GPU_DRIVER unknown)"
        printf '  Virtualization: %s\n\n' "$(detect_vm 2>/dev/null || echo none)"

        printf 'User Accounts:\n'
        local count="${USER_COUNT:-1}"
        for ((i=1; i<=count; i++)); do
            local name_var="USER_${i}_NAME"
            local shell_var="USER_${i}_SHELL"
            local sudo_var="USER_${i}_SUDO"
            local de_var="USER_${i}_DE"
            local dotfiles_var="USER_${i}_DOTFILES"
            local uname="${!name_var:-unnamed}"
            local ushell="${!shell_var:-/bin/bash}"
            local usudo="${!sudo_var:-yes}"
            local ude="${!de_var:-system default}"
            local udot="${!dotfiles_var:-none}"
            printf '  %s (shell: %s, sudo: %s, DE: %s, dotfiles: %s)\n' "${uname}" "${ushell}" "${usudo}" "${ude}" "${udot}"
        done
        printf '\n'

        printf 'Disk Layout:\n'
        printf '  Target Disk: %s\n' "$(state_get DISK)"
        printf '  Partition Table: %s\n' "$([[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]] && echo MBR || echo GPT)"
        printf '  LUKS: %s\n' "$(state_get USE_LUKS no)"
        printf '  LVM: %s\n' "$(state_get USE_LVM no)"
        printf '  Swap: %s\n\n' "$(state_get SWAP_ENABLED none)"

        if [[ -n "${WARNING_LOG:-}" ]]; then
            printf 'Installation Warnings:\n%s\n\n' "$(echo -e "${WARNING_LOG}")"
        fi

        printf 'Post-Install:\n'
        printf '  Run sudo pacman -Syu to update.\n'
        printf '  Issues? Check artix-debug.log or open an issue at:\n'
        printf '  https://github.com/realvolk/ArtixForge/issues\n'
    } > "${report}"
    chmod 644 "${report}"
    log_info "Installation report written to /root/artixforge-install-report.txt"
}

_finalize_run_post_install_script() {
    local script_path
    script_path="$(state_get POST_INSTALL_SCRIPT '')"
    [[ -n "${script_path}" ]] || return 0

    log_info "Running post-install script..."

    local script_name
    script_name=$(basename "${script_path}")

    if [[ -n "${ARTIX_RUNTIME_DIR:-}" ]]; then
        cp "${script_path}" "${ARTIX_RUNTIME_DIR}/${script_name}" 2>/dev/null || true
    fi

    install -Dm755 "${script_path}" "/mnt/root/${script_name}" 2>/dev/null || {
        log_warn "Failed to copy post-install script to target"
        return 1
    }

    artix-chroot /mnt "/root/${script_name}" >> /tmp/artix-installer/install.log 2>&1 || {
        log_warn "Post-install script exited with non-zero status"
        log_warn "Check /root/${script_name} on the installed system"
    }

    log_info "Post-install script completed"
}

_finalize_write_oneshot_service() {
    local command
    command="$(state_get POST_INSTALL_ONESHOT '')"
    [[ -n "${command}" ]] || return 0

    local init
    init="$(state_get INIT openrc)"

    log_info "Writing one-shot post-install service..."

    mkdir -p /mnt/usr/local/lib/artix-installer
    cat > /mnt/usr/local/lib/artix-installer/oneshot.sh <<'ONESHOT'
#!/bin/sh
command="$1"

if eval "$command"; then
    echo "One-shot post-install completed successfully."
    if command -v rc-update >/dev/null 2>&1; then
        rc-update del artixforge-oneshot default 2>/dev/null || true
        rm -f /etc/init.d/artixforge-oneshot
    elif [ -d /etc/runit/sv/artixforge-oneshot ]; then
        rm -rf /etc/runit/sv/artixforge-oneshot
        rm -f /etc/runit/runsvdir/default/artixforge-oneshot
    elif command -v dinitctl >/dev/null 2>&1; then
        dinitctl disable artixforge-oneshot 2>/dev/null || true
        rm -f /etc/dinit.d/artixforge-oneshot
    elif command -v s6-rc-bundle-update >/dev/null 2>&1; then
        s6-rc-bundle-update del default artixforge-oneshot 2>/dev/null || true
        rm -rf /etc/s6/sv/artixforge-oneshot
    fi
    exit 0
else
    echo "One-shot post-install failed — will retry on next boot." >&2
    exit 1
fi
ONESHOT
    chmod +x /mnt/usr/local/lib/artix-installer/oneshot.sh

    case "${init}" in
        openrc)
            cat > /mnt/etc/init.d/artixforge-oneshot <<EOF
#!/sbin/openrc-run
description="ArtixForge one-shot post-install service"

start() {
    ebegin "Running one-shot post-install"
    /usr/local/lib/artix-installer/oneshot.sh "${command}"
    eend \$?
}
EOF
            chmod +x /mnt/etc/init.d/artixforge-oneshot
            artix-chroot /mnt rc-update add artixforge-oneshot default
            ;;
        runit)
            mkdir -p /mnt/etc/runit/sv/artixforge-oneshot
            cat > /mnt/etc/runit/sv/artixforge-oneshot/run <<EOF
#!/bin/sh
exec /usr/local/lib/artix-installer/oneshot.sh "${command}"
EOF
            chmod +x /mnt/etc/runit/sv/artixforge-oneshot/run
            mkdir -p /mnt/etc/runit/runsvdir/default
            ln -sf /etc/runit/sv/artixforge-oneshot /mnt/etc/runit/runsvdir/default/artixforge-oneshot 2>/dev/null || true
            ;;
        dinit)
            cat > /mnt/etc/dinit.d/artixforge-oneshot <<EOF
type = process
command = /usr/local/lib/artix-installer/oneshot.sh "${command}"
restart = true
logfile = /tmp/artixforge-oneshot.log
EOF
            mkdir -p /mnt/etc/dinit.d/boot.d
            ln -sf ../artixforge-oneshot /mnt/etc/dinit.d/boot.d/artixforge-oneshot 2>/dev/null || true
            ;;
        s6)
            mkdir -p /mnt/etc/s6/sv/artixforge-oneshot
            cat > /mnt/etc/s6/sv/artixforge-oneshot/run <<EOF
#!/bin/sh
exec /usr/local/lib/artix-installer/oneshot.sh "${command}"
EOF
            chmod +x /mnt/etc/s6/sv/artixforge-oneshot/run
            artix-chroot /mnt s6-rc-bundle-update add default artixforge-oneshot 2>/dev/null || true
            ;;
    esac

    log_info "One-shot post-install service enabled for ${init}"
}

_finalize_success_dialog() {
    printf '\n\e[1;32mArtix installation completed successfully!\e[0m\n'
    printf 'You may now reboot.\n'
    printf '\nPress Enter to finish...'
    read -r
}

_save_preset() {
    if tui_yesno "Save Preset" "Installation complete. Save this configuration as a reusable preset?"; then
        local preset_name
        preset_name=$(tui_input "Preset Name" "Enter a name for this preset:" "my-artix") || true
        if [[ -n "${preset_name}" ]]; then
            local preset_dir="${BASE_DIR}/presets"
            mkdir -p "${preset_dir}"
            cp "${STATE_FILE}" "${preset_dir}/${preset_name// /_}.conf"
            tui_msg "Preset Saved" "Preset '${preset_name}' saved."
        fi
    fi
}

stage_finalize() {
    if stage_should_skip finalize; then return 0; fi
    if ! stage_is_done post; then
        log_error "Post-install stage did not complete. Refusing to finalize."
        return 1
    fi

    log_info "Running post-install validation..."
    _finalize_validate

    log_info "Running post-install script..."
    _finalize_run_post_install_script

    log_info "Writing one-shot service..."
    _finalize_write_oneshot_service

    log_info "Applying final system configuration..."
    _finalize_write_report
    _finalize_sync || { log_error "Failed to sync filesystem buffers."; return 1; }
    _finalize_cleanup_installer_state || { log_error "Failed to clean installer state."; return 1; }
    _finalize_unmount || { log_error "Failed to unmount installation target."; return 1; }

    stage_mark_done finalize
    _finalize_success_dialog
    _save_preset
}