#!/usr/bin/env bash
set -Eeuo pipefail;

stage_preflight() {
    if stage_should_skip preflight; then
        return 0;
    fi;

    require_root;
    require_internet;

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "uefi" ]]; then
        modprobe fat 2>/dev/null || true
        modprobe vfat 2>/dev/null || true
        if ! grep -q 'vfat' /proc/filesystems 2>/dev/null; then
            log_warn "VFAT kernel module unavailable — attempting to install linux kernel modules..."
            pacman -Sy --noconfirm --needed linux 2>/dev/null || true
            modprobe vfat 2>/dev/null || true
            if ! grep -q 'vfat' /proc/filesystems 2>/dev/null; then
                die "VFAT kernel support is required for EFI partition. Your live ISO's kernel lacks VFAT support. Try a different ISO."
            fi
        fi
    fi

    pacman -Sy --noconfirm || log_warn "Failed to refresh package database."

    local pkgs=();
    local fs_type;
    fs_type="$(state_get FS_TYPE ext4)";

    command_exists sgdisk       || pkgs+=(gptfdisk);
    command_exists partprobe    || pkgs+=(parted);
    command_exists cryptsetup   || pkgs+=(cryptsetup);
    command_exists mount        || pkgs+=(util-linux);
    command_exists mkfs.fat     || pkgs+=(dosfstools);
    command_exists lsblk        || pkgs+=(util-linux);
    command_exists wipefs       || pkgs+=(util-linux);
    command_exists btrfs        || pkgs+=(btrfs-progs);

    [[ "$(state_get USE_LVM no)" == "yes" ]] && { command_exists pvcreate || pkgs+=(lvm2); }

    if [[ "$(state_get POWER_USER no)" == "yes" ]]; then
        for tool in bc flex bison openssl fakeroot; do
            command -v "${tool}" &>/dev/null || pkgs+=("${tool}")
        done
    fi

    if [[ "$(state_get KERNEL_CHOICE linux)" == "linux-bazzite-bin" ]]; then
        command -v fakeroot &>/dev/null || pkgs+=(fakeroot)
        command -v makepkg &>/dev/null || pkgs+=(base-devel)
    fi

    case "${fs_type}" in
        xfs)      command_exists mkfs.xfs || pkgs+=(xfsprogs) ;;
        f2fs)     command_exists mkfs.f2fs || pkgs+=(f2fs-tools) ;;
    esac

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        log_info "Installing required tools: ${pkgs[*]}"
        if ! pacman -S --noconfirm --needed "${pkgs[@]}"; then
            pacman -Sy --noconfirm || true
            if ! pacman -S --noconfirm --needed "${pkgs[@]}"; then
                log_error "Failed to install: ${pkgs[*]}"
                recoverable_error "Package installation failed. Check network and mirrorlist."
            fi
        fi
        log_info "Preflight dependencies installed.";
        for pkg in "${pkgs[@]}"; do
            local pkg_name="${pkg##*/}"
            pacman -Q "${pkg_name}" &>/dev/null || recoverable_error "Failed to install ${pkg}"
        done
    fi;

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        local parted_ver
        parted_ver=$(parted --version | head -1 | awk '{print $NF}')
        if [[ "${parted_ver}" > "3.4" ]]; then
            log_warn "parted ${parted_ver} may create partitions GRUB cannot read."
            if tui_yesno "Downgrade parted" "Downgrade parted to 3.4-2 for compatibility?"; then
                pacman -U --noconfirm "https://archive.artixlinux.org/packages/p/parted/parted-3.4-2-x86_64.pkg.tar.zst" || log_warn "Downgrade failed – continuing"
            fi
        fi
    fi

    check_disk_space 3 /mnt
    stage_mark_done preflight;
}