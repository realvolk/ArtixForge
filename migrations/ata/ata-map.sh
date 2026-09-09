#!/usr/bin/env bash
set -Eeuo pipefail

ATA_MAP_CACHE="/tmp/ata-pkg-map.txt"

ata_build_package_map() {
    log_info "Building package availability map..."
    pacman -Sy --noconfirm 2>/dev/null || true
    : > "${ATA_MAP_CACHE}"

    local -A skip_units=(
        ["systemd-journald.service"]=1
        ["systemd-journal-flush.service"]=1
        ["systemd-journal-catalog-update.service"]=1
        ["systemd-journald-dev-log.socket"]=1
        ["systemd-journald.socket"]=1
        ["systemd-logind.service"]=1
        ["systemd-user-sessions.service"]=1
        ["systemd-userdbd.service"]=1
        ["user-runtime-dir@.service"]=1
        ["systemd-homed.service"]=1
        ["systemd-homed-activate.service"]=1
        ["systemd-resolved.service"]=1
        ["systemd-networkd.service"]=1
        ["systemd-networkd-wait-online.service"]=1
        ["systemd-network-generator.service"]=1
        ["systemd-resolved-generator.service"]=1
        ["systemd-timesyncd.service"]=1
        ["systemd-udevd.service"]=1
        ["systemd-udevd-control.socket"]=1
        ["systemd-udevd-kernel.socket"]=1
        ["systemd-udev-trigger.service"]=1
        ["systemd-udev-settle.service"]=1
        ["systemd-modules-load.service"]=1
        ["systemd-boot-check-no-failures.service"]=1
        ["systemd-boot-system-token.service"]=1
        ["systemd-fsck@.service"]=1
        ["systemd-fsck-root.service"]=1
        ["systemd-growfs@.service"]=1
        ["systemd-growfs-root.service"]=1
        ["systemd-repart.service"]=1
        ["systemd-pstore.service"]=1
        ["systemd-binfmt.service"]=1
        ["systemd-sysctl.service"]=1
        ["systemd-random-seed.service"]=1
        ["systemd-tmpfiles-setup.service"]=1
        ["systemd-tmpfiles-setup-dev.service"]=1
        ["systemd-tmpfiles-clean.service"]=1
        ["systemd-sysusers.service"]=1
        ["systemd-machine-id-commit.service"]=1
        ["systemd-update-utmp.service"]=1
        ["systemd-update-utmp-runlevel.service"]=1
        ["systemd-backlight@.service"]=1
        ["systemd-rfkill.service"]=1
        ["systemd-rfkill.socket"]=1
        ["systemd-hwdb-update.service"]=1
        ["systemd-ask-password-console.service"]=1
        ["systemd-ask-password-wall.service"]=1
        ["systemd-fstab-generator"]=1
        ["systemd-cryptsetup@.service"]=1
        ["systemd-cryptsetup-generator"]=1
        ["systemd-veritysetup-generator"]=1
        ["systemd-veritysetup@.service"]=1
        ["systemd-swap-generator"]=1
        ["systemd-mount.service"]=1
        ["systemd-umount.service"]=1
        ["systemd-remount-fs.service"]=1
        ["systemd-shutdown"]=1
        ["systemd-reboot"]=1
        ["systemd-poweroff"]=1
        ["systemd-oomd.service"]=1
        ["systemd-oomd.socket"]=1
        ["systemd-watchdog.service"]=1
        ["sysinit.target"]=1
        ["basic.target"]=1
        ["multi-user.target"]=1
        ["graphical.target"]=1
        ["default.target"]=1
        ["shutdown.target"]=1
        ["poweroff.target"]=1
        ["reboot.target"]=1
        ["halt.target"]=1
        ["rescue.target"]=1
        ["emergency.target"]=1
        ["local-fs.target"]=1
        ["local-fs-pre.target"]=1
        ["remote-fs.target"]=1
        ["remote-fs-pre.target"]=1
        ["network.target"]=1
        ["network-online.target"]=1
        ["time-sync.target"]=1
        ["nss-lookup.target"]=1
        ["nss-user-lookup.target"]=1
        ["paths.target"]=1
        ["sockets.target"]=1
        ["timers.target"]=1
        ["getty.target"]=1
        ["getty-pre.target"]=1
        ["suspend.target"]=1
        ["hibernate.target"]=1
        ["hybrid-sleep.target"]=1
        ["suspend-then-hibernate.target"]=1
        ["sleep.target"]=1
        ["system-update.target"]=1
        ["system-update-pre.target"]=1
        ["kexec.target"]=1
        ["systemd-tmpfiles-clean.timer"]=1
        ["systemd-timesyncd.timer"]=1
        ["systemd-rfkill.timer"]=1
        ["systemd-userdbd.socket"]=1
        ["systemd-journald-audit.socket"]=1
        ["systemd-networkd.socket"]=1
        ["systemd-resolved.socket"]=1
        ["systemd"]=1
        ["systemd-stub"]=1
        ["systemd-shutdown"]=1
        ["systemd-reboot"]=1
        ["systemd-poweroff"]=1
        ["systemd-halt"]=1
        ["systemd-kexec"]=1
    )

    while IFS= read -r unit; do
        [[ -z "${unit}" ]] && continue

        [[ -n "${skip_units[${unit}]:-}" ]] && continue

        if [[ ! "${unit}" =~ \.(service|target|socket|timer)$ ]]; then
            continue
        fi

        if [[ "${unit}" =~ ^systemd- ]] || \
           [[ "${unit}" == "getty@.service" ]] || \
           [[ "${unit}" == "serial-getty@.service" ]]; then
            continue
        fi

        local pkg=""
        local orig_unit="${unit}"
        unit="${unit%.service}"
        unit="${unit%.target}"
        unit="${unit%.timer}"
        unit="${unit%.socket}"
        unit="${unit%@*}"

        local svc_file=""
        for path in /usr/lib/systemd/system /etc/systemd/system; do
            for ext in service target timer socket; do
                if [[ -f "${path}/${unit}.${ext}" ]]; then
                    svc_file="${path}/${unit}.${ext}"
                    break 2
                fi
            done
        done
        if [[ -n "${svc_file}" ]]; then
            pkg=$(pacman -Qo "${svc_file}" 2>/dev/null | awk '{print $5}' | cut -d/ -f1) || true
        fi
        [[ -z "${pkg}" ]] && pkg="${unit}"

        local arch_repo=""
        arch_repo=$(pacman -Si "${pkg}" 2>/dev/null | grep 'Repository' | head -n1 | awk '{print $3}') || true

        local artix_repo=""
        case "${arch_repo}" in
            core) artix_repo="system" ;;
            extra) artix_repo="world" ;;
            multilib) artix_repo="lib32" ;;
            *) artix_repo="${arch_repo}" ;;
        esac

        local artix_pkg="${pkg}"
        local artix_ver=""
        if ! pacman -Si "${artix_pkg}" 2>/dev/null | grep -q 'Repository'; then
            local found=0
            for suffix in -openrc -runit -dinit -s6; do
                if pacman -Si "${pkg}${suffix}" 2>/dev/null | grep -q 'Repository'; then
                    artix_pkg="${pkg}${suffix}"
                    found=1
                    break
                fi
            done
            [[ $found -eq 0 ]] && artix_pkg="MISSING"
        fi

        if [[ "${artix_pkg}" != "MISSING" ]]; then
            artix_ver=$(pacman -Si "${artix_pkg}" 2>/dev/null | grep 'Version' | head -n1 | awk '{print $3}')
        fi

        local arch_ver=""
        arch_ver=$(pacman -Q "${pkg}" 2>/dev/null | awk '{print $2}') || true

        local status="migratable"
        [[ "${artix_pkg}" == "MISSING" ]] && status="no-artix-equivalent"
        [[ -n "${arch_ver}" && -n "${artix_ver}" && "${arch_ver}" != "${artix_ver}" ]] && status="version-mismatch"

        printf '%s|%s|%s|%s|%s|%s\n' \
            "${orig_unit}" "${pkg}" "${arch_ver}" "${artix_pkg}" "${artix_ver}" "${status}" >> "${ATA_MAP_CACHE}"
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