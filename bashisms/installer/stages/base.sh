#!/usr/bin/env bash
set -Eeuo pipefail

stage_base() {
    if stage_should_skip base; then return 0; fi
    install_base_system
    check_disk_space 5 /mnt
    stage_mark_done base
}