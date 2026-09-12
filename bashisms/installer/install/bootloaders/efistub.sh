#!/usr/bin/env bash
set -Eeuo pipefail

bootloader_install_efistub() {
    log_info "Configuring EFIStub boot entry..."
    command -v efibootmgr >/dev/null 2>&1 || die 'efibootmgr unavailable'

    local kernel_choice kernel_image initramfs_image microcode_file
    kernel_choice="$(state_get KERNEL_CHOICE linux)"
    kernel_image=$(find_kernel_image "${kernel_choice}")
    [[ -n "${kernel_image}" ]] || die 'failed to locate kernel image'
    local kver
    kver=$(basename "${kernel_image}" | sed 's/^vmlinuz-//')
    initramfs_image=$(find_initramfs_image "${kver}")
    [[ -n "${initramfs_image}" ]] || die 'failed to locate initramfs image'
    microcode_file="$(state_get MICROCODE_IMAGE)"

    local kernel_basename initramfs_basename microcode_image_str
    kernel_basename="$(basename "${kernel_image}")"
    initramfs_basename="$(basename "${initramfs_image}")"
    local esp_artix_dir="${esp_mount}/EFI/Artix"
    mkdir -p "${esp_artix_dir}"
    cp -f "${kernel_image}" "${esp_artix_dir}/${kernel_basename}"
    cp -f "${initramfs_image}" "${esp_artix_dir}/${initramfs_basename}"

    if [[ -n "${microcode_file}" && -f "/mnt/boot/${microcode_file}" ]]; then
        cp -f "/mnt/boot/${microcode_file}" "${esp_artix_dir}/${microcode_file}"
        microcode_image_str="initrd=\\EFI\\Artix\\${microcode_file}"
    fi

    local loader="\\EFI\\Artix\\${kernel_basename}"
    local cmdline
    cmdline=$(generate_root_cmdline "${fs_type}" "${crypt_uuid}" "${mapper_name}" "${root_uuid}" "no")
    [[ -n "${microcode_image_str:-}" ]] && cmdline+=" ${microcode_image_str}"
    cmdline+=" initrd=\\EFI\\Artix\\${initramfs_basename}"

    log_info "Creating EFI boot entry..."
    artix-chroot /mnt efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
        --label 'Artix Linux' --loader "${loader}" --unicode "${cmdline}" --verbose \
        || die 'failed to create EFI boot entry'

    log_info "Verifying EFI boot entries..."
    artix-chroot /mnt efibootmgr -v | grep -qi 'Artix Linux' || die "failed to verify EFI boot entry"
}