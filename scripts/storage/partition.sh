#!/usr/bin/env bash
set -Eeuo pipefail

partition_disk() {
    local disk swap_type swap_size
    disk="$(state_get DISK)"
    [[ -n "${disk}" ]] || die 'no disk selected'
    [[ -b "${disk}" ]] || die 'invalid disk device'
    swap_type="$(state_get SWAP_ENABLED none)"
    swap_size="$(state_get SWAP_SIZE 0)"

    log_info "Preparing disk ${disk}..."
    swapoff -a 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    zpool export -a 2>/dev/null || true
    vgchange -an vg0 2>/dev/null || true
    dmsetup remove_all 2>/dev/null || true

    log_info "Wiping existing signatures..."
    wipefs --all --force "${disk}"
    sgdisk --zap-all "${disk}" 2>/dev/null || true
    dd if=/dev/zero of="${disk}" bs=1M count=32 conv=fsync status=none 2>/dev/null || true
    partprobe "${disk}" 2>/dev/null || true
    udevadm settle
    sleep 1
    blockdev --rereadpt "${disk}" 2>/dev/null || true

    local fs_type
    fs_type="$(state_get FS_TYPE ext4)"
    local use_swap_partition="no"
    if [[ "${swap_type}" == "partition" ]]; then
        use_swap_partition="yes"
    fi

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        log_info "Creating MBR partition layout..."
        parted -s "${disk}" mklabel msdos
        parted -s "${disk}" mkpart primary 1MiB 2MiB
        if [[ "${use_swap_partition}" == "yes" ]]; then
            parted -s "${disk}" mkpart primary linux-swap 2MiB "${swap_size}"
            parted -s "${disk}" mkpart primary "${swap_size}" 100%
        else
            parted -s "${disk}" mkpart primary 2MiB 100%
        fi
        partprobe "${disk}" 2>/dev/null || true
        udevadm settle
        sleep 2

        if [[ "${use_swap_partition}" == "yes" ]]; then
            [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'swap partition not created'
            [[ -b "$(get_partition_name "${disk}" 3)" ]] || die 'root partition not created'
        else
            [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'root partition not created'
        fi
        return 0
    fi

    log_info "Creating GPT partition layout..."
    sgdisk -n 1:0:+1024M -t 1:ef00 "${disk}"
    if [[ "${use_swap_partition}" == "yes" ]]; then
        sgdisk -n 2:0:+"${swap_size}" -t 2:8200 "${disk}"
        sgdisk -n 3:0:0 -t 3:8300 "${disk}"
    else
        sgdisk -n 2:0:0 -t 2:8300 "${disk}"
    fi

    partprobe "${disk}" 2>/dev/null || true
    udevadm settle
    sleep 2
    blockdev --rereadpt "${disk}" 2>/dev/null || true

    [[ -b "$(get_partition_name "${disk}" 1)" ]] || die 'EFI partition not created'
    if [[ "${use_swap_partition}" == "yes" ]]; then
        [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'swap partition not created'
        [[ -b "$(get_partition_name "${disk}" 3)" ]] || die 'root partition not created'
    else
        [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'root partition not created'
    fi

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        log_info "Setting up LVM..."
        local root_part
        if [[ "${use_swap_partition}" == "yes" ]]; then
            root_part=$(get_partition_name "${disk}" 3)
        else
            root_part=$(get_partition_name "${disk}" 2)
        fi

        sgdisk -t "$(lsblk -no PARTN "${root_part}" | head -n1)":8e00 "${disk}"
        partprobe "${disk}" 2>/dev/null || true
        udevadm settle

        local lvm_target="${root_part}"
        local vg_name="${LVM_VG_NAME:-vg0}"
        if vgdisplay "${vg_name}" &>/dev/null; then
            vg_name=$(tui_input "LVM" "Volume group '${vg_name}' already exists. Enter new name:" "vg1") || die "LVM cancelled"
        fi
        state_set LVM_VG_NAME "${vg_name}"

        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            dmsetup remove cryptlvm 2>/dev/null || true
            wipefs -af "${root_part}" || true
            log_info "Formatting LUKS container on ${root_part}..."
            local luks_pass="$(state_get LUKS_PASS)"
            printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "${root_part}" -
            log_info "Opening LUKS container..."
            printf '%s' "${luks_pass}" | cryptsetup luksOpen "${root_part}" cryptlvm -
            if [[ ! -b /dev/mapper/cryptlvm ]]; then
                die "LUKS mapper /dev/mapper/cryptlvm not created"
            fi
            lvm_target="/dev/mapper/cryptlvm"
        fi

        xtrace_safe pvcreate -ff "${lvm_target}" || die "pvcreate failed"
        xtrace_safe vgcreate "${vg_name}" "${lvm_target}" || die "vgcreate failed"
        xtrace_safe lvcreate -L 20G -n root "${vg_name}" || die "lvcreate root failed"
        xtrace_safe lvcreate -L 8G -n home "${vg_name}" || true
        xtrace_safe lvcreate -l 100%FREE -n data "${vg_name}" || true
    fi

    log_info "Partitioning complete."
}