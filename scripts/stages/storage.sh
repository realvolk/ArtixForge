#!/usr/bin/env bash
set -Eeuo pipefail

stage_storage() {
    if stage_should_skip storage; then
        if ! mountpoint -q /mnt; then
            log_info "Storage stage completed — remounting filesystems for resume"
            mount_filesystems
        fi
        return 0
    fi

    local disk
    disk="$(state_get DISK)"
    [[ -n "${disk}" ]] || die "No disk selected"

    if [[ -z "$(state_get EFI_PART '')" ]]; then
        partition_disk
    fi

    create_filesystems
    mount_filesystems
    stage_mark_done storage
}