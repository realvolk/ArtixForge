#!/usr/bin/env bash
set -Eeuo pipefail

QUEUE_DIR="${POWERUSER_DIR}/build/queue"
mkdir -p "${QUEUE_DIR}"

generate_queue() {
    local -a pkgs=("$@")
    printf '%s\n' "${pkgs[@]}" > "${QUEUE_DIR}/order.txt"
    : > "${QUEUE_DIR}/status.txt"
    for pkg in "${pkgs[@]}"; do
        printf '%s|pending\n' "${pkg}" >> "${QUEUE_DIR}/status.txt"
    done
}

queue_next() {
    grep '|pending$' "${QUEUE_DIR}/status.txt" | head -n1 | cut -d'|' -f1
}

queue_mark() {
    local pkg="${1}" status="${2}"
    sed -i "s/^${pkg}|.*/${pkg}|${status}/" "${QUEUE_DIR}/status.txt"
}

queue_all_done() {
    ! grep -q '|pending$' "${QUEUE_DIR}/status.txt" 2>/dev/null
}

queue_remaining() {
    grep -c '|pending$' "${QUEUE_DIR}/status.txt" 2>/dev/null || echo 0
}