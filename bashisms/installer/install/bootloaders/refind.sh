#!/usr/bin/env bash
set -Eeuo pipefail

bootloader_install_refind() {
    log_info "Installing rEFInd..."
    findmnt -rn -o FSTYPE /mnt/boot/efi | grep -qx 'vfat' || die 'EFI partition not mounted as vfat'
    
    local refind_root_param
    if [[ -n "${root_param}" ]]; then
        refind_root_param="${root_param}"
    else
        refind_root_param=$(generate_root_cmdline "${fs_type}" "${crypt_uuid}" "${mapper_name}" "${root_uuid}" "no")
    fi

    artix-chroot /mnt bash -c "echo \"${refind_root_param}\" > /boot/refind_linux.conf"
    artix-chroot /mnt refind-install || die 'refind-install failed'
}