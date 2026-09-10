#!/usr/bin/env bash
set -Eeuo pipefail

ata_convert_all() {
    ata_convert_network_credentials
    ata_convert_timers
    ata_convert_pam
    ata_convert_mkinitcpio
    ata_convert_mkinitcpio_presets
    ata_convert_resolv_conf
    ata_convert_pacman_hooks
    ata_convert_crypttab
    ata_convert_timesyncd
}

ata_convert_network_credentials() {
    log_info "Converting network credentials..."

    local found=0
    local wpa_conf=""
    local iface
    iface=$(ip -o link show | awk -F': ' '$2 ~ /^wl/ {print $2; exit}') || true
    [[ -z "$iface" ]] && iface="wlan0"
    wpa_conf="/etc/wpa_supplicant/wpa_supplicant-${iface}.conf"

    for f in /etc/systemd/network/*.network; do
        [[ -f "$f" ]] || continue
        local ssid psk
        ssid=$(grep -oP 'SSID=\K.*' "$f" 2>/dev/null || true)
        psk=$(grep -oP 'Password=\K.*' "$f" 2>/dev/null || true)
        if [[ -n "${ssid}" && -n "${psk}" ]]; then
            mkdir -p /etc/wpa_supplicant
            cat >> "$wpa_conf" <<WPA
network={
    ssid="${ssid}"
    psk="${psk}"
}
WPA
            chmod 600 "$wpa_conf"
            found=1
        fi
    done

    if [[ -d /var/lib/iwd ]]; then
        mkdir -p /var/lib/iwd
        cp -a /var/lib/iwd/*.psk /var/lib/iwd/ 2>/dev/null || true
        chmod -R 600 /var/lib/iwd/
        found=1
    fi

    if [[ -d /etc/NetworkManager/system-connections ]]; then
        mkdir -p /etc/NetworkManager/system-connections
        cp -a /etc/NetworkManager/system-connections/* /etc/NetworkManager/system-connections/ 2>/dev/null || true
        chmod -R 600 /etc/NetworkManager/system-connections/
        found=1
    fi

    [[ $found -eq 1 ]] && log_info "Network credentials converted."
}

ata_convert_timers() {
    log_info "Converting systemd timers to cron..."

    if [[ ! -s /tmp/ata-timers.txt ]]; then
        log_info "  No timers found."
        return 0
    fi

    mkdir -p /etc/cron.d
    local cronfile="/etc/cron.d/ata-migrated-timers"
    : > "${cronfile}"

    local converted=0 monotonic=0

    while IFS= read -r timer_unit; do
        [[ -z "${timer_unit}" ]] && continue

        local unit_config
        unit_config=$(systemctl cat "${timer_unit}" 2>/dev/null)
        if [[ -z "$unit_config" ]]; then
            continue
        fi

        local oncalendar onbootsec onunitactivesec service_unit
        oncalendar=$(echo "$unit_config" | grep 'OnCalendar=' | head -n1 | cut -d= -f2-)
        onbootsec=$(echo "$unit_config" | grep 'OnBootSec=' | head -n1 | cut -d= -f2-)
        onunitactivesec=$(echo "$unit_config" | grep 'OnUnitActiveSec=' | head -n1 | cut -d= -f2-)
        service_unit=$(echo "$unit_config" | grep 'Unit=' | head -n1 | cut -d= -f2)

        local cmd="${service_unit:-true}"

        if [[ -n "${oncalendar}" ]]; then
            local cron_expr
            cron_expr=$(ata_oncalendar_to_cron "${oncalendar}")
            if [[ -n "${cron_expr}" ]]; then
                printf '%s root %s\n' "${cron_expr}" "${cmd}" >> "${cronfile}"
                log_info "  Timer ${timer_unit} → cron (OnCalendar)"
                converted=$((converted + 1))
                continue
            fi
        fi

        if [[ -n "${onbootsec}" ]]; then
            local seconds
            seconds=$(ata_parse_time_seconds "${onbootsec}")
            if [[ -n "${seconds}" ]]; then
                printf '@reboot root sleep %s && %s\n' "${seconds}" "${cmd}" >> "${cronfile}"
                log_info "  Timer ${timer_unit} → @reboot + ${seconds}s (OnBootSec)"
                converted=$((converted + 1))
                monotonic=$((monotonic + 1))
                continue
            fi
        fi

        if [[ -n "${onunitactivesec}" ]]; then
            local seconds
            seconds=$(ata_parse_time_seconds "${onunitactivesec}")
            if [[ -n "${seconds}" ]]; then
                local safe_name="${timer_unit//[\/@]/-}"
                local wrapper_script="/etc/cron.d/ata-timer-${safe_name}.sh"
                cat > "${wrapper_script}" <<WRAPPER
#!/bin/bash
while true; do
    sleep ${seconds}
    ${cmd}
done
WRAPPER
                chmod +x "${wrapper_script}"
                printf '@reboot root %s &\n' "${wrapper_script}" >> "${cronfile}"
                log_info "  Timer ${timer_unit} → loop script (OnUnitActiveSec=${seconds}s)"
                converted=$((converted + 1))
                monotonic=$((monotonic + 1))
                continue
            fi
        fi

        log_warn "  Timer ${timer_unit} could not be converted"
    done < /tmp/ata-timers.txt

    if [[ ${converted} -gt 0 ]]; then
        chmod 644 "${cronfile}"
        log_info "  Converted ${converted} timers (${monotonic} monotonic)"
    else
        rm -f "${cronfile}"
    fi
}

ata_parse_time_seconds() {
    local time_str="${1}"
    time_str="${time_str// /}"
    local seconds=0
    local weeks=0 days=0 hours=0 mins=0 secs=0

    if [[ "${time_str}" =~ ([0-9]+)w ]]; then weeks="${BASH_REMATCH[1]}"; fi
    if [[ "${time_str}" =~ ([0-9]+)d ]]; then days="${BASH_REMATCH[1]}"; fi
    if [[ "${time_str}" =~ ([0-9]+)h ]]; then hours="${BASH_REMATCH[1]}"; fi
    if [[ "${time_str}" =~ ([0-9]+)min ]]; then mins="${BASH_REMATCH[1]}"; fi
    if [[ "${time_str}" =~ ([0-9]+)s ]]; then secs="${BASH_REMATCH[1]}"; fi
    if [[ "${time_str}" =~ ^([0-9]+)$ ]]; then secs="${BASH_REMATCH[1]}"; fi

    seconds=$((weeks * 604800 + days * 86400 + hours * 3600 + mins * 60 + secs))
    [[ ${seconds} -gt 0 ]] && echo "${seconds}" || echo ""
}

ata_oncalendar_to_cron() {
    local expr="${1}"
    case "${expr}" in
        daily|"*-*-* 00:00:00")       echo "0 0 * * *" ;;
        hourly|"*-*-* *:00:00")       echo "0 * * * *" ;;
        weekly|"Mon *-*-* 00:00:00")  echo "0 0 * * 1" ;;
        monthly|"*-*-01 00:00:00")    echo "0 0 1 * *" ;;
        "*-*-* *:*:*")
            local time="${expr##* }"
            local hour="${time%%:*}"
            local min="${time#*:}"; min="${min%%:*}"
            echo "${min} ${hour} * * *"
            ;;
        *)  echo "" ;;
    esac
}

ata_convert_pam() {
    log_info "Converting PAM modules..."
    if [[ ! -s /tmp/ata-pam-systemd.txt ]]; then
        log_info "No systemd PAM references found."
        return 0
    fi
    while IFS= read -r pamfile; do
        sed -i 's/pam_systemd\.so/pam_elogind.so/g' "${pamfile}"
        sed -i '/pam_systemd_home\.so/d' "${pamfile}"
        log_info "  Patched ${pamfile}"
    done < /tmp/ata-pam-systemd.txt
}

ata_convert_mkinitcpio() {
    log_info "Converting mkinitcpio hooks..."
    [[ ! -f /etc/mkinitcpio.conf ]] && return 0

    sed -i 's/\bsystemd\b/udev/g' /etc/mkinitcpio.conf
    sed -i 's/\bsd-encrypt\b/encrypt/g' /etc/mkinitcpio.conf
    sed -i 's/\bsd-vconsole\b/consolefont/g' /etc/mkinitcpio.conf
    sed -i 's/\bsd-lvm2\b/lvm2/g' /etc/mkinitcpio.conf

    if ! grep -q 'fsck' /etc/mkinitcpio.conf; then
        sed -i 's/\(filesystems\)/fsck \1/' /etc/mkinitcpio.conf
    fi
}

ata_convert_resolv_conf() {
    log_info "Fixing resolv.conf..."

    local resolved_active="no"
    if systemctl is-active systemd-resolved >/dev/null 2>&1 || [[ -L /etc/resolv.conf ]]; then
        resolved_active="yes"
    fi

    if [[ "${resolved_active}" == "yes" ]]; then
        systemctl stop systemd-resolved 2>/dev/null || true
        systemctl disable systemd-resolved 2>/dev/null || true

        local dns_choice
        dns_choice=$(tui_menu "DNS Resolver" \
"systemd-resolved was detected and must be replaced.

Choose a DNS provider for the migration:" \
            "Cloudflare (1.1.1.1)" \
            "Google (8.8.8.8)" \
            "Quad9 (9.9.9.9)" \
            "Copy from backup" \
            "Enter custom DNS") || dns_choice="Cloudflare"

        case "${dns_choice}" in
            *Cloudflare*)
                printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' > /etc/resolv.conf.tmp
                ;;
            *Google*)
                printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf.tmp
                ;;
            *Quad9*)
                printf 'nameserver 9.9.9.9\nnameserver 149.112.112.112\n' > /etc/resolv.conf.tmp
                ;;
            *backup*)
                if [[ -n "${resolv_backup:-}" ]]; then
                    printf '%s\n' "${resolv_backup}" > /etc/resolv.conf.tmp
                else
                    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf.tmp
                    log_warn "No backup available – using Cloudflare"
                fi
                ;;
            *custom*)
                local custom_dns
                custom_dns=$(tui_input "Custom DNS" "Enter DNS server IP:" "1.1.1.1") || custom_dns="1.1.1.1"
                printf 'nameserver %s\n' "${custom_dns}" > /etc/resolv.conf.tmp
                ;;
        esac

        mv -f /etc/resolv.conf.tmp /etc/resolv.conf
        log_info "DNS resolver configured. Edit /etc/resolv.conf if needed."
    fi
}

ata_convert_timesyncd() {
    log_info "Installing NTP replacement..."
    local init
    init=$(state_get INIT openrc)
    local installed=0
    case "${init}" in
        openrc)
            _pacman -S --noconfirm --needed ntp-openrc 2>/dev/null && installed=1
            [[ ${installed} -eq 0 ]] && _pacman -S --noconfirm --needed chrony-openrc 2>/dev/null && installed=1
            ;;
        runit)
            _pacman -S --noconfirm --needed ntp-runit 2>/dev/null && installed=1
            [[ ${installed} -eq 0 ]] && _pacman -S --noconfirm --needed chrony-runit 2>/dev/null && installed=1
            ;;
        dinit)
            _pacman -S --noconfirm --needed ntp-dinit 2>/dev/null && installed=1
            [[ ${installed} -eq 0 ]] && _pacman -S --noconfirm --needed chrony-dinit 2>/dev/null && installed=1
            ;;
        s6)
            _pacman -S --noconfirm --needed ntp-s6 2>/dev/null && installed=1
            [[ ${installed} -eq 0 ]] && _pacman -S --noconfirm --needed chrony-s6 2>/dev/null && installed=1
            ;;
    esac

    if [[ ${installed} -eq 0 ]]; then
        log_warn "Could not install NTP package — time sync will need manual setup"
        return 0
    fi

    enable_service ntpd 2>/dev/null || enable_service ntp 2>/dev/null || enable_service chronyd 2>/dev/null || \
        log_warn "Could not enable NTP service — enable manually after boot"
}

ata_convert_pacman_hooks() {
    log_info "Disabling systemd-dependent pacman hooks..."
    if [[ -s /tmp/ata-systemd-hooks.txt ]]; then
        mkdir -p /etc/pacman.d/hooks.bak
        while IFS= read -r hook; do
            local name="${hook##*/}"
            mv "${hook}" "/etc/pacman.d/hooks.bak/${name}" 2>/dev/null || true
            log_info "  Moved ${name} to hooks.bak/"
        done < /tmp/ata-systemd-hooks.txt
    fi
}

ata_convert_crypttab() {
    log_info "Converting crypttab to kernel parameters..."
    if [[ ! -f /tmp/ata-crypttab.txt ]]; then
        return 0
    fi
    while IFS= read -r line; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        local name device uuid
        name=$(echo "${line}" | awk '{print $1}')
        device=$(echo "${line}" | awk '{print $2}')
        device=$(blkid -U "${device#UUID=}" 2>/dev/null || echo "${device}")
        uuid=$(blkid -s UUID -o value "${device}" 2>/dev/null || true)
        if [[ -n "${uuid}" ]]; then
            if ! grep -q "cryptdevice=UUID=${uuid}" /etc/default/grub 2>/dev/null; then
                sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 cryptdevice=UUID=${uuid}:${name}\"|" /etc/default/grub
                log_info "  Added cryptdevice=${uuid}:${name} to GRUB"
            fi
        fi
    done < /tmp/ata-crypttab.txt
}