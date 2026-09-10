#!/usr/bin/env bash
set -Eeuo pipefail

ATA_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ATA_DIR}/../.." && pwd)}"

source "${BASE_DIR}/scripts/common.sh" 2>/dev/null || true
source "${BASE_DIR}/scripts/state.sh" 2>/dev/null || true
source "${BASE_DIR}/scripts/recovery/detect.sh" 2>/dev/null || true
source "${BASE_DIR}/scripts/recovery/core.sh" 2>/dev/null || true

source "${BASE_DIR}/migrations/inits/common.sh" 2>/dev/null || true
source "${BASE_DIR}/migrations/des/common.sh" 2>/dev/null || true

source "${ATA_DIR}/ata-detect.sh"
source "${ATA_DIR}/ata-backup.sh"
source "${ATA_DIR}/ata-map.sh"
source "${ATA_DIR}/ata-convert.sh"
source "${ATA_DIR}/ata-restore.sh"

readonly MIGRATION_STAGE_FILE="/tmp/artix-installer/migration-stage.conf"

ata_migrate_main() {
    if [[ -d /run/artix/sfs/rootfs ]]; then
        tui_msg "Cannot Run from Live ISO" \
            "Arch → Artix migration must be run from the booted Arch system.\n\nBoot into your Arch installation and run ArtixForge from there."
        return 0
    fi

    if ! grep -q '^ID=arch' /etc/os-release 2>/dev/null; then
        tui_msg "Not Arch Linux" "This system doesn't appear to be Arch Linux."
        return 0
    fi

    if [[ ! -f /etc/resolv.conf || -L /etc/resolv.conf || ! -s /etc/resolv.conf ]]; then
        systemctl stop systemd-resolved 2>/dev/null || true
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf.tmp
        mv -f /etc/resolv.conf.tmp /etc/resolv.conf
        log_info "DNS resolver created (was missing or broken)"
    fi

    if ! ping -c 1 -W 3 1.1.1.1 &>/dev/null && ! curl -s --max-time 5 https://1.1.1.1 &>/dev/null; then
        tui_msg "No Network" "Internet connection required for migration.\n\nFix your network and retry."
        return 0
    fi

    local target_init aur_helper backup_dir has_homed de
    target_init="$(state_get INIT '')"
    aur_helper="$(state_get ATA_AUR_HELPER '')"
    backup_dir="$(state_get MIGRATION_BACKUP_DIR '')"
    has_homed="$(state_get ATA_HAS_HOMED 0)"
    de="$(state_get WM_DE none)"

    local resolv_backup=""
    if [[ -f /etc/resolv.conf ]]; then
        resolv_backup="$(cat /etc/resolv.conf)"
    fi
    export resolv_backup

    local migration_stage="init"
    if [[ -f "${MIGRATION_STAGE_FILE}" ]]; then
        migration_stage=$(cat "${MIGRATION_STAGE_FILE}")
        tui_msg "Failed Migration Detected" \
            "A previous ATA migration was interrupted at stage: ${migration_stage}.\n\nYou can resume or start fresh."
        if tui_yesno "Resume Migration?" "Resume the interrupted migration?"; then
            log_info "Resuming ATA migration from stage: ${migration_stage}"
            state_load
            target_init="$(state_get INIT '')"
            aur_helper="$(state_get ATA_AUR_HELPER '')"
            backup_dir="$(state_get MIGRATION_BACKUP_DIR '')"
            has_homed="$(state_get ATA_HAS_HOMED 0)"
            de="$(state_get WM_DE none)"
        else
            log_info "Starting fresh – removing partial state..."
            remove_systemd 2>/dev/null || true
            [[ -n "${backup_dir}" && -d "${backup_dir}" ]] && rm -rf "${backup_dir}"
            rm -f "${MIGRATION_STAGE_FILE}"
            migration_stage="init"
            backup_dir=""
            target_init=""
            aur_helper=""
            de="none"
            has_homed=0
        fi
    fi

    if [[ "${migration_stage}" != "init" && -z "${target_init}" ]]; then
        target_init="$(state_get INIT '')"
        if [[ -z "${target_init}" ]]; then
            die "No init system was selected. The migration cannot continue."
        fi
    fi

    if [[ "${migration_stage}" == "init" ]]; then
        tui_msg "Arch → Artix Migration" \
"This will convert your Arch Linux system to Artix.

WHAT CAN BE MIGRATED AUTOMATICALLY:
  Packages (with version mismatch warnings)
  Desktop environment and display manager
  User files and home directories
  System configs (/etc/fstab, /etc/hostname, locale)
  Enabled system services → init equivalents
  WiFi passwords and network configs
  SSH keys and host configs
  Firewall rules and cron jobs
  Pacman hooks (systemd-dependent ones disabled)
  PAM modules (pam_systemd → pam_elogind)
  mkinitcpio hooks (systemd → udev/encrypt)
  systemd timers → cron (OnCalendar + basic monotonic)
  crypttab → kernel parameters
  DNS resolver fix
  systemd-boot → GRUB (auto-install)
  Flatpaks (remotes + apps preserved)
  DKMS modules (auto-rebuild)
  systemd-homed users (with password unlock)
  systemd --user services → autostart
  AUR packages (attempt batch reinstall)

WHAT WILL BE BACKED UP:
  All of /home (excluding caches)
  /etc, /boot, /usr/local
  Pacman database
  System journal (text export)
  Everything to /arch-migration-backup-YYYYMMDD-HHMMSS"

        if ! tui_yesno "Begin Migration" "This is destructive. Proceed?"; then
            return 0
        fi

        ata_detect_all

        target_init=$(tui_menu "Choose Init System" "Select your new init:" \
            "openrc" "runit" "dinit" "s6") || return 0
        state_set INIT "${target_init}"

        local use_arch_repos="yes"
        tui_yesno "Arch Repositories" "Keep access to Arch repositories for AUR helpers?" || use_arch_repos="no"
        state_set ENABLE_ARCH_REPOS "${use_arch_repos}"

        aur_helper=""
        if [[ -s /tmp/ata-aur.txt ]]; then
            local aur_count
            aur_count=$(wc -l < /tmp/ata-aur.txt)
            if tui_yesno "AUR Packages" "${aur_count} AUR packages detected.\n\nAttempt to reinstall them automatically after migration?"; then
                aur_helper=$(tui_menu "AUR Helper" "Select AUR helper:" "paru" "yay" "Skip") || aur_helper=""
                [[ "${aur_helper}" == "Skip" ]] && aur_helper=""
            fi
        fi
        state_set ATA_AUR_HELPER "${aur_helper}"

        has_homed=0
        if [[ -s /tmp/ata-homed.txt ]]; then
            has_homed=1
            tui_msg "systemd-homed Detected" "Users with systemd-homed were found.\n\nTheir home directories will be unlocked and migrated to standard /home if you provide their passwords."
        fi
        state_set ATA_HAS_HOMED "${has_homed}"

        de=$(state_get WM_DE none)
        local aur_count flatpak_count snap_count
        aur_count=$(wc -l < /tmp/ata-aur.txt 2>/dev/null || echo 0)
        flatpak_count=$(wc -l < /tmp/ata-flatpak.txt 2>/dev/null || echo 0)
        snap_count=$(wc -l < /tmp/ata-snap.txt 2>/dev/null || echo 0)

        local summary=""
        summary+="Desktop: ${de}"$'\n'
        summary+="AUR packages: ${aur_count}"$'\n'
        summary+="Flatpaks: ${flatpak_count}"$'\n'
        summary+="Snaps: ${snap_count}"$'\n'
        summary+="Target init: ${target_init}"$'\n'
        summary+="Arch repos: ${use_arch_repos}"$'\n'
        [[ -n "${aur_helper}" ]] && summary+="AUR helper: ${aur_helper}"$'\n'
        tui_msg "Migration Summary" "${summary}"

        if ! tui_yesno "Final Confirmation" "This is the point of no return.\n\nAll changes are backed up.\n\nProceed with migration?"; then
            log_info "Migration cancelled."
            return 0
        fi

        state_save
        echo "backup" > "${MIGRATION_STAGE_FILE}"
        migration_stage="backup"
    fi

    if [[ "${migration_stage}" == "backup" ]]; then
        backup_dir="/arch-migration-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "${backup_dir}"
        chmod 700 "${backup_dir}"
        state_set MIGRATION_BACKUP_DIR "${backup_dir}"
        ata_backup_all "${backup_dir}"
        echo "convert" > "${MIGRATION_STAGE_FILE}"
        migration_stage="convert"
    fi

    if [[ "${migration_stage}" == "convert" ]]; then
        ata_convert_all
        [[ ${has_homed} -eq 1 ]] && ata_migrate_homed_users "${backup_dir}"

        if [[ ! -f /etc/resolv.conf || -L /etc/resolv.conf ]]; then
            if [[ -n "${resolv_backup}" ]]; then
                printf '%s\n' "${resolv_backup}" > /etc/resolv.conf
            else
                printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
            fi
            log_info "DNS resolver restored for package downloads"
        fi

        echo "repos" > "${MIGRATION_STAGE_FILE}"
        migration_stage="repos"
    fi

    if [[ "${migration_stage}" == "repos" ]]; then
        if [[ ! -s /etc/resolv.conf ]]; then
            printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
            log_info "DNS resolver created (was empty)"
        fi

        log_info "Pre-downloading Artix base packages..."
        cache_artix_packages "${target_init}"

        prepare_artix_repos
        clean_pacman_cache
        install_artix_keyring

        _chroot pacman-key --init 2>/dev/null || true
        if ! _chroot pacman-key --populate artix 2>/dev/null; then
            log_warn "Key population failed — retrying with SigLevel = Never"
            sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
            _pacman -S --noconfirm artix-keyring
            _chroot pacman-key --init
            _chroot pacman-key --populate artix
            sed -i 's/^SigLevel = Never/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
            log_info "Keyring forcibly reinstalled and populated"
        fi

        if [[ "$(state_get ENABLE_ARCH_REPOS yes)" == "yes" ]]; then
            _pacman -S --noconfirm --needed archlinux-keyring 2>/dev/null || true
            _chroot pacman-key --populate archlinux 2>/dev/null || true
            log_info "Arch Linux keyring preserved and populated"
        fi

        ata_build_package_map
        ata_show_migration_list

        remove_systemd
        echo "install" > "${MIGRATION_STAGE_FILE}"
        migration_stage="install"
    fi

    if [[ "${migration_stage}" == "install" ]]; then
        if [[ ! -s /etc/resolv.conf ]]; then
            printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
            log_info "DNS resolver created for install stage"
        fi

        log_info "Clearing pacman cache to avoid corrupted downloads..."
        rm -rf /var/cache/pacman/pkg/* 2>/dev/null || true
        rm -rf /var/lib/pacman/sync/* 2>/dev/null || true
        rm -f /var/cache/pacman/pkg/mkinitcpio-*.pkg.tar.zst 2>/dev/null || true

        retry_command "base system install" \
            _pacman -S --noconfirm base base-devel grub linux linux-headers mkinitcpio rsync artix-branding-base

        if [[ ! -f /boot/vmlinuz-linux ]]; then
            log_warn "Kernel missing after base install — forcing reinstall"
            _pacman -S --noconfirm linux linux-headers
        fi

        retry_command "target init install" \
            install_target_init "systemd" "${target_init}"

        retry_command "full package replacement" \
            reinstall_artix_packages

        log_info "Replacing systemd-linked base packages..."
        _pacman -Rdd --noconfirm systemd-libs 2>/dev/null || true
        _pacman -S --noconfirm --needed util-linux e2fsprogs coreutils findutils grep sed gawk

        _pacman -S --noconfirm --needed artix-keyring 2>/dev/null || true
        _chroot pacman-key --init 2>/dev/null || true
        _chroot pacman-key --populate artix 2>/dev/null || true

        if [[ "$(state_get ENABLE_ARCH_REPOS yes)" == "yes" ]]; then
            _pacman -S --noconfirm --needed archlinux-keyring 2>/dev/null || true
            _chroot pacman-key --populate archlinux 2>/dev/null || true
        fi
        log_info "Keyrings reinstalled and populated"

        local -a critical_pkgs=( base linux linux-headers mkinitcpio grub util-linux e2fsprogs coreutils findutils pacman dbus )
        case "${target_init}" in
            openrc) critical_pkgs+=( openrc elogind-openrc ) ;;
            runit)  critical_pkgs+=( runit elogind-runit ) ;;
            dinit)  critical_pkgs+=( dinit elogind-dinit ) ;;
            s6)     critical_pkgs+=( s6 elogind-s6 ) ;;
        esac
        
        local net_stack
        net_stack="$(state_get NETWORK_STACK networkmanager)"
        case "${net_stack}" in
            networkmanager) critical_pkgs+=( networkmanager "networkmanager-${target_init}" ) ;;
            dhcpcd+iwd)     critical_pkgs+=( dhcpcd iwd "dhcpcd-${target_init}" "iwd-${target_init}" ) ;;
            connman)        critical_pkgs+=( connman "connman-${target_init}" ) ;;
        esac

        for pkg in "${critical_pkgs[@]}"; do
            if ! _pacman -Q "${pkg}" &>/dev/null; then
                log_warn "${pkg} missing — installing"
                _pacman -S --noconfirm --needed "${pkg}" || log_error "Failed to install ${pkg}"
            fi
        done
        log_info "Minimum viable system verified"

        if [[ ! -f /boot/vmlinuz-linux ]]; then
            log_error "Kernel still missing after all install attempts"
            _pacman -S --noconfirm linux linux-headers
        fi

        [[ "${de}" != "none" ]] && run_de_migration "none" "${de}"

        echo "services" > "${MIGRATION_STAGE_FILE}"
        migration_stage="services"
    fi

    if [[ "${migration_stage}" == "services" ]]; then
        log_info "Enabling selected services..."
        while IFS= read -r unit; do
            local mapped
            mapped=$(awk -F'|' -v u="${unit}" '$1==u {print $4}' "${ATA_MAP_CACHE}")
            [[ -n "${mapped}" && "${mapped}" != "MISSING" ]] && _enable_service "${mapped}" "${target_init}"
        done < /tmp/ata-migrate-selection.txt 2>/dev/null

        ata_convert_user_services
        ata_convert_systemd_boot
        ata_rebuild_dkms
        ata_restore_user_data "${backup_dir}"
        ata_restore_flatpaks "${backup_dir}"
        ata_restore_network_credentials "${backup_dir}"

        if [[ -n "${aur_helper}" && -s /tmp/ata-aur.txt ]]; then
            ata_reinstall_aur "${aur_helper}"
        fi

        if [[ -s /tmp/ata-exotic-mounts.txt ]]; then
            log_warn "Exotic mounts (NFS/CIFS/etc.) found in /etc/fstab. Verify after boot."
        fi

        mountpoint -q /proc || mount -t proc proc /proc
        mountpoint -q /sys  || mount -t sysfs sys /sys
        mountpoint -q /dev  || mount --bind /dev /dev

        log_info "Rebuilding initramfs..."
        if ! _chroot mkinitcpio -P 2>/dev/null; then
            log_warn "mkinitcpio failed — attempting with fallback kernel"
            _chroot mkinitcpio -P -k /boot/vmlinuz-linux 2>/dev/null || log_warn "mkinitcpio failed completely — manual repair may be needed"
        fi

        log_info "Updating bootloader..."
        if ! update_bootloader; then
            log_warn "Bootloader update failed — you may need to run grub-install manually"
        fi

        echo "finalize" > "${MIGRATION_STAGE_FILE}"
        migration_stage="finalize"
    fi

    rm -f /tmp/ata-*.txt /tmp/ata-pkg-map.txt
    rm -f "${MIGRATION_STAGE_FILE}"

    tui_msg "Migration Complete" \
"Your system has been converted to Artix Linux (${target_init}).

Backup: ${backup_dir}
Journal: ${backup_dir}/journal-full.txt

AFTER REBOOT:
  Check services with your init's service manager
  Verify DNS in /etc/resolv.conf
  AUR packages: check ${backup_dir}/lists/ata-aur.txt"

    if tui_yesno "Reboot" "Reboot now?"; then
        reboot
    fi
}