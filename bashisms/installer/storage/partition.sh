#!/usr/bin/env bash
set -Eeuo pipefail

_get_root_partition_num() {
    local use_swap="$1"
    if [[ "${use_swap}" == "yes" ]]; then
        echo 3
    else
        echo 2
    fi
}

_partition_wipe() {
    local disk="$1"
    log_info "Preparing disk ${disk}..."
    swapoff -a 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    zpool export -a 2>/dev/null || true
    vgchange -an "$(state_get LVM_VG_NAME vg0)" 2>/dev/null || true
    dmsetup remove_all 2>/dev/null || true

    log_info "Wiping existing signatures..."
    wipefs --all --force "${disk}"
    sgdisk --zap-all "${disk}" 2>/dev/null || true
    dd if=/dev/zero of="${disk}" bs=1M count=32 conv=fsync status=none 2>/dev/null || true
    partprobe "${disk}" 2>/dev/null || true
    udevadm settle
    sleep 1
    blockdev --rereadpt "${disk}" 2>/dev/null || true
}

_partition_layout_bios() {
    local disk="$1" use_swap="$2" swap_size_mb="$3"

    log_info "Creating MBR partition layout..."
    parted -s "${disk}" mklabel msdos
    parted -s "${disk}" mkpart primary 1MiB 2MiB
    if [[ "${use_swap}" == "yes" ]]; then
        local swap_end=$(( 2 + swap_size_mb ))MiB
        parted -s "${disk}" mkpart primary linux-swap 2MiB "${swap_end}"
        parted -s "${disk}" mkpart primary "${swap_end}" 100%
    else
        parted -s "${disk}" mkpart primary 2MiB 100%
    fi
    partprobe "${disk}" 2>/dev/null || true
    udevadm settle
    sleep 2

    local root_num
    root_num=$(_get_root_partition_num "${use_swap}")
    [[ -b "$(get_partition_name "${disk}" "${root_num}")" ]] || die 'root partition not created'
    [[ "${use_swap}" == "yes" && -b "$(get_partition_name "${disk}" 2)" ]] || die 'swap partition not created'
}

_partition_layout_uefi() {
    local disk="$1" use_swap="$2" swap_size_mb="$3"

    log_info "Creating GPT partition layout..."
    sgdisk -n 1:0:+1024M -t 1:ef00 "${disk}"
    if [[ "${use_swap}" == "yes" ]]; then
        sgdisk -n 2:0:+"${swap_size_mb}M" -t 2:8200 "${disk}"
        sgdisk -n 3:0:0 -t 3:8300 "${disk}"
    else
        sgdisk -n 2:0:0 -t 2:8300 "${disk}"
    fi

    partprobe "${disk}" 2>/dev/null || true
    udevadm settle
    sleep 2
    blockdev --rereadpt "${disk}" 2>/dev/null || true

    [[ -b "$(get_partition_name "${disk}" 1)" ]] || die 'EFI partition not created'
    local root_num
    root_num=$(_get_root_partition_num "${use_swap}")
    [[ -b "$(get_partition_name "${disk}" "${root_num}")" ]] || die 'root partition not created'
    [[ "${use_swap}" == "yes" && -b "$(get_partition_name "${disk}" 2)" ]] || die 'swap partition not created'
}

_mark_partition_lvm() {
    local disk="$1" part_num="$2"
    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        parted -s "${disk}" set "${part_num}" lvm on
    else
        sgdisk -t "${part_num}:8e00" "${disk}"
    fi
    partprobe "${disk}" 2>/dev/null || true
    udevadm settle
}

_partition_luks_on_lvm() {
    local target="$1"
    dmsetup remove cryptlvm 2>/dev/null || true
    wipefs -af "${target}" || true
    log_info "Formatting LUKS container on ${target}..."
    local luks_pass
    luks_pass="$(state_get LUKS_PASS)"
    printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 "${target}" -
    log_info "Opening LUKS container..."
    printf '%s' "${luks_pass}" | cryptsetup luksOpen "${target}" cryptlvm -
    [[ -b /dev/mapper/cryptlvm ]] || die "LUKS mapper /dev/mapper/cryptlvm not created"
}

_partition_setup_lvm() {
    local disk="$1" root_part="$2" root_part_num="$3"

    log_info "Setting up LVM..."
    _mark_partition_lvm "${disk}" "${root_part_num}"

    local vg_name
    vg_name="$(state_get LVM_VG_NAME vg0)"
    if vgdisplay "${vg_name}" &>/dev/null; then
        vg_name=$(tui_input "LVM" "Volume group '${vg_name}' already exists. Enter new name:" "vg1") || die "LVM cancelled"
    fi
    state_set LVM_VG_NAME "${vg_name}"

    local lvm_target="${root_part}"
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        _partition_luks_on_lvm "${root_part}"
        lvm_target="/dev/mapper/cryptlvm"
    fi

    xtrace_safe pvcreate -ff "${lvm_target}" || die "pvcreate failed"
    xtrace_safe vgcreate "${vg_name}" "${lvm_target}" || die "vgcreate failed"
    xtrace_safe lvcreate -L 20G -n root "${vg_name}" || die "lvcreate root failed"
    xtrace_safe lvcreate -L 8G -n home "${vg_name}" || true
    xtrace_safe lvcreate -l 100%FREE -n data "${vg_name}" || true
}

partition_disk() {
    local disk swap_type swap_size
    disk="$(state_get DISK)"
    [[ -n "${disk}" ]] || die 'no disk selected'
    [[ -b "${disk}" ]] || die 'invalid disk device'
    swap_type="$(state_get SWAP_ENABLED none)"
    swap_size="$(state_get SWAP_SIZE 0)"

    local use_swap="no"
    [[ "${swap_type}" == "partition" ]] && use_swap="yes"

    _partition_wipe "${disk}"

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        _partition_layout_bios "${disk}" "${use_swap}" "${swap_size}"
    else
        _partition_layout_uefi "${disk}" "${use_swap}" "${swap_size}"
    fi

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        local root_num root_part
        root_num=$(_get_root_partition_num "${use_swap}")
        root_part=$(get_partition_name "${disk}" "${root_num}")
        _partition_setup_lvm "${disk}" "${root_part}" "${root_num}"
    fi

    log_info "Partitioning complete."
}