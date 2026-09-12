#!/usr/bin/env bash
set -Eeuo pipefail

detect_install_stage() {
    local status=""
    [[ -f "${ROOT}/etc/fstab" ]] && status+="fstab "
    [[ -x "${ROOT}/usr/bin/bash" ]] && status+="basestrap "
    [[ -f "${ROOT}/boot/grub/grub.cfg" ]] && status+="grub "
    [[ -f "${ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI" ]] && status+="limine "
    [[ -f "${ROOT}/boot/refind_linux.conf" ]] && status+="refind "
    [[ -f "${ROOT}/boot/efi/EFI/Artix/linux-custom.efi" ]] && status+="uki "
    [[ -d "${ROOT}/home" ]] && status+="home "
    [[ -f "${ROOT}/etc/hostname" ]] && status+="hostname "
    [[ -f "${ROOT}/etc/locale.conf" ]] && status+="locale "
    [[ -f "${ROOT}/root/.artix-post-complete" ]] && status+="post-complete "
    if pacman_root_has xfce4 || pacman_root_has plasma-desktop || pacman_root_has hyprland; then
        status+="desktop "
    fi
    [[ -z "${status}" ]] && status="minimal (base system only)"
    state_set RECOVERY_STATUS "${status}"
}

detect_fstab_health() {
    if [[ -f "${ROOT}/etc/fstab" ]]; then
        local issues=""
        while IFS= read -r line; do
            [[ -z "${line}" || "${line}" == \#* ]] && continue
            local device
            device=$(echo "${line}" | awk '{print $1}')
            if [[ "${device}" == UUID=* ]]; then
                local uuid="${device#UUID=}"
                if ! blkid -U "${uuid}" &>/dev/null; then
                    issues+="missing-uuid:${uuid} "
                fi
            fi
        done < "${ROOT}/etc/fstab"
        state_set FSTAB_ISSUES "${issues:-none}"
    else
        state_set FSTAB_ISSUES "missing"
    fi
}

detect_boot_health() {
    local issues=""
    if [[ -d "${ROOT}/boot" ]]; then
        if ! ls "${ROOT}/boot/vmlinuz-"* &>/dev/null; then
            issues+="no-kernel "
        fi
        if ! ls "${ROOT}/boot/initramfs-"*.img &>/dev/null; then
            issues+="no-initramfs "
        fi
    else
        issues+="no-boot-dir "
    fi

    if [[ ! -e "${ROOT}/sbin/init" ]]; then
        issues+="no-init "
    fi

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        if [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "bios" ]]; then
            state_set GENERATE_UKI "no"
        elif ! compgen -G "${ROOT}/boot/efi/EFI/Linux/artix-*.efi" >/dev/null 2>&1 && \
             ! [[ -f "${ROOT}/boot/efi/EFI/Artix/linux-custom.efi" ]]; then
            log_info "UKI enabled but no UKI file found — system will boot via bootloader"
        fi
    fi

    if [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "uefi" ]]; then
        if command -v efibootmgr &>/dev/null; then
            if ! efibootmgr 2>/dev/null | grep -qi 'Artix'; then
                issues+="no-efi-entry "
            fi
        fi
    fi

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local cmdline_missing=0
        local bootloader
        bootloader=$(state_get BOOTLOADER grub)

        case "${bootloader}" in
            grub)
                if [[ -f "${ROOT}/boot/grub/grub.cfg" ]]; then
                    grep -q 'cryptdevice=' "${ROOT}/boot/grub/grub.cfg" || cmdline_missing=1
                else
                    cmdline_missing=1
                fi
                ;;
            limine)
                local limine_conf
                limine_conf="${ROOT}/boot/efi/limine.conf"
                [[ -f "${ROOT}/boot/limine.conf" ]] && limine_conf="${ROOT}/boot/limine.conf"
                if [[ -f "${limine_conf}" ]]; then
                    grep -q 'cryptdevice=' "${limine_conf}" || cmdline_missing=1
                else
                    cmdline_missing=1
                fi
                ;;
            refind)
                if [[ -f "${ROOT}/boot/refind_linux.conf" ]]; then
                    grep -q 'cryptdevice=' "${ROOT}/boot/refind_linux.conf" || cmdline_missing=1
                else
                    cmdline_missing=1
                fi
                ;;
            efistub)
                ;;
        esac

        if [[ ${cmdline_missing} -eq 1 ]]; then
            issues+="missing-cryptdevice "
        fi

        if [[ -f "${ROOT}/etc/mkinitcpio.conf" ]]; then
            grep -q 'encrypt' "${ROOT}/etc/mkinitcpio.conf" || issues+="missing-encrypt-hook "
        fi
    fi

    state_set BOOT_ISSUES "${issues:-none}"
}

detect_pacman_health() {
    local issues=""
    if [[ -f "${ROOT}/var/lib/pacman/db.lck" ]]; then
        issues+="stale-lock "
    fi
    if ! pacman --root "${ROOT}" -Q base &>/dev/null 2>&1; then
        issues+="base-missing "
    fi
    local broken
    broken=$(pacman --root "${ROOT}" -Qk 2>/dev/null | grep ': missing' | cut -d: -f1 | sort -u | tr '\n' ' ') || true
    if [[ -n "${broken}" ]]; then
        local count
        count=$(echo "${broken}" | wc -w)
        issues+="broken-pkgs:${count} "
        state_set BROKEN_PACKAGES "${broken}"
    else
        state_set BROKEN_PACKAGES ""
    fi
    state_set PACMAN_ISSUES "${issues:-none}"
}

detect_init_actual() {
    if [[ -x "${ROOT}/usr/bin/runit" ]]; then echo "runit"
    elif [[ -x "${ROOT}/usr/bin/dinit" ]]; then echo "dinit"
    elif [[ -x "${ROOT}/usr/bin/s6-rc" ]]; then echo "s6"
    elif [[ -x "${ROOT}/usr/bin/openrc" ]]; then echo "openrc"
    else echo "unknown"
    fi
}

detect_migration_health() {
    local issues=""
    local found_inits=()
    
    [[ -d "${ROOT}/etc/runit" ]] && found_inits+=("runit")
    [[ -d "${ROOT}/etc/dinit.d" ]] && found_inits+=("dinit")
    [[ -d "${ROOT}/etc/s6" ]] && found_inits+=("s6")
    [[ -d "${ROOT}/etc/init.d" ]] && found_inits+=("openrc")
    
    if [[ ${#found_inits[@]} -gt 1 ]]; then
        issues+="multiple-inits:${found_inits[*]} "
    fi
    
    local current_init expected_init
    current_init="$(state_get INIT openrc)"
    expected_init="$(detect_init_actual)"
    if [[ "${current_init}" != "${expected_init}" && "${expected_init}" != "unknown" ]]; then
        issues+="init-mismatch:state=${current_init},system=${expected_init} "
    fi
    
    if [[ -d "${ROOT}/etc/dinit.d/boot.d" ]] && [[ ! -f "${ROOT}/usr/bin/dinit" ]]; then
        issues+="dinit-services-no-binary "
    fi
    
    if [[ -d "${ROOT}/etc/runit/runsvdir/default" ]]; then
        local orphan
        orphan=$(find "${ROOT}/etc/runit/runsvdir/default" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
        [[ ${orphan} -gt 0 ]] && issues+="runit-orphaned-symlinks:${orphan} "
    fi
    
    state_set MIGRATION_ISSUES "${issues:-none}"
}

detect_iso_health() {
    local issues=""

    if [[ ! -f /root/ArtixForge/install && ! -f /run/artix/sfs/rootfs ]]; then
        state_set ISO_ISSUES "none"
        return 0
    fi
    
    if ! command -v pacman &>/dev/null; then
        issues+="no-pacman "
    else
        if [[ ! -d "${ROOT}/var/lib/pacman/local" ]] || \
           ! pacman --root "${ROOT}" -Q base &>/dev/null 2>&1; then
            issues+="pacman-db-broken "
        fi
    fi
    
    if [[ ! -f /root/ArtixForge/install ]]; then
        issues+="missing-artixforge "
    fi
    
    if ! pacman --root "${ROOT}" -Qk base 2>/dev/null | grep -q '0 missing'; then
        issues+="base-incomplete "
    fi
    
    if ! compgen -G "${ROOT}/boot/vmlinuz-*" >/dev/null 2>&1; then
        issues+="no-kernel-iso "
    fi
    
    state_set ISO_ISSUES "${issues:-none}"
}