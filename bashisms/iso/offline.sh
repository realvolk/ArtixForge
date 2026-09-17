#!/usr/bin/env bash
set -Eeuo pipefail

build_offline_repo() {
    local repo_dir="${1}"
    local pkg_list_file="${2}"
    local download_log="/tmp/artix-installer/logs/offline-download.log"
    local staging_repo="/tmp/artix-installer/offline-staging"

    mkdir -p "$(dirname "${download_log}")" "${staging_repo}"

    if id alpm &>/dev/null; then
        chown alpm:alpm "${staging_repo}"
    fi

    if [[ ! -f "${pkg_list_file}" ]]; then
        log_error "No package list found at ${pkg_list_file}"
        rm -rf "${staging_repo}"
        return 1
    fi

    log_info "Syncing package databases..."
    if [[ -f /var/lib/pacman/db.lck ]]; then
        log_warn "Removing stale pacman lock: /var/lib/pacman/db.lck"
        rm -f /var/lib/pacman/db.lck
    fi
    if ! pacman -Sy --noconfirm >"${download_log}" 2>&1; then
        log_error "Failed to sync package databases — see ${download_log}"
        tail -20 "${download_log}" | while IFS= read -r line; do log_error "  ${line}"; done
        rm -rf "${staging_repo}"
        return 1
    fi

    local -a pkg_names=()
    mapfile -t pkg_names < "${pkg_list_file}"

    local -a valid=()
    local -a missing=()
    local p
    for p in "${pkg_names[@]}"; do
        [[ -n "${p}" ]] || continue
        if pacman -Si "${p}" >/dev/null 2>&1; then
            valid+=("${p}")
        else
            missing+=("${p}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Packages not found in any configured repo (skipping): ${missing[*]}"
    fi

    if [[ ${#valid[@]} -eq 0 ]]; then
        log_error "No valid packages to download — offline repo cannot be built"
        rm -rf "${staging_repo}"
        return 1
    fi

    log_info "Downloading ${#valid[@]} packages..."
    log_info "Download log: ${download_log}"

    if ! pacman -Syw --cachedir "${staging_repo}" --noconfirm --ask=4 "${valid[@]}" >"${download_log}" 2>&1; then
        log_error "Package download failed — see ${download_log}"
        tail -30 "${download_log}" | while IFS= read -r line; do log_error "  ${line}"; done
        rm -rf "${staging_repo}"
        return 1
    fi

    local downloaded
    downloaded=$(find "${staging_repo}" -maxdepth 1 -type f -name '*.pkg.tar.*' | wc -l)

    if [[ ${downloaded} -eq 0 ]]; then
        log_error "No packages downloaded"
        rm -rf "${staging_repo}"
        return 1
    fi

    log_info "Downloaded ${downloaded} package files"

    mkdir -p "${repo_dir}"
    log_info "Moving packages into ${repo_dir}..."
    find "${staging_repo}" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig' -exec mv {} "${repo_dir}/" \;

    rm -rf "${staging_repo}"

    log_info "Building offline repository index..."
    rm -f "${repo_dir}"/*.sig
    if ! repo-add "${repo_dir}/custom.db.tar.zst" "${repo_dir}"/*.pkg.tar.zst >"${download_log}" 2>&1; then
        log_error "repo-add failed — see ${download_log}"
        tail -20 "${download_log}" | while IFS= read -r line; do log_error "  ${line}"; done
        return 1
    fi

    log_info "Offline repository created: ${repo_dir} (${downloaded} packages)"
    return 0
}