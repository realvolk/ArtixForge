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

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        echo 'GRUB_PRELOAD_MODULES="lvm dm-mod"' >> /mnt/etc/default/grub
        grub_extra_args+=( --modules )
        grub_extra_args+=( "part_gpt part_msdos fat lvm dm-mod ext2" )
    fi

    xtrace_safe artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ARTIX "${grub_extra_args[@]}" || recoverable_error 'grub-install failed – updating ArtixForge may help'
    if [[ -n "${root_param}" ]]; then
        artix-chroot /mnt sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${root_param}\"|" /etc/default/grub
    fi
    log_info "Generating GRUB configuration..."
    xtrace_safe artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || recoverable_error 'grub-mkconfig failed – updating ArtixForge may fix this'
}