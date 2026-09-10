#!/usr/bin/env bash
set -Eeuo pipefail

basestrap_kernel_standard() {
    local -n pkgs_ref="${1}"
    local skip="${2}"
    if [[ ${skip} -eq 1 ]]; then
        log_info "Skipping binary ${kernel} kernel (fallback disabled)"
    else
        pkgs_ref+=("${KERNEL_PACKAGE}" "${KERNEL_HEADERS}")
    fi
}

basestrap_kernel_linux_libre() {
    local -n pkgs_ref="${1}"
    local skip="${2}"
    if [[ ${skip} -eq 1 ]]; then
        log_info "Skipping binary linux-libre kernel (fallback disabled)"
    else
        log_info "Enabling linux-libre repository..."
        if ! grep -q '^\[libre\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[libre]
SigLevel = Never
Server = https://repo.parabola.nu/libre/os/x86_64
EOF
        fi
        pkgs_ref+=(linux-libre linux-libre-headers)
        log_warn "linux-libre removes non-free firmware/drivers. NVIDIA, Wi‑Fi, Bluetooth may stop working."
    fi
}

_detect_cachyos_cpu_level() {
    if grep -q avx512 /proc/cpuinfo 2>/dev/null; then
        echo "x86-64-v4"
    elif grep -q avx2 /proc/cpuinfo 2>/dev/null; then
        echo "x86-64-v3"
    else
        echo "x86-64-v2"
    fi
}

basestrap_kernel_cachyos() {
    local -n pkgs_ref="${1}"
    local skip="${2}"
    if [[ ${skip} -eq 1 ]]; then
        log_info "Skipping binary cachyos kernel (fallback disabled)"
    else
        log_info "Setting up CachyOS repository..."
        pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
        pacman-key --lsign-key F3B607488DB35A47
        
        local cachyos_keyring cachyos_mirrorlist
        cachyos_keyring=$(curl -sL 'https://mirror.cachyos.org/repo/x86_64/cachyos/' | grep -oP 'cachyos-keyring-\d+.*?\.pkg\.tar\.zst' | sort -V | tail -1)
        cachyos_mirrorlist=$(curl -sL 'https://mirror.cachyos.org/repo/x86_64/cachyos/' | grep -oP 'cachyos-mirrorlist-\d+.*?\.pkg\.tar\.zst' | sort -V | tail -1)
        if [[ -z "${cachyos_keyring}" || -z "${cachyos_mirrorlist}" ]]; then
            log_warn "Could not scrape CachyOS mirror — trying static fallback URLs"
            cachyos_keyring="cachyos-keyring-20250101-1-any.pkg.tar.zst"
            cachyos_mirrorlist="cachyos-mirrorlist-20250101-1-any.pkg.tar.zst"
        fi
        pacman -U --noconfirm \
            "https://mirror.cachyos.org/repo/x86_64/cachyos/${cachyos_keyring}" \
            "https://mirror.cachyos.org/repo/x86_64/cachyos/${cachyos_mirrorlist}" || {
            log_error "Failed to install CachyOS bootstrap packages — mirror may be down"
            die 'CachyOS repository setup failed'
        }

        local cpu_level
        cpu_level=$(_detect_cachyos_cpu_level)
        log_info "Detected CPU level: ${cpu_level}"

        if [[ "${cpu_level}" == "x86-64-v4" ]]; then
            local v4_mirrorlist_pkg
            v4_mirrorlist_pkg=$(curl -sL 'https://mirror.cachyos.org/repo/x86_64/cachyos/' | grep -oP 'cachyos-v4-mirrorlist-\d+.*?\.pkg\.tar\.zst' | sort -V | tail -1)
            if [[ -n "${v4_mirrorlist_pkg}" ]]; then
                pacman -U --noconfirm "https://mirror.cachyos.org/repo/x86_64/cachyos/${v4_mirrorlist_pkg}" || {
                    log_warn "Failed to install cachyos-v4-mirrorlist — skipping v4 repos"
                }
            fi
            if [[ -f /etc/pacman.d/cachyos-v4-mirrorlist ]]; then
                if ! grep -q '^Architecture =.*x86_64_v4' /etc/pacman.conf; then
                    sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v4' /etc/pacman.conf
                fi
                cat <<'EOF' >> /etc/pacman.conf
[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

EOF
            fi
        elif [[ "${cpu_level}" == "x86-64-v3" ]]; then
            local v3_mirrorlist_pkg
            v3_mirrorlist_pkg=$(curl -sL 'https://mirror.cachyos.org/repo/x86_64/cachyos/' | grep -oP 'cachyos-v3-mirrorlist-\d+.*?\.pkg\.tar\.zst' | sort -V | tail -1)
            if [[ -n "${v3_mirrorlist_pkg}" ]]; then
                pacman -U --noconfirm "https://mirror.cachyos.org/repo/x86_64/cachyos/${v3_mirrorlist_pkg}" || {
                    log_warn "Failed to install cachyos-v3-mirrorlist — skipping v3 repos"
                }
            fi
            if [[ -f /etc/pacman.d/cachyos-v3-mirrorlist ]]; then
                if ! grep -q '^Architecture =.*x86_64_v3' /etc/pacman.conf; then
                    sed -i '/^\[options\]/a Architecture = x86_64 x86_64_v3' /etc/pacman.conf
                fi
                cat <<'EOF' >> /etc/pacman.conf
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

EOF
            fi
        fi

        if ! grep -q '^\[cachyos\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
        fi
        pkgs_ref+=("${kernel}" "${kernel}-headers")
    fi
}

basestrap_kernel_bazzite() {
    local -n pkgs_ref="${1}"
    local skip="${2}"
    if [[ ${skip} -eq 1 ]]; then
        log_info "Skipping binary bazzite kernel (fallback disabled)"
    else
        log_info "Setting up Bazzite kernel AUR build..."
        if ! pacman -Q artix-archlinux-support >/dev/null 2>&1; then
            pacman -S --noconfirm --needed artix-archlinux-support
        fi
        local arch_mirrorlist='/etc/pacman.d/mirrorlist-arch'
        if [[ ! -f "${arch_mirrorlist}" ]]; then
            install -Dm644 /dev/null "${arch_mirrorlist}"
            cat > "${arch_mirrorlist}" <<'MIRROR_EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
MIRROR_EOF
        fi
        if ! grep -q '^\[extra\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[extra]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
        if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
        pkgs_ref+=(base-devel git mkinitcpio)
    fi
}

basestrap_kernel_xanmod() {
    local -n pkgs_ref="${1}"
    local skip="${2}"
    if [[ ${skip} -eq 1 ]]; then
        log_info "Skipping binary xanmod kernel (fallback disabled)"
    else
        log_info "Setting up Chaotic-AUR for XanMod..."
        export GNUPGHOME="/etc/pacman.d/gnupg"
        mkdir -p "${GNUPGHOME}"
        chmod 700 "${GNUPGHOME}"
        pacman-key --init
        pacman-key --populate artix
        pacman-key --recv-keys 3056513887B78AEB --keyserver hkp://keyserver.ubuntu.com
        pacman-key --lsign-key 3056513887B78AEB
        pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
        if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
        fi
        pkgs_ref+=("${KERNEL_PACKAGE}" "${KERNEL_HEADERS}")
    fi
}

basestrap_kernel_tkg() {
    local -n pkgs_ref="${1}"
    if [[ "$(state_get TKG_BINARY no)" == "yes" ]]; then
        log_info "TKG binary selected — no build dependencies needed"
        return 0
    fi
    log_info "Setting up TKG build dependencies..."
    pkgs_ref+=(bc cpio flex libelf pahole base-devel git dkms)
}

basestrap_install_tkg_binary() {
    local sched
    sched="$(state_get TKG_SCHEDULER eevdf)"
    log_info "Downloading TKG binary kernel (${sched})..."

    local api_url="https://api.github.com/repos/Frogging-Family/linux-tkg/releases/latest"
    local release_json
    release_json=$(curl -sL "${api_url}") || {
        log_error "Failed to fetch TKG release info from GitHub"
        return 1
    }

    local kernel_url headers_url
    kernel_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | test("linux[0-9]+-tkg-'"${sched}"'-llvm-[0-9].*-x86_64\\.pkg\\.tar\\.zst")) | .browser_download_url' | grep -v headers | head -n1)
    headers_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | test("linux[0-9]+-tkg-'"${sched}"'-llvm-headers-.*\\.pkg\\.tar\\.zst")) | .browser_download_url' | head -n1)

    if [[ -z "${kernel_url}" || -z "${headers_url}" ]]; then
        log_error "Could not find TKG binary packages for scheduler: ${sched}"
        log_error "Kernel URL: ${kernel_url:-not found}"
        log_error "Headers URL: ${headers_url:-not found}"
        return 1
    fi

    log_info "Downloading kernel from: ${kernel_url}"
    curl -L -o /tmp/tkg-kernel.pkg.tar.zst "${kernel_url}" || { log_error "Failed to download TKG kernel"; return 1; }

    log_info "Downloading headers from: ${headers_url}"
    curl -L -o /tmp/tkg-headers.pkg.tar.zst "${headers_url}" || { log_error "Failed to download TKG headers"; return 1; }

    log_info "Installing TKG kernel and headers..."
    artix-chroot /mnt pacman -U --noconfirm /tmp/tkg-kernel.pkg.tar.zst /tmp/tkg-headers.pkg.tar.zst || {
        log_error "Failed to install TKG binary packages"
        return 1
    }

    rm -f /tmp/tkg-kernel.pkg.tar.zst /tmp/tkg-headers.pkg.tar.zst
    log_info "TKG binary kernel installed successfully"

    local kver
    kver=$(artix-chroot /mnt ls -1 /boot/vmlinuz-*tkg* 2>/dev/null | head -n1 | sed 's/.*vmlinuz-//')
    if [[ -n "${kver}" ]]; then
        state_set KERNEL_IMAGE "vmlinuz-${kver}"
        state_set INITRAMFS_IMAGE "initramfs-${kver}.img"
    fi
}

basestrap_repo_auris() {
    if [[ "$(state_get ENABLE_AURIS no)" != "yes" ]]; then
        return 0
    fi
    log_info "Enabling AURIS community init scripts repository..."
    local key_url="https://auris.artixlinux.org/api/packages/auris/arch/repository.key"
    curl -sL "${key_url}" -o /tmp/auris.key
    pacman-key --add /tmp/auris.key
    pacman-key --lsign-key 74E5750C4A3C00F037070EF2357B525A97500B9F
    rm -f /tmp/auris.key
    
    if ! grep -q '^\[auris\]' /etc/pacman.conf; then
        cat <<'EOF' >> /etc/pacman.conf
[auris]
SigLevel = Required
Server = https://auris.artixlinux.org/api/packages/auris/arch/$repo/$arch
EOF
    fi
    pacman -Sy --noconfirm
}