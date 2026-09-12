#!/usr/bin/env bash
set -Eeuo pipefail

_backup_user() {
    local src="$1" dest="$2"
    mkdir -p "$dest"
    rsync -a --safe-links \
        --exclude='.cache' \
        --exclude='.local/share/flatpak' \
        --exclude='.local/share/docker' \
        --exclude='.local/share/containers' \
        --exclude='.local/share/Trash' \
        --exclude='.local/share/baloo' \
        --exclude='.local/share/akonadi' \
        --exclude='.local/share/recently-used.xbel' \
        --exclude='.thumbnails' \
        --exclude='.gradle' \
        --exclude='.npm' \
        --exclude='.cargo' \
        --exclude='.rustup' \
        --exclude='node_modules' \
        --exclude='target' \
        --exclude='build' \
        --exclude='dist' \
        "$src/" "$dest/"
}

ata_backup_all() {
    local backup_dir="${1}"
    mkdir -p "${backup_dir}"
    chmod 700 "${backup_dir}"

    log_info "Creating backup at ${backup_dir}..."

    mkdir -p "${backup_dir}/home"
    while IFS= read -r user; do
        if [[ -d "/home/${user}" ]]; then
            _backup_user "/home/${user}" "${backup_dir}/home/${user}"
        elif [[ -f "/home/${user}.home" ]]; then
            log_info "  ${user} has a systemd-homed image — will be migrated later"
        else
            log_warn "  ${user} has no home directory — skipping backup"
        fi
    done < /tmp/ata-users.txt

    mkdir -p "${backup_dir}/etc"
    rsync -a --safe-links \
        --exclude='mtab' \
        --exclude='resolv.conf' \
        --exclude='pacman.d/' \
        --exclude='crypttab' \
        --exclude='crypttab.initramfs' \
        /etc/ "${backup_dir}/etc/"

    cp -a /var/lib/pacman "${backup_dir}/var-lib-pacman"

    cp -a /var/spool/cron "${backup_dir}/var-spool-cron" 2>/dev/null || true

    cp -a /boot "${backup_dir}/boot"

    [[ -d /usr/local ]] && cp -a /usr/local "${backup_dir}/usr-local"

    mkdir -p "${backup_dir}/network-configs"
    for d in /etc/systemd/network /var/lib/systemd/network /etc/NetworkManager/system-connections /etc/netctl /var/lib/iwd; do
        [[ -d "$d" ]] && cp -a "$d" "${backup_dir}/network-configs/"
    done
    chmod -R 700 "${backup_dir}/network-configs"

    if command -v journalctl >/dev/null 2>&1; then
        log_info "Exporting system journal..."
        journalctl --no-pager --output=short-full > "${backup_dir}/journal-full.txt" 2>/dev/null || true
        journalctl --export > "${backup_dir}/journal-export.bin" 2>/dev/null || true
    fi

    mkdir -p "${backup_dir}/lists"
    for f in /tmp/ata-*.txt /tmp/ata-*.conf /tmp/ata-*.rules; do
        [[ -f "$f" ]] && cp "$f" "${backup_dir}/lists/"
    done

    log_info "Backup saved to ${backup_dir}"
}