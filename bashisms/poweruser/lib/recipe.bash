#!/usr/bin/env bash
set -Eeuo pipefail

load_recipe() {
    local recipe_name="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${recipe_name}.sh"
    [[ -f "${recipe_file}" ]] || die "Recipe not found: ${recipe_name}"

    pkgname='' pkgver='' pkgrel='' desc='' url=''
    sources=() depends=() makedepends=() feature_flags=() provides=()
    unset -f prepare configure build check package 2>/dev/null || true

    source "${recipe_file}"

    [[ -n "${pkgname}" ]] || die "Recipe ${recipe_name} missing pkgname"
    [[ -n "${pkgver}" ]]  || die "Recipe ${recipe_name} missing pkgver"
    [[ -n "${pkgrel}" ]]  || die "Recipe ${recipe_name} missing pkgrel"

    depends=("${depends[@]:-}")
    makedepends=("${makedepends[@]:-}")
    feature_flags=("${feature_flags[@]:-}")
    provides=("${provides[@]:-}")

    declare -A feature_depends=()
    local _varname _flag
    while IFS='=' read -r _varname _; do
        [[ "${_varname}" == feature_depends_* ]] || continue
        _flag="${_varname#feature_depends_}"
        local -n _ref_deps="${_varname}" 2>/dev/null || continue
        feature_depends["${_flag}"]="${_ref_deps[*]}"
    done < <(declare -p 2>/dev/null | grep -o 'feature_depends_[a-z0-9_-]*')

    declare -A feature_conflicts=()
    while IFS='=' read -r _varname _; do
        [[ "${_varname}" == feature_conflicts_* ]] || continue
        _flag="${_varname#feature_conflicts_}"
        local -n _ref_confs="${_varname}" 2>/dev/null || continue
        feature_conflicts["${_flag}"]="${_ref_confs[*]}"
    done < <(declare -p 2>/dev/null | grep -o 'feature_conflicts_[a-z0-9_-]*')

    declare -A flag_descriptions=()
    while IFS='=' read -r _varname _; do
        [[ "${_varname}" == flag_desc_* ]] || continue
        _flag="${_varname#flag_desc_}"
        local -n _ref_desc="${_varname}" 2>/dev/null || continue
        flag_descriptions["${_flag}"]="${_ref_desc}"
    done < <(declare -p 2>/dev/null | grep -o 'flag_desc_[a-z0-9_-]*')

    export pkgname pkgver pkgrel desc url sources depends makedepends feature_flags provides
    export feature_depends feature_conflicts flag_descriptions
}

list_recipes() {
    local recipe
    for recipe in "${POWERUSER_DIR}"/recipes/*.sh; do
        [[ -f "${recipe}" ]] || continue
        local name
        name="$(basename "${recipe}" .sh)"
        [[ "${name}" == "template" ]] && continue
        local d
        d="$(grep -m1 '^desc=' "${recipe}" | cut -d'"' -f2)"
        printf '%s — %s\n' "${name}" "${d:-no description}"
    done
}