#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="/mnt"

recovery_mount_all() {
    local -a luks_parts=()
    local part
    while IFS= read -r part; do
        if cryptsetup isLuks "$part" &>/dev/null; then
            luks_parts+=("$part")
        fi
    done < <(lsblk -n -o PATH)

    if [[ ${#luks_parts[@]} -gt 0 ]]; then
        tui_msg "LUKS Container Found" "Found encrypted partition(s): ${luks_parts[*]}"
        for part in "${luks_parts[@]}"; do
            local mapper_name="crypt_$(basename "${part}")"
            if [[ -b "/dev/mapper/${mapper_name}" ]]; then
                log_info "Mapper ${mapper_name} already open — skipping unlock"
                continue
            fi
            if tui_yesno "Unlock LUKS" "Unlock ${part}?"; then
                local pass=""
                pass=$(tui_password "LUKS Passphrase" "Enter passphrase for ${part}:") || die "LUKS unlock cancelled"
                printf '%s' "${pass}" | cryptsetup luksOpen "${part}" "${mapper_name}" - || {
                    log_warn "Failed to unlock ${part} – wrong passphrase?"
                    continue
                }
                log_info "Unlocked ${part}"
            fi
        done
    fi

    if command -v vgchange &>/dev/null && vgscan 2>/dev/null | grep -q 'Found volume group'; then
        if tui_yesno "LVM Detected" "Activate LVM volume groups?"; then
            vgchange -ay || log_warn "LVM activation failed"
        fi
    fi

    local root_candidate=""
    for dev in /dev/mapper/vg0-root /dev/mapper/cryptroot /dev/mapper/crypt_sda3 /dev/mapper/crypt_sda2; do
        if [[ -b "${dev}" ]]; then
            root_candidate="${dev}"
            break
        fi
    done

    if [[ -z "${root_candidate}" ]]; then
        for dev in /dev/mapper/*-root; do
            [[ -b "${dev}" ]] || continue
            root_candidate="${dev}"
            break
        done
    fi

    if [[ -z "${root_candidate}" ]]; then
        for dev in /dev/mapper/*; do
            [[ -b "${dev}" ]] || continue
            [[ "$(basename "${dev}")" == "control" ]] && continue
            local fs_type
            fs_type=$(blkid -o value -s TYPE "${dev}" 2>/dev/null || true)
            if [[ "${fs_type}" =~ ^(ext[234]|xfs|btrfs|f2fs)$ ]]; then
                root_candidate="${dev}"
                break
            fi
        done
    fi

    if [[ -z "${root_candidate}" ]]; then
        log_info "No LUKS/LVM root found — scanning plain partitions..."
        while IFS= read -r dev; do
            local fs_type
            fs_type=$(blkid -o value -s TYPE "${dev}" 2>/dev/null || true)
            if [[ "${fs_type}" =~ ^(ext[234]|xfs|btrfs|f2fs)$ ]]; then
                root_candidate="${dev}"
                break
            fi
        done < <(lsblk -no PATH 2>/dev/null | grep -v '/dev/loop')
    fi

    if [[ -z "${root_candidate}" ]]; then
        die "Could not find a root filesystem. Please mount /mnt manually."
    fi

    log_info "Mounting ${root_candidate} at /mnt..."
    mount "${root_candidate}" /mnt || die "Failed to mount root"

    local esp=""
    for candidate in /dev/sda1 /dev/nvme0n1p1 /dev/vda1; do
        if [[ -b "${candidate}" ]] && blkid -o value -s TYPE "${candidate}" 2>/dev/null | grep -qi 'vfat'; then
            esp="${candidate}"
            break
        fi
    done
    if [[ -n "${esp}" ]]; then
        mkdir -p /mnt/boot/efi
        mount "${esp}" /mnt/boot/efi || log_warn "Failed to mount ESP"
    fi

    mkdir -p /mnt/dev /mnt/proc /mnt/sys
    mount --bind /dev /mnt/dev || true
    mount --bind /proc /mnt/proc || true
    mount --bind /sys /mnt/sys || true

    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /mnt/etc/resolv.conf || true
    fi

    if [[ -d /sys/firmware/efi/efivars ]]; then
        mkdir -p /mnt/sys/firmware/efi
        mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars 2>/dev/null || true
    fi

    log_info "Mounted ${root_candidate} at /mnt with ESP."
}

recovery_detect_install() {
    mountpoint -q "${ROOT}" || return 1
    [[ -d "${ROOT}/etc" ]] || return 1
    return 0
}

recovery_import_state() {
    reconstruct_state_from_system
}

validate_recovery_root() {
    mountpoint -q "${ROOT}" \
        || die "recovery root is not mounted: ${ROOT}"

    [[ -d "${ROOT}/etc" ]] \
        || die "missing ${ROOT}/etc"

    [[ -d "${ROOT}/var/lib/pacman" ]] \
        || die "missing pacman database"
}

pacman_root_has() {
    [[ -n "${1:-}" ]] || return 1
    [[ -d "${ROOT}/var/lib/pacman/local" ]] \
        || return 1

    pacman \
        --root "${ROOT}" \
        -Qq "${1}" \
        &>/dev/null
}

service_exists() {
    local path="${1}"
    [[ -e "${ROOT}/${path}" ]]
}

recovery_get_status() {
    local status=""
    status+="Install stage: $(state_get RECOVERY_STATUS unknown)"$'\n'
    status+="Filesystem: $(state_get FS_TYPE ext4)"$'\n'
    status+="LVM: $(state_get USE_LVM no)"$'\n'
    status+="LUKS: $(state_get USE_LUKS no)"$'\n'
    status+="UKI: $(state_get GENERATE_UKI no)"$'\n'
    status+="Bootloader: $(state_get BOOTLOADER unknown)"$'\n'
    status+="Kernel: $(state_get KERNEL_CHOICE unknown)"$'\n'
    status+="Power User: $(state_get POWER_USER no)"$'\n'
    status+="Coreutils: $(state_get COREUTILS unknown)"$'\n'

    local fstab_issues boot_issues pacman_issues migration_issues iso_issues
    fstab_issues=$(state_get FSTAB_ISSUES none)
    boot_issues=$(state_get BOOT_ISSUES none)
    pacman_issues=$(state_get PACMAN_ISSUES none)
    migration_issues=$(state_get MIGRATION_ISSUES none)
    iso_issues=$(state_get ISO_ISSUES none)

    [[ "${fstab_issues}" != "none" ]] && status+=$'\n'"FSTAB issues: ${fstab_issues}"
    [[ "${boot_issues}" != "none" ]] && status+=$'\n'"Boot issues: ${boot_issues}"
    [[ "${pacman_issues}" != "none" ]] && status+=$'\n'"Pacman issues: ${pacman_issues}"
    [[ "${migration_issues}" != "none" ]] && status+=$'\n'"Migration issues: ${migration_issues}"
    [[ "${iso_issues}" != "none" ]] && status+=$'\n'"ISO issues: ${iso_issues}"

    printf '%s\n' "${status}"
}

reconstruct_state_from_system() {
    validate_recovery_root
    detect_boot_mode
    detect_disk
    detect_init
    detect_filesystem
    detect_zfs
    detect_lvm
    detect_bootloader
    detect_uki
    detect_kernel
    detect_desktop
    detect_display_manager
    detect_xstack
    detect_seat_manager
    detect_network_stack
    detect_audio_stack
    detect_ucode
    detect_user_shell
    detect_extras
    detect_repositories
    detect_username
    detect_luks
    detect_display_protocol
    detect_nvidia
    detect_virtualization
    detect_hostname
    detect_coreutils
    detect_poweruser
    detect_priv_escalation
    detect_install_stage
    detect_fstab_health
    detect_boot_health
    detect_pacman_health
    if tui_yesno "Extended Detection" "Run extended checks for INIT migration issues or broken ISO builds?"; then
        detect_migration_health
        detect_iso_health
    fi

    state_save
}