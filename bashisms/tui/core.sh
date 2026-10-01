#!/usr/bin/env bash
set -Eeuo pipefail

GUM_TITLE_COLOR="${GUM_TITLE_COLOR:-212}"
GUM_ACCENT_COLOR="${GUM_ACCENT_COLOR:-34}"

if [[ -z "${LAPKA_THEME:-}" ]]; then
    for _t in artixforge artix forge; do
        if [[ -r "/usr/share/artixforge/themes/${_t}.theme" ]]; then
            export LAPKA_THEME="/usr/share/artixforge/themes/${_t}.theme"
            break
        fi
    done
    unset _t
fi

LOG_FILE="/tmp/artix-installer/install.log"
CHROOT_LOG="/mnt/var/log/artix-installer.log"

TUI_BIN=""

_tui_find_bin() {
    if [[ -n "${TUI_BIN}" ]] && [[ -x "${TUI_BIN}" ]]; then
        return 0
    fi
    if [[ -n "${LAPKA_TUI:-}" ]] && [[ -x "${LAPKA_TUI}" ]]; then
        TUI_BIN="${LAPKA_TUI}"
        return 0
    fi
    if [[ -n "${BASHISMS_DIR:-}" ]] && [[ -x "${BASHISMS_DIR}/bin/tui-$(uname -m)" ]]; then
        TUI_BIN="${BASHISMS_DIR}/bin/tui-$(uname -m)"
        return 0
    fi
    if [[ -n "${BASHISMS_DIR:-}" ]] && [[ -x "${BASHISMS_DIR}/bin/tui" ]]; then
        TUI_BIN="${BASHISMS_DIR}/bin/tui"
        return 0
    fi
    if [[ -x "${XDG_CACHE_HOME:-${HOME:-/root}/.cache}/lapka/tui-$(uname -m)" ]]; then
        TUI_BIN="${XDG_CACHE_HOME:-${HOME:-/root}/.cache}/lapka/tui-$(uname -m)"
        return 0
    fi
    if [[ -x "/var/cache/artixforge/tui-$(uname -m)" ]]; then
        TUI_BIN="/var/cache/artixforge/tui-$(uname -m)"
        return 0
    fi
    if [[ -x /usr/local/bin/tui ]]; then
        TUI_BIN="/usr/local/bin/tui"
        return 0
    fi
    if command -v tui >/dev/null 2>&1; then
        TUI_BIN="$(command -v tui)"
        return 0
    fi
    return 1
}

_tui_require_bin() {
    if ! _tui_find_bin; then
        printf 'artix-installer: tui binary not found\n' >&2
        return 1
    fi
}

_term_reset() {
    stty sane 2>/dev/null || true
    if [[ -w /dev/tty ]]; then
        printf '\e[?1049l\e[0m\e[?25h' > /dev/tty 2>/dev/null || true
    fi
}

tui_session_begin() {
    if [[ -w /dev/tty ]]; then
        printf '\033[?1049h\033[H\033[2J' > /dev/tty
        export LAPKA_ALT_SCREEN=1
    fi
}

tui_session_end() {
    if [[ -w /dev/tty ]]; then
        printf '\033[?1049l' > /dev/tty
    fi
    unset LAPKA_ALT_SCREEN
}

_ensure_log_dirs() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    if [[ -d /mnt ]]; then
        mkdir -p "$(dirname "${CHROOT_LOG}")" 2>/dev/null || true
    fi
}

theme_ansi() {
    local code="${1:-212}"
    case "${code}" in
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
        *)   printf '\e[38;5;%sm' "${code}" ;;
    esac
}

log_info() {
    local msg="${1}"
    local colour
    colour=$(theme_ansi "${GUM_ACCENT_COLOR:-34}")
    _ensure_log_dirs
    printf '%s[*] %s\e[0m\n' "${colour}" "${msg}" | tee -a "${LOG_FILE}" >&2
    if [[ -d /mnt ]]; then
        printf '[*] %s\n' "${msg}" >> "${CHROOT_LOG}" 2>/dev/null || true
    fi
}

log_warn() {
    local msg="${1}"
    local colour
    colour=$(theme_ansi "${GUM_TITLE_COLOR:-212}")
    _ensure_log_dirs
    printf '%s[!] %s\e[0m\n' "${colour}" "${msg}" | tee -a "${LOG_FILE}" >&2
    if [[ -d /mnt ]]; then
        printf '[!] %s\n' "${msg}" >> "${CHROOT_LOG}" 2>/dev/null || true
    fi
}

log_error() {
    local msg="${1}"
    _ensure_log_dirs
    printf '\e[1;31m[✗] %s\e[0m\n' "${msg}" | tee -a "${LOG_FILE}" >&2
}

tui_msg() {
    local title="${1}" msg="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" msg "${title}" "${msg}" "$@" </dev/tty
}

tui_yesno() {
    local title="${1}" msg="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" yesno "${title}" "${msg}" "$@" </dev/tty
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}"; shift 3 || shift $#
    _tui_require_bin || return 1
    "${TUI_BIN}" input "${title}" "${msg}" --default "${default}" "$@" </dev/tty
}

tui_password() {
    local title="${1}" msg="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" password "${title}" "${msg}" "$@" </dev/tty
}

tui_password_confirm() {
    local title="${1:-Password}" prompt="${2:-Enter password:}" confirm_prompt="${3:-Confirm password:}"
    shift $(( $# < 3 ? $# : 3 ))
    _tui_require_bin || return 1
    "${TUI_BIN}" password-confirm "${title}" "${prompt}" --confirm-prompt "${confirm_prompt}" "$@" </dev/tty
}

tui_menu() {
    local title="${1}" msg="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" menu "${title}" "${msg}" "$@" </dev/tty
}

tui_checklist() {
    local title="${1}" msg="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" checklist "${title}" "${msg}" "$@" </dev/tty
}

tui_filter() {
    local title="${1}" msg="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" filter "${title}" "${msg}" "$@"
}

tui_radiolist() { tui_menu "$@"; }

tui_show_file() {
    local title="${1}" file="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" show-file "${title}" "${file}" "$@" </dev/tty
}

tui_toast() {
    local msg="${1}"; shift
    _tui_require_bin || return 1
    "${TUI_BIN}" toast "${msg}" "$@"
}

tui_spin() {
    local title="${1}" cmd="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" spin "${title}" "Running..." "$@" -- bash -c "${cmd}"
}

tui_spin_argv() {
    local title="${1}"; shift
    _tui_require_bin || return 1
    "${TUI_BIN}" spin "${title}" "Running..." "$@"
}

tui_hub() {
    local in_file="${1}" out_file="${2}"; shift 2
    _tui_require_bin || return 1
    "${TUI_BIN}" hub --in="${in_file}" --out="${out_file}" "$@" </dev/tty
}

tui_hub_apply() {
    local in_file="${1}"; shift
    local out_file
    out_file="$(mktemp)" || { log_error "tui_hub_apply: mktemp failed"; return 1; }
    chmod 0600 "${out_file}"

    if ! tui_hub "${in_file}" "${out_file}" "$@"; then
        local rc=$?
        rm -f "${out_file}"
        return ${rc}
    fi

    local k v
    while IFS='=' read -r k v; do
        [[ -n "${k}" ]] || continue
        if [[ "${v}" == \'*\' ]]; then
            v="${v#\'}"
            v="${v%\'}"
            v="${v//"'\''"/\'}"
        fi
        state_set "${k}" "${v}"
    done < "${out_file}"

    rm -f "${out_file}"
    return 0
}

tui_run_interactive() {
    tui_session_end
    "$@"
    local rc=$?
    tui_session_begin
    return ${rc}
}