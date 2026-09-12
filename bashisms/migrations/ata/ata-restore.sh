#!/usr/bin/env bash
set -Eeuo pipefail

ata_restore_user_data() {
    local backup_dir="${1}"
    log_info "Restoring user data..."

    while IFS= read -r user; do
        [[ -d "${backup_dir}/home/${user}" ]] || continue
        if [[ "$(realpath "${backup_dir}/home/${user}")" == "$(realpath "/home/${user}")" ]]; then
            log_info "  /home/${user} already in place — skipping"
            continue
        fi
        cp -a "${backup_dir}/home/${user}/" "/home/${user}/"
        chown -R "${user}:${user}" "/home/${user}" 2>/dev/null || true
        log_info "  Restored /home/${user}"
    done < /tmp/ata-users.txt

    local restore_paths=(
        ssh
        X11/xorg.conf.d
        lightdm
        sddm.conf.d
        polkit-1
        udev
        modprobe.d
        modules-load.d
        sysctl.d
        cron.d
        cron.daily
        cron.hourly
        cron.monthly
        cron.weekly
        iwd
        NetworkManager/system-connections
    )
    for path in "${restore_paths[@]}"; do
        local src="${backup_dir}/etc/${path}"
        local dst="/etc/${path}"
        if [[ -d "${src}" ]]; then
            if [[ "$(realpath "${src}" 2>/dev/null)" == "$(realpath "${dst}" 2>/dev/null)" ]]; then
                log_info "  /etc/${path} already in place — skipping"
                continue
            fi
            mkdir -p "$(dirname "${dst}")" 2>/dev/null || true
            cp -a "${src}" "${dst}"
            log_info "  Restored /etc/${path}"
        fi
    done

    log_info "User data restored."
}

ata_restore_flatpaks() {
    local backup_dir="${1}"
    if ! command -v flatpak >/dev/null 2>&1; then
        log_info "Flatpak not installed — skipping."
        return 0
    fi
    if [[ ! -f "${backup_dir}/lists/ata-flatpak.txt" ]]; then
        return 0
    fi

    log_info "Restoring flatpak remotes and apps..."
    if [[ -f "${backup_dir}/lists/flatpak-remotes.txt" ]]; then
        while IFS= read -r remote; do
            flatpak remote-add --if-not-exists "${remote}" 2>/dev/null || true
        done < "${backup_dir}/lists/flatpak-remotes.txt"
    fi

    if [[ -s "${backup_dir}/lists/ata-flatpak.txt" ]]; then
        log_info "Flatpak apps to reinstall saved to ${backup_dir}/lists/ata-flatpak.txt"
        log_info "Run: flatpak install --reinstall $(tr '\n' ' ' < ${backup_dir}/lists/ata-flatpak.txt)"
    fi
}

ata_restore_network_credentials() {
    local backup_dir="${1}"
    [[ -d "${backup_dir}/network-configs" ]] || return 0

    log_info "Restoring network credentials..."
    for d in /etc/NetworkManager/system-connections /var/lib/iwd /etc/wpa_supplicant; do
        mkdir -p "$d"
    done

    if [[ -d "${backup_dir}/network-configs/NetworkManager" ]]; then
        cp -a "${backup_dir}/network-configs/NetworkManager/"* /etc/NetworkManager/system-connections/ 2>/dev/null || true
        chmod -R 600 /etc/NetworkManager/system-connections/
    fi
    if [[ -d "${backup_dir}/network-configs/iwd" ]]; then
        cp -a "${backup_dir}/network-configs/iwd/"* /var/lib/iwd/ 2>/dev/null || true
        chmod -R 600 /var/lib/iwd/
    fi
    chmod -R 700 "${backup_dir}/network-configs"
}

ata_reinstall_aur() {
    local helper="${1}"
    log_info "Attempting AUR package reinstall with ${helper}..."

    if ! command -v "${helper}" >/dev/null 2>&1; then
        log_info "${helper} not found — installing..."
        pacman -S --noconfirm --needed base-devel git
        local tmpdir="/tmp/${helper}-build"
        rm -rf "${tmpdir}"
        git clone "https://aur.archlinux.org/${helper}.git" "${tmpdir}"
        (cd "${tmpdir}" && makepkg -si --noconfirm) || {
            log_warn "Failed to install ${helper} — AUR packages will need manual reinstall"
            return 1
        }
        rm -rf "${tmpdir}"
    fi

    local failed=0 success=0
    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        log_info "  Installing ${pkg}..."
        if "${helper}" -S --noconfirm "${pkg}" 2>/dev/null; then
            success=$((success + 1))
        else
            log_warn "  Failed: ${pkg}"
            failed=$((failed + 1))
        fi
    done < /tmp/ata-aur.txt

    log_info "AUR reinstall: ${success} succeeded, ${failed} failed"
    [[ ${failed} -gt 0 ]] && log_warn "${failed} AUR packages failed. Check the backup list and reinstall manually."
}

ata_rebuild_dkms() {
    if [[ -s /tmp/ata-dkms.txt ]]; then
        log_info "Rebuilding DKMS modules..."
        dkms autoinstall 2>/dev/null || log_warn "DKMS rebuild failed for some modules"
    fi
}

ata_migrate_homed_users() {
    local backup_dir="${1}"
    log_info "Migrating systemd-homed users..."

    if [[ ! -s /tmp/ata-homed.txt ]]; then
        log_info "No homed users found."
        return 0
    fi

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        local username uid shell storage
        username=$(echo "${line}" | awk '{print $1}')
        if command -v homectl >/dev/null 2>&1; then
            uid=$(homectl inspect "${username}" 2>/dev/null | grep 'Uid=' | cut -d= -f2)
            shell=$(homectl inspect "${username}" 2>/dev/null | grep 'Shell=' | cut -d= -f2)
            storage=$(homectl inspect "${username}" 2>/dev/null | grep 'Storage=' | cut -d= -f2)
        else
            uid=""
            shell=""
            storage=""
        fi

        [[ -z "${uid}" ]] && uid=$(id -u "${username}" 2>/dev/null || echo "")
        [[ -z "${uid}" ]] && { log_warn "  Cannot determine UID for ${username} — skipping"; continue; }
        [[ -z "${shell}" ]] && shell="/bin/bash"

        log_info "  Migrating user ${username} (UID ${uid})..."

        if [[ "${storage}" == "luks" ]]; then
            local pass
            pass=$(tui_password "Unlock ${username}" "Enter password for systemd-homed user ${username}:") || {
                log_warn "  Skipping ${username} — no password provided"
                continue
            }
            local homed_img="/home/${username}.home"
            local mapper="homed-${username}"
            if [[ -f "${homed_img}" ]]; then
                printf '%s' "${pass}" | cryptsetup luksOpen "${homed_img}" "${mapper}" - 2>/dev/null || {
                    log_warn "  Failed to unlock ${homed_img} — skipping"
                    continue
                }
                mkdir -p "/mnt/homed-${username}"
                mount "/dev/mapper/${mapper}" "/mnt/homed-${username}" 2>/dev/null || {
                    log_warn "  Failed to mount home image"
                    cryptsetup close "${mapper}" 2>/dev/null || true
                    continue
                }
                useradd -u "${uid}" -s "${shell}" -m "${username}" 2>/dev/null || true
                cp -a "/mnt/homed-${username}/" "/home/${username}/"
                chown -R "${username}:${username}" "/home/${username}"
                umount "/mnt/homed-${username}"
                cryptsetup close "${mapper}" 2>/dev/null || true
                rmdir "/mnt/homed-${username}"
                log_info "    Migrated LUKS home to /home/${username}"
            fi
        else
            useradd -u "${uid}" -s "${shell}" -m "${username}" 2>/dev/null || true
            log_info "    Created user ${username}"
        fi
    done < /tmp/ata-homed.txt
}

ata_convert_user_services() {
    log_info "Converting systemd --user services..."

    if [[ ! -s /tmp/ata-user-units.txt ]]; then
        log_info "  No user services found."
        return 0
    fi

    mkdir -p /etc/xdg/autostart
    : > /tmp/ata-unknown-user-services.txt

    while IFS= read -r unit; do
        [[ -z "${unit}" ]] && continue
        local name="${unit%.service}"
        log_warn "  ${unit} — manual setup required after migration"
        printf '%s\n' "${unit}" >> /tmp/ata-unknown-user-services.txt
    done < /tmp/ata-user-units.txt

    if [[ -s /tmp/ata-unknown-user-services.txt ]]; then
        log_warn "Some user services could not be auto-converted. List saved to ${backup_dir}/lists/ata-unknown-user-services.txt (if exists)"
        cp /tmp/ata-unknown-user-services.txt "${backup_dir}/lists/" 2>/dev/null || true
    fi
}

ata_convert_systemd_boot() {
    if [[ ! -s /tmp/ata-bootctl.txt ]]; then
        return 0
    fi

    log_info "systemd-boot detected — installing GRUB..."

    local esp_path
    esp_path=$(bootctl status 2>/dev/null | grep 'ESP:' | awk '{print $2}') || true
    [[ -z "${esp_path}" ]] && esp_path="/boot"

    pacman -S --noconfirm --needed grub efibootmgr 2>/dev/null || {
        log_warn "Failed to install GRUB — manual bootloader setup required"
        return 1
    }

    if [[ -d /sys/firmware/efi ]]; then
        grub-install --target=x86_64-efi --efi-directory="${esp_path}" --bootloader-id=ARTIX 2>/dev/null || {
            log_warn "grub-install failed — manual bootloader setup required"
            return 1
        }
    else
        local disk
        disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -n1)
        [[ -n "${disk}" ]] && grub-install --target=i386-pc "/dev/${disk}" 2>/dev/null
    fi

    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || log_warn "grub-mkconfig failed"

    if command -v efibootmgr >/dev/null 2>&1; then
        efibootmgr 2>/dev/null | grep -i 'Linux Boot Manager' | while IFS= read -r entry; do
            local bootnum="${entry#Boot}"
            bootnum="${bootnum%% *}"
            efibootmgr -b "${bootnum}" -B 2>/dev/null || true
        done
    fi

    log_info "GRUB installed. Old systemd-boot entries removed."
}