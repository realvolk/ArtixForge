#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${ROOT:-/mnt}"

repair_fstab() {
    local issues
    issues=$(state_get FSTAB_ISSUES none)
    if [[ "${issues}" == "missing" ]]; then
        log_warn "fstab is missing. Regenerating..."
        if tui_yesno "Repair fstab" "Regenerate fstab from current mounts?"; then
            fstabgen -U "${ROOT}" > "${ROOT}/etc/fstab"
            log_info "fstab regenerated."
        fi
    elif [[ "${issues}" != "none" ]]; then
        log_warn "fstab has stale UUIDs: ${issues}"
        if tui_yesno "Repair fstab" "Regenerate fstab to fix UUIDs?"; then
            fstabgen -U "${ROOT}" > "${ROOT}/etc/fstab"
            log_info "fstab regenerated."
        fi
    fi
}

_kernel_pkg() {
    local choice="${1:-linux}"

    case "${choice}" in
        tkg|linux-custom)
            printf '%s\n' ""
            return 0
            ;;
    esac

    local main headers
    main="${KERNEL_PACKAGES[${choice}]:-}"
    [[ -n "${main}" ]] || main="linux"

    headers="$(resolve_kernel_headers "${choice}" 2>/dev/null || true)"
    [[ -n "${headers}" ]] || headers="${main}-headers"

    printf '%s %s\n' "${main}" "${headers}"
}

repair_boot() {
    local issues
    issues=$(state_get BOOT_ISSUES none)

    if [[ "${issues}" =~ no-kernel ]]; then
        if tui_yesno "Reinstall kernel" "Reinstall kernel?"; then
            local kpkg
            kpkg=$(_kernel_pkg "$(state_get KERNEL_CHOICE linux)")
            if [[ -n "${kpkg}" ]]; then
                pkg_install ${kpkg}
            else
                log_warn "No installable kernel package for '$(state_get KERNEL_CHOICE)' — TKG and custom kernels must be rebuilt, not reinstalled"
            fi
        fi
    fi
    if [[ "${issues}" =~ no-initramfs ]]; then
        if tui_yesno "Regenerate initramfs" "Run mkinitcpio?"; then
            artix-chroot "${ROOT}" mkinitcpio -P
        fi
    fi
    if [[ "${issues}" =~ no-init ]]; then
        log_warn "/sbin/init missing."
        local init
        init=$(detect_init 2>/dev/null || state_get INIT openrc)
        if tui_yesno "Repair init" "Create /sbin/init symlink to ${init}?"; then
            artix-chroot "${ROOT}" ln -sf "/usr/bin/${init}" /sbin/init
            log_info "Init symlink created."
        fi
    fi
    if [[ "${issues}" =~ no-efi-entry ]] && [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "uefi" ]]; then
        if tui_yesno "Reinstall bootloader" "Reinstall $(state_get BOOTLOADER)?"; then
            configure_bootloader
        fi
    fi
    if [[ "${issues}" =~ no-uki ]] && [[ "$(state_get ARTIX_BOOT_MODE uefi)" == "uefi" ]]; then
        repair_uki
    fi
    if [[ "${issues}" =~ missing-cryptdevice ]]; then
        if tui_yesno "Repair cmdline" "Regenerate bootloader config?"; then
            configure_bootloader
        fi
    fi
    if [[ "${issues}" =~ missing-encrypt-hook ]]; then
        if tui_yesno "Repair hooks" "Add encrypt hook?"; then
            artix-chroot "${ROOT}" sed -i '/^HOOKS=/s/\(block\)/\1 encrypt/' /etc/mkinitcpio.conf
            artix-chroot "${ROOT}" mkinitcpio -P
        fi
    fi
    if [[ "${issues}" =~ btrfs-wrong-subvolume ]]; then
        repair_btrfs_subvolume "${issues}"
    fi

    repair_seat_manager
}

repair_btrfs_subvolume() {
    local issues="${1}"
    local expected_subvol
    expected_subvol=$(grep -oP 'btrfs-wrong-subvolume:expected=\K[^,]*' <<< "${issues}")
    [[ -n "${expected_subvol}" ]] || expected_subvol="@"

    log_warn "btrfs: system files are at the top level, but cmdline expects subvol=${expected_subvol}"

    tui_msg "btrfs Layout Mismatch" \
"Your system was installed to the btrfs top-level subvolume,
but the boot cmdline expects subvol=${expected_subvol}.

This usually means the installer forgot to switch into the
subvolume before writing files.

Two repair options:
  • Move the files into ${expected_subvol} and clean the top level
  • Rewrite the boot cmdline to not use subvol= at all"

    local method
    method=$(tui_menu "btrfs Repair" "Choose repair approach:" \
        "Move files into ${expected_subvol}" \
        "Remove subvol= from cmdline" \
        "Cancel") || return 0

    case "${method}" in
        "Move files"*)
            _repair_btrfs_move_to_subvol "${expected_subvol}"
            ;;
        "Remove subvol"*)
            _repair_btrfs_remove_subvol_flag
            ;;
    esac
}

_repair_btrfs_move_to_subvol() {
    local subvol="${1}"

    local root_dev
    root_dev=$(findmnt -no SOURCE "${ROOT}" 2>/dev/null || echo "")
    [[ -n "${root_dev}" ]] || {
        log_error "Cannot determine root device for ${ROOT}"
        return 1
    }

    umount -R "${ROOT}" 2>/dev/null || {
        log_error "Cannot unmount ${ROOT} — something is still using it"
        return 1
    }

    local work_dir="/tmp/btrfs-work.$$"
    mkdir -p "${work_dir}"

    mount "${root_dev}" "${work_dir}" || {
        log_error "Failed to mount top level for restructuring"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    }

    if [[ ! -d "${work_dir}/${subvol}" ]]; then
        log_error "Subvolume ${subvol} does not exist on disk"
        umount "${work_dir}"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    fi

    log_info "Moving files into ${subvol}..."
    local entry
    for entry in bin boot dev etc home lib lib64 mnt opt proc root run sbin srv sys tmp usr var crypto_keyfile.bin; do
        [[ -e "${work_dir}/${entry}" ]] || continue
        [[ "${entry}" == "${subvol}" ]] && continue
        [[ "${entry}" == "@home" ]] && continue
        [[ "${entry}" == "@"* ]] && continue
        mv "${work_dir}/${entry}" "${work_dir}/${subvol}/" 2>/dev/null || \
            log_warn "Failed to move ${entry}"
    done

    umount "${work_dir}"
    rmdir "${work_dir}" 2>/dev/null || true

    log_info "Files moved into ${subvol}. Remounting target..."
    mount -o "subvol=${subvol}" "${root_dev}" "${ROOT}" || {
        log_error "Failed to remount after move"
        return 1
    }
    log_info "btrfs restructuring complete."
}

_repair_btrfs_move_to_subvol() {
    local subvol="${1}"

    local root_dev
    root_dev=$(findmnt -no SOURCE "${ROOT}" 2>/dev/null || echo "")
    [[ -n "${root_dev}" && -b "${root_dev}" ]] || {
        log_error "Cannot determine root device for ${ROOT}"
        return 1
    }

    local work_dir="/tmp/btrfs-work.$$"
    mkdir -p "${work_dir}" || {
        log_error "Cannot create work directory"
        return 1
    }

    local original_opts
    original_opts=$(findmnt -no OPTIONS "${ROOT}" 2>/dev/null || echo "")

    umount -R "${ROOT}" 2>/dev/null || {
        log_error "Cannot unmount ${ROOT} — something is still using it"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    }

    mount "${root_dev}" "${work_dir}" || {
        log_error "Failed to mount top level for restructuring — attempting remount of target"
        mount "${root_dev}" "${ROOT}" 2>/dev/null || \
            log_error "CRITICAL: target is unmounted and could not be remounted"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    }

    if [[ ! -d "${work_dir}/${subvol}" ]]; then
        log_error "Subvolume ${subvol} does not exist on disk — aborting"
        umount "${work_dir}"
        mount "${root_dev}" "${ROOT}" 2>/dev/null || log_error "CRITICAL: failed to remount target"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    fi

    if [[ -f "${work_dir}/${subvol}/etc/passwd" ]]; then
        log_info "Subvolume ${subvol} already contains a system — nothing to move"
        umount "${work_dir}"
        mount -o "subvol=${subvol}" "${root_dev}" "${ROOT}" 2>/dev/null || \
            log_error "CRITICAL: failed to remount target"
        rmdir "${work_dir}" 2>/dev/null || true
        return 0
    fi

    log_info "Verifying all entries can be moved..."
    local -a to_move=()
    local entry
    for entry in bin boot dev etc home lib lib64 mnt opt proc root run sbin srv sys tmp usr var crypto_keyfile.bin; do
        [[ -e "${work_dir}/${entry}" ]] || continue
        [[ "${entry}" == "${subvol}" ]] && continue
        [[ "${entry}" == "@home" ]] && continue
        [[ "${entry}" == "@"* ]] && continue
        to_move+=("${entry}")
    done

    if [[ ${#to_move[@]} -eq 0 ]]; then
        log_warn "No entries found to move — aborting"
        umount "${work_dir}"
        mount "${root_dev}" "${ROOT}" 2>/dev/null || log_error "CRITICAL: failed to remount target"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    fi

    log_info "Moving ${#to_move[@]} entries into ${subvol}..."
    local -a moved=()
    local failed=0

    for entry in "${to_move[@]}"; do
        if mv "${work_dir}/${entry}" "${work_dir}/${subvol}/"; then
            moved+=("${entry}")
        else
            log_warn "Failed to move ${entry}"
            failed=1
        fi
    done

    if [[ ${failed} -eq 1 ]]; then
        log_warn "Some entries could not be moved — attempting to restore"
        for entry in "${moved[@]}"; do
            mv "${work_dir}/${subvol}/${entry}" "${work_dir}/" 2>/dev/null || \
                log_error "CRITICAL: could not restore ${entry}"
        done
        umount "${work_dir}"
        mount "${root_dev}" "${ROOT}" 2>/dev/null || log_error "CRITICAL: failed to remount target"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    fi

    if [[ ! -f "${work_dir}/${subvol}/etc/passwd" ]]; then
        log_error "Post-move validation failed: ${subvol}/etc/passwd missing — attempting to restore"
        for entry in "${moved[@]}"; do
            mv "${work_dir}/${subvol}/${entry}" "${work_dir}/" 2>/dev/null || \
                log_error "CRITICAL: could not restore ${entry}"
        done
        umount "${work_dir}"
        mount "${root_dev}" "${ROOT}" 2>/dev/null || log_error "CRITICAL: failed to remount target"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    fi

    sync
    umount "${work_dir}" || {
        log_error "Failed to unmount work directory — target may be inconsistent"
        rmdir "${work_dir}" 2>/dev/null || true
        return 1
    }
    rmdir "${work_dir}" 2>/dev/null || true

    log_info "Remounting target at subvol=${subvol}..."
    mount -o "subvol=${subvol}" "${root_dev}" "${ROOT}" || {
        log_error "CRITICAL: files moved successfully but target could not be remounted"
        log_error "Mount manually with: mount -o subvol=${subvol} ${root_dev} ${ROOT}"
        return 1
    }

    if [[ ! -f "${ROOT}/etc/passwd" ]]; then
        log_error "Post-remount validation failed: ${ROOT}/etc/passwd missing"
        return 1
    fi

    log_info "btrfs restructuring complete — system files are now in ${subvol}"
    return 0
}

repair_uki() {
    if [[ "$(state_get GENERATE_UKI no)" != "yes" ]]; then
        return 0
    fi

    local uki_dir="${ROOT}/boot/efi/EFI/Linux"
    local uki_file=""

    if [[ -d "${uki_dir}" ]]; then
        uki_file=$(compgen -G "${uki_dir}/artix-*.efi" 2>/dev/null | head -n1)
    fi

    if [[ -z "${uki_file}" ]]; then
        log_warn "UKI is enabled but no UKI file found."
        if tui_yesno "Repair UKI" "Regenerate UKI and EFI boot entry?"; then
            if ! artix-chroot "${ROOT}" command -v ukify &>/dev/null; then
                log_warn "ukify not found — install eukify package first"
                return 1
            fi
            source "${SCRIPT_DIR}/install/bootloader.sh"
            configure_bootloader
        fi
    else
        log_info "UKI found: ${uki_file}"
    fi
}

repair_kernel() {
    log_info "Checking custom kernel health..."
    if [[ ! -f "${ROOT}/boot/vmlinuz-linux-custom" ]]; then
        log_warn "Custom kernel not found – nothing to repair."
        return 0
    fi

    if ! tui_yesno "Repair Custom Kernel" "Rebuild the custom kernel with the latest recipe?"; then
        return 0
    fi

    POWERUSER_DIR="${BASE_DIR}/bashisms/poweruser"

    if [[ ! -f "${POWERUSER_DIR}/recipes/linux.sh" ]]; then
        log_info "Fetching kernel recipe from community repository..."
        local list_url="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main/.LIST"
        local repo_base="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main"
        curl -fsSL "${list_url}" -o /tmp/artix-recipes.list 2>/dev/null
        local section
        section=$(awk -F'|' -v pkg="linux" '$1 == pkg {print $2}' /tmp/artix-recipes.list 2>/dev/null)
        if [[ -n "${section}" ]]; then
            curl -sL "${repo_base}/${section}/linux.sh" -o "${POWERUSER_DIR}/recipes/linux.sh"
        fi
        rm -f /tmp/artix-recipes.list
    fi

    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"

    local profile_name
    if [[ -f "${ROOT}/usr/share/artix-poweruser/profile/active" ]]; then
        profile_name=$(tr -d '[:space:]' < "${ROOT}/usr/share/artix-poweruser/profile/active")
    else
        profile_name="default"
    fi

    export POWERUSER_PROFILE="${profile_name}"
    load_profile "${profile_name}"

    load_recipe linux
    build_package linux

    if [[ -f "${ROOT}/boot/vmlinuz-linux-custom" ]]; then
        log_info "Custom kernel rebuilt successfully."
        artix-chroot "${ROOT}" mkinitcpio -P 2>/dev/null || log_warn "mkinitcpio failed"
        if [[ -d "${ROOT}/boot/grub" ]]; then
            artix-chroot "${ROOT}" grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warn "grub-mkconfig failed"
        fi
    else
        log_error "Kernel rebuild may have failed – check logs."
    fi
}

repair_seat_manager() {
    local detected seat_pkg service_name
    detected="$(state_get SEAT_MANAGER elogind)"

    if [[ "${detected}" == "seatd" ]]; then
        seat_pkg="seatd"
        service_name="seatd"
    else
        seat_pkg="elogind"
        service_name="logind"
    fi

    if ! pacman_root_has "${seat_pkg}"; then
        log_warn "${seat_pkg} is not installed — desktop sessions will fail."
        if tui_yesno "Repair Seat Manager" "Install ${seat_pkg} and enable the service?"; then
            artix-chroot "${ROOT}" pacman -S --noconfirm "${seat_pkg}" || {
                log_error "Failed to install ${seat_pkg}"
                return 1
            }
            if recovery_enable_service "${service_name}"; then
                log_info "${seat_pkg} installed and enabled."
            else
                log_warn "${seat_pkg} installed, but service could not be enabled — enable manually"
            fi
        fi
        return 0
    fi

    if ! service_exists "${service_name}"; then
        log_warn "${service_name} service not found for init: $(state_get INIT openrc)"
        return 0
    fi

    local init
    init="$(state_get INIT openrc)"
    local service_ok=0

    case "${init}" in
        openrc) [[ -L "${ROOT}/etc/runlevels/default/${service_name}" ]] || [[ -L "${ROOT}/etc/runlevels/boot/${service_name}" ]] && service_ok=1 ;;
        runit)  [[ -L "${ROOT}/etc/runit/runsvdir/default/${service_name}" ]] && service_ok=1 ;;
        dinit)  [[ -L "${ROOT}/etc/dinit.d/boot.d/elogind" ]] || [[ -L "${ROOT}/etc/dinit.d/boot.d/logind" ]] && service_ok=1 ;;
        s6)     [[ -d "${ROOT}/etc/s6/sv/${service_name}" ]] && service_ok=1 ;;
    esac

    if [[ ${service_ok} -eq 0 ]]; then
        log_warn "${service_name} service is not enabled — desktop sessions will fail."
        if tui_yesno "Enable Service" "Enable ${service_name} service for ${init}?"; then
            if recovery_enable_service "${service_name}"; then
                log_info "${service_name} enabled."
            else
                log_warn "Failed to enable ${service_name} — enable manually"
            fi
        fi
    fi
}

repair_dns() {
    local issues
    issues=$(state_get DNS_ISSUES none)
    [[ "${issues}" == "none" ]] && return 0

    if [[ "${issues}" =~ no-resolv-conf || "${issues}" =~ broken-resolv-symlink || "${issues}" =~ no-nameserver ]]; then
        log_warn "resolv.conf is missing or broken: ${issues}"
        if tui_yesno "Repair DNS" "Write a working /etc/resolv.conf?"; then
            local dns
            dns=$(tui_menu "DNS Server" "Choose a resolver:" \
                "Cloudflare (1.1.1.1)" \
                "Google (8.8.8.8)" \
                "Quad9 (9.9.9.9)" \
                "Custom") || return 0

            local primary secondary
            case "${dns}" in
                Cloudflare*) primary="1.1.1.1"; secondary="1.0.0.1" ;;
                Google*)     primary="8.8.8.8"; secondary="8.8.4.4" ;;
                Quad9*)      primary="9.9.9.9"; secondary="149.112.112.112" ;;
                Custom)
                    primary=$(tui_input "DNS" "Primary DNS:" "1.1.1.1") || return 0
                    secondary=$(tui_input "DNS" "Secondary DNS (optional):" "") || secondary=""
                    ;;
            esac

            [[ -L "${ROOT}/etc/resolv.conf" ]] && rm -f "${ROOT}/etc/resolv.conf"
            {
                printf 'nameserver %s\n' "${primary}"
                [[ -n "${secondary}" ]] && printf 'nameserver %s\n' "${secondary}"
            } > "${ROOT}/etc/resolv.conf"
            chmod 644 "${ROOT}/etc/resolv.conf"
            log_info "Wrote /etc/resolv.conf with ${primary}"
        fi
    fi

    if [[ "${issues}" =~ hosts-no-localhost || "${issues}" =~ hosts-no-ipv6-localhost || "${issues}" =~ no-etc-hosts ]]; then
        log_warn "hosts file is missing or incomplete: ${issues}"
        if tui_yesno "Repair hosts" "Restore the default /etc/hosts entries?"; then
            local hostname
            hostname=$(tr -d '[:space:]' < "${ROOT}/etc/hostname" 2>/dev/null || echo "artix")

            if [[ ! -f "${ROOT}/etc/hosts" ]]; then
                cat > "${ROOT}/etc/hosts" <<EOF
# /etc/hosts: Local Host Database
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
EOF
                log_info "Created /etc/hosts"
            else
                if ! grep -qE '^127\.0\.0\.1\s+localhost' "${ROOT}/etc/hosts"; then
                    printf '127.0.0.1   localhost\n' >> "${ROOT}/etc/hosts"
                fi
                if ! grep -qE '^::1\s+localhost' "${ROOT}/etc/hosts"; then
                    printf '::1         localhost\n' >> "${ROOT}/etc/hosts"
                fi
                log_info "Appended missing entries to /etc/hosts"
            fi
        fi
    fi
}

repair_hostname_drift() {
    local drift
    drift=$(state_get HOSTNAME_DRIFT none)
    [[ "${drift}" == "none" || "${drift}" == "no-hostname-file" ]] && return 0

    log_warn "Hostname drift detected: ${drift}"

    local file_host state_host
    file_host=$(grep -oP 'file=\K[^,]*' <<< "${drift}" || echo "")
    state_host=$(grep -oP 'state=\K.*' <<< "${drift}" || echo "")

    local choice
    choice=$(tui_menu "Hostname Drift" \
"Installed hostname: ${file_host:-unknown}
Recorded hostname:  ${state_host:-unknown}

Something renamed the system after installation." \
        "Use installed hostname (${file_host})" \
        "Use recorded hostname (${state_host})" \
        "Leave as-is") || return 0

    case "${choice}" in
        "Use installed"*)
            state_set HOSTNAME "${file_host}"
            log_info "State updated to match installed hostname: ${file_host}"
            ;;
        "Use recorded"*)
            printf '%s\n' "${state_host}" > "${ROOT}/etc/hostname"
            log_info "Wrote recorded hostname to /etc/hostname: ${state_host}"
            ;;
    esac
}