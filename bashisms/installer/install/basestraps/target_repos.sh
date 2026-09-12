#!/usr/bin/env bash
set -Eeuo pipefail

_detect_cachyos_cpu_level() {
    if grep -q avx512 /proc/cpuinfo 2>/dev/null; then
        echo "x86-64-v4"
    elif grep -q avx2 /proc/cpuinfo 2>/dev/null; then
        echo "x86-64-v3"
    else
        echo "x86-64-v2"
    fi
}

basestrap_target_repo_cachyos() {
    if ! grep -q '^\[cachyos\]' /mnt/etc/pacman.conf 2>/dev/null; then
        mkdir -p /mnt/etc/pacman.d
        cp /etc/pacman.d/cachyos-mirrorlist /mnt/etc/pacman.d/ 2>/dev/null || true
        cp /etc/pacman.d/cachyos-v3-mirrorlist /mnt/etc/pacman.d/ 2>/dev/null || true
        cp /etc/pacman.d/cachyos-v4-mirrorlist /mnt/etc/pacman.d/ 2>/dev/null || true

        local cpu_level
        cpu_level=$(_detect_cachyos_cpu_level)
        log_info "Target CPU level: ${cpu_level}"

        if [[ "${cpu_level}" == "x86-64-v4" ]]; then
            if ! grep -q '^Architecture =.*x86_64_v4' /mnt/etc/pacman.conf; then
                sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v4' /mnt/etc/pacman.conf
            fi
            cat <<'EOF' >> /mnt/etc/pacman.conf
[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

EOF
        elif [[ "${cpu_level}" == "x86-64-v3" ]]; then
            if ! grep -q '^Architecture =.*x86_64_v3' /mnt/etc/pacman.conf; then
                sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v3' /mnt/etc/pacman.conf
            fi
            cat <<'EOF' >> /mnt/etc/pacman.conf
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

EOF
        fi

        cat <<'EOF' >> /mnt/etc/pacman.conf
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
    fi
}

basestrap_target_repo_bazzite() {
    if ! grep -q '^\[extra\]' /mnt/etc/pacman.conf 2>/dev/null; then
        mkdir -p /mnt/etc/pacman.d
        cp /etc/pacman.d/mirrorlist-arch /mnt/etc/pacman.d/ 2>/dev/null || true
        cat <<'EOF' >> /mnt/etc/pacman.conf
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
    fi
}

basestrap_target_repo_xanmod() {
    if ! grep -q '^\[chaotic-aur\]' /mnt/etc/pacman.conf 2>/dev/null; then
        mkdir -p /mnt/etc/pacman.d
        cp /etc/pacman.d/chaotic-mirrorlist /mnt/etc/pacman.d/ 2>/dev/null || true
        cat <<'EOF' >> /mnt/etc/pacman.conf
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    fi
}

basestrap_target_repo_auris() {
    if [[ "$(state_get ENABLE_AURIS no)" != "yes" ]]; then
        return 0
    fi
    if ! grep -q '^\[auris\]' /mnt/etc/pacman.conf 2>/dev/null; then
        cat <<'EOF' >> /mnt/etc/pacman.conf
[auris]
SigLevel = Required
Server = https://auris.artixlinux.org/api/packages/auris/arch/$repo/$arch
EOF
    fi
}