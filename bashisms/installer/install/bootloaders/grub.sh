#!/usr/bin/env bash
set -Eeuo pipefail

bootloader_install_grub() {
    log_info "Installing GRUB..."
    findmnt -rn -o FSTYPE /mnt/boot/efi | grep -qx 'vfat' || die 'EFI partition not mounted as vfat'

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
        local grub_cmdline
        grub_cmdline=$(generate_root_cmdline "${fs_type}" "${crypt_uuid}" "${mapper_name}" "${root_uuid}" "no")
        artix-chroot /mnt sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 ${grub_cmdline}\"|" /etc/default/grub
    fi

    if [[ "${fs_type}" == "xfs" ]]; then
        log_info "Verifying XFS features for GRUB compatibility..."
        if artix-chroot /mnt xfs_info "${root_device}" 2>/dev/null | grep -q 'bigtime=1'; then
            die "XFS bigtime is enabled and may be incompatible with older GRUB builds."
        fi
    fi

    local -a grub_extra_args=()
    grub_extra_args+=( --removable )

    local -a grub_modules=( part_gpt part_msdos fat ext2 )
    local -a grub_preload=()

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        grub_modules+=( lvm )
        grub_preload+=( lvm )
    fi
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        grub_modules+=( cryptodisk luks )
        grub_preload+=( cryptodisk luks )
    fi

    if [[ ${#grub_modules[@]} -gt 4 ]]; then
        grub_extra_args+=( --modules )
        grub_extra_args+=( "${grub_modules[*]}" )
    fi

    if [[ ${#grub_preload[@]} -gt 0 ]]; then
        echo "GRUB_PRELOAD_MODULES=\"${grub_preload[*]}\"" >> /mnt/etc/default/grub
    fi

    xtrace_safe artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARTIX "${grub_extra_args[@]}" || recoverable_error 'grub-install failed – updating ArtixForge may help'
    if [[ -n "${root_param}" ]]; then
        artix-chroot /mnt sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${root_param}\"|" /etc/default/grub
    fi
    log_info "Generating GRUB configuration..."
    xtrace_safe artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || recoverable_error 'grub-mkconfig failed – updating ArtixForge may fix this'
}