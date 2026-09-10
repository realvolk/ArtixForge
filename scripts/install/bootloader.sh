#!/usr/bin/env bash
set -Eeuo pipefail

BOOTLOADER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bootloaders"

source "${BOOTLOADER_DIR}/grub.sh"
source "${BOOTLOADER_DIR}/refind.sh"
source "${BOOTLOADER_DIR}/efistub.sh"
source "${BOOTLOADER_DIR}/limine.sh"
source "${BOOTLOADER_DIR}/uboot.sh"

generate_root_cmdline() {
    local fs_type="${1}"
    local crypt_uuid="${2}"
    local mapper_name="${3}"
    local root_uuid="${4}"
    local include_rootfstype="${5:-no}"

    local cmdline=""
    if [[ "${fs_type}" == 'zfs' ]]; then
        cmdline="root=ZFS=zroot/root rw modules=zfs rootfstype=zfs"
    else
        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            cmdline+="cryptdevice=UUID=${crypt_uuid}:${mapper_name} "
        fi
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            cmdline+="root=/dev/vg0/root "
        elif [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            cmdline+="root=/dev/mapper/${mapper_name} "
        else
            cmdline+="root=UUID=${root_uuid} "
        fi
        cmdline+="rw"
    fi

    if [[ "${fs_type}" == "btrfs" ]]; then
        local btrfs_layout
        btrfs_layout="$(state_get BTRFS_LAYOUT standard)"
        cmdline+=" rootflags=subvol=@"
        if [[ "${btrfs_layout}" == "flat" ]]; then
            cmdline="root=UUID=${root_uuid} rw"
        fi
    fi

    if [[ "${include_rootfstype}" == "yes" ]]; then
        case "${fs_type}" in
            btrfs) cmdline+=" rootfstype=btrfs" ;;
            xfs)   cmdline+=" rootfstype=xfs" ;;
            f2fs)  cmdline+=" rootfstype=f2fs" ;;
        esac
    fi

    printf '%s' "${cmdline}"
}

find_kernel_image() {
    local kernel_choice="${1:-linux}"
    local dir="${2:-/mnt/boot}"

    if [[ -f "${dir}/vmlinuz-${kernel_choice}" ]]; then
        echo "${dir}/vmlinuz-${kernel_choice}"
        return 0
    fi

    if [[ "${kernel_choice}" == linux-cachyos* ]]; then
        local match
        match=$(ls -1 "${dir}/vmlinuz-linux-cachyos"* 2>/dev/null | head -n1)
        if [[ -n "${match}" ]]; then
            echo "${match}"
            return 0
        fi
    fi

    if [[ "${kernel_choice}" == xanmod ]]; then
        local match
        match=$(ls -1 "${dir}/vmlinuz-linux-xanmod"* 2>/dev/null | head -n1)
        if [[ -n "${match}" ]]; then
            echo "${match}"
            return 0
        fi
    fi

    if [[ -f "${dir}/vmlinuz-linux-custom" ]]; then
        echo "${dir}/vmlinuz-linux-custom"
        return 0
    fi

    ls -1 "${dir}/vmlinuz-"* 2>/dev/null | head -n1 || echo ""
}

find_initramfs_image() {
    local kver="${1}"
    local dir="${2:-/mnt/boot}"

    if [[ -f "${dir}/initramfs-${kver}.img" ]]; then
        echo "${dir}/initramfs-${kver}.img"
        return 0
    fi

    ls -1 "${dir}/initramfs-"*.img 2>/dev/null | grep -v fallback | head -n1 || echo ""
}

get_luks_raw_uuid() {
    local dev="$1"
    local disk
    disk="$(state_get DISK)"
    local current="$dev"

    while [[ -n "$current" ]]; do
        if blkid -o value -s TYPE "$current" 2>/dev/null | grep -q 'crypto_LUKS'; then
            blkid -s UUID -o value "$current" 2>/dev/null || echo ""
            return 0
        fi
        local parent
        parent="$(lsblk -no PKNAME "$current" 2>/dev/null || true)"
        if [[ -z "$parent" ]]; then
            break
        fi
        current="/dev/$parent"
        if [[ "$(lsblk -no TYPE "$current" 2>/dev/null)" == "disk" ]]; then
            break
        fi
    done

    local luks_dev
    luks_dev=$(blkid -o device -t TYPE=crypto_LUKS 2>/dev/null | while read -r candidate; do
        local cand_disk
        cand_disk="/dev/$(lsblk -no PKNAME "$candidate" 2>/dev/null | head -n1)"
        if [[ "${cand_disk}" == "${disk}" ]]; then
            echo "${candidate}"
            break
        fi
    done)
    if [[ -n "$luks_dev" ]]; then
        blkid -s UUID -o value "$luks_dev" 2>/dev/null || echo ""
        return 0
    fi

    echo ""
}

configure_bootloader() {
    local bootloader kernel fs_type root_param=''
    bootloader="$(state_get BOOTLOADER grub)"
    kernel="$(state_get KERNEL_CHOICE linux)"
    fs_type="$(state_get FS_TYPE)"
    [[ "${fs_type}" == 'zfs' ]] && root_param='root=ZFS=zroot/root'

    log_info "Generating initramfs..."
    artix-chroot /mnt mkinitcpio -P || true
    if ! compgen -G "/mnt/boot/initramfs-*.img" >/dev/null 2>&1; then
        recoverable_error 'No initramfs image was created – updating ArtixForge may fix this'
    fi
    log_info "Initramfs generation complete"

    if [[ "$(state_get LUKS_KEYFILE no)" == "yes" ]]; then
        local keyfile_path="$(state_get LUKS_KEYFILE_PATH /crypto_keyfile.bin)"
        if [[ -f "${keyfile_path}" ]]; then
            log_info "Embedding LUKS keyfile in initramfs..."
            cp "${keyfile_path}" /mnt/crypto_keyfile.bin
            chmod 000 /mnt/crypto_keyfile.bin
            if ! grep -q '/crypto_keyfile.bin' /mnt/etc/mkinitcpio.conf; then
                sed -i "s|^FILES=(|FILES=(/crypto_keyfile.bin |" /mnt/etc/mkinitcpio.conf
            fi
            artix-chroot /mnt mkinitcpio -P || true
        fi
    fi

    local root_device
    root_device=$(artix-chroot /mnt findmnt -n -o SOURCE /) || true
    root_device="${root_device%%[*}"
    [[ -n "${root_device}" ]] || die 'failed to detect root device'

    local root_source root_uuid esp_source esp_mount esp_disk esp_part
    root_source="$(findmnt -rn -o SOURCE --target /mnt)"
    root_source="${root_source%%[*}"
    [[ -n "${root_source}" ]] || die 'failed to detect root partition'
    [[ -b "${root_source}" ]] || die 'invalid root block device'
    root_uuid="$(blkid -s UUID -o value "${root_source}")"
    [[ -n "${root_uuid}" ]] || die 'failed to detect root UUID'

    local mapper_name="cryptroot"
    local crypt_uuid="${root_uuid}"

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local raw_uuid
        raw_uuid="$(get_luks_raw_uuid "${root_source}")"
        if [[ -n "${raw_uuid}" ]]; then
            crypt_uuid="${raw_uuid}"
        fi
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            mapper_name="cryptlvm"
        fi

        local luks_check
        luks_check=$(blkid -o device -t UUID="${crypt_uuid}" 2>/dev/null || true)
        if [[ -z "${luks_check}" ]] || ! blkid -o value -s TYPE "${luks_check}" 2>/dev/null | grep -q 'crypto_LUKS'; then
            luks_check=$(blkid -o device -t TYPE=crypto_LUKS 2>/dev/null | head -n1)
            if [[ -n "${luks_check}" ]]; then
                crypt_uuid=$(blkid -s UUID -o value "${luks_check}" 2>/dev/null)
                log_warn "Auto-corrected cryptdevice UUID to ${crypt_uuid} (found LUKS on ${luks_check})"
            else
                die "cryptdevice= required but no LUKS partition found"
            fi
        fi
    fi

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        log_info "Installing GRUB for BIOS..."

        local bios_cmdline
        bios_cmdline=$(generate_root_cmdline "${fs_type}" "${crypt_uuid}" "${mapper_name}" "${root_uuid}" "no")
        if [[ -n "${bios_cmdline}" ]]; then
            log_info "Setting GRUB cmdline: ${bios_cmdline}"
            if grep -q '^GRUB_CMDLINE_LINUX=' /mnt/etc/default/grub; then
                artix-chroot /mnt sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 ${bios_cmdline}\"|" /etc/default/grub
            else
                printf 'GRUB_CMDLINE_LINUX="%s"\n' "${bios_cmdline}" >> /mnt/etc/default/grub
            fi
        fi

        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
        fi

        artix-chroot /mnt grub-install --target=i386-pc --boot-directory=/boot "$(state_get DISK)" || die 'grub-install failed'
        artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || die 'grub-mkconfig failed'
        log_info "Bootloader setup complete (BIOS)."
        return 0
    fi

    for esp_mount in /mnt/boot/efi /mnt/efi /mnt/boot; do
        if findmnt -rn -o FSTYPE "${esp_mount}" | grep -qx 'vfat'; then
            esp_source="$(findmnt -rn -o SOURCE "${esp_mount}")"
            break
        fi
    done
    [[ -n "${esp_source}" ]] || die 'failed to detect EFI partition'
    log_info "EFI partition mount: ${esp_mount}"
    esp_disk="/dev/$(lsblk -no PKNAME "${esp_source}" | head -n1)"
    esp_part="$(lsblk -no PARTN "${esp_source}" | head -n1)"
    [[ -n "${esp_part}" ]] || die 'failed to detect EFI partition number'

    export fs_type crypt_uuid mapper_name root_uuid root_param root_device
    export esp_source esp_mount esp_disk esp_part

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        log_info "Configuring UKI generation..."
        local uki_kernel_image uki_kernel_name uki_kver
        uki_kernel_image=$(find_kernel_image "${kernel}")
        [[ -n "${uki_kernel_image}" ]] || die "No kernel image found for UKI (kernel: ${kernel})"
        uki_kernel_name=$(basename "${uki_kernel_image}")
        uki_kver="${uki_kernel_name#vmlinuz-}"
        local uki_initramfs_name="initramfs-${uki_kver}.img"
        local uki_output="/boot/efi/EFI/Linux/artix-${uki_kver}.efi"

        local uki_cmdline
        uki_cmdline=$(generate_root_cmdline "${fs_type}" "${crypt_uuid}" "${mapper_name}" "${root_uuid}" "no")

        if [[ -x /mnt/usr/bin/ukify ]]; then
            log_info "Generating UKI with ukify..."
            artix-chroot /mnt mkdir -p /boot/efi/EFI/Linux
            artix-chroot /mnt /usr/bin/ukify build \
                --linux="/boot/${uki_kernel_name}" \
                --initrd="/boot/${uki_initramfs_name}" \
                --cmdline="${uki_cmdline}" \
                --output="${uki_output}" || log_warn "ukify failed — UKI not generated"
        else
            die "ukify not found — install eukify package for UKI support"
        fi
    fi

    case "${bootloader}" in
        grub)    bootloader_install_grub ;;
        refind)  bootloader_install_refind ;;
        efistub) bootloader_install_efistub ;;
        limine)  bootloader_install_limine ;;
        uboot)   bootloader_install_uboot ;;
        *)       die "unsupported bootloader: ${bootloader}" ;;
    esac

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        local uki_file="/mnt/boot/efi/EFI/Linux/artix-${uki_kver}.efi"
        if [[ -f "${uki_file}" ]]; then
            log_info "Creating EFI boot entry for UKI..."
            artix-chroot /mnt efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
                --label 'Artix Linux (UKI)' \
                --loader "\\EFI\\Linux\\artix-${uki_kver}.efi" \
                --unicode "${uki_cmdline}" --verbose \
                || log_warn "Failed to create UKI EFI boot entry"

            if tui_yesno "Secure Boot" "Sign the UKI for Secure Boot?"; then
                local sb_key sb_cert
                sb_key=$(tui_input "Secure Boot" "Path to DB.key (on target):" "/etc/secureboot/DB.key")
                sb_cert=$(tui_input "Secure Boot" "Path to DB.crt (on target):" "/etc/secureboot/DB.crt")
                if [[ -f "/mnt${sb_key}" && -f "/mnt${sb_cert}" ]]; then
                    artix-chroot /mnt sbsign --key "${sb_key}" --cert "${sb_cert}" \
                        --output "/boot/efi/EFI/Linux/artix-${uki_kver}-signed.efi" \
                        "/boot/efi/EFI/Linux/artix-${uki_kver}.efi" || die "sbsign failed"
                    artix-chroot /mnt efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
                        --label 'Artix Linux (UKI Signed)' \
                        --loader "\\EFI\\Linux\\artix-${uki_kver}-signed.efi" \
                        --unicode "${uki_cmdline}" --verbose \
                        || log_warn "Failed to create signed UKI boot entry"
                    log_info "UKI signed for Secure Boot."
                else
                    log_warn "Signing keys not found at /mnt${sb_key} and /mnt${sb_cert}"
                fi
            fi
        else
            die "UKI generation failed — ${uki_file} was not created."
        fi
    fi

    log_info "Bootloader setup complete."
}