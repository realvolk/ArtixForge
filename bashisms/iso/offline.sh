#!/usr/bin/env bash
set -Eeuo pipefail

build_offline_repo() {
    local repo_dir="${1}"
    local pkg_list_file="${2}"
    mkdir -p "${repo_dir}"

    if [[ ! -f "${pkg_list_file}" ]]; then
        log_warn "No package list found at ${pkg_list_file} — skipping offline repo"
        return 0
    fi

    log_info "Downloading all packages and dependencies for offline installation..."
    pacman -Sy --noconfirm || {
        log_warn "Failed to sync package databases"
        return 1
    }
    
    pacman -Syw --cachedir "${repo_dir}" --noconfirm --ask=4 $(cat "${pkg_list_file}") 2>/dev/null || {
        log_warn "Some packages could not be downloaded – continuing with what we have"
    }

    if compgen -G "${repo_dir}/*.pkg.tar.*" >/dev/null 2>&1; then
        repo-add "${repo_dir}/custom.db.tar.zst" "${repo_dir}"/*.pkg.tar.* 2>/dev/null || true
        log_info "Offline repository created: ${repo_dir}"
    else
        log_warn "No packages downloaded – offline repository empty"
    fi
}