#!/usr/bin/env bash
set -Eeuo pipefail

validate_recipe() {
    local recipe_name="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${recipe_name}.sh"
    [[ -f "${recipe_file}" ]] || die "Recipe file missing: ${recipe_file}"

    local pkgname='' pkgver='' pkgrel='' sources=() depends=() makedepends=()
    unset -f prepare configure build check package 2>/dev/null || true
    source "${recipe_file}"

    [[ -n "${pkgname}" ]] || die "Recipe ${recipe_name}: pkgname missing"
    [[ -n "${pkgver}" ]]  || die "Recipe ${recipe_name}: pkgver missing"
    [[ -n "${pkgrel}" ]]  || die "Recipe ${recipe_name}: pkgrel missing"
    [[ "${#sources[@]}" -gt 0 ]] || die "Recipe ${recipe_name}: sources empty"

    if ! declare -f build >/dev/null; then
        die "Recipe ${recipe_name}: build() function missing"
    fi
    if ! declare -f package >/dev/null; then
        die "Recipe ${recipe_name}: package() function missing"
    fi

    local src entry
    for src in "${sources[@]}"; do
        IFS='|' read -ra entry <<< "${src}"
        [[ "${#entry[@]}" -eq 3 ]] || die "Recipe ${recipe_name}: malformed source entry: ${src}"
    done
}

validate_system() {
    log_info "Running post-build system validation..."

    local fs_type bootloader
    fs_type="$(state_get FS_TYPE ext4)"
    bootloader="$(state_get BOOTLOADER grub)"

    local kver
    kver=$(ls -1 /mnt/lib/modules | grep -v 'artix' | sort -V | tail -1)
    [[ -n "${kver}" ]] || { log_warn "No custom kernel modules found"; return 0; }

    local config_file="/mnt/boot/config-${kver}"
    if [[ -f "${config_file}" ]]; then
        case "${fs_type}" in
            ext4)   grep -q 'CONFIG_EXT4_FS=y' "${config_file}" || log_warn "ext4 not built-in" ;;
            btrfs)  grep -q 'CONFIG_BTRFS_FS=y' "${config_file}" || log_warn "btrfs not built-in" ;;
            xfs)    grep -q 'CONFIG_XFS_FS=y' "${config_file}" || log_warn "xfs not built-in" ;;
            f2fs)   grep -q 'CONFIG_F2FS_FS=y' "${config_file}" || log_warn "f2fs not built-in" ;;
        esac
        grep -q 'CONFIG_BLK_DEV_SD=y' "${config_file}" || log_warn "CONFIG_BLK_DEV_SD not built-in"
        (grep -q 'CONFIG_ATA=y' "${config_file}" || grep -q 'CONFIG_VIRTIO_BLK=y' "${config_file}") || log_warn "No ATA/VIRTIO_BLK built-in"
    else
        log_warn "Kernel config not found: ${config_file}"
    fi

    local initramfs_file="/mnt/boot/initramfs-linux-custom.img"
    [[ -f "${initramfs_file}" ]] || log_warn "No initramfs for custom kernel"

    case "${bootloader}" in
        grub)
            if artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; then
                artix-chroot /mnt grep -q 'linux-custom' /boot/grub/grub.cfg || log_warn "GRUB config missing linux-custom entry"
            else
                log_warn "Could not regenerate GRUB config"
            fi
            ;;
        efistub)
            artix-chroot /mnt efibootmgr -v 2>/dev/null | grep -qi 'Artix' || log_warn "No EFI boot entry found"
            ;;
    esac

    if [[ "${bootloader}" == "uki" ]]; then
        local uki_file="/mnt/boot/efi/EFI/Artix/linux-custom.efi"
        [[ -f "${uki_file}" ]] || log_warn "UKI file not found: ${uki_file}"
        artix-chroot /mnt efibootmgr -v 2>/dev/null | grep -qi 'UKI' || log_warn "No UKI boot entry found"
    fi

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        artix-chroot /mnt command -v lvm &>/dev/null || log_warn "lvm2 not found in target"
        local vg_name
        vg_name="$(state_get LVM_VG_NAME vg0)"
        if ! artix-chroot /mnt vgscan 2>/dev/null | grep -q 'Found volume group'; then
            log_warn "No LVM volume group found — LVM configuration may be incomplete"
        elif ! artix-chroot /mnt vgscan 2>/dev/null | grep -q "${vg_name}"; then
            log_warn "LVM volume group ${vg_name} not found (other VGs present)"
        fi
    fi

    log_info "Post-build validation complete."
}