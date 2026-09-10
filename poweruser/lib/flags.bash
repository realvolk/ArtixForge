#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE_USE_DIR="${POWERUSER_DIR}/package.use"

load_profile() {
    local profile_name="${1:-default}"
    local profile_file="${POWERUSER_DIR}/profile/${profile_name}.sh"
    [[ -f "${profile_file}" ]] || die "Profile not found: ${profile_name}"
    source "${profile_file}"
    export ARTIX_PROFILE="${profile_name}"
    GLOBAL_FEATURES="${GLOBAL_FEATURES:-}"
    export GLOBAL_FEATURES
}

use_enable() {
    local flag="${1}"
    [[ " ${selected_features[*]:-} " =~ " ${flag} " ]] && return 0 || return 1
}

apply_pkg_flags() {
    ARTIX_CFLAGS="${PKG_CFLAGS:-${ARTIX_CFLAGS}}"
    ARTIX_CXXFLAGS="${PKG_CXXFLAGS:-${ARTIX_CXXFLAGS}}"
    ARTIX_LDFLAGS="${PKG_LDFLAGS:-${ARTIX_LDFLAGS}}"
    ARTIX_MAKEFLAGS="${PKG_MAKEFLAGS:-${ARTIX_MAKEFLAGS:-$(nproc)}}"
}

read_pkg_flags() {
    local pkg="${1}"
    local flag_file="${PACKAGE_USE_DIR}/${pkg}"
    local -a flags=()
    if [[ -f "${flag_file}" ]]; then
        local line
        while IFS= read -r line; do
            [[ -z "${line}" || "${line}" == \#* ]] && continue
            flags+=("${line}")
        done < "${flag_file}"
    fi
    printf '%s\n' "${flags[@]}"
}

resolve_pkg_flags() {
    local pkg="${1}"
    load_recipe "${pkg}"

    local -a global_flags pkg_flags resolved_flags
    read -ra global_flags <<< "${GLOBAL_FEATURES:-}"
    read -ra pkg_flags <<< "$(read_pkg_flags "${pkg}")"

    local -A flag_state=()
    local flag

    for flag in "${global_flags[@]}"; do
        if [[ "${flag}" == -* ]]; then
            flag_state["${flag#-}"]="off"
        else
            flag_state["${flag}"]="on"
        fi
    done

    for flag in "${pkg_flags[@]}"; do
        if [[ "${flag}" == -* ]]; then
            flag_state["${flag#-}"]="off"
        else
            flag_state["${flag}"]="on"
        fi
    done

    for flag in "${!flag_state[@]}"; do
        [[ "${flag_state[${flag}]}" == "on" ]] && resolved_flags+=("${flag}")
    done

    selected_features=("${resolved_flags[@]}")
    export selected_features
}

resolve_flag_conflicts() {
    local flag
    for flag in "${selected_features[@]}"; do
        local conflicts="${feature_conflicts[${flag}]:-}"
        [[ -z "${conflicts}" ]] && continue
        for conflict in ${conflicts}; do
            if [[ " ${selected_features[*]} " =~ " ${conflict} " ]]; then
                log_warn "Flag conflict: ${flag} and ${conflict} cannot both be enabled for ${pkgname}"
                log_warn "  Disable one with: anvil flag ${pkgname} ${conflict} off"
                return 1
            fi
        done
    done
    return 0
}

flags_hash() {
    local feature_string="${selected_features[*]:-}"
    feature_string="${feature_string:-none}"
    local dep_string="${1:-}"
    local patch_string="${2:-}"
    printf '%s%s%s%s%s%s%s' \
        "${ARTIX_CFLAGS}" "${ARTIX_CXXFLAGS}" "${ARTIX_LDFLAGS}" \
        "${ARTIX_MAKEFLAGS}" "${feature_string}" "${dep_string}" "${patch_string}" \
        | sha256sum | cut -d' ' -f1
}