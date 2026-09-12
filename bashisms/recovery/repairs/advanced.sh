#!/usr/bin/env bash
set -Eeuo pipefail

repair_detected_issues() {
    local fstab_issues boot_issues pacman_issues migration_issues iso_issues
    fstab_issues=$(state_get FSTAB_ISSUES none)
    boot_issues=$(state_get BOOT_ISSUES none)
    pacman_issues=$(state_get PACMAN_ISSUES none)
    migration_issues=$(state_get MIGRATION_ISSUES none)
    iso_issues=$(state_get ISO_ISSUES none)

    local did_something=0

    if [[ "${fstab_issues}" != "none" ]]; then
        log_info "FSTAB issues detected: ${fstab_issues}"
        repair_fstab
        did_something=1
    fi

    if [[ "${pacman_issues}" != "none" ]]; then
        log_info "Pacman issues detected: ${pacman_issues}"
        repair_pacman
        did_something=1
    fi

    if [[ "${boot_issues}" != "none" ]]; then
        log_info "Boot issues detected: ${boot_issues}"
        repair_boot
        did_something=1
    fi

    if [[ "${migration_issues}" != "none" ]]; then
        log_info "Migration issues detected: ${migration_issues}"
        repair_migration
        did_something=1
    fi

    if [[ "${iso_issues}" != "none" ]]; then
        log_info "ISO issues detected: ${iso_issues}"
        repair_iso
        did_something=1
    fi

    if [[ ${did_something} -eq 1 ]]; then
        if [[ "${boot_issues}" =~ no-initramfs || "${boot_issues}" =~ no-kernel ]] || \
           [[ "${fstab_issues}" != "none" ]]; then
            if [[ -x /mnt/usr/bin/mkinitcpio ]]; then
                log_info "Regenerating initramfs..."
                artix-chroot /mnt mkinitcpio -P 2>/dev/null || log_warn "mkinitcpio failed"
            fi
        fi

        if [[ "${boot_issues}" != "none" ]] && [[ -d /mnt/boot/grub ]]; then
            log_info "Regenerating GRUB config..."
            artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warn "grub-mkconfig failed"
        fi
    else
        log_info "No issues detected — nothing to repair."
    fi

    log_info "Repair complete."
}

repair_system() {
    log_info "Running full system repair (nuclear option)..."
    repair_fstab
    repair_pacman
    repair_boot
    repair_kernel
    if [[ -x /mnt/usr/bin/mkinitcpio ]]; then
        artix-chroot /mnt mkinitcpio -P 2>/dev/null || log_warn "mkinitcpio failed"
    fi
    if [[ -d /mnt/boot/grub ]]; then
        artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warn "grub-mkconfig failed"
    fi
    log_info "Full repair complete."
}

repair_filesystem() {
    local root_part fs_type
    root_part="$(findmnt -no SOURCE /mnt 2>/dev/null || true)"
    fs_type="$(state_get FS_TYPE ext4)"

    if [[ -z "${root_part}" || ! -b "${root_part}" ]]; then
        log_error "Could not determine root partition — is /mnt mounted?"
        return 1
    fi

    tui_msg "Filesystem Repair" \
"Filesystem: ${fs_type} on ${root_part}

This will attempt to repair filesystem corruption.
You can choose:
  • Safe – non-destructive check and repair
  • Destructive – aggressive repair, may discard data

Always back up your data first."

    local method
    method=$(tui_menu "Repair Method" "Select repair approach:" \
        "Safe (fsck -p / equivalent)" \
        "Destructive (fsck -f -y / equivalent)" \
        "Cancel") || return 1

    if [[ "${method}" == "Cancel" ]]; then
        return 0
    fi

    if [[ "${fs_type}" == "btrfs" ]]; then
        log_info "Unmounting BTRFS subvolumes recursively..."
        umount -R /mnt 2>/dev/null || { log_error "Failed to unmount /mnt recursively — something is using it"; return 1; }
    else
        log_info "Unmounting /mnt for filesystem check..."
        umount /mnt 2>/dev/null || { log_error "Failed to unmount /mnt — something is using it"; return 1; }
    fi

    case "${fs_type}" in
        ext4)
            if [[ "${method}" == Safe* ]]; then
                log_info "Running safe fsck.ext4 -p on ${root_part}..."
                fsck.ext4 -p "${root_part}" || log_warn "fsck reported errors (safe mode)"
            else
                log_info "Running destructive fsck.ext4 -f -y on ${root_part}..."
                fsck.ext4 -f -y "${root_part}" || log_warn "fsck reported errors (destructive mode)"
            fi
            ;;
        btrfs)
            if [[ "${method}" == Safe* ]]; then
                log_info "Running btrfs check (read-only) on ${root_part}..."
                btrfs check "${root_part}" || log_warn "btrfs check found issues"
            else
                log_warn "btrfs check --repair can make corruption worse."
                if tui_yesno "DANGER" "Really run btrfs check --repair? This may destroy data."; then
                    btrfs check --repair "${root_part}" || log_warn "btrfs repair attempted"
                fi
            fi
            ;;
        xfs)
            if ! xfs_repair -n "${root_part}" &>/dev/null; then
                if [[ "${method}" == Safe* ]]; then
                    log_info "Running xfs_repair -n (dry-run) on ${root_part}..."
                    xfs_repair -n "${root_part}" || log_warn "xfs_repair -n found issues"
                else
                    log_info "Running xfs_repair on ${root_part}..."
                    xfs_repair "${root_part}" || log_warn "xfs_repair reported errors"
                fi
            else
                log_info "xfs_repair -n reports filesystem is clean — nothing to repair"
            fi
            ;;
        *)
            log_warn "Filesystem repair not supported for ${fs_type}"
            mount "${root_part}" /mnt || die "Failed to remount after repair attempt"
            return 1
            ;;
    esac

    if ! blkid -o value -s TYPE "${root_part}" &>/dev/null; then
        log_error "Filesystem signature missing on ${root_part} after repair — refusing to mount"
        die "Filesystem may be destroyed. Manual recovery required."
    fi

    log_info "Remounting ${root_part} to /mnt..."
    if [[ "${fs_type}" == "btrfs" ]]; then
        mount "${root_part}" /mnt || die "Failed to remount after repair"
        if [[ -f /mnt/etc/fstab ]]; then
            mount -a --fstab /mnt/etc/fstab 2>/dev/null || true
        fi
    else
        mount "${root_part}" /mnt || die "Failed to remount after repair"
    fi

    if tui_yesno "Post-Repair" "Would you like to run standard system repair (fstab, boot, etc.)?"; then
        repair_detected_issues
    fi

    log_info "Filesystem repair complete."
}

untrusted_recovery() {
    tui_msg "Untrusted Recovery" \
"This is a DANGEROUS operation intended for systems you
believe may be compromised.

What it will do:
  • Run a rootkit scan (rkhunter)
  • Check for common malware indicators
  • Optionally scan with ClamAV

It will NOT modify your filesystem or attempt repairs.
You run this AT YOUR OWN RISK.

Proceed?"

    if ! tui_yesno "Untrusted Recovery" "Are you absolutely sure?"; then
        log_info "Untrusted recovery cancelled."
        return 0
    fi

    log_info "Running rootkit scan..."
    if ! command -v rkhunter >/dev/null; then
        pacman -S --noconfirm rkhunter
    fi
    rkhunter --check --skip-keypress --report-warnings-only 2>&1 | tee /tmp/rkhunter-untrusted.log
    if grep -q 'Warning' /tmp/rkhunter-untrusted.log; then
        log_warn "Rootkit warnings found. Review /tmp/rkhunter-untrusted.log"
    else
        log_info "No rootkit warnings detected."
    fi

    log_info "Checking for common malware indicators..."
    local indicators=0
    if [[ -d /mnt/etc/cron.d ]]; then
        if grep -rl 'wget\|curl.*|.*sh' /mnt/etc/cron.* /mnt/var/spool/cron 2>/dev/null; then
            log_warn "Suspicious cron entries found (wget/curl piped to shell)"
            indicators=1
        fi
    fi
    if [[ -d /mnt/etc/systemd/system ]]; then
        if grep -rl 'ExecStart=.*/tmp/' /mnt/etc/systemd/system 2>/dev/null; then
            log_warn "Systemd services executing from /tmp found"
            indicators=1
        fi
    fi
    if [[ -f /mnt/root/.ssh/authorized_keys ]]; then
        if grep -q 'ssh-rsa' /mnt/root/.ssh/authorized_keys 2>/dev/null; then
            log_info "Root SSH keys present — ensure you recognize them"
        fi
    fi
    local suid_check
    suid_check=$(find /mnt/usr/bin /mnt/bin /mnt/sbin -type f -perm -4000 -perm -o+w 2>/dev/null)
    if [[ -n "${suid_check}" ]]; then
        log_warn "World-writable SUID binaries found:"
        printf '%s\n' "${suid_check}" | tee -a /tmp/untrusted-recovery.log
        indicators=1
    fi

    if [[ ${indicators} -eq 0 ]]; then
        log_info "No common malware indicators found."
    fi

    if tui_yesno "Malware Scan" "Run ClamAV scan on the installation? (requires ClamAV)"; then
        if ! command -v clamscan >/dev/null; then
            log_info "Installing ClamAV..."
            pacman -S --noconfirm clamav
            freshclam --quiet || log_warn "ClamAV database update failed"
        fi
        log_info "Scanning /mnt with ClamAV (this may take a long time)..."
        clamscan -r --bell --max-filesize=100M --max-scansize=100M /mnt 2>&1 | tee /tmp/clamav-untrusted.log
        if grep -q 'FOUND' /tmp/clamav-untrusted.log; then
            log_warn "ClamAV found potential threats. Review /tmp/clamav-untrusted.log"
        else
            log_info "ClamAV scan clean."
        fi
    fi

    log_info "Untrusted recovery scans complete."
    tui_msg "Untrusted Recovery" \
"Scans complete. Review logs in /tmp:
  rkhunter-untrusted.log
  clamav-untrusted.log (if run)
  untrusted-recovery.log

If threats were found, consider reinstalling from a
trusted ISO rather than repairing."
}