#!/usr/bin/env bash
set -Eeuo pipefail

anvil_recovery_status() {
    log_info "Checking source‑built packages..."
    local db="${POWERUSER_DIR}/db/local.db"
    [[ -f "${db}" ]] || { echo "No source packages installed."; return 0; }

    local issues=0
    while IFS='|' read -r pkgname version flags date features; do
        local recipe="${POWERUSER_DIR}/recipes/${pkgname}.sh"
        if [[ ! -f "${recipe}" ]]; then
            log_warn "${pkgname}: recipe missing"
            issues=$((issues + 1))
            continue
        fi
        if [[ "${pkgname}" == "linux-custom" ]]; then
            if [[ ! -f /boot/vmlinuz-linux-custom ]]; then
                log_warn "${pkgname}: kernel image missing"
                issues=$((issues + 1))
            fi
        else
            if ! compgen -G "/usr/share/${pkgname}*" >/dev/null 2>&1 && ! compgen -G "/usr/lib/${pkgname}*" >/dev/null 2>&1; then
                log_warn "${pkgname}: installed files may be missing"
                issues=$((issues + 1))
            fi
        fi
    done < <(tail -n +2 "${db}" 2>/dev/null)

    if [[ ${issues} -eq 0 ]]; then
        log_info "All source‑built packages are healthy."
    else
        log_warn "Found ${issues} potential issue(s)."
    fi
}

anvil_recovery_repair() {
    local pkg="${1:-linux-custom}"
    log_info "Rebuilding ${pkg} for recovery..."

    local recipe_file="${POWERUSER_DIR}/recipes/${pkg}.sh"
    if [[ ! -f "${recipe_file}" ]]; then
        log_error "Recipe for ${pkg} not found."
        return 1
    fi

    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"

    local profile_name
    if [[ -f "${POWERUSER_DIR}/profile/active" ]]; then
        profile_name=$(tr -d '[:space:]' < "${POWERUSER_DIR}/profile/active")
    else
        profile_name="default"
    fi
    export POWERUSER_PROFILE="${profile_name}"
    load_profile "${profile_name}"

    load_recipe "${pkg}"
    build_package "${pkg}"

    if [[ "${pkg}" == "linux-custom" ]]; then
        if [[ -f /boot/vmlinuz-linux-custom ]]; then
            log_info "Kernel rebuilt. Running mkinitcpio and grub-mkconfig..."
            mkinitcpio -P
            grub-mkconfig -o /boot/grub/grub.cfg
        else
            log_error "Kernel rebuild may have failed."
            return 1
        fi
    fi
    log_info "${pkg} recovery complete."
}