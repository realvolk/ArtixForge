#!/usr/bin/env bash
set -Eeuo pipefail

create_filesystems() {
    local disk fs_type swap_type swap_size
    disk="$(state_get DISK)"
    [[ -b "${disk}" ]] || die "invalid disk: ${disk}"
    fs_type="$(state_get FS_TYPE)"
    swap_type="$(state_get SWAP_ENABLED none)"
    swap_size="$(state_get SWAP_SIZE 0)"
    local use_swap_partition="no"
    if [[ "${swap_type}" == "partition" ]]; then
        use_swap_partition="yes"
    fi

    local efi_part swap_part root_part

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        if [[ "${use_swap_partition}" == "yes" ]]; then
            swap_part=$(get_partition_name "${disk}" 2)
            root_part=$(get_partition_name "${disk}" 3)
        else
            root_part=$(get_partition_name "${disk}" 2)
        fi

        if [[ "${use_swap_partition}" == "yes" && -n "${swap_part:-}" ]]; then
            log_info "Initializing swap partition..."
            [[ -b "${swap_part}" ]] || die "invalid swap partition: ${swap_part}"
            mkswap "${swap_part}"
            swapon "${swap_part}"
        fi

        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            log_info "Setting up LUKS on ${root_part}..."
            cryptsetup close cryptroot 2>/dev/null || true
            local luks_pass="$(state_get LUKS_PASS)"
            printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "${root_part}" -
            printf '%s' "${luks_pass}" | cryptsetup luksOpen "${root_part}" cryptroot -
            root_part="/dev/mapper/cryptroot"
        fi

        case "${fs_type}" in
            ext4)     mkfs.ext4 -F "${root_part}" ;;
            btrfs)    mkfs.btrfs -f "${root_part}" ;;
            xfs)
                if [[ -f "/usr/share/xfsprogs/mkfs/lts_6.6.conf" ]]; then
                    mkfs.xfs -f -m bigtime=0 "${root_part}"
                else
                    mkfs.xfs -f -m bigtime=0 "${root_part}"
                    log_warn "XFS LTS config not found — using upstream defaults."
                fi
                ;;
            f2fs)
                local dev_rota
                dev_rota=$(lsblk -dno ROTA "${root_part}" 2>/dev/null)
                if [[ "${dev_rota}" == "0" ]]; then
                    log_warn "F2FS on non-rotational SSD — ext4 or XFS often perform better."
                    if ! tui_yesno "F2FS on SSD" "F2FS is designed for raw flash (eMMC/SD/USB). Continue?"; then
                        die "User aborted F2FS creation"
                    fi
                fi
                mkfs.f2fs -f -O extra_attr,compression "${root_part}"
                ;;
            *)        die "unsupported filesystem: ${fs_type}" ;;
        esac

        if [[ "$(state_get LUKS_KEYFILE no)" == "yes" ]]; then
            log_info "Creating LUKS keyfile to avoid double password prompt..."
            dd bs=512 count=4 if=/dev/urandom of=/crypto_keyfile.bin 2>/dev/null
            cryptsetup luksAddKey "${root_part}" /crypto_keyfile.bin
            chmod 000 /crypto_keyfile.bin
            state_set LUKS_KEYFILE_PATH "/crypto_keyfile.bin"
        fi

        log_info "Filesystem creation complete."
        return 0
    fi

    if [[ -n "$(state_get EFI_PART '')" ]]; then
        efi_part="$(state_get EFI_PART)"
        root_part="$(state_get ROOT_PART)"
        if [[ "${use_swap_partition}" == "yes" ]]; then
            swap_part="$(state_get SWAP_PART)"
        fi
    else
        efi_part=$(get_partition_name "${disk}" 1)
        if [[ "${use_swap_partition}" == "yes" ]]; then
            swap_part=$(get_partition_name "${disk}" 2)
            root_part=$(get_partition_name "${disk}" 3)
        else
            root_part=$(get_partition_name "${disk}" 2)
        fi
    fi

    [[ -b "${efi_part}" ]] || die "invalid EFI partition: ${efi_part}"
    [[ -b "${root_part}" ]] || die "invalid root partition: ${root_part}"
    [[ "/dev/$(lsblk -no PKNAME "${efi_part}" | tail -n1)" == "${disk}" ]] || die "EFI partition does not belong to selected disk"
    if [[ "$(state_get USE_LVM no)" != "yes" ]]; then
        [[ "/dev/$(lsblk -no PKNAME "${root_part}" | tail -n1)" == "${disk}" ]] || die "Root partition does not belong to selected disk"
    fi

    log_info "Wiping old filesystem signatures..."
    wipefs -af "${efi_part}" || true
    if [[ "$(state_get USE_LUKS no)" != "yes" ]]; then
        wipefs -af "${root_part}" || true
    fi
    if [[ "${use_swap_partition}" == "yes" && -n "${swap_part:-}" ]]; then
        wipefs -af "${swap_part}" || true
    fi

    log_info "Ensuring EFI filesystem support..."
    pacman -S --needed --noconfirm dosfstools
    modprobe fat 2>/dev/null || true
    modprobe vfat 2>/dev/null || true

    case "${fs_type}" in
        btrfs)     pacman -S --needed --noconfirm btrfs-progs ; modprobe btrfs 2>/dev/null || true ;;
        ext4)      pacman -S --needed --noconfirm e2fsprogs  ; modprobe ext4 2>/dev/null || true ;;
        xfs)       pacman -S --needed --noconfirm xfsprogs   ; modprobe xfs 2>/dev/null || true ;;
        f2fs)      pacman -S --needed --noconfirm f2fs-tools ; command -v mkfs.f2fs >/dev/null || die 'mkfs.f2fs unavailable'; modprobe f2fs 2>/dev/null || true ;;
    esac

    log_info "Formatting EFI partition..."
    mkfs.fat -F32 "${efi_part}" || recoverable_error 'Failed to create FAT32 EFI filesystem'
    partprobe "${disk}" || true
    udevadm settle || true

    if ! blkid -o value -s TYPE "${efi_part}" | grep -qi 'vfat'; then
        die "EFI partition ${efi_part} does not have a vfat signature — mkfs.fat may have failed silently"
    fi

    local tmp_efi_mount="/tmp/efi-check.$$"
    mkdir -p "${tmp_efi_mount}"
    if ! mount -t vfat "${efi_part}" "${tmp_efi_mount}"; then
        rmdir "${tmp_efi_mount}" 2>/dev/null || true
        die "EFI partition ${efi_part} cannot be mounted — mkfs.fat failed, check kernel VFAT support"
    fi
    umount "${tmp_efi_mount}"
    rmdir "${tmp_efi_mount}"

    if [[ "${use_swap_partition}" == "yes" && -n "${swap_part:-}" ]]; then
        log_info "Initializing swap partition..."
        [[ -b "${swap_part}" ]] || die "invalid swap partition: ${swap_part}"
        mkswap "${swap_part}"
        swapon "${swap_part}"
    fi

    local fs_target="${root_part}"

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        local root_lv="/dev/vg0/root"
        local home_lv="/dev/vg0/home"
        local data_lv="/dev/vg0/data"

        [[ -b "${root_lv}" ]] || die "Root LV not found: ${root_lv} — LVM may not have been set up correctly"

        log_info "LVM detected — creating filesystem on logical volume ${root_lv}..."

        case "${fs_type}" in
            btrfs)     mkfs.btrfs -f "${root_lv}" ;;
            ext4)      mkfs.ext4 -F "${root_lv}" ;;
            xfs)
                if [[ -f "/usr/share/xfsprogs/mkfs/lts_6.6.conf" ]]; then
                    mkfs.xfs -f -m bigtime=0 "${root_lv}"
                else
                    mkfs.xfs -f -m bigtime=0 "${root_lv}"
                    log_warn "XFS LTS config not found — using upstream defaults."
                fi
                ;;
            f2fs)
                local dev_rota
                dev_rota=$(lsblk -dno ROTA "${root_part}" 2>/dev/null)
                if [[ "${dev_rota}" == "0" ]]; then
                    log_warn "F2FS on non-rotational SSD — ext4 or XFS often perform better."
                    if ! tui_yesno "F2FS on SSD" "F2FS is designed for raw flash (eMMC/SD/USB). Continue?"; then
                        die "User aborted F2FS creation"
                    fi
                fi
                mkfs.f2fs -f -O extra_attr,compression "${root_lv}"
                ;;
            *)        die "Unsupported filesystem for LVM: ${fs_type}" ;;
        esac

        if [[ -b "${home_lv}" ]]; then
            log_info "Creating filesystem on home LV..."
            mkfs.ext4 -F "${home_lv}"
        fi
        if [[ -b "${data_lv}" ]]; then
            log_info "Creating filesystem on data LV..."
            mkfs.ext4 -F "${data_lv}"
        fi

        log_info "LVM filesystem creation complete."
        return 0
    fi

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        log_info "Setting up LUKS on ${fs_target}..."
        cryptsetup close cryptroot 2>/dev/null || true
        local luks_pass
        luks_pass="$(state_get LUKS_PASS)"
        printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "${fs_target}" -
        printf '%s' "${luks_pass}" | cryptsetup luksOpen "${fs_target}" cryptroot -
        fs_target="/dev/mapper/cryptroot"
    fi

    case "${fs_type}" in
        btrfs)
            log_info "Creating BTRFS filesystem..."
            mkfs.btrfs -f "${fs_target}"
            ;;
        ext4)
            log_info "Creating EXT4 filesystem..."
            mkfs.ext4 -F "${fs_target}"
            ;;
        xfs)
            log_info "Creating XFS filesystem (GRUB-compatible)..."
            if [[ -f "/usr/share/xfsprogs/mkfs/lts_6.6.conf" ]]; then
                mkfs.xfs -f -m bigtime=0 "${fs_target}"
            else
                mkfs.xfs -f -m bigtime=0 "${fs_target}"
                log_warn "XFS LTS config not found – using upstream defaults. GRUB may fail if features are incompatible."
            fi
            ;;
        f2fs)
            log_info "Creating F2FS filesystem..."
            local dev_rota
            dev_rota=$(lsblk -dno ROTA "${fs_target}" 2>/dev/null)
            if [[ "${dev_rota}" == "0" ]]; then
                log_warn "F2FS on non-rotational SSD – ext4 or XFS often perform better."
                if ! tui_yesno "F2FS on SSD" "F2FS is designed for raw flash (eMMC/SD/USB). Continue?"; then
                    die "User aborted F2FS creation"
                fi
            fi
            mkfs.f2fs -f -O extra_attr,compression "${fs_target}"
            ;;
    esac

    log_info "Filesystem creation complete."
}