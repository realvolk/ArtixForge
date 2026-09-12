#!/usr/bin/env bash
set -Eeuo pipefail

repair_fstab() {
    local issues
    issues=$(state_get FSTAB_ISSUES none)
    if [[ "${issues}" == "missing" ]]; then
        log_warn "fstab is missing. Regenerating..."
        if tui_yesno "Repair fstab" "Regenerate fstab from current mounts?"; then
            fstabgen -U /mnt > /mnt/etc/fstab
            log_info "fstab regenerated."
        fi
    elif [[ "${issues}" != "none" ]]; then
        log_warn "fstab has stale UUIDs: ${issues}"
        if tui_yesno "Repair fstab" "Regenerate fstab to fix UUIDs?"; then
            fstabgen -U /mnt > /mnt/etc/fstab
            log_info "fstab regenerated."
        fi
    fi
}

_kernel_pkg() {
    local choice="${1:-linux}"
    case "${choice}" in
        linux)                echo "linux linux-headers" ;;
        linux-zen)            echo "linux-zen linux-zen-headers" ;;
        linux-lts)            echo "linux-lts linux-lts-headers" ;;
        linux-hardened)       echo "linux-hardened linux-hardened-headers" ;;
        linux-libre)          echo "linux-libre linux-libre-headers" ;;
        linux-cachyos-bore)   echo "linux-cachyos-bore linux-cachyos-bore-headers" ;;
        linux-bazzite-bin)    echo "linux-bazzite-bin linux-bazzite-bin-headers" ;;
        xanmod)               echo "linux-xanmod linux-xanmod-headers" ;;
        tkg)                  echo "" ;;
        linux-custom)         echo "" ;;
        *)                    echo "linux linux-headers" ;;
    esac
}

repair_boot() {
    local issues=$(state_get BOOT_ISSUES none)
    if [[ "${issues}" =~ no-kernel ]]; then
        if tui_yesno "Reinstall kernel" "Reinstall kernel?"; then
            local kpkg=$(_kernel_pkg "$(state_get KERNEL_CHOICE)")
            [[ -n "${kpkg}" ]] && pkg_install ${kpkg}
        fi
    fi
    if [[ "${issues}" =~ no-initramfs ]]; then
        if tui_yesno "Regenerate initramfs" "Run mkinitcpio?"; then
            artix-chroot "${ROOT}" mkinitcpio -P
        fi
    fi
    if [[ "${issues}" =~ no-init ]]; then
        log_warn "/sbin/init missing."
        local init=$(detect_init 2>/dev/null || state_get INIT openrc)
        if tui_yesno "Repair init" "Create /sbin/init symlink to ${init}?"; then
            artix-chroot "${ROOT}" ln -sf "/usr/bin/${init}" /sbin/init
            log_info "Init symlink created."
        fi
    fi
    if [[ "${issues}" =~ no-efi-entry ]] && [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "uefi" ]]; then
        if tui_yesno "Reinstall bootloader" "Reinstall $(state_get BOOTLOADER)?"; then
            configure_bootloader
        fi
    fi
    if [[ "${issues}" =~ no-uki ]] && [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "uefi" ]]; then
        repair_uki
    fi
    if [[ "${issues}" =~ missing-cryptdevice ]]; then
        if tui_yesno "Repair cmdline" "Regenerate bootloader config?"; then
            configure_bootloader
        fi
    fi
    if [[ "${issues}" =~ missing-encrypt-hook ]]; then
        if tui_yesno "Repair hooks" "Add encrypt hook?"; then
            artix-chroot "${ROOT}" sed -i '/^HOOKS=/s/\(block\)/\1 encrypt/' /etc/mkinitcpio.conf
            artix-chroot "${ROOT}" mkinitcpio -P
        fi
    fi

    repair_seat_manager
}

repair_uki() {
    if [[ "$(state_get GENERATE_UKI no)" != "yes" ]]; then
        return 0
    fi

    local uki_dir="/mnt/boot/efi/EFI/Linux"
    local uki_file=""

    if [[ -d "${uki_dir}" ]]; then
        uki_file=$(compgen -G "${uki_dir}/artix-*.efi" 2>/dev/null | head -n1)
    fi

    if [[ -z "${uki_file}" ]]; then
        log_warn "UKI is enabled but no UKI file found."
        if tui_yesno "Repair UKI" "Regenerate UKI and EFI boot entry?"; then
            if ! artix-chroot /mnt command -v ukify &>/dev/null; then
                log_warn "ukify not found — install eukify package first"
                return 1
            fi
            source "${SCRIPT_DIR}/install/bootloader.sh"
            configure_bootloader
        fi
    else
        log_info "UKI found: ${uki_file}"
    fi
}

repair_kernel() {
    log_info "Checking custom kernel health..."
    if [[ ! -f /mnt/boot/vmlinuz-linux-custom ]]; then
        log_warn "Custom kernel not found – nothing to repair."
        return 0
    fi

    if ! tui_yesno "Repair Custom Kernel" "Rebuild the custom kernel with the latest recipe?"; then
        return 0
    fi

    POWERUSER_DIR="${BASE_DIR}/bashisms/poweruser"

    if [[ ! -f "${POWERUSER_DIR}/recipes/linux.sh" ]]; then
        log_info "Fetching kernel recipe from community repository..."
        local list_url="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main/.LIST"
        local repo_base="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main"
        curl -fsSL "${list_url}" -o /tmp/artix-recipes.list 2>/dev/null
        local section
        section=$(awk -F'|' -v pkg="linux" '$1 == pkg {print $2}' /tmp/artix-recipes.list 2>/dev/null)
        if [[ -n "${section}" ]]; then
            curl -sL "${repo_base}/${section}/linux.sh" -o "${POWERUSER_DIR}/recipes/linux.sh"
        fi
        rm -f /tmp/artix-recipes.list
    fi

    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"

    local profile_name
    if [[ -f /mnt/usr/share/artix-poweruser/profile/active ]]; then
        profile_name=$(tr -d '[:space:]' < /mnt/usr/share/artix-poweruser/profile/active)
    else
        profile_name="default"
    fi

    export POWERUSER_PROFILE="${profile_name}"
    load_profile "${profile_name}"

    load_recipe linux
    build_package linux

    if [[ -f /mnt/boot/vmlinuz-linux-custom ]]; then
        log_info "Custom kernel rebuilt successfully."
        artix-chroot /mnt mkinitcpio -P 2>/dev/null || log_warn "mkinitcpio failed"
        if [[ -d /mnt/boot/grub ]]; then
            artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warn "grub-mkconfig failed"
        fi
    else
        log_error "Kernel rebuild may have failed – check logs."
    fi
}

repair_seat_manager() {
    local detected seat_pkg service_name
    detected="$(state_get SEAT_MANAGER elogind)"
    
    if [[ "${detected}" == "seatd" ]]; then
        seat_pkg="seatd"
        service_name="seatd"
    else
        seat_pkg="elogind"
        service_name="logind"
    fi
    
    if ! pacman_root_has "${seat_pkg}"; then
        log_warn "${seat_pkg} is not installed — desktop sessions will fail."
        if tui_yesno "Repair Seat Manager" "Install ${seat_pkg} and enable the service?"; then
            artix-chroot /mnt pacman -S --noconfirm "${seat_pkg}" || {
                log_error "Failed to install ${seat_pkg}"
                return 1
            }
            enable_service "${service_name}"
            log_info "${seat_pkg} installed and enabled."
        fi
        return 0
    fi
    
    if ! service_exists "${service_name}"; then
        log_warn "${service_name} service not found for init: $(state_get INIT openrc)"
        return 0
    fi
    
    local init
    init="$(state_get INIT openrc)"
    local service_ok=0
    
    case "${init}" in
        openrc) [[ -L /mnt/etc/runlevels/default/${service_name} ]] || [[ -L /mnt/etc/runlevels/boot/${service_name} ]] && service_ok=1 ;;
        runit)  [[ -L /mnt/etc/runit/runsvdir/default/${service_name} ]] && service_ok=1 ;;
        dinit)  [[ -L /mnt/etc/dinit.d/boot.d/elogind ]] || [[ -L /mnt/etc/dinit.d/boot.d/logind ]] && service_ok=1 ;;
        s6)     [[ -d /mnt/etc/s6/sv/${service_name} ]] && service_ok=1 ;;
    esac
    
    if [[ ${service_ok} -eq 0 ]]; then
        log_warn "${service_name} service is not enabled — desktop sessions will fail."
        if tui_yesno "Enable Service" "Enable ${service_name} service for ${init}?"; then
            enable_service "${service_name}"
            log_info "${service_name} enabled."
        fi
    fi
}