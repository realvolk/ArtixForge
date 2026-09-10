#!/usr/bin/env bash
set -Eeuo pipefail

ATA_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ATA_DIR}/../.." && pwd)}"

source "${BASE_DIR}/scripts/common.sh" 2>/dev/null || true
source "${BASE_DIR}/scripts/state.sh" 2>/dev/null || true
source "${BASE_DIR}/scripts/recovery/detect.sh" 2>/dev/null || true
source "${BASE_DIR}/scripts/recovery/core.sh" 2>/dev/null || true
source "${BASE_DIR}/migrations/inits/common.sh" 2>/dev/null || true
source "${ATA_DIR}/ata-detect.sh"
source "${ATA_DIR}/ata-map.sh"

ata_dryrun() {
    if [[ -d /run/artix/sfs/rootfs ]]; then
        tui_msg "Cannot Run from Live ISO" "ATA dry-run must be run from the booted Arch system."
        return 0
    fi

    if ! grep -q '^ID=arch' /etc/os-release 2>/dev/null; then
        tui_msg "Not Arch Linux" "This system does not appear to be Arch Linux."
        return 0
    fi

    if [[ ! -f /etc/resolv.conf || -L /etc/resolv.conf || ! -s /etc/resolv.conf ]]; then
        systemctl stop systemd-resolved 2>/dev/null || true
        printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    fi

    if ! ping -c 1 -W 3 1.1.1.1 &>/dev/null && ! curl -s --max-time 5 https://1.1.1.1 &>/dev/null; then
        tui_msg "No Network" "Internet connection required for dry-run."
        return 0
    fi

    tui_msg "ATA Dry-Run" "Detecting system configuration. This will not modify anything."

    log_info "Running system audit..."
    ata_detect_all

    local target_init
    target_init=$(tui_menu "Choose Init System" "Select your target init:" \
        "openrc" "runit" "dinit" "s6") || return 0

    ata_build_package_map

    local aur_count flatpak_count snap_count
    aur_count=$(wc -l < /tmp/ata-aur.txt 2>/dev/null || echo 0)
    flatpak_count=$(wc -l < /tmp/ata-flatpak.txt 2>/dev/null || echo 0)
    snap_count=$(wc -l < /tmp/ata-snap.txt 2>/dev/null || echo 0)

    local summary=""
    summary+="Target init: ${target_init}"$'\n'
    summary+="Desktop: $(state_get WM_DE none)"$'\n'
    summary+="AUR packages: ${aur_count}"$'\n'
    summary+="Flatpaks: ${flatpak_count}"$'\n'
    summary+="Snaps: ${snap_count}"$'\n'
    summary+=""$'\n'
    summary+="Packages to migrate:"$'\n'

    local migratable=0 missing=0 mismatch=0
    while IFS='|' read -r unit pkg arch_ver artix_pkg artix_ver status; do
        [[ -z "${unit}" ]] && continue
        case "${status}" in
            migratable) migratable=$((migratable + 1)) ;;
            no-artix-equivalent) missing=$((missing + 1)) ;;
            version-mismatch) mismatch=$((mismatch + 1)) ;;
        esac
    done < "${ATA_MAP_CACHE}"

    summary+="  Migratable services: ${migratable}"$'\n'
    summary+="  Version mismatches: ${mismatch}"$'\n'
    summary+="  No Artix equivalent: ${missing}"$'\n'

    if [[ ${missing} -gt 0 ]]; then
        summary+=""$'\n'
        summary+="Packages with no Artix equivalent:"$'\n'
        while IFS='|' read -r unit pkg arch_ver artix_pkg artix_ver status; do
            [[ "${status}" == "no-artix-equivalent" ]] && summary+="  - ${pkg}"$'\n'
        done < "${ATA_MAP_CACHE}"
    fi

    if [[ ${mismatch} -gt 0 ]]; then
        summary+=""$'\n'
        summary+="Version mismatches (will be replaced):"$'\n'
        while IFS='|' read -r unit pkg arch_ver artix_pkg artix_ver status; do
            [[ "${status}" == "version-mismatch" ]] && summary+="  - ${pkg}: Arch ${arch_ver} → Artix ${artix_ver}"$'\n'
        done < "${ATA_MAP_CACHE}"
    fi

    if [[ ${snap_count} -gt 0 ]]; then
        summary+=""$'\n'
        summary+="WARNING: ${snap_count} Snap packages will NOT function on Artix."$'\n'
    fi

    tui_msg "Migration Plan" "${summary}"

    if tui_yesno "Proceed?" "Start the full migration now?"; then
        ata_migrate_main
    else
        log_info "Dry-run complete. No changes were made."
    fi
}