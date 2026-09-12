#!/usr/bin/env bash
set -Eeuo pipefail

[[ -n "${_ARTIX_INITS_COMMON_SOURCED:-}" ]] && return 0
_ARTIX_INITS_COMMON_SOURCED=1

MIG_ROOT=""

_verify_migration_root() {
    local root="${1}"
    [[ -d "${root}" ]] || return 1
    [[ -f "${root}/etc/os-release" ]] || return 1
    [[ -x "${root}/usr/bin/pacman" ]] || return 1
    [[ -d "${root}/var/lib/pacman" ]] || return 1
    return 0
}

_verify_running_system() {
    [[ -f /etc/os-release ]] || return 1
    [[ -x /usr/bin/pacman ]] || return 1
    [[ -d /var/lib/pacman ]] || return 1
    return 0
}

ensure_migration_root() {
    if [[ -n "${MIG_ROOT}" ]] && _verify_migration_root "${MIG_ROOT}"; then
        export MIG_ROOT
        return 0
    fi

    local persisted_root
    persisted_root="$(state_get MIG_ROOT "")"

    if [[ -n "${persisted_root}" ]]; then
        if _verify_migration_root "${persisted_root}"; then
            MIG_ROOT="${persisted_root}"
            export MIG_ROOT
            log_info "Migration target (resumed): ${MIG_ROOT}"
            return 0
        fi
        log_warn "Persisted migration root ${persisted_root} is no longer valid."
    fi

    local on_live_iso=false
    [[ -d /run/artix/sfs/rootfs ]] && on_live_iso=true
    [[ -f /run/artix/live ]] && on_live_iso=true

    if [[ "${on_live_iso}" == true ]]; then
        tui_msg "Live ISO Detected" "Migration requires the target system to be mounted."
        local mount_choice
        mount_choice=$(tui_menu "Target Selection" "How do you want to locate the target system?" \
            "Auto-mount (LUKS/LVM/plain)" \
            "Use /mnt (already mounted)" \
            "Specify mount point") || { tui_msg_quick "Cancelled" "Migration cancelled."; exit 0; }

        case "${mount_choice}" in
            "Auto-mount"*)
                recovery_mount_all || { tui_msg_quick "Mount Failed" "Could not mount target system."; exit 1; }
                MIG_ROOT="/mnt"
                ;;
            "Use /mnt"*)
                _verify_migration_root "/mnt" || { tui_msg "Invalid Target" "/mnt is not a valid Artix installation."; exit 1; }
                MIG_ROOT="/mnt"
                ;;
            "Specify"*)
                MIG_ROOT=$(tui_input "Mount Point" "Enter the mount point of the target system:" "/mnt") || exit 1
                [[ -n "${MIG_ROOT}" ]] || exit 1
                _verify_migration_root "${MIG_ROOT}" || { tui_msg "Invalid Target" "${MIG_ROOT} is not a valid Artix installation."; exit 1; }
                ;;
        esac
    else
        local choice
        choice=$(tui_menu "Migration Target" "Which system do you want to migrate?" \
            "This running system" \
            "A mounted installation") || { tui_msg_quick "Cancelled" "Migration cancelled."; exit 0; }

        case "${choice}" in
            "This running"*)
                MIG_ROOT=""
                _verify_running_system || { tui_msg "Invalid System" "This does not appear to be a valid Artix installation."; exit 1; }
                ;;
            "A mounted"*)
                MIG_ROOT=$(tui_input "Mount Point" "Enter the mount point of the target system:" "/mnt") || exit 1
                [[ -n "${MIG_ROOT}" ]] || exit 1
                _verify_migration_root "${MIG_ROOT}" || { tui_msg "Invalid Target" "${MIG_ROOT} is not a valid Artix installation."; exit 1; }
                ;;
        esac
    fi

    export MIG_ROOT
    state_set MIG_ROOT "${MIG_ROOT}"
    log_info "Migration target: ${MIG_ROOT:-running system}"
}

ensure_migration_root

_chroot() {
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" "$@"
    else
        "$@"
    fi
}

_pacman() {
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" pacman "$@"
    else
        pacman "$@"
    fi
}

HUB_INIT="openrc"

get_migration_table() {
    local src="${1}" tgt="${2}"
    local table_name="SERVICE_MAP_${src^^}_${tgt^^}"
    declare -p "$table_name" &>/dev/null && echo "$table_name" || echo ""
}

has_direct_table() {
    local src="${1}" tgt="${2}"
    local table_name="SERVICE_MAP_${src^^}_${tgt^^}"
    declare -p "$table_name" &>/dev/null && return 0 || return 1
}

list_enabled_services() {
    local init="${1:-openrc}"
    if [[ -n "${MIG_ROOT}" ]]; then
        case "$init" in
            openrc)
                if ! artix-chroot "${MIG_ROOT}" command -v rc-update &>/dev/null; then
                    echo ""
                    return 0
                fi
                artix-chroot "${MIG_ROOT}" rc-update show -v 2>/dev/null | awk '/default|boot|nonetwork/ {print $1}' | sort -u
                ;;
            runit)
                [[ -d "${MIG_ROOT}/etc/runit/runsvdir/default" ]] && find "${MIG_ROOT}/etc/runit/runsvdir/default" -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort -u || echo ""
                ;;
            dinit)
                [[ -d "${MIG_ROOT}/etc/dinit.d/boot.d" ]] && find "${MIG_ROOT}/etc/dinit.d/boot.d" -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort -u || echo ""
                ;;
            s6)
                artix-chroot "${MIG_ROOT}" sh -c 's6-rc-db list bundle default 2>/dev/null || s6-rc-db list services 2>/dev/null' 2>/dev/null || echo ""
                ;;
            systemd)
                artix-chroot "${MIG_ROOT}" systemctl list-unit-files --state=enabled 2>/dev/null | awk '/\.service/ {gsub(/\.service$/, "", $1); print $1}' | sort -u || echo ""
                ;;
            *)      echo "" ;;
        esac
    else
        case "$init" in
            openrc)
                if ! command -v rc-update &>/dev/null; then
                    echo ""
                    return 0
                fi
                rc-update show -v 2>/dev/null | awk '/default|boot|nonetwork/ {print $1}' | sort -u
                ;;
            runit)
                [[ -d /etc/runit/runsvdir/default ]] && find /etc/runit/runsvdir/default -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort -u || echo ""
                ;;
            dinit)
                [[ -d /etc/dinit.d/boot.d ]] && find /etc/dinit.d/boot.d -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | sort -u || echo ""
                ;;
            s6)
                sh -c 's6-rc-db list bundle default 2>/dev/null || s6-rc-db list services 2>/dev/null' 2>/dev/null || echo ""
                ;;
            systemd)
                systemctl list-unit-files --state=enabled 2>/dev/null | awk '/\.service/ {gsub(/\.service$/, "", $1); print $1}' | sort -u || echo ""
                ;;
            *)      echo "" ;;
        esac
    fi
}

map_service() {
    resolve_service_map "${1}" "${2}" "${3}"
}

list_init_packages() {
    local init_suffix="${1}"
    _pacman -Qsq "${init_suffix}" 2>/dev/null || true
}

cache_target_init_packages() {
    local source_init="${1}" target_init="${2}"
    log_info "Downloading target init packages before removing ${source_init}..."
    local target_pkgs_raw
    target_pkgs_raw="$(resolve_init_fallback_packages "${target_init}")"
    if [[ -z "${target_pkgs_raw}" ]]; then
        log_warn "No package set for target init ${target_init} — skipping download"
        return 0
    fi
    log_info "Caching: ${target_pkgs_raw}"
    _pacman -Sw --noconfirm ${target_pkgs_raw} 2>/dev/null || log_warn "Some packages could not be downloaded"
}

remove_source_init() {
    local src="${1}"
    case "$src" in
        systemd)
            log_info "Removing systemd and related packages..."
            _pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus 2>/dev/null || true
            rm -fv "${MIG_ROOT}/etc/resolv.conf" 2>/dev/null || true
            cp -vf "${MIG_ROOT}/etc/pacman.d/mirrorlist.artix" "${MIG_ROOT}/etc/pacman.d/mirrorlist" 2>/dev/null || true
            ;;
        *)
            local catalog_pkgs=""
            catalog_pkgs="$(resolve_init_fallback_packages "$src")"
            local qsq_pkgs=""
            qsq_pkgs="$(list_init_packages "$src")"
            local -A to_remove=()
            local p
            for p in $catalog_pkgs $qsq_pkgs; do
                [[ -n "$p" ]] && to_remove["$p"]=1
            done
            if [[ ${#to_remove[@]} -gt 0 ]]; then
                log_info "Removing ${src} packages: ${!to_remove[*]}"
                _pacman -Rdd --noconfirm "${!to_remove[@]}" 2>/dev/null || log_warn "Some packages could not be removed"
            else
                log_warn "No ${src} packages found to remove"
            fi
            ;;
    esac
}

install_target_init() {
    local target_init="${1}"
    local target_pkgs_raw=""
    target_pkgs_raw="$(resolve_init_fallback_packages "$target_init")"
    [[ -n "$target_pkgs_raw" ]] || die "No package set for init: $target_init"
    local -a target_pkgs=()
    read -ra target_pkgs <<< "$target_pkgs_raw"
    log_info "Installing target init packages: ${target_pkgs[*]}"
    if [[ "$target_init" == "openrc" ]]; then
        _pacman -Rdd --noconfirm cryptsetup-scripts 2>/dev/null || true
    fi
    _pacman -S --noconfirm --needed "${target_pkgs[@]}" || die "Failed to install ${target_init}"
}

backup_init_config() {
    local init="${1}" backup_dir="${2}"
    mkdir -p "$backup_dir"
    case "$init" in
        openrc) cp -a "${MIG_ROOT}/etc/runlevels" "$backup_dir/" 2>/dev/null || true ;;
        runit)  cp -a "${MIG_ROOT}/etc/runit/runsvdir" "$backup_dir/" 2>/dev/null || true ;;
        dinit)  cp -a "${MIG_ROOT}/etc/dinit.d" "$backup_dir/" 2>/dev/null || true ;;
        s6)     cp -a "${MIG_ROOT}/etc/s6" "$backup_dir/" 2>/dev/null || true ;;
        systemd) cp -a "${MIG_ROOT}/etc/systemd" "$backup_dir/" 2>/dev/null || true ;;
    esac
    log_info "Init configuration backed up to $backup_dir"
}

detect_custom_services() {
    local init="${1}"
    local -a custom=()
    local -a known_services=(NetworkManager networkmanager dhcpcd iwd sshd cronie dbus elogind logind seatd acpid alsa bluetoothd connmand firewalld ntpd syslog-ng lvm2 dmcrypt zfs-zed lightdm agetty bootmisc binfmt esysusers etmpfiles fsck hostname hwclock keymaps localmount loopback modules mtab netmount procfs root save-keymaps save-termencoding seedrng swap sysctl termencoding)
    local svc
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        for known in "${known_services[@]}"; do
            [[ "$svc" == "$known" ]] && continue 2
        done
        local owned=0
        case "$init" in
            openrc) _pacman -Qo "${MIG_ROOT}/etc/init.d/$svc" &>/dev/null && owned=1 ;;
            runit)  _pacman -Qo "${MIG_ROOT}/etc/runit/sv/$svc" &>/dev/null && owned=1 ;;
            dinit)  _pacman -Qo "${MIG_ROOT}/etc/dinit.d/$svc" &>/dev/null && owned=1 ;;
            s6)     _pacman -Qo "${MIG_ROOT}/etc/s6/sv/$svc" &>/dev/null && owned=1 ;;
        esac
        [[ $owned -eq 0 ]] && custom+=("$svc")
    done < <(list_enabled_services "$init")
    printf '%s\n' "${custom[@]}"
}

validate_migration() {
    local src="${1}" tgt="${2}"
    [[ "$src" != "$tgt" ]] || die "Source and target init are the same: $src"
    command -v pacman &>/dev/null || die "This migration requires pacman"
}

_enable_service() {
    local svc="$1" init="${2:-${INIT:-openrc}}"
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" bash -c "
            source /usr/local/lib/artix-installer/services.sh 2>/dev/null || \
            source /root/ArtixForge/bashisms/installer/install/services.sh
            export INIT='${init}'
            enable_service '${svc}'
        " 2>/dev/null || log_warn "Could not enable $svc service"
    else
        export INIT="${init}"
        enable_service "$svc" 2>/dev/null || log_warn "Could not enable $svc service"
    fi
}

_run_single_migration() {
    local source_init="${1}" target_init="${2}"
    log_info "Migrating services from $source_init to $target_init..."
    local enabled_svcs
    enabled_svcs=$(list_enabled_services "$source_init")
    local migrated=0 skipped=0
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local mapped
        mapped=$(map_service "$source_init" "$target_init" "$svc" 2>/dev/null || true)
        if [[ -n "$mapped" ]]; then
            log_info "  Migrating: $svc → $mapped"
            _enable_service "$mapped" "$target_init"
            migrated=$((migrated + 1))
        else
            log_warn "  No mapping for $svc – skipping"
            skipped=$((skipped + 1))
        fi
    done <<< "$enabled_svcs"
    log_info "Step complete: $migrated services migrated, $skipped skipped"
}

prepare_artix_repos() {
    log_info "Replacing pacman.conf and mirrorlist with Artix versions..."
    mv -vf "${MIG_ROOT}/etc/pacman.conf" "${MIG_ROOT}/etc/pacman.conf.arch" 2>/dev/null || true
    curl -sL https://gitea.artixlinux.org/packages/pacman/raw/branch/master/pacman.conf -o "${MIG_ROOT}/etc/pacman.conf"
    mv -vf "${MIG_ROOT}/etc/pacman.d/mirrorlist" "${MIG_ROOT}/etc/pacman.d/mirrorlist-arch" 2>/dev/null || true
    curl -sL https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o "${MIG_ROOT}/etc/pacman.d/mirrorlist"
    cp -vf "${MIG_ROOT}/etc/pacman.d/mirrorlist" "${MIG_ROOT}/etc/pacman.d/mirrorlist.artix" 2>/dev/null || true

    if [[ "$(state_get ENABLE_ARCH_REPOS no)" == "yes" ]]; then
        log_info "Enabling Arch repositories in pacman.conf..."
        if ! grep -q '^\[extra\]' "${MIG_ROOT}/etc/pacman.conf" 2>/dev/null; then
            cat >> "${MIG_ROOT}/etc/pacman.conf" <<'EOF'
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
    fi
}

clean_pacman_cache() {
    log_info "Cleaning all pacman caches and forcing sync..."
    _pacman -Scc --noconfirm 2>/dev/null || true
    _pacman -Syy --noconfirm
}

install_artix_keyring() {
    log_info "Temporarily lowering pacman security level..."
    sed -i 's/^SigLevel.*/SigLevel = Never/' "${MIG_ROOT}/etc/pacman.conf"

    log_info "Installing Artix PGP keyring..."
    _pacman -S --noconfirm artix-keyring
    _chroot pacman-key --populate artix
    _chroot pacman-key --lsign-key 95AEC5D0C1E294FC9F82B253573A673A53C01BC2

    log_info "Restoring pacman security level..."
    sed -i 's/^SigLevel = Never/SigLevel = Required DatabaseOptional/' "${MIG_ROOT}/etc/pacman.conf"
}

cache_artix_packages() {
    local init="${1:-openrc}"
    log_info "Downloading base Artix packages into cache..."
    local -a pkgs=(base base-devel grub linux linux-headers mkinitcpio
                   rsync lsb-release esysusers etmpfiles artix-branding-base)
    local init_pkgs=""
    init_pkgs="$(resolve_init_fallback_packages "${init}")"
    [[ -n "$init_pkgs" ]] && pkgs+=($init_pkgs)
    _pacman -Sw --noconfirm "${pkgs[@]}" 2>/dev/null || log_warn "Some packages could not be downloaded"
}

remove_systemd() {
    log_info "Removing systemd and related packages..."
    _pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus 2>/dev/null || true
    rm -fv "${MIG_ROOT}/etc/resolv.conf" 2>/dev/null || true
    cp -vf "${MIG_ROOT}/etc/pacman.d/mirrorlist.artix" "${MIG_ROOT}/etc/pacman.d/mirrorlist" 2>/dev/null || true
}

reinstall_artix_packages() {
    log_info "Reinstalling all packages from Artix repositories..."
    export LC_ALL=C
    _pacman -Sl system | grep installed | cut -d" " -f2 | _pacman -S --noconfirm -
    _pacman -Sl world  | grep installed | cut -d" " -f2 | _pacman -S --noconfirm -
    _pacman -Sl galaxy | grep installed | cut -d" " -f2 | _pacman -S --noconfirm -
    if [[ "$(state_get ENABLE_ARCH_REPOS no)" == "yes" ]]; then
        _pacman -Sl lib32 | grep installed | cut -d" " -f2 | _pacman -S --noconfirm - 2>/dev/null || true
    fi
}

enable_lvm_services() {
    if [[ -f "${MIG_ROOT}/etc/lvm/lvm.conf" ]] || _pacman -Q lvm2 &>/dev/null; then
        log_info "Enabling LVM services..."
        local init
        init=$(detect_init 2>/dev/null || state_get INIT openrc)
        case "$init" in
            openrc)
                _enable_service lvm boot "$init"
                _enable_service device-mapper boot "$init"
                ;;
            runit)
                _enable_service lvm2 "$init"
                _enable_service device-mapper "$init"
                ;;
            dinit)
                _enable_service lvm2 "$init"
                _enable_service dmeventd "$init"
                ;;
            s6)
                ;;
        esac
    fi
}

cleanup_systemd_junk() {
    log_info "Removing systemd junk accounts and directories..."
    for user in journal journal-gateway timesync network bus-proxy journal-remote journal-upload resolve coredump; do
        _chroot userdel "systemd-$user" 2>/dev/null || true
    done
    rm -vfr "${MIG_ROOT}/"{etc,var/lib}/systemd 2>/dev/null || true
}

update_bootloader() {
    log_info "Recreating initramfs and updating bootloader..."
    if [[ -x "${MIG_ROOT}/usr/bin/mkinitcpio" ]]; then
        _chroot mkinitcpio -P 2>/dev/null || log_warn "mkinitcpio failed"
    fi
    if _chroot command -v grub-mkconfig &>/dev/null; then
        _chroot grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warn "grub-mkconfig failed"
    elif _chroot command -v update-grub &>/dev/null; then
        _chroot update-grub 2>/dev/null || log_warn "update-grub failed"
    fi
    if [[ -d "${MIG_ROOT}/boot/efi" ]]; then
        log_info "Reinstalling GRUB for UEFI..."
        _chroot grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB 2>/dev/null || log_warn "grub-install failed"
    else
        log_info "Reinstalling GRUB for BIOS..."
        local disk
        disk="$(lsblk -no PKNAME "$(findmnt -no SOURCE "${MIG_ROOT}/" 2>/dev/null)" 2>/dev/null | head -n1)"
        if [[ -n "$disk" ]]; then
            _chroot grub-install "/dev/$disk" 2>/dev/null || log_warn "grub-install failed"
        fi
    fi
}

cold_reboot() {
    log_info "Init has been swapped — performing cold reboot via SysRq..."
    sync
    local remount_target="${MIG_ROOT:-/}"
    mount "$remount_target" -o remount,ro 2>/dev/null || true
    echo s >| /proc/sysrq-trigger 2>/dev/null || true
    echo u >| /proc/sysrq-trigger 2>/dev/null || true
    echo b >| /proc/sysrq-trigger 2>/dev/null || true
    reboot
}

run_init_migration() {
    local source_init="${1}" target_init="${2}"
    validate_migration "$source_init" "$target_init"

    local migration_stage_file="/tmp/artix-installer/migration-stage.conf"
    local migration_stage
    migration_stage="$(cat "${migration_stage_file}" 2>/dev/null || echo "init")"
    log_info "Migration stage: ${migration_stage}"

    if [[ "${migration_stage}" != "init" && "${migration_stage}" != "finalize" ]]; then
        tui_msg "Failed Migration Detected" \
            "A previous migration attempt was interrupted at stage: ${migration_stage}.\n\n
You can:\n
  • Resume – continue from where it stopped\n
  • Start Fresh – remove both init systems and perform a clean migration"

        if ! tui_yesno "Resume Migration?" "Resume the interrupted migration?"; then
            log_info "User chose to start fresh — removing both init systems..."
            remove_source_init "$source_init" 2>/dev/null || true
            remove_source_init "$target_init" 2>/dev/null || true
            local backup_dir
            backup_dir="$(state_get MIGRATION_BACKUP_DIR '')"
            if [[ -n "${backup_dir}" && -d "${backup_dir}" ]]; then
                rm -rf "${backup_dir}" 2>/dev/null || true
            fi
            rm -f "${migration_stage_file}"
            migration_stage="init"
            log_info "Both init systems removed. Starting clean migration."
        fi
    fi

    if [[ "$source_init" == "systemd" ]]; then
        if [[ -n "${MIG_ROOT}" ]]; then
            die "Systemd→Artix migration must be run from the installed system, not the live ISO."
        fi
        log_info "Starting migration from Arch/systemd to Artix/${target_init}..."
        if ! tui_yesno "Full Migration" "This will replace your entire system with Artix.\n\nProceed?"; then
            log_info "Migration cancelled."
            return 0
        fi

        prepare_artix_repos
        clean_pacman_cache
        install_artix_keyring
        cache_artix_packages "$target_init"
        remove_systemd
        install_target_init "$target_init"
        log_info "Installing base Artix packages..."
        _pacman -S --noconfirm base base-devel grub linux linux-headers mkinitcpio \
            rsync lsb-release esysusers etmpfiles artix-branding-base
        reinstall_artix_packages
    else
        if [[ "${migration_stage}" == "init" || "${migration_stage}" == "backup" ]]; then
            local backup_dir="${MIG_ROOT}/root/init-backup-${source_init}-$(date +%Y%m%d-%H%M%S)"
            backup_init_config "$source_init" "$backup_dir"

            local -a custom_services
            mapfile -t custom_services < <(detect_custom_services "$source_init")
            if [[ ${#custom_services[@]} -gt 0 ]]; then
                log_warn "Custom services detected: ${custom_services[*]}"
                mkdir -p "$backup_dir/custom"
                for svc in "${custom_services[@]}"; do
                    case "$source_init" in
                        openrc) cp -a "${MIG_ROOT}/etc/init.d/$svc" "$backup_dir/custom/" 2>/dev/null || true ;;
                        runit)  cp -a "${MIG_ROOT}/etc/runit/sv/$svc" "$backup_dir/custom/" 2>/dev/null || true ;;
                        dinit)  cp -a "${MIG_ROOT}/etc/dinit.d/$svc" "$backup_dir/custom/" 2>/dev/null || true ;;
                        s6)     cp -a "${MIG_ROOT}/etc/s6/sv/$svc" "$backup_dir/custom/" 2>/dev/null || true ;;
                    esac
                done
                log_info "Custom services saved to $backup_dir/custom/"
            fi
            state_set MIGRATION_BACKUP_DIR "${backup_dir}"
            echo "backup" > "${migration_stage_file}"
        else
            log_info "Skipping backup (already done)"
        fi

        if [[ "${migration_stage}" == "backup" || "${migration_stage}" == "cache" ]]; then
            cache_target_init_packages "$source_init" "$target_init"

            local enabled_svcs
            enabled_svcs=$(list_enabled_services "$source_init")
            local svc_pkgs=""
            while IFS= read -r svc; do
                [[ -z "$svc" ]] && continue
                local mapped
                mapped=$(map_service "$source_init" "$target_init" "$svc" 2>/dev/null || true)
                if [[ -n "$mapped" ]]; then
                    svc_pkgs+=" ${mapped}-${target_init}"
                fi
            done <<< "$enabled_svcs"
            if [[ -n "$svc_pkgs" ]]; then
                log_info "Installing service packages: ${svc_pkgs}"
                _pacman -S --noconfirm --needed ${svc_pkgs} 2>/dev/null || log_warn "Some service packages could not be installed"
            fi
            echo "cache" > "${migration_stage_file}"
        else
            log_info "Skipping package cache (already done)"
        fi

        if [[ "${migration_stage}" == "cache" || "${migration_stage}" == "remove" ]]; then
            remove_source_init "$source_init"
            echo "remove" > "${migration_stage_file}"
        else
            log_info "Skipping source init removal (already done)"
        fi

        if [[ "${migration_stage}" == "remove" || "${migration_stage}" == "install" ]]; then
            install_target_init "$target_init"
            echo "install" > "${migration_stage_file}"
        else
            log_info "Skipping target init install (already done)"
        fi
    fi

    if [[ "${migration_stage}" == "install" || "${migration_stage}" == "services" || "${migration_stage}" == "cache" || "${migration_stage}" == "remove" ]]; then
        if has_direct_table "$source_init" "$target_init"; then
            log_info "Direct migration: $source_init → $target_init"
            _run_single_migration "$source_init" "$target_init"
        elif [[ "$source_init" != "$HUB_INIT" && "$target_init" != "$HUB_INIT" ]]; then
            log_info "Chaining through $HUB_INIT"
            _run_single_migration "$source_init" "$HUB_INIT"
            _run_single_migration "$HUB_INIT" "$target_init"
        elif [[ "$source_init" != "$HUB_INIT" && "$target_init" == "$HUB_INIT" ]]; then
            _run_single_migration "$source_init" "$HUB_INIT"
        elif [[ "$source_init" == "$HUB_INIT" && "$target_init" != "$HUB_INIT" ]]; then
            _run_single_migration "$HUB_INIT" "$target_init"
        fi
        echo "services" > "${migration_stage_file}"
    else
        log_info "Skipping service migration (already done)"
    fi

    if [[ "${migration_stage}" == "services" || "${migration_stage}" == "finalize" ]]; then
        enable_lvm_services
        [[ "$source_init" == "systemd" ]] && cleanup_systemd_junk
        update_bootloader
        echo "finalize" > "${migration_stage_file}"
    else
        log_info "Skipping finalization (already done)"
    fi

    rm -f "${migration_stage_file}"

    log_info "Init migration complete."

    if [[ "$source_init" != "systemd" ]]; then
        if tui_yesno "Reboot" "A cold reboot is required. Proceed?"; then
            cold_reboot
        else
            log_warn "You must cold reboot manually to complete the migration."
            log_warn "Run: sync && echo b > /proc/sysrq-trigger"
        fi
    else
        if tui_yesno "Reboot" "Reboot now?"; then
            reboot
        fi
    fi
}

tui_init_migration_menu() {
    detect_init >/dev/null 2>&1 || true
    local current_init
    current_init=$(state_get INIT openrc)
    tui_msg_quick "Current Init" "Detected init system: ${current_init}"

    local source_init target_init
    source_init=$(tui_menu "Source Init" "Select current init system:" \
        "openrc" "runit" "dinit" "s6" "systemd") || return 1
    target_init=$(tui_menu "Target Init" "Select new init system:" \
        "openrc" "runit" "dinit" "s6") || return 1
    [[ "$source_init" != "$target_init" ]] || die "Source and target are the same."

    run_init_migration "${source_init}" "${target_init}"
}