#!/usr/bin/env bash
set -Eeuo pipefail

prepare_handoff() {
    local script_dir kernel_choice kernel_image initramfs_image microcode_image
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    kernel_choice="$(state_get KERNEL_CHOICE linux)"

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        log_info "BIOS mode – skipping UKI and EFI detection"
        state_set GENERATE_UKI "no"
    fi

    log_info "Detecting boot artifacts..."
    case "${kernel_choice}" in
        linux)               kernel_image='/mnt/boot/vmlinuz-linux' ; initramfs_image='/mnt/boot/initramfs-linux.img' ;;
        linux-zen)           kernel_image='/mnt/boot/vmlinuz-linux-zen' ; initramfs_image='/mnt/boot/initramfs-linux-zen.img' ;;
        linux-lts)           kernel_image='/mnt/boot/vmlinuz-linux-lts' ; initramfs_image='/mnt/boot/initramfs-linux-lts.img' ;;
        linux-hardened)     kernel_image='/mnt/boot/vmlinuz-linux-hardened' ; initramfs_image='/mnt/boot/initramfs-linux-hardened.img' ;;
        linux-libre)        kernel_image='/mnt/boot/vmlinuz-linux-libre' ; initramfs_image='/mnt/boot/initramfs-linux-libre.img' ;;
        linux-cachyos*)
            mapfile -t k < <(find /mnt/boot -maxdepth 1 -type f -name 'vmlinuz-linux-cachyos*' 2>/dev/null | sort)
            mapfile -t i < <(find /mnt/boot -maxdepth 1 -type f -name 'initramfs-linux-cachyos*.img' ! -name '*fallback*' 2>/dev/null | sort)
            [[ ${#k[@]} -gt 0 ]] && kernel_image="${k[0]}"
            [[ ${#i[@]} -gt 0 ]] && initramfs_image="${i[0]}"
            ;;
        linux-bazzite-bin)  kernel_image='/mnt/boot/vmlinuz-linux-bazzite-bin' ; initramfs_image='/mnt/boot/initramfs-linux-bazzite-bin.img' ;;
        xanmod)
            mapfile -t k < <(find /mnt/boot -maxdepth 1 -type f -name 'vmlinuz-linux-xanmod*' 2>/dev/null | sort)
            mapfile -t i < <(find /mnt/boot -maxdepth 1 -type f -name 'initramfs-linux-xanmod*.img' ! -name '*fallback*' 2>/dev/null | sort)
            [[ ${#k[@]} -gt 0 ]] && kernel_image="${k[0]}"
            [[ ${#i[@]} -gt 0 ]] && initramfs_image="${i[0]}"
            ;;
        linux-custom)
            mapfile -t k < <(find /mnt/boot -maxdepth 1 -type f -name 'vmlinuz-linux-custom*' 2>/dev/null | sort)
            mapfile -t i < <(find /mnt/boot -maxdepth 1 -type f -name 'initramfs-linux-custom*.img' ! -name '*fallback*' 2>/dev/null | sort)
            [[ ${#k[@]} -gt 0 ]] && kernel_image="${k[0]}"
            [[ ${#i[@]} -gt 0 ]] && initramfs_image="${i[0]}"
            ;;
        *)
            mapfile -t k < <(find /mnt/boot -maxdepth 1 -type f -name 'vmlinuz-*' 2>/dev/null | sort)
            mapfile -t i < <(find /mnt/boot -maxdepth 1 -type f -name 'initramfs-*.img' ! -name '*fallback*' 2>/dev/null | sort)
            [[ ${#k[@]} -gt 0 ]] && kernel_image="${k[0]}"
            [[ ${#i[@]} -gt 0 ]] && initramfs_image="${i[0]}"
            ;;
    esac

    [[ -f "${kernel_image}" ]] || kernel_image=''
    [[ -f "${initramfs_image}" ]] || initramfs_image=''

    microcode_image=''
    if [[ -f /mnt/boot/intel-ucode.img ]]; then microcode_image='intel-ucode.img'
    elif [[ -f /mnt/boot/amd-ucode.img ]]; then microcode_image='amd-ucode.img'
    fi

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        local uki_found
        uki_found=$(find /mnt/boot/efi/EFI/Artix -maxdepth 1 -type f -name '*.efi' 2>/dev/null | head -n1)
        if [[ -n "${uki_found}" ]]; then
            kernel_image="${uki_found}"
            initramfs_image=''
        fi
    fi

    [[ -n "${kernel_image}" ]]     && state_set KERNEL_IMAGE "$(basename "${kernel_image}")"
    [[ -n "${initramfs_image}" ]]  && state_set INITRAMFS_IMAGE "$(basename "${initramfs_image}")"
    [[ -n "${microcode_image}" ]]  && state_set MICROCODE_IMAGE "${microcode_image}"

    log_info "Writing installer configuration..."
    install -Dm600 /dev/null /mnt/etc/artix-installer.conf
    log_info "Writing installer configuration..."
    install -Dm600 /dev/null /mnt/etc/artix-installer.conf
    {
        for key in "${STATE_KEYS_CHROOT[@]}"; do
            printf '%s="%s"\n' "${key}" "$(state_get "${key}" "${STATE_DEFAULTS[$key]:-}")"
        done
        for ((i=1; i<=$(state_get USER_COUNT 1); i++)); do
            printf 'USER_%d_NAME="%s"\n'   "$i" "$(state_get "USER_${i}_NAME" "")"
            printf 'USER_%d_SHELL="%s"\n'  "$i" "$(state_get "USER_${i}_SHELL" "/bin/bash")"
            printf 'USER_%d_GROUPS="%s"\n' "$i" "$(state_get "USER_${i}_GROUPS" "")"
            printf 'USER_%d_SUDO="%s"\n'   "$i" "$(state_get "USER_${i}_SUDO" "yes")"
            printf 'USER_%d_DE="%s"\n'     "$i" "$(state_get "USER_${i}_DE" "")"
            printf 'USER_%d_DOTFILES="%s"\n' "$i" "$(state_get "USER_${i}_DOTFILES" "")"
        done
    } > /mnt/etc/artix-installer.conf
    chmod 600 /mnt/etc/artix-installer.conf

    cat > /mnt/etc/anvil-theme.conf <<EOF
GUM_TITLE_COLOR="$(state_get GUM_TITLE_COLOR 212)"
GUM_ACCENT_COLOR="$(state_get GUM_ACCENT_COLOR 34)"
EOF

    if [[ "$(state_get QUICK_INSTALL no)" == "yes" ]]; then
        log_info "Saving reusable quick profile..."
        {
            for key in "${STATE_KEYS_PROFILE[@]}"; do
                printf '%s="%s"\n' "${key}" "$(state_get "${key}" "${STATE_DEFAULTS[$key]:-}")"
            done
        } > /mnt/etc/artixforge-profile.conf
        chmod 644 /mnt/etc/artixforge-profile.conf
    fi

    log_info "Copying post-install modules..."
    install -d /mnt/usr/local/lib/artix-installer
    cp -r "${script_dir}/../post/." /mnt/usr/local/lib/artix-installer/post
    cp "${script_dir}/services.sh" /mnt/usr/local/lib/artix-installer/services.sh

    log_info "Handoff preparation complete."
}