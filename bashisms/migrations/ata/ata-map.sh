#!/usr/bin/env bash
set -Eeuo pipefail

ATA_MAP_CACHE="/tmp/ata-pkg-map.txt"

ata_build_package_map() {
    log_info "Building package availability map..."
    pacman -Sy --noconfirm 2>/dev/null || true
    : > "${ATA_MAP_CACHE}"

    local target_init
    target_init="$(state_get INIT openrc)"

    while IFS= read -r unit; do
        [[ -z "${unit}" ]] && continue
        [[ -n "${ATA_SKIP_UNITS[${unit}]:-}" ]] && continue
        [[ "${unit}" =~ \.(service|target|socket|timer)$ ]] || continue
        [[ "${unit}" =~ ^systemd- ]] && continue
        [[ "${unit}" == "getty@.service" ]] && continue
        [[ "${unit}" == "serial-getty@.service" ]] && continue

        local orig_unit="${unit}"
        local base_unit="${unit%.service}"
        base_unit="${base_unit%.target}"
        base_unit="${base_unit%.timer}"
        base_unit="${base_unit%.socket}"
        base_unit="${base_unit%@*}"

        local svc_file=""
        local path ext
        for path in /usr/lib/systemd/system /etc/systemd/system; do
            for ext in service target timer socket; do
                if [[ -f "${path}/${base_unit}.${ext}" ]]; then
                    svc_file="${path}/${base_unit}.${ext}"
                    break 2
                fi
            done
        done

        local arch_pkg=""
        if [[ -n "${svc_file}" ]]; then
            arch_pkg="$(pacman -Qo "${svc_file}" 2>/dev/null | awk '{print $5}' | cut -d/ -f1)" || true
        fi
        [[ -z "${arch_pkg}" ]] && arch_pkg="${base_unit}"

        local arch_ver=""
        arch_ver=$(pacman -Q "${arch_pkg}" 2>/dev/null | awk '{print $2}') || true

        local artix_pkg=""
        artix_pkg="$(resolve_systemd_unit_package "${unit}" "${target_init}")" || artix_pkg="MISSING"

        local artix_ver=""
        [[ "${artix_pkg}" != "MISSING" ]] && artix_ver=$(pacman -Si "${artix_pkg}" 2>/dev/null | grep 'Version' | head -n1 | awk '{print $3}')

        local status="migratable"
        [[ "${artix_pkg}" == "MISSING" ]] && status="no-artix-equivalent"
        [[ -n "${arch_ver}" && -n "${artix_ver}" && "${arch_ver}" != "${artix_ver}" ]] && status="version-mismatch"

        printf '%s|%s|%s|%s|%s|%s\n' \
            "${orig_unit}" "${arch_pkg}" "${arch_ver}" "${artix_pkg}" "${artix_ver}" "${status}" >> "${ATA_MAP_CACHE}"
    done < /tmp/ata-units.txt
}

ata_show_migration_list() {
    tui_msg "Package Migration" "The following systemd units were detected."

    local items=()
    while IFS='|' read -r unit pkg arch_ver artix_pkg artix_ver status; do
        [[ -z "${unit}" ]] && continue
        local label="${unit} → ${artix_pkg}"
        case "${status}" in
            version-mismatch) label+=" [ARCH: ${arch_ver} / ARTIX: ${artix_ver}]" ;;
            no-artix-equivalent) label+=" [NO ARTIX EQUIVALENT]" ;;
        esac
        items+=("${label}")
    done < "${ATA_MAP_CACHE}"

    [[ ${#items[@]} -eq 0 ]] && { tui_msg "No units" "No enabled systemd units found."; return; }

    local chosen
    chosen=$(tui_checklist "Migrate Services" "Select services to migrate:" "${items[@]}") || true
    printf '%s\n' "${chosen}" | sed 's/ .*//' > /tmp/ata-migrate-selection.txt
}