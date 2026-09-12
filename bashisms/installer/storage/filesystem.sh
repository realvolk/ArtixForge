#!/usr/bin/env bash
set -Eeuo pipefail

_install_fs_tools() {
    local fs_type="$1"
    case "${fs_type}" in
        ext4)  pacman -S --needed --noconfirm e2fsprogs  ;;
        btrfs) pacman -S --needed --noconfirm btrfs-progs ;;
        xfs)   pacman -S --needed --noconfirm xfsprogs   ;;
        f2fs)  pacman -S --needed --noconfirm f2fs-tools
               command -v mkfs.f2fs >/dev/null || die 'mkfs.f2fs unavailable' ;;
        *)     die "unsupported filesystem: ${fs_type}" ;;
    esac
    modprobe "${fs_type}" 2>/dev/null || true
}

_mkfs_f2fs() {
    local target="$1"
    local dev_rota
    dev_rota=$(lsblk -dno ROTA "${target}" 2>/dev/null)
    if [[ "${dev_rota}" == "0" ]]; then
        log_warn "F2FS on non-rotational SSD — ext4 or XFS often perform better."
        if ! tui_yesno "F2FS on SSD" "F2FS is designed for raw flash (eMMC/SD/USB). Continue?"; then
            die "User aborted F2FS creation"
        fi
    fi
    mkfs.f2fs -f -O extra_attr,compression "${target}"
}

_mkfs_xfs() {
    local target="$1"
    [[ -f "/usr/share/xfsprogs/mkfs/lts_6.6.conf" ]] || \
        log_warn "XFS LTS config not found — using upstream defaults."
    mkfs.xfs -f -m bigtime=0 "${target}"
}

_mkfs_target() {
    local fs_type="$1" target="$2"
    case "${fs_type}" in
        ext4)  mkfs.ext4 -F "${target}" ;;
        btrfs) mkfs.btrfs -f "${target}" ;;
        xfs)   _mkfs_xfs "${target}" ;;
        f2fs)  _mkfs_f2fs "${target}" ;;
        *)     die "unsupported filesystem: ${fs_type}" ;;
    esac
}

_create_luks_keyfile() {
    local device="$1"
    local luks_pass
    luks_pass="$(state_get LUKS_PASS)"
    local keyfile="/crypto_keyfile.bin"

    log_info "Generating LUKS keyfile..."
    dd if=/dev/urandom of="${keyfile}" bs=512 count=8 status=none
    chmod 000 "${keyfile}"

    log_info "Adding keyfile as LUKS keyslot..."
    printf '%s' "${luks_pass}" | cryptsetup luksAddKey --key-file - "${device}" "${keyfile}" \
        || die "Failed to add LUKS keyfile to ${device}"

    state_set LUKS_KEYFILE_PATH "${keyfile}"
    log_info "Keyfile registered on ${device}"
}


_setup_luks_container() {
    local target="$1" mapper="$2"
    cryptsetup close "${mapper}" 2>/dev/null || true
    log_info "Setting up LUKS on ${target}..."
    local luks_pass
    luks_pass="$(state_get LUKS_PASS)"
    printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "${target}" -
    printf '%s' "${luks_pass}" | cryptsetup luksOpen "${target}" "${mapper}" -

    if [[ "$(state_get LUKS_KEYFILE no)" == "yes" ]]; then
        _create_luks_keyfile "${target}"
    fi
}

_format_esp() {
    local disk="$1" efi_part="$2"

    log_info "Ensuring EFI filesystem support..."
    pacman -S --needed --noconfirm dosfstools
    modprobe fat 2>/dev/null || true
    modprobe vfat 2>/dev/null || true

    log_info "Formatting EFI partition..."
    mkfs.fat -F32 "${efi_part}" || recoverable_error 'Failed to create FAT32 EFI filesystem'
    partprobe "${disk}" || true
    udevadm settle || true

    if ! blkid -o value -s TYPE "${efi_part}" | grep -qi 'vfat'; then
        die "EFI partition ${efi_part} does not have a vfat signature — mkfs.fat may have failed silently"
    fi

    local tmp="/tmp/efi-check.$$"
    mkdir -p "${tmp}"
    if ! mount -t vfat "${efi_part}" "${tmp}"; then
        rmdir "${tmp}" 2>/dev/null || true
        die "EFI partition ${efi_part} cannot be mounted — mkfs.fat failed, check kernel VFAT support"
    fi
    umount "${tmp}"
    rmdir "${tmp}"
}

_initialize_swap() {
    local swap_part="$1"
    log_info "Initializing swap partition..."
    [[ -b "${swap_part}" ]] || die "invalid swap partition: ${swap_part}"
    mkswap "${swap_part}"
    swapon "${swap_part}"
}

_create_lvm_filesystems() {
    local fs_type="$1"
    local vg_name
    vg_name="$(state_get LVM_VG_NAME vg0)"

    local root_lv="/dev/${vg_name}/root"
    local home_lv="/dev/${vg_name}/home"
    local data_lv="/dev/${vg_name}/data"

    [[ -b "${root_lv}" ]] || die "Root LV not found: ${root_lv} — LVM may not have been set up correctly"

    log_info "LVM detected — creating filesystem on logical volume ${root_lv}..."
    _mkfs_target "${fs_type}" "${root_lv}"

    if [[ -b "${home_lv}" ]]; then
        log_info "Creating filesystem on home LV..."
        mkfs.ext4 -F "${home_lv}"
    fi
    if [[ -b "${data_lv}" ]]; then
        log_info "Creating filesystem on data LV..."
        mkfs.ext4 -F "${data_lv}"
    fi

    log_info "LVM filesystem creation complete."
}

create_filesystems() {
    local disk fs_type swap_type swap_size
    disk="$(state_get DISK)"
    [[ -b "${disk}" ]] || die "invalid disk: ${disk}"
    fs_type="$(state_get FS_TYPE)"
    swap_type="$(state_get SWAP_ENABLED none)"
    swap_size="$(state_get SWAP_SIZE 0)"

    local use_swap="no"
    [[ "${swap_type}" == "partition" ]] && use_swap="yes"

    local use_luks use_lvm
    use_luks="$(state_get USE_LUKS no)"
    use_lvm="$(state_get USE_LVM no)"

    local efi_part="" swap_part="" root_part=""
    local root_num
    root_num=$(_get_root_partition_num "${use_swap}")

    if [[ "${ARTIX_BOOT_MODE:-uefi}" != "bios" ]]; then
        if [[ -n "$(state_get EFI_PART '')" ]]; then
            efi_part="$(state_get EFI_PART)"
        else
            efi_part=$(get_partition_name "${disk}" 1)
        fi
    fi

    if [[ -n "$(state_get ROOT_PART '')" ]]; then
        root_part="$(state_get ROOT_PART)"
    else
        root_part=$(get_partition_name "${disk}" "${root_num}")
    fi

    if [[ "${use_swap}" == "yes" ]]; then
        if [[ -n "$(state_get SWAP_PART '')" ]]; then
            swap_part="$(state_get SWAP_PART)"
        else
            swap_part=$(get_partition_name "${disk}" 2)
        fi
    fi

    [[ -b "${root_part}" ]] || die "invalid root partition: ${root_part}"
    if [[ -n "${efi_part}" ]]; then
        [[ -b "${efi_part}" ]] || die "invalid EFI partition: ${efi_part}"
        [[ "/dev/$(lsblk -no PKNAME "${efi_part}" | tail -n1)" == "${disk}" ]] || die "EFI partition does not belong to selected disk"
    fi
    if [[ "${use_lvm}" != "yes" ]]; then
        [[ "/dev/$(lsblk -no PKNAME "${root_part}" | tail -n1)" == "${disk}" ]] || die "Root partition does not belong to selected disk"
    fi

    log_info "Wiping old filesystem signatures..."
    [[ -n "${efi_part}" ]] && wipefs -af "${efi_part}" || true
    if [[ "${use_luks}" != "yes" ]]; then
        wipefs -af "${root_part}" || true
    fi
    if [[ "${use_swap}" == "yes" && -n "${swap_part}" ]]; then
        wipefs -af "${swap_part}" || true
    fi

    _install_fs_tools "${fs_type}"

    if [[ -n "${efi_part}" ]]; then
        _format_esp "${disk}" "${efi_part}"
    fi

    if [[ "${use_swap}" == "yes" && -n "${swap_part}" ]]; then
        _initialize_swap "${swap_part}"
    fi

    if [[ "${use_lvm}" == "yes" ]]; then
        _create_lvm_filesystems "${fs_type}"
        return 0
    fi

    local fs_target="${root_part}"
    if [[ "${use_luks}" == "yes" ]]; then
        _setup_luks_container "${fs_target}" cryptroot
        fs_target="/dev/mapper/cryptroot"
    fi

    _mkfs_target "${fs_type}" "${fs_target}"

    log_info "Filesystem creation complete."
}