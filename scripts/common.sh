#!/usr/bin/env bash
set -Eeuo pipefail;

LOG_FILE="/tmp/artix-installer/install.log"
CHROOT_LOG="/mnt/var/log/artix-installer.log"
WARNING_LOG=""

_ensure_log_dirs() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    [[ -d /mnt ]] && mkdir -p "$(dirname "${CHROOT_LOG}")" 2>/dev/null || true
}

log_info() {
    _ensure_log_dirs
    printf '\e[1;34m[*] %s\e[0m\n' "$*" | tee -a "${LOG_FILE}" >&2
    [[ -d /mnt ]] && printf '[*] %s\n' "$*" >> "${CHROOT_LOG}" 2>/dev/null || true
}

log_warn() {
    _ensure_log_dirs
    printf '\e[1;33m[!] %s\e[0m\n' "$*" | tee -a "${LOG_FILE}" >&2
}

warn_collect() {
    local msg="${1}"
    WARNING_LOG="${WARNING_LOG}  - ${msg}\n"
    log_warn "${msg}"
}

log_error() {
    _ensure_log_dirs
    printf '\e[1;31m[✗] %s\e[0m\n' "$*" | tee -a "${LOG_FILE}" >&2
}

die() {
    local reason="${1:-unknown error}"
    log_error "${reason^}"
    exit 1
}

warn() {
    local message="${1:-warning}"
    log_warn "${message^}"
}

info() {
    local message="${1:-info}"
    log_info "${message}"
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die 'must be run as root'
}

require_internet() {
    if [[ -d /mnt/repo || -d /run/artix/repo ]]; then
        export ALLOW_OFFLINE=yes
        log_info "Local repository detected – enabling offline mode"
        return 0
    fi

    if command -v dig &>/dev/null; then
        if dig +short +timeout=3 cloudflare.com &>/dev/null; then
            return 0
        fi
    elif command -v nslookup &>/dev/null; then
        if nslookup -timeout=3 cloudflare.com &>/dev/null; then
            return 0
        fi
    elif command -v curl &>/dev/null; then
        if curl -fsSL --max-time 5 https://1.1.1.1 &>/dev/null; then
            return 0
        fi
    elif ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        return 0
    fi

    if [[ "${ALLOW_OFFLINE:-no}" == "yes" ]]; then
        warn 'continuing in offline mode'
        return 0
    fi

    warn 'no internet connection detected'

    if ! tui_yesno "Network Setup" "No internet detected. Configure network now?"; then
        recoverable_error 'no internet connection'
        return 1
    fi

    local net_type
    net_type=$(tui_menu "Network Type" "Select connection type:" \
        "DHCP (automatic)" \
        "WiFi" \
        "Static IP") || { recoverable_error 'no internet connection'; return 1; }

    case "${net_type}" in
        *DHCP*)
            dhcpcd -q 2>/dev/null || true
            ;;
        *WiFi*)
            command -v iwctl &>/dev/null || pacman -S --noconfirm iwd
            iwctl station list
            local wifi_iface wifi_ssid wifi_pass
            wifi_iface=$(iwctl station list | grep -oP 'wlan\S+' | head -n1)
            [[ -n "${wifi_iface}" ]] || wifi_iface=$(tui_input "WiFi" "Enter wireless interface:" "wlan0")
            wifi_ssid=$(tui_input "WiFi" "Enter SSID:")
            wifi_pass=$(tui_password "WiFi" "Enter passphrase:")
            iwctl station "${wifi_iface}" connect "${wifi_ssid}" --passphrase "${wifi_pass}" || {
                log_warn "WiFi connection failed."
                recoverable_error 'no internet connection'
                return 1
            }
            ;;
        *Static*)
            local ip mask gw dns
            ip=$(tui_input "Static IP" "IP address:" "192.168.1.100")
            mask=$(tui_input "Static IP" "Netmask (CIDR):" "24")
            gw=$(tui_input "Static IP" "Gateway:" "192.168.1.1")
            dns=$(tui_input "Static IP" "DNS server:" "1.1.1.1")
            local iface
            iface=$(ip route | grep default | grep -oP 'dev \K\S+' | head -n1)
            [[ -n "${iface}" ]] || iface=$(tui_input "Static IP" "Interface:" "eth0")
            ip addr add "${ip}/${mask}" dev "${iface}" 2>/dev/null || true
            ip route add default via "${gw}" 2>/dev/null || true
            echo "nameserver ${dns}" > /etc/resolv.conf
            ;;
    esac

    if command -v curl &>/dev/null; then
        if curl -fsSL --max-time 5 https://1.1.1.1 &>/dev/null; then
            log_info "Network configured successfully."
            return 0
        fi
    elif ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        log_info "Network configured successfully."
        return 0
    fi

    recoverable_error 'network configuration failed. No internet connection'
    return 1
}

get_partition_name() {
    local disk="${1}"
    local partition="${2}"
    if [[ "${disk}" =~ ^/dev/(nvme|mmcblk|loop) ]]; then
        printf '%sp%s\n' "${disk}" "${partition}"
    else
        printf '%s%s\n' "${disk}" "${partition}"
    fi
}

command_exists() {
    command -v "${1}" &>/dev/null
}

ensure_dirs() {
    mkdir -p /tmp/artix-installer/{stages,logs}
}

validate_display_stack() {
    local x_stack
    x_stack="$(state_get X_STACK xorg | tr -d '[:space:]')"

    if [[ "${x_stack}" != "xorg" ]]; then
        return 0
    fi

    if artix-chroot /mnt pacman -Qq xlibre-xserver &>/dev/null; then
        log_error "xlibre-xserver is installed but Xorg was selected."
        log_error "Remove xlibre-xserver manually or perform a clean installation."
        return 1
    fi
    return 0
}

check_disk_space() {
    local required_gb="${1:-5}" target="${2:-/mnt}"
    local avail_gb
    avail_gb=$(df -BG --output=avail "${target}" 2>/dev/null | tail -1 | tr -d ' G')
    if [[ -n "${avail_gb}" && "${avail_gb}" -lt "${required_gb}" ]]; then
        log_error "Low disk space on ${target}: ${avail_gb}GB available, ${required_gb}GB needed"
        if ! tui_yesno "Low Disk Space" "Only ${avail_gb}GB free on ${target}. Continue anyway?"; then
            recoverable_error "Not enough disk space"
        fi
    fi
}

xtrace_safe() {
    ( unset BASH_XTRACEFD; "$@" )
}

retry_command() {
    local desc="${1}"; shift
    local retries=3 delay=5
    for ((i=1; i<=retries; i++)); do
        local output
        output=$("$@" 2>&1)
        local rc=$?
        if [[ ${rc} -eq 0 ]]; then
            return 0
        fi
        if echo "${output}" | grep -qi "signature.*invalid\|signature.*corrupted\|PGP.*invalid\|unknown trust"; then
            log_error "${desc} failed with signature errors — keyring may be corrupted"
            recoverable_error "${desc} failed — signature verification error. Keyring may need repair."
            return 1
        fi
        if echo "${output}" | grep -qi "corrupted.*package\|invalid or corrupted"; then
            log_error "${desc} failed with corrupted package — clearing cache and refreshing mirrors"
            rm -f /var/cache/pacman/pkg/*.part /var/cache/pacman/pkg/*.tar.zst 2>/dev/null || true
            pacman -Syy --noconfirm 2>/dev/null || true
            recoverable_error "${desc} failed — package may be corrupted. Mirrors refreshed."
            return 1
        fi
        if echo "${output}" | grep -qi "could not resolve\|no address\|connection refused\|could not connect\|failed retrieving"; then
            log_warn "${desc} failed with network errors (attempt ${i}/${retries})"
        else
            log_warn "${desc} failed (attempt ${i}/${retries})"
        fi
        if [[ ${i} -lt ${retries} ]]; then
            sleep "${delay}"
            delay=$((delay * 2))
        fi
    done
    log_error "${desc} failed after ${retries} attempts"
    return 1
}

clean_pacman_lock() {
    local lockfile="${1:-/mnt/var/lib/pacman/db.lck}"
    if [[ -f "${lockfile}" ]]; then
        log_warn "Stale pacman lock found: ${lockfile}"
        if tui_yesno "Pacman Lock" "A previous pacman transaction appears interrupted. Remove the lock and continue?"; then
            rm -f "${lockfile}"
            log_info "Pacman lock removed"
        fi
    fi
}

curl_resume() {
    local url="${1}" out="${2}"
    if [[ -f "${out}" ]]; then
        local remote_size local_size
        remote_size=$(curl -sI "${url}" | grep -i content-length | awk '{print $2}' | tr -d '\r')
        local_size=$(stat -c%s "${out}" 2>/dev/null || echo 0)
        if [[ -n "${remote_size}" && "${local_size}" -lt "${remote_size}" ]]; then
            log_info "Resuming download: ${out} (${local_size}/${remote_size} bytes)"
            curl -C - -L -o "${out}" "${url}" || { log_error "Resume failed: ${url}"; return 1; }
            return 0
        fi
    fi
    curl -L -o "${out}" "${url}" || { log_error "Download failed: ${url}"; return 1; }
    return 0
}

recoverable_error() {
    local msg="${1}"
    log_error "${msg}"
    while true; do
        local action
        action=$(tui_menu "Error" "${msg}" \
            "Retry" \
            "Retry with Debug Mode (writes detailed log)" \
            "Refresh mirrors and retry" \
            "Update ArtixForge and retry" \
            "Abort") || exit 1

        case "${action}" in
            "Retry")
                return 0
                ;;
            "Retry with Debug"*)
                export ARTIX_DEBUG='true'
                exec 19> "${BASE_DIR}/artix-debug.log"
                export BASH_XTRACEFD=19
                export PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
                set -x
                log_info "Debug mode enabled — retrying..."
                return 0
                ;;
            "Refresh mirrors"*)
                log_info "Refreshing mirrors and retrying..."
                if [[ -f /etc/pacman.d/mirrorlist.orig ]]; then
                    cp /etc/pacman.d/mirrorlist.orig /etc/pacman.d/mirrorlist
                fi
                pacman -Syy --noconfirm 2>/dev/null || true
                return 0
                ;;
            "Update ArtixForge"*)
                log_info "Updating ArtixForge from GitHub..."
                local update_dir="/tmp/artixforge-update"
                rm -rf "${update_dir}"
                git clone --depth 1 https://github.com/realvolk/ArtixForge.git "${update_dir}" || {
                    log_warn "Update failed – check network"
                    continue
                }
                cp -a "${update_dir}/." "${BASE_DIR}/"
                rm -rf "${update_dir}"
                log_info "ArtixForge updated. Restarting installer – use Resume to continue."
                exec sudo "${BASE_DIR}/install"
                ;;
            "Abort")
                die "Installation aborted by user"
                ;;
        esac
    done
}