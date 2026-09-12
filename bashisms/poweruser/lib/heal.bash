#!/usr/bin/env bash
set -Eeuo pipefail

# Attempt to auto-heal a recipe whose fetch failed by detecting
# a newer source version and bumping pkgver/pkgrel.
# Returns 0 if the recipe was healed (retry build).
# Returns 1 if healing failed or wasn't possible.

heal_recipe() {
    local recipe_name="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${recipe_name}.sh"

    [[ -f "${recipe_file}" ]] || { log_warn "Cannot heal — recipe file missing: ${recipe_file}"; return 1; }

    log_info "Attempting to heal recipe: ${recipe_name}..."

    local old_pkgver old_pkgrel old_major old_url old_filename
    old_pkgver=$(grep -m1 '^pkgver=' "${recipe_file}" | cut -d'=' -f2 | tr -d '"')
    old_pkgrel=$(grep -m1 '^pkgrel=' "${recipe_file}" | cut -d'=' -f2 | tr -d '"')
    old_major=$(grep -m1 '^_major=' "${recipe_file}" | cut -d'=' -f2 | tr -d '"')
    old_url=$(grep -m1 '^  "' "${recipe_file}" | head -n1 | cut -d'"' -f2 | cut -d'|' -f1)
    old_filename=$(grep -m1 '^  "' "${recipe_file}" | head -n1 | cut -d'|' -f3)

    [[ -n "${old_pkgver}" ]] || { log_warn "Cannot parse pkgver from ${recipe_file}"; return 1; }
    [[ -n "${old_url}" ]] || { log_warn "Cannot parse source URL from ${recipe_file}"; return 1; }

    log_info "Current version: ${old_pkgver}-${old_pkgrel}"
    log_info "Source URL: ${old_url}"

    local new_pkgver=""

    if [[ "${old_url}" =~ https?://cdn\.kernel\.org/pub/linux/kernel/v([0-9]+)\.x/linux-([0-9]+\.[0-9]+\.[0-9]+)\.tar\.xz ]]; then
        local major_ver="${BASH_REMATCH[1]}"
        local dir_url="https://cdn.kernel.org/pub/linux/kernel/v${major_ver}.x/"

        log_info "Detected kernel.org pattern — scanning ${dir_url}..."
        local latest
        latest=$(curl -sL "${dir_url}" | grep -oP 'linux-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.xz)' | sort -V | tail -n1)

        if [[ -n "${latest}" && "${latest}" != "${old_pkgver}" ]]; then
            new_pkgver="${latest}"
        else
            log_info "Already at latest kernel.org version (${old_pkgver})"
        fi
    fi

    if [[ -z "${new_pkgver}" && "${old_url}" =~ https?://github\.com/([^/]+)/([^/]+)/ ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        repo="${repo%.git}"

        log_info "Detected GitHub pattern — checking ${owner}/${repo}..."

        local api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
        local latest_tag
        latest_tag=$(curl -sL "${api_url}" | grep -m1 '"tag_name"' | cut -d'"' -f4 | sed 's/^v//')

        if [[ -n "${latest_tag}" && "${latest_tag}" != "${old_pkgver}" ]]; then
            new_pkgver="${latest_tag}"
        elif [[ -z "${latest_tag}" ]]; then
            local tags_url="https://api.github.com/repos/${owner}/${repo}/tags"
            latest_tag=$(curl -sL "${tags_url}" | grep -m1 '"name"' | cut -d'"' -f4 | sed 's/^v//')
            if [[ -n "${latest_tag}" && "${latest_tag}" != "${old_pkgver}" ]]; then
                new_pkgver="${latest_tag}"
            fi
        fi
    fi

    if [[ -z "${new_pkgver}" ]]; then
        local dir_url
        dir_url=$(dirname "${old_url}")/
        log_info "Scanning parent directory: ${dir_url}..."

        local name_pattern="${old_filename//${old_pkgver}/[0-9]*}"
        name_pattern="${name_pattern//./\\.}"

        local latest_file
        latest_file=$(curl -sL "${dir_url}" | grep -oP "${name_pattern}" | sort -V | tail -n1)

        if [[ -n "${latest_file}" ]]; then
            new_pkgver=$(echo "${latest_file}" | grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
        fi

        if [[ -z "${new_pkgver}" || "${new_pkgver}" == "${old_pkgver}" ]]; then
            log_info "No newer version found via directory scan"
        fi
    fi

    if [[ -z "${new_pkgver}" || "${new_pkgver}" == "${old_pkgver}" ]]; then
        log_warn "No newer version found for ${recipe_name} — source may be unavailable"
        log_warn "Check the URL manually: ${old_url}"
        return 1
    fi

    log_info "Healing ${recipe_name}: ${old_pkgver} → ${new_pkgver}"

    sed -i "s/^pkgver=${old_pkgver}/pkgver=${new_pkgver}/" "${recipe_file}"

    sed -i "s/^pkgrel=${old_pkgrel}/pkgrel=1/" "${recipe_file}"

    if [[ "${old_url}" == *"${old_pkgver}"* ]]; then
        local new_url="${old_url//${old_pkgver}/${new_pkgver}}"
        local new_filename="${old_filename//${old_pkgver}/${new_pkgver}}"
        sed -i "s|${old_url}|${new_url}|" "${recipe_file}"
        sed -i "s|${old_filename}|${new_filename}|" "${recipe_file}"
    fi

    if [[ -n "${old_major}" ]]; then
        local new_major="${new_pkgver%%.*}"
        sed -i "s/^_major=${old_major}/_major=${new_major}/" "${recipe_file}"
    fi

    log_info "Recipe ${recipe_name} healed: ${old_pkgver}-${old_pkgrel} → ${new_pkgver}-1"
    return 0
}