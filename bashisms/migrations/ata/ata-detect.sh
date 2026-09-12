#!/usr/bin/env bash
set -Eeuo pipefail

ATA_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ata_detect_all() {
    log_info "Auditing Arch system..."

    detect_init
    detect_display_manager
    detect_xstack
    detect_audio_stack
    detect_network_stack
    detect_kernel
    detect_ucode
    detect_bootloader
    detect_filesystem
    detect_luks
    detect_lvm
    detect_uki

    local detected_de="none"
    local de pkg
    for de in "${!ATA_ARCH_DE_PACKAGES[@]}"; do
        for pkg in ${ATA_ARCH_DE_PACKAGES[$de]}; do
            if pacman -Q "$pkg" &>/dev/null; then
                detected_de="$de"
                break 2
            fi
        done
    done

    if [[ "$detected_de" == "gnome" ]]; then
        log_warn "GNOME detected. GNOME is not supported on Artix — Artix dropped GNOME"
        log_warn "in September 2025 due to systemd dependencies in gnome-session 49."
        log_warn "Your GNOME packages will be preserved, but GNOME will not work after"
        log_warn "migration. Install a supported desktop (KDE, XFCE, etc.) or run"
        log_warn "ArtixForge's DE migration after boot."
        state_set WM_DE none
    else
        state_set WM_DE "$detected_de"
    fi

    awk -F: '$3>=1000 && $1!="nobody" {print $1}' /etc/passwd > /tmp/ata-users.txt

    pacman -Qq > /tmp/ata-all-pkgs.txt
    pacman -Qqe > /tmp/ata-explicit.txt
    pacman -Qqm > /tmp/ata-aur.txt
    pacman -Qqd > /tmp/ata-deps.txt

    while IFS= read -r pkg; do
        pacman -Qi "$pkg" 2>/dev/null | grep -E '^(Name|Version|Description|URL):' >> /tmp/ata-aur-info.txt
    done < /tmp/ata-aur.txt

    flatpak list --app --columns=application 2>/dev/null > /tmp/ata-flatpak.txt || true
    snap list 2>/dev/null | tail -n +2 | awk '{print $1}' > /tmp/ata-snap.txt || true

    find /home /opt -name '*.AppImage' 2>/dev/null > /tmp/ata-appimages.txt

    docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' 2>/dev/null > /tmp/ata-docker.txt || true

    systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' > /tmp/ata-units.txt

    : > /tmp/ata-user-units.txt
    while IFS= read -r user; do
        if id "$user" &>/dev/null; then
            su - "$user" -c 'systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null' 2>/dev/null | awk '{print $1}' >> /tmp/ata-user-units.txt || true
        fi
    done < /tmp/ata-users.txt

    find /etc/systemd/system -name '*.service' -not -name 'dbus-org.*' > /tmp/ata-custom-units.txt 2>/dev/null

    systemctl list-timers --all --no-legend 2>/dev/null | awk '{print $NF}' > /tmp/ata-timers.txt

    for d in /etc/systemd/network /etc/netctl /etc/NetworkManager/system-connections /var/lib/iwd; do
        find "$d" -type f 2>/dev/null
    done > /tmp/ata-network-files.txt

    [[ -f /etc/systemd/resolved.conf ]] && cp /etc/systemd/resolved.conf /tmp/ata-resolved.conf
    if [[ -L /etc/resolv.conf ]]; then
        readlink -f /etc/resolv.conf > /tmp/ata-resolv-link.txt
    fi

    homectl list 2>/dev/null > /tmp/ata-homed.txt || true

    bootctl status 2>/dev/null > /tmp/ata-bootctl.txt || true

    journalctl --disk-usage 2>/dev/null > /tmp/ata-journal-size.txt || true

    dkms status 2>/dev/null > /tmp/ata-dkms.txt || true

    grep -E 'nfs|cifs|sshfs|ceph|gluster' /etc/fstab 2>/dev/null > /tmp/ata-exotic-mounts.txt || true

    grep -rhE '^\[.*\]' /etc/pacman.conf /etc/pacman.d/ 2>/dev/null | sort -u > /tmp/ata-custom-repos.txt

    grep -rl 'systemctl\|journalctl\|systemd' /usr/share/libalpm/hooks/ 2>/dev/null > /tmp/ata-systemd-hooks.txt || true

    grep -rl 'pam_systemd' /etc/pam.d/ 2>/dev/null > /tmp/ata-pam-systemd.txt || true

    [[ -f /etc/crypttab ]] && cp /etc/crypttab /tmp/ata-crypttab.txt

    iptables-save 2>/dev/null > /tmp/ata-iptables.rules || true
    nft list ruleset 2>/dev/null > /tmp/ata-nftables.rules || true

    while IFS= read -r user; do
        crontab -u "$user" -l > "/tmp/ata-cron-${user}.txt" 2>/dev/null || true
    done < /tmp/ata-users.txt
    find /etc/cron.* -type f > /tmp/ata-cron-files.txt 2>/dev/null || true

    find /etc/ssh -type f > /tmp/ata-ssh.txt 2>/dev/null || true

    find /usr/local -type f 2>/dev/null > /tmp/ata-usrlocal.txt || true

    timedatectl show 2>/dev/null > /tmp/ata-timedatectl.txt || true

    flatpak remotes --columns=name 2>/dev/null > /tmp/ata-flatpak-remotes.txt || true

    if command -v snap >/dev/null 2>&1; then
        snap list 2>/dev/null | tail -n +2 | awk '{print $1}' > /tmp/ata-snap.txt || true
        log_warn "Snap packages detected. Snaps require systemd and will NOT function on Artix."
        log_warn "List saved to backup. Consider replacing with flatpaks or native packages."
    fi

    log_info "Audit complete."
}