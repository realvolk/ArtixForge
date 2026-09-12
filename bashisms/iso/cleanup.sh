#!/usr/bin/env bash
set -Eeuo pipefail

cleanup_iso_build() {
    local workspace="${1:-${HOME}/artools-workspace}"
    local keep_artifacts="${2:-no}"
    local output_dir="${3:-${HOME}/artixforge-iso}"

    log_info "Cleaning up ISO build workspace..."
    if [[ "${keep_artifacts}" == "yes" ]]; then
        log_info "Keeping ISO output and build logs, removing only working directory."
        find "${workspace}" -maxdepth 1 -type f -name '*.log' -exec cp {} "${output_dir}/" \; 2>/dev/null || true
        rm -rf "${workspace}/chroot" 2>/dev/null || true
        rm -rf "${workspace}/iso-profiles" 2>/dev/null || true
    else
        find "${workspace}" -maxdepth 1 -type f -name '*.log' -exec cp {} "${output_dir}/" \; 2>/dev/null || true
        rm -rf "${workspace}" 2>/dev/null || true
    fi
    log_info "Cleanup complete."
}