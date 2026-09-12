#!/usr/bin/env bash
set -Eeuo pipefail

GUM_TITLE_COLOR="${GUM_TITLE_COLOR:-212}"
GUM_ACCENT_COLOR="${GUM_ACCENT_COLOR:-34}"

LOG_FILE="/tmp/artix-installer/install.log"
CHROOT_LOG="/mnt/var/log/artix-installer.log"

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
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──"
    gum format "${msg}"
    gum confirm "Press Enter to continue" --affirmative="OK" --timeout=0 </dev/tty 2>/dev/null || true
}

tui_yesno() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──"
    gum format "${msg}"
    gum confirm </dev/tty
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}" result
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    result=$(gum input --value "${default}" --prompt "> " </dev/tty) || true
    printf '%s' "${result}"
}

tui_password() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum input --password --prompt "> " </dev/tty || true
}

tui_msg_quick() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──"
    gum format "${msg}"
}

tui_password_confirm() {
    local title="${1:-Password}" prompt="${2:-Enter password:}" confirm_prompt="${3:-Confirm password:}"
    local pass confirm
    while true; do
        gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
        pass=$(gum input --password --prompt "${prompt}: " </dev/tty) || true
        [[ -n "${pass}" ]] || return 1
        confirm=$(gum input --password --prompt "${confirm_prompt}: " </dev/tty) || true
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
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --height=15 "$@" </dev/tty
}

tui_menu_custom() {
    local title="${1}" msg="${2}"
    local height="${3:-15}"
    shift 3
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --height="${height}" "$@" </dev/tty
}

tui_checklist() {
    local title="${1}" msg="${2}"
    shift 2
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --no-limit --height=15 "$@" </dev/tty
}

tui_filter() {
    local title="${1}" msg="${2}"
    shift 2
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum filter --height=20 "$@"
}

tui_radiolist() {
    tui_menu "$@"
}

tui_spin() {
    local title="${1}" cmd="${2}"
    gum spin --spinner dot --title "${title}" -- bash -c "${cmd}" 2>&1 | while IFS= read -r line; do log_info "${line}"; done
}

tui_show_file() {
    local title="${1}" file="${2}"
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──"
    gum pager < "${file}"
}