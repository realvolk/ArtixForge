#!/usr/bin/env bash
set -Eeuo pipefail

_activate_storage() {
    local root_part="$1" use_luks="$2" use_lvm="$3"
    local vg_name
    vg_name="$(state_get LVM_VG_NAME vg0)"

    if [[ "${use_luks}" == "yes" && "${use_lvm}" == "yes" ]]; then
        log_info "Opening LUKS container for LVM..."
        cryptsetup close cryptlvm 2>/dev/null || true
        printf '%s' "$(state_get LUKS_PASS)" | cryptsetup luksOpen "${root_part}" cryptlvm -
        [[ -b /dev/mapper/cryptlvm ]] || die "LUKS mapper /dev/mapper/cryptlvm not created"
    fi

    if [[ "${use_lvm}" == "yes" ]]; then
        log_info "Activating LVM volumes..."
        modprobe dm-mod 2>/dev/null || true
        xtrace_safe vgchange -ay || recoverable_error "Failed to activate LVM volume group"
        printf '%s\n' "/dev/mapper/${vg_name}-root"
        return 0
    fi

    if [[ "${use_luks}" == "yes" ]]; then
        log_info "Opening LUKS container..."
        cryptsetup close cryptroot 2>/dev/null || true
        printf '%s' "$(state_get LUKS_PASS)" | cryptsetup luksOpen "${root_part}" cryptroot -
        printf '%s\n' "/dev/mapper/cryptroot"
        return 0
    fi

    printf '%s\n' "${root_part}"
}

_mount_root() {
    local root_part="$1" fs_type="$2" btrfs_layout="$3"

    case "${fs_type}" in
        btrfs)
            mount "${root_part}" /mnt
            mountpoint -q /mnt || die 'failed to mount root filesystem'

            log_info "Creating BTRFS subvolumes..."
            local -a subvols
            case "${btrfs_layout}" in
                flat)     subvols=(@) ;;
                snapshot) subvols=(@ @home @log @pkg @snapshots) ;;
                *)        subvols=(@ @home) ;;
            esac
            local sv
            for sv in "${subvols[@]}"; do
                if ! btrfs subvolume list /mnt | awk '{print $NF}' | grep -qx "${sv}"; then
                    btrfs subvolume create "/mnt/${sv}"
                fi
            done

            mount -o remount,noatime,compress=zstd,subvol=@ "${root_part}" /mnt
            mountpoint -q /mnt || die 'failed to remount root filesystem with subvol'

            case "${btrfs_layout}" in
                flat) ;;
                snapshot)
                    mount --mkdir -o noatime,compress=zstd,subvol=@home "${root_part}" /mnt/home
                    mount --mkdir -o noatime,compress=zstd,subvol=@log "${root_part}" /mnt/var/log
                    mount --mkdir -o noatime,compress=zstd,subvol=@pkg "${root_part}" /mnt/var/cache/pacman/pkg
                    mount --mkdir -o noatime,compress=zstd,subvol=@snapshots "${root_part}" /mnt/.snapshots
                    ;;
                *)
                    mount --mkdir -o noatime,compress=zstd,subvol=@home "${root_part}" /mnt/home
                    ;;
            esac
            ;;
        ext4|xfs|f2fs)
            local mount_opts="defaults"
            if [[ "$(lsblk -dno ROTA "${root_part}" 2>/dev/null)" == "0" ]]; then
                mount_opts="${mount_opts},discard"
            fi
            mount -t "${fs_type}" -o "${mount_opts}" "${root_part}" /mnt
            mountpoint -q /mnt || die 'failed to mount root filesystem'
            ;;
        *)
            die "unsupported filesystem: ${fs_type}"
            ;;
    esac
}

mount_filesystems() {
    local disk fs_type swap_type bootloader btrfs_layout
    disk="$(state_get DISK)"
    fs_type="$(state_get FS_TYPE)"
    swap_type="$(state_get SWAP_ENABLED none)"
    bootloader="$(state_get BOOTLOADER grub)"
    btrfs_layout="$(state_get BTRFS_LAYOUT standard)"

    local use_swap="no"
    [[ "${swap_type}" == "partition" ]] && use_swap="yes"

    local use_luks use_lvm
    use_luks="$(state_get USE_LUKS no)"
    use_lvm="$(state_get USE_LVM no)"

    local is_uefi=1
    [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]] && is_uefi=0

    local efi_mount='/mnt/boot/efi'
    [[ "${bootloader}" == 'efistub' ]] && efi_mount='/mnt/boot'

    local efi_part="" root_part=""
    local root_num
    root_num=$(_get_root_partition_num "${use_swap}")

    if [[ ${is_uefi} -eq 1 ]]; then
        if [[ -n "$(state_get EFI_PART '')" ]]; then
            efi_part="$(state_get EFI_PART)"
        else
            efi_part=$(get_partition_name "${disk}" 1)
        fi
        mkdir -p "${efi_mount}"
    fi

    if [[ -n "$(state_get ROOT_PART '')" ]]; then
        root_part="$(state_get ROOT_PART)"
    else
        root_part=$(get_partition_name "${disk}" "${root_num}")
    fi

    modprobe "${fs_type}" 2>/dev/null || true
    if [[ ${is_uefi} -eq 1 ]]; then
        modprobe fat 2>/dev/null || true
        modprobe vfat 2>/dev/null || true
        grep -q 'vfat' /proc/filesystems 2>/dev/null || die 'FAT/VFAT kernel support unavailable — check kernel config'
    fi

    command -v mount >/dev/null || die 'mount unavailable (util-linux missing)'

    if mountpoint -q /mnt; then
        if [[ ${is_uefi} -eq 0 ]] || mountpoint -q "${efi_mount}"; then
            log_info "Filesystems already mounted, skipping remount."
            return 0
        fi
    fi

    umount -R /mnt/boot/efi 2>/dev/null || true
    umount -R /mnt/boot 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    mkdir -p /mnt

    local mount_target
    mount_target="$(_activate_storage "${root_part}" "${use_luks}" "${use_lvm}")"

    log_info "Mounting root filesystem..."
    _mount_root "${mount_target}" "${fs_type}" "${btrfs_layout}"

    if [[ ${is_uefi} -eq 1 ]]; then
        local efi_fs
        efi_fs="$(blkid -o value -s TYPE "${efi_part}" 2>/dev/null || true)"
        case "${efi_fs}" in
            vfat) ;;
            *) die "EFI partition is not FAT32 (detected: ${efi_fs:-unknown})" ;;
        esac

        log_info "Mounting EFI partition..."
        mount -t vfat --mkdir "${efi_part}" "${efi_mount}"
        mountpoint -q "${efi_mount}" || die 'failed to mount EFI partition'
    fi

    log_info "Mount setup completed."
}