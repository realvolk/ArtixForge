#!/usr/bin/env bash
set -Eeuo pipefail

theme_ansi() {
    local gum_code="${1:-212}"
    case "${gum_code}" in
        212) printf '\e[38;5;212m' ;;  34)  printf '\e[38;5;34m' ;;
        39)  printf '\e[38;5;39m' ;;   117) printf '\e[38;5;117m' ;;
        245) printf '\e[38;5;245m' ;;  196) printf '\e[38;5;196m' ;;
        250) printf '\e[38;5;250m' ;;  255) printf '\e[38;5;255m' ;;
        3)   printf '\e[38;5;3m' ;;    11)  printf '\e[38;5;11m' ;;
        *)   printf '\e[38;5;%sm' "${gum_code}" ;;
    esac
}

die()   { printf '\e[1;31m[✗] %s\e[0m\n' "${1:-fatal error}" >&2; exit 1; }
log_info()  { local c; c=$(theme_ansi "${GUM_ACCENT_COLOR:-34}"); printf '%s[*] %s\e[0m\n' "${c}" "$*" >&2; }
log_warn()  { local c; c=$(theme_ansi "${GUM_TITLE_COLOR:-212}"); printf '%s[!] %s\e[0m\n' "${c}" "$*" >&2; }
log_error() { printf '\e[1;31m[✗] %s\e[0m\n' "$*" >&2; }
require_root() { [[ $EUID -eq 0 ]] || die "This command must be run as root"; }

if ! command -v gum &>/dev/null; then
    echo "[*] Installing gum..."
    pacman -Sy --noconfirm gum || die "Failed to install gum. Install it manually and retry."
fi

load_sections() {
    if [[ -f "${SECTION_CONFIG}" ]]; then
        source "${SECTION_CONFIG}"
    fi
    ANVIL_SECTIONS="${ANVIL_SECTIONS:-${DEFAULT_SECTIONS}}"
}

save_sections() {
    printf 'ANVIL_SECTIONS="%s"\n' "${ANVIL_SECTIONS}" > "${SECTION_CONFIG}"
}

fetch_list() {
    log_info "Fetching recipe list..."
    curl -sL "${LIST_URL}" -o "${LOCAL_LIST}" || {
        log_warn "Failed to download recipe list from ${LIST_URL}"
        return 1
    }
    log_info "Recipe list updated."
}

list_available() {
    load_sections
    [[ -f "${LOCAL_LIST}" ]] || fetch_list || { echo "No recipe list available."; return 1; }
    local IFS='|'
    while read -r name section desc; do
        for s in ${ANVIL_SECTIONS}; do
            if [[ "${section}" == "${s}" ]]; then
                echo "${name} - ${desc:-no description} [${section}]"
                break
            fi
        done
    done < "${LOCAL_LIST}"
}

list_packages() {
    [[ -f "${POWERUSER_DIR}/db/local.db" ]] || { echo "No packages installed."; return; }
    column -t -s '|' "${POWERUSER_DIR}/db/local.db"
}

list_recipes() {
    for f in "${POWERUSER_DIR}"/recipes/*.sh; do
        [[ -f "${f}" ]] || continue
        local name desc
        name=$(basename "${f}" .sh)
        desc=$(grep -m1 '^desc=' "${f}" | cut -d'"' -f2)
        echo "${name} - ${desc:-no description}"
    done
}

info_package() {
    local pkg="${1}"
    grep "^${pkg}|" "${POWERUSER_DIR}/db/local.db" || echo "No info for ${pkg}"
}

_recipe_git_init() {
    local recipe_dir="${POWERUSER_DIR}/recipes"
    if [[ ! -d "${recipe_dir}/.git" ]]; then
        cd "${recipe_dir}"
        git init
        git config user.email "anvil@localhost"
        git config user.name "anvil"
        git add -A
        git commit -m "Initial recipe state" 2>/dev/null || true
    fi
}

_recipe_git_commit() {
    local recipe_dir="${POWERUSER_DIR}/recipes"
    local msg="${1:-recipe update}"
    [[ -d "${recipe_dir}/.git" ]] || return 0
    cd "${recipe_dir}"
    git add -A
    git commit -m "${msg}" 2>/dev/null || true
}