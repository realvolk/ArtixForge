#!/usr/bin/env bash
set -Eeuo pipefail

needs_rebuild() {
    local pkgname="${1}"
    local db_entry
    db_entry="$(grep "^${pkgname}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null | tail -n1)"
    [[ -n "${db_entry}" ]] || return 0

    local saved_flags
    saved_flags="$(echo "${db_entry}" | cut -d'|' -f3)"
    local current_flags
    current_flags="$(flags_hash)"
    [[ "${saved_flags}" == "${current_flags}" ]] || return 0

    local recipe_file="${POWERUSER_DIR}/recipes/${pkgname}.sh"
    if [[ -f "${recipe_file}" ]]; then
        source "${recipe_file}" 2>/dev/null || true
        local dep
        for dep in "${depends[@]}" "${makedepends[@]}"; do
            local installed_ver db_dep_ver
            installed_ver=$(pacman -Q "${dep}" 2>/dev/null | cut -d' ' -f2)
            db_dep_ver=$(grep "^${dep}|" "${POWERUSER_DIR}/db/local.db" | tail -n1 | cut -d'|' -f2)
            [[ "${installed_ver}" == "${db_dep_ver}" ]] || return 0
        done
    fi

    return 1
}