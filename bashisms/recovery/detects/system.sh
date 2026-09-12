#!/usr/bin/env bash
set -Eeuo pipefail

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        state_set ARTIX_BOOT_MODE "uefi"
    else
        state_set ARTIX_BOOT_MODE "bios"
    fi
}

detect_init() {
    if [[ -f "${ROOT}/usr/lib/systemd/systemd" ]] || [[ -f "${ROOT}/usr/bin/systemctl" ]]; then
        state_set INIT systemd
    elif [[ -x "${ROOT}/usr/bin/runit" ]]; then
        state_set INIT runit
    elif [[ -x "${ROOT}/usr/bin/dinit" ]]; then
        state_set INIT dinit
    elif [[ -x "${ROOT}/usr/bin/s6-rc" ]]; then
        state_set INIT s6
    elif [[ -x "${ROOT}/usr/bin/openrc" ]]; then
        state_set INIT openrc
    else
        state_set INIT openrc
    fi
}

detect_filesystem() {
    local fs
    fs="$(findmnt -no FSTYPE "${ROOT}" 2>/dev/null || true)"
    [[ -n "${fs}" ]] || fs='ext4'
    state_set FS_TYPE "${fs}"
}

detect_zfs() {
    if pacman_root_has zfs-utils || pacman_root_has zfs-dkms; then
        state_set FS_TYPE zfs
    fi
}

detect_lvm() {
    if [[ -f "${ROOT}/etc/lvm/lvm.conf" ]] || pacman_root_has lvm2; then
        state_set USE_LVM yes
    else
        state_set USE_LVM no
    fi
}

detect_bootloader() {
    if [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "bios" ]]; then
        state_set BOOTLOADER grub
        return 0
    fi

    if [[ -d "${ROOT}/boot/grub" ]] || [[ -f "${ROOT}/boot/grub/grub.cfg" ]]; then
        state_set BOOTLOADER grub
    elif [[ -d "${ROOT}/boot/EFI/refind" ]] || [[ -f "${ROOT}/boot/refind_linux.conf" ]]; then
        state_set BOOTLOADER refind
    elif [[ -f "${ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI" ]] || [[ -f "${ROOT}/boot/limine.conf" ]] || [[ -f "${ROOT}/boot/efi/limine.conf" ]]; then
        state_set BOOTLOADER limine
    else
        state_set BOOTLOADER efistub
    fi
}

detect_uki() {
    if [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "bios" ]]; then
        state_set GENERATE_UKI "no"
        return 0
    fi
    if [[ -f "${ROOT}/boot/efi/EFI/Artix/linux-custom.efi" ]] || \
       compgen -G "${ROOT}/boot/efi/EFI/Linux/"*.efi >/dev/null 2>&1 || \
       grep -qE 'default_uki|uki_output' "${ROOT}/etc/mkinitcpio.d/"*.preset 2>/dev/null; then
        state_set GENERATE_UKI yes
    else
        state_set GENERATE_UKI no
    fi
}

detect_kernel() {
    if [[ -f "${ROOT}/boot/vmlinuz-linux-custom" ]]; then
        state_set KERNEL_CHOICE linux-custom
        return 0
    fi

    local -a tier1=(
        linux-cachyos-bmq linux-cachyos-eevdf linux-cachyos-rt-bore
        linux-cachyos-hardened linux-cachyos-lts linux-cachyos-server
        linux-cachyos-deckify linux-cachyos-bore linux-cachyos
        linux-xanmod-x64v4 linux-xanmod-x64v3 linux-xanmod-x64v2 linux-xanmod
        linux-bazzite-bin
        linux-tkg linux-tkg-bore
    )

    for k in "${tier1[@]}"; do
        if pacman_root_has "${k}"; then
            state_set KERNEL_CHOICE "${k#linux-}"
            return 0
        fi
    done

    local -a tier2=(linux-zen linux-lts linux-hardened linux-libre linux)
    for k in "${tier2[@]}"; do
        if pacman_root_has "${k}"; then
            state_set KERNEL_CHOICE "${k#linux-}"
            return 0
        fi
    done

    if [[ -d "${ROOT}/opt/linux-tkg" ]]; then
        state_set KERNEL_CHOICE tkg
        return 0
    fi

    local kver
    kver=$(ls -1 "${ROOT}/boot/vmlinuz-"* 2>/dev/null | sort -V | head -n1 | sed 's/.*vmlinuz-//')
    case "${kver}" in
        *cachyos*)  state_set KERNEL_CHOICE linux-cachyos ;;
        *zen*)      state_set KERNEL_CHOICE linux-zen ;;
        *lts*)      state_set KERNEL_CHOICE linux-lts ;;
        *hardened*) state_set KERNEL_CHOICE linux-hardened ;;
        *)          state_set KERNEL_CHOICE linux ;;
    esac
}

detect_seat_manager() {
    if pacman_root_has seatd; then
        state_set SEAT_MANAGER seatd
    else
        state_set SEAT_MANAGER elogind
    fi

    local init seat_svc
    init="$(state_get INIT openrc)"
    local seat_mgr
    seat_mgr="$(state_get SEAT_MANAGER elogind)"
    
    case "${seat_mgr}" in
        seatd) seat_svc="seatd" ;;
        *)     seat_svc="logind" ;;
    esac

    local enabled=0
    case "${init}" in
        openrc) [[ -L "${ROOT}/etc/runlevels/default/${seat_svc}" ]] || [[ -L "${ROOT}/etc/runlevels/boot/${seat_svc}" ]] && enabled=1 ;;
        runit)  [[ -L "${ROOT}/etc/runit/runsvdir/default/${seat_svc}" ]] && enabled=1 ;;
        dinit)
            if [[ -L "${ROOT}/etc/dinit.d/boot.d/elogind" ]] || [[ -L "${ROOT}/etc/dinit.d/boot.d/logind" ]]; then
                enabled=1
            fi
            ;;
        s6)     [[ -d "${ROOT}/etc/s6/sv/${seat_svc}" ]] && enabled=1 ;;
    esac

    if [[ ${enabled} -eq 0 ]]; then
        local boot_issues
        boot_issues="$(state_get BOOT_ISSUES none)"
        if [[ "${boot_issues}" == "none" ]]; then
            boot_issues=""
        fi
        boot_issues+="seat-manager-disabled "
        state_set BOOT_ISSUES "${boot_issues}"
        state_set SEAT_MANAGER_DISABLED "yes"
    else
        state_set SEAT_MANAGER_DISABLED "no"
    fi
}