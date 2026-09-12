#!/usr/bin/env bash
set -Eeuo pipefail

REPAIR_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/repairs"

source "${REPAIR_DIR}/system.sh"
source "${REPAIR_DIR}/packages.sh"
source "${REPAIR_DIR}/advanced.sh"
source "${REPAIR_DIR}/migration_iso.sh"

_kernel_pkg() {
    local choice="${1:-linux}"
    case "${choice}" in
        linux)                echo "linux linux-headers" ;;
        linux-zen)            echo "linux-zen linux-zen-headers" ;;
        linux-lts)            echo "linux-lts linux-lts-headers" ;;
        linux-hardened)       echo "linux-hardened linux-hardened-headers" ;;
        linux-libre)          echo "linux-libre linux-libre-headers" ;;
        linux-cachyos-bore)   echo "linux-cachyos-bore linux-cachyos-bore-headers" ;;
        linux-bazzite-bin)    echo "linux-bazzite-bin linux-bazzite-bin-headers" ;;
        xanmod)               echo "linux-xanmod linux-xanmod-headers" ;;
        tkg)                  echo "" ;;
        linux-custom)         echo "" ;;
        *)                    echo "linux linux-headers" ;;
    esac
}