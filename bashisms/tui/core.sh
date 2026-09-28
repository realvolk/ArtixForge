#!/usr/bin/env bash
set -Eeuo pipefail

LAPKA_THEME="${LAPKA_THEME:-}"
GUM_TITLE_COLOR="${GUM_TITLE_COLOR:-212}"
GUM_ACCENT_COLOR="${GUM_ACCENT_COLOR:-34}"

LOG_FILE="/tmp/artix-installer/install.log"
CHROOT_LOG="/mnt/var/log/artix-installer.log"

_tui_find_bin() {
    if [[ -n "${TUI_BIN:-}" ]] && [[ -x "${TUI_BIN}" ]]; then
        return 0
    fi
    if [[ -n "${BASE_DIR:-}" ]] && [[ -x "${BASE_DIR}/bashisms/bin/tui" ]]; then
        TUI_BIN="${BASE_DIR}/bashisms/bin/tui"
        return 0
    fi
    local script_dir
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${script_dir}/../bin/tui" ]]; then
        TUI_BIN="${script_dir}/../bin/tui"
        return 0
    fi
    if command -v tui >/dev/null 2>&1; then
        TUI_BIN="$(command -v tui)"
        return 0
    fi
    return 1
}

_tui_find_bin || {
    printf '\e[1;31m[✗] tui binary not found — checked $TUI_BIN, $BASE_DIR/bashisms/bin/tui, script-relative ../bin/tui, and PATH\e[0m\n' >&2
    exit 1
}

_ensure_log_dirs() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    [[ -d /mnt ]] && mkdir -p "$(dirname "${CHROOT_LOG}")" 2>/dev/null || true
}

theme_ansi() {
    local gum_code="${1:-212}"
    case "${gum_code}" in
        212) printf '\e[38;5;212m' ;;
        39)  printf '\e[38;5;39m' ;;
        245) printf '\e[38;5;245m' ;;
        250) printf '\e[38;5;250m' ;;
        3)   printf '\e[38;5;3m' ;;
        34)  printf '\e[38;5;34m' ;;
        117) printf '\e[38;5;117m' ;;
        196) printf '\e[38;5;196m' ;;
        255) printf '\e[38;5;255m' ;;
        11)  printf '\e[38;5;11m' ;;
        *)   printf '\e[38;5;%sm' "${gum_code}" ;;
    esac
}

log_info() {
    local msg="${1}"
    local colour
    colour=$(theme_ansi "${GUM_ACCENT_COLOR:-34}")
    _ensure_log_dirs
    printf '%s[*] %s\e[0m\n' "${colour}" "${msg}" | tee -a "${LOG_FILE}" >&2
    [[ -d /mnt ]] && printf '[*] %s\n' "${msg}" >> "${CHROOT_LOG}" 2>/dev/null || true
}

log_warn() {
    local msg="${1}"
    local colour
    colour=$(theme_ansi "${GUM_TITLE_COLOR:-212}")
    _ensure_log_dirs
    printf '%s[!] %s\e[0m\n' "${colour}" "${msg}" | tee -a "${LOG_FILE}" >&2
    [[ -d /mnt ]] && printf '[!] %s\n' "${msg}" >> "${CHROOT_LOG}" 2>/dev/null || true
}

log_error() {
    local msg="${1}"
    _ensure_log_dirs
    printf '\e[1;31m[✗] %s\e[0m\n' "${msg}" | tee -a "${LOG_FILE}" >&2
}

tui_msg() {
    local title="${1}" msg="${2}"
    "${TUI_BIN}" msg "${title}" "${msg}" </dev/tty
}

tui_yesno() {
    local title="${1}" msg="${2}"
    "${TUI_BIN}" yesno "${title}" "${msg}" </dev/tty
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}" result
    result=$("${TUI_BIN}" input "${title}" "${msg}" --default "${default}" </dev/tty) || true
    printf '%s' "${result}"
}

tui_password() {
    local title="${1}" msg="${2}"
    "${TUI_BIN}" password "${title}" "${msg}" </dev/tty
}

tui_msg_quick() {
    local title="${1}" msg="${2}"
    "${TUI_BIN}" msg "${title}" "${msg}" --no-wait </dev/tty
}

tui_password_confirm() {
    local title="${1:-Password}" prompt="${2:-Enter password:}" confirm_prompt="${3:-Confirm password:}"
    local pass confirm
    while true; do
        pass=$("${TUI_BIN}" password "${title}" "${prompt}" </dev/tty) || return 1
        [[ -n "${pass}" ]] || return 1
        confirm=$("${TUI_BIN}" password "${title}" "${confirm_prompt}" </dev/tty) || return 1
        [[ -n "${confirm}" ]] || return 1
        if [[ "${pass}" == "${confirm}" ]]; then
            printf '%s\n' "${pass}"
            return 0
        fi
        tui_msg_quick "Mismatch" "Passwords do not match. Try again."
    done
}

tui_menu() {
    local title="${1}" msg="${2}"
    shift 2
    "${TUI_BIN}" menu "${title}" "${msg}" "$@" </dev/tty
}

tui_menu_custom() {
    local title="${1}" msg="${2}"
    local height="${3:-15}"
    shift 3
    "${TUI_BIN}" menu "${title}" "${msg}" --height="${height}" "$@" </dev/tty
}

tui_checklist() {
    local title="${1}" msg="${2}"
    shift 2
    "${TUI_BIN}" checklist "${title}" "${msg}" "$@" </dev/tty
}

tui_filter() {
    local title="${1}" msg="${2}"
    shift 2
    "${TUI_BIN}" filter "${title}" "${msg}" "$@"
}

tui_radiolist() {
    tui_menu "$@"
}

tui_spin() {
    local title="${1}" cmd="${2}"
    "${TUI_BIN}" spin "${title}" -- bash -c "${cmd}" 2>&1 | while IFS= read -r line; do log_info "${line}"; done
}

tui_show_file() {
    local title="${1}" file="${2}"
    "${TUI_BIN}" show-file "${title}" "${file}"
}