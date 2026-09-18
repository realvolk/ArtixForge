#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT="/mnt"

recovery_mount_all() {
    if mountpoint -q /mnt; then
        log_info "/mnt already mounted — reusing existing mount"
        return 0
    fi

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
                if ! pass=$(tui_password "LUKS Passphrase" "Enter passphrase for ${part}:"); then
                    log_warn "Skipped ${part}"
                    continue
                fi
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
    if [[ -f "${ROOT}/etc/fstab" ]]; then
        local fstab_esp
        fstab_esp=$(awk '$3 == "vfat" {print $1; exit}' "${ROOT}/etc/fstab")
        if [[ "${fstab_esp}" == UUID=* ]]; then
            esp="$(blkid -U "${fstab_esp#UUID=}" 2>/dev/null || true)"
        elif [[ -b "${fstab_esp}" ]]; then
            esp="${fstab_esp}"
        fi
    fi

    if [[ -z "${esp}" ]]; then
        local root_disk
        root_disk=$(lsblk -no PKNAME "${root_candidate}" 2>/dev/null | head -n1)
        if [[ -n "${root_disk}" ]]; then
            while IFS= read -r name; do
                [[ -z "${name}" ]] && continue
                local candidate_dev="/dev/${name}"
                if blkid -o value -s TYPE "${candidate_dev}" 2>/dev/null | grep -qi 'vfat'; then
                    esp="${candidate_dev}"
                    break
                fi
            done < <(lsblk -no NAME "/dev/${root_disk}" | tail -n +2)
        fi
    fi

    if [[ -n "${esp}" ]]; then
        local esp_mount=""
        if [[ -d "${ROOT}/boot/efi" ]] || [[ ! -d "${ROOT}/efi" ]]; then
            esp_mount="${ROOT}/boot/efi"
        else
            esp_mount="${ROOT}/efi"
        fi
        mkdir -p "${esp_mount}"
        mount "${esp}" "${esp_mount}" || log_warn "Failed to mount ESP at ${esp_mount}"
        log_info "Mounted ESP ${esp} at ${esp_mount}"
    else
        log_warn "No ESP detected — UEFI boot repair may not work"
    fi

    mkdir -p "${ROOT}/dev" "${ROOT}/proc" "${ROOT}/sys"
    mount --bind /dev "${ROOT}/dev" || true
    mount --bind /proc "${ROOT}/proc" || true
    mount --bind /sys "${ROOT}/sys" || true

    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf "${ROOT}/etc/resolv.conf" || true
    fi

    if [[ -d /sys/firmware/efi/efivars ]]; then
        mkdir -p "${ROOT}/sys/firmware/efi"
        mount --bind /sys/firmware/efi/efivars "${ROOT}/sys/firmware/efi/efivars" 2>/dev/null || true
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
    local service="${1}"
    [[ -n "${service}" ]] || return 1

    local init
    init="$(state_get INIT openrc)"

    case "${init}" in
        openrc) [[ -e "${ROOT}/etc/init.d/${service}" ]] ;;
        runit)  [[ -d "${ROOT}/etc/runit/sv/${service}" ]] ;;
        dinit)  [[ -e "${ROOT}/etc/dinit.d/${service}" ]] ;;
        s6)     [[ -d "${ROOT}/etc/s6/sv/${service}" ]] ;;
        *)      return 1 ;;
    esac
}

recovery_enable_service() {
    local svc="${1}"
    local init
    init="$(state_get INIT openrc)"

    case "${init}:${svc}" in
        dinit:logind) svc="elogind" ;;
        dinit:dbus)   svc="dbus" ;;
    esac

    case "${init}" in
        openrc)
            [[ -f "${ROOT}/etc/init.d/${svc}" ]] || return 1
            mkdir -p "${ROOT}/etc/runlevels/default"
            ln -sf "/etc/init.d/${svc}" "${ROOT}/etc/runlevels/default/${svc}"
            ;;
        runit)
            [[ -d "${ROOT}/etc/runit/sv/${svc}" ]] || return 1
            mkdir -p "${ROOT}/etc/runit/runsvdir/default"
            ln -sf "/etc/runit/sv/${svc}" "${ROOT}/etc/runit/runsvdir/default/${svc}"
            ;;
        dinit)
            [[ -f "${ROOT}/etc/dinit.d/${svc}" ]] || return 1
            mkdir -p "${ROOT}/etc/dinit.d/boot.d"
            ln -sf "../${svc}" "${ROOT}/etc/dinit.d/boot.d/${svc}"
            ;;
        s6)
            [[ -d "${ROOT}/etc/s6/sv/${svc}" ]] || return 1
            artix-chroot "${ROOT}" s6-rc-bundle-update add default "${svc}" 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
    return 0
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
    detect_luks
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
    detect_btrfs_subvol_health
    detect_pacman_health
    if tui_yesno "Extended Detection" "Run extended checks for INIT migration issues or broken ISO builds?"; then
        detect_migration_health
        detect_iso_health
    fi

    state_save
}