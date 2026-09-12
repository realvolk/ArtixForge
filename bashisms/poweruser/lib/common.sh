#!/usr/bin/env bash
set -Eeuo pipefail

die() {
    printf '\e[1;31m[✗] %s\e[0m\n' "${1:-fatal error}" >&2
    exit 1
}

log_info()  { printf '\e[1;34m[*] %s\e[0m\n' "$*" >&2; }
log_warn()  { printf '\e[1;33m[!] %s\e[0m\n' "$*" >&2; }
log_error() { printf '\e[1;31m[✗] %s\e[0m\n' "$*" >&2; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This command must be run as root"
}

check_disk_space() {
    local required_gb="${1:-5}" target="${2:-/mnt}"
    local avail_gb
    avail_gb=$(df -BG --output=avail "${target}" 2>/dev/null | tail -1 | tr -d ' G')
    if [[ -n "${avail_gb}" && "${avail_gb}" -lt "${required_gb}" ]]; then
        log_error "Low disk space on ${target}: ${avail_gb}GB available, ${required_gb}GB needed"
        if ! tui_yesno "Low Disk Space" "Only ${avail_gb}GB free on ${target}. Continue anyway?"; then
            die "Not enough disk space"
        fi
    fi
}

retry_command() {
    local desc="${1}"; shift
    local retries=3 delay=5
    for ((i=1; i<=retries; i++)); do
        if "$@"; then
            return 0
        fi
        log_warn "${desc} failed (attempt ${i}/${retries})"
        if [[ ${i} -lt ${retries} ]]; then
            sleep "${delay}"
            delay=$((delay * 2))
        fi
    done
    return 1
}

clean_pacman_lock() {
    local lockfile="${1:-/var/lib/pacman/db.lck}"
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