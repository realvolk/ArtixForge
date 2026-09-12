#!/usr/bin/env bash
set -Eeuo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ISO_DIR}/../.." && pwd)}"

build_nonrepo_for_offline() {
    local kernel_name="${1}" chroot_dir="${2}" repo_dir="${3}"

    log_info "Building ${kernel_name} for offline bundle..."

    case "${kernel_name}" in
        linux-bazzite-bin)
            artix-chroot "${chroot_dir}" bash -c "
                pacman -S --noconfirm --needed base-devel git
                cd /tmp
                rm -rf linux-bazzite-bin
                git clone https://aur.archlinux.org/linux-bazzite-bin.git
                chown -R nobody: /tmp/linux-bazzite-bin
                su nobody -c 'cd /tmp/linux-bazzite-bin && makepkg -s --noconfirm --needed --skippgpcheck'
            " || die "${kernel_name} build for offline bundle failed"
            cp "${chroot_dir}/tmp/linux-bazzite-bin/"*.pkg.tar.* "${repo_dir}/" 2>/dev/null || true
            echo "linux-bazzite-bin" >> "${repo_dir}/../packages-target.x86_64"
            echo "linux-bazzite-bin-headers" >> "${repo_dir}/../packages-target.x86_64"
            ;;
        linux-cachyos*)
            artix-chroot "${chroot_dir}" bash -c "
                pacman -S --noconfirm --needed base-devel curl
                pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
                pacman-key --lsign-key F3B607488DB35A47
                local cachyos_keyring cachyos_mirrorlist
                cachyos_keyring=\$(curl -sL 'https://mirror.cachyos.org/repo/x86_64/cachyos/' | grep -oP 'cachyos-keyring-\d+.*?\.pkg\.tar\.zst' | sort -V | tail -1)
                cachyos_mirrorlist=\$(curl -sL 'https://mirror.cachyos.org/repo/x86_64/cachyos/' | grep -oP 'cachyos-mirrorlist-\d+.*?\.pkg\.tar\.zst' | sort -V | tail -1)
                [[ -z \"\${cachyos_keyring}\" ]] && cachyos_keyring='cachyos-keyring-20250101-1-any.pkg.tar.zst'
                [[ -z \"\${cachyos_mirrorlist}\" ]] && cachyos_mirrorlist='cachyos-mirrorlist-20250101-1-any.pkg.tar.zst'
                pacman -U --noconfirm \"https://mirror.cachyos.org/repo/x86_64/cachyos/\${cachyos_keyring}\" \"https://mirror.cachyos.org/repo/x86_64/cachyos/\${cachyos_mirrorlist}\"
                grep -q '^\[cachyos\]' /etc/pacman.conf || cat >> /etc/pacman.conf <<'REPO_EOF'
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
REPO_EOF
                pacman -Sy --noconfirm
                mkdir -p /tmp/offline-kernel
                pacman -Sw --noconfirm --cachedir /tmp/offline-kernel '${kernel_name}' '${kernel_name}-headers'
            " || die "CachyOS kernel download for offline bundle failed"
            cp "${chroot_dir}/tmp/offline-kernel/"*.pkg.tar.* "${repo_dir}/" 2>/dev/null || true
            echo "${kernel_name}" >> "${repo_dir}/../packages-target.x86_64"
            echo "${kernel_name}-headers" >> "${repo_dir}/../packages-target.x86_64"
            ;;
        xanmod)
            artix-chroot "${chroot_dir}" bash -c "
                pacman -S --noconfirm --needed base-devel
                export GNUPGHOME=/etc/pacman.d/gnupg
                mkdir -p \"\${GNUPGHOME}\"
                chmod 700 \"\${GNUPGHOME}\"
                pacman-key --init
                pacman-key --populate artix
                pacman-key --recv-keys 3056513887B78AEB --keyserver hkp://keyserver.ubuntu.com
                pacman-key --lsign-key 3056513887B78AEB
                pacman -U --noconfirm https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst
                grep -q '^\[chaotic-aur\]' /etc/pacman.conf || cat >> /etc/pacman.conf <<'REPO_EOF'
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
REPO_EOF
                pacman -Sy --noconfirm
                mkdir -p /tmp/offline-kernel
                pacman -Sw --noconfirm --cachedir /tmp/offline-kernel linux-xanmod linux-xanmod-headers
            " || die "XanMod kernel download for offline bundle failed"
            cp "${chroot_dir}/tmp/offline-kernel/"*.pkg.tar.* "${repo_dir}/" 2>/dev/null || true
            echo "linux-xanmod" >> "${repo_dir}/../packages-target.x86_64"
            echo "linux-xanmod-headers" >> "${repo_dir}/../packages-target.x86_64"
            ;;
        *)
            log_warn "Non-repo kernel '${kernel_name}' not supported for offline builds — substituting linux"
            return 1
            ;;
    esac

    return 0
}

_iso_build_restore() {
    local mount_sh="/usr/share/artools/lib/iso/mount.sh"
    local mount_sh_backup="${mount_sh}.orig"
    local buildiso_bin="/usr/bin/buildiso"
    local buildiso_backup="${buildiso_bin}.orig"

    if [[ -f "${mount_sh_backup}" ]]; then
        mv "${mount_sh_backup}" "${mount_sh}" 2>/dev/null || true
    fi
    if [[ -f "${buildiso_backup}" ]]; then
        mv "${buildiso_backup}" "${buildiso_bin}" 2>/dev/null || true
    fi
}

build_artix_iso() {
    local profile_name="${1:-Desktop}"
    local init="${2:-openrc}"
    local kernel="${3:-linux}"
    local offline="${4:-no}"
    local boot_mode="${5:-live}"
    local user_output_dir="${6:-${HOME}/ArtixForge-ISO}"
    local base_profile="${7:-base}"

    local workspace
    if [[ -d /run/artix/sfs/rootfs ]]; then
        workspace="/root/artools-workspace"
    else
        workspace="${HOME}/artools-workspace"
    fi
    local iso_output_dir="${workspace}/iso"
    local iso_profile_dir="${workspace}/iso-profiles/${profile_name}"
    local mount_sh="/usr/share/artools/lib/iso/mount.sh"
    local mount_sh_backup="${mount_sh}.orig"
    local buildiso_bin="/usr/bin/buildiso"
    local buildiso_backup="${buildiso_bin}.orig"
    local iso_stage_file="/tmp/artix-installer/iso-build-stage.conf"
    local iso_stage
    iso_stage="$(cat "${iso_stage_file}" 2>/dev/null || echo "init")"
    log_info "ISO build stage: ${iso_stage}"

    local arch_repos arch_flag
    arch_repos="$(state_get ISO_ARCH_REPOS 'no')"
    arch_flag=""
    if [[ "${arch_repos}" == "yes" ]]; then
        arch_flag="-R arch"
    fi

    trap '_iso_build_restore' EXIT

    if ! command -v buildiso >/dev/null; then
        log_info "Installing artools and iso-profiles..."
        pacman -S --noconfirm artools iso-profiles || die "Failed to install artools"
        modprobe loop
    fi

    mkdir -p "${workspace}"/{iso-profiles,chroot,iso}

    if [[ -f "${mount_sh}" ]] && [[ ! -f "${mount_sh_backup}" ]]; then
        cp "${mount_sh}" "${mount_sh_backup}"
        sed -i 's/umount "${FS_ACTIVE_MOUNTS\[@\]}"/for i in {1..5}; do if umount -l "${FS_ACTIVE_MOUNTS[@]}" 2>\/dev\/null; then break; fi; sleep 1; done/' "${mount_sh}"
    fi

    if [[ -f "${buildiso_bin}" ]] && [[ ! -f "${buildiso_backup}" ]]; then
        cp "${buildiso_bin}" "${buildiso_backup}"
        sed -i '/find.*-delete &> \/dev\/null/s/ &> \/dev\/null/ 2>\/dev\/null || true/g' "${buildiso_bin}"
        sed -i '/find "\$mnt" -name.*\.pacnew.*-delete/s/$/ 2>\/dev\/null || true/' "${buildiso_bin}"
    fi

    if [[ "${iso_stage}" == "init" || "${iso_stage}" == "profile" ]]; then
        log_info "Extending upstream '${base_profile}' profile for ${profile_name} (${init}, ${boot_mode} mode)..."
        source "${ISO_DIR}/common.sh"
        generate_artools_profile "${iso_profile_dir}" "${profile_name}" "${init}" "${kernel}" "${boot_mode}" "${base_profile}"
        export WORKSPACE_DIR="${workspace}"
        echo "profile" > "${iso_stage_file}"
    else
        log_info "Skipping profile generation (already done)"
        source "${ISO_DIR}/common.sh"
        export WORKSPACE_DIR="${workspace}"
    fi

    if [[ "${offline}" == "yes" ]]; then
        if [[ "${iso_stage}" == "profile" || "${iso_stage}" == "offline" ]]; then
            source "${ISO_DIR}/offline.sh"
            log_info "Building offline package repository..."

            local offline_pkg_list="${iso_profile_dir}/packages-offline.x86_64"

            if [[ -f /tmp/artix-installer/iso-target-state.conf ]]; then
                log_info "Generating target system package list from target state..."
                source /tmp/artix-installer/iso-target-state.conf
                local target_kernel="${KERNEL_CHOICE:-linux}"

                case "${target_kernel}" in
                    linux|linux-zen|linux-lts|linux-hardened|linux-libre)
                        generate_offline_package_list "${INIT:-openrc}" "${target_kernel}" > "${iso_profile_dir}/packages-target.x86_64"
                        offline_pkg_list="${iso_profile_dir}/packages-target.x86_64"
                        ;;
                    *)
                        log_info "Non-repo kernel '${target_kernel}' — building for offline bundle..."
                        generate_offline_package_list "${INIT:-openrc}" "linux" > "${iso_profile_dir}/packages-target.x86_64"
                        offline_pkg_list="${iso_profile_dir}/packages-target.x86_64"

                        buildiso -p "${profile_name}" -i "${init}" -c -x ${arch_flag} 2>&1 || die "buildiso -x failed for offline kernel build"

                        local chroot_dir=""
                        local search_paths=(
                            "/var/lib/artools/buildiso/${profile_name}/artix/rootfs"
                            "${workspace}/buildiso/${profile_name}/artix/rootfs"
                        )
                        for candidate in "${search_paths[@]}"; do
                            if [[ -d "${candidate}" && -x "${candidate}/bin/sh" ]]; then
                                chroot_dir="${candidate}"
                                break
                            fi
                        done
                        [[ -z "${chroot_dir}" ]] && chroot_dir=$(find "${workspace}" -type d -name rootfs -path "*/artix/rootfs" 2>/dev/null | head -n1)

                        if [[ -n "${chroot_dir}" && -d "${chroot_dir}" ]]; then
                            mkdir -p "${iso_profile_dir}/airootfs/mnt/repo"
                            if ! build_nonrepo_for_offline "${target_kernel}" "${chroot_dir}" "${iso_profile_dir}/airootfs/mnt/repo"; then
                                log_warn "Falling back to linux for offline bundle"
                                generate_offline_package_list "${INIT:-openrc}" "linux" > "${iso_profile_dir}/packages-target.x86_64"
                                offline_pkg_list="${iso_profile_dir}/packages-target.x86_64"
                            fi
                        else
                            log_warn "Could not create chroot for kernel build — falling back to linux"
                            generate_offline_package_list "${INIT:-openrc}" "linux" > "${iso_profile_dir}/packages-target.x86_64"
                            offline_pkg_list="${iso_profile_dir}/packages-target.x86_64"
                        fi
                        ;;
                esac
            fi

            build_offline_repo "${iso_profile_dir}/airootfs/mnt/repo" "${offline_pkg_list}"
            mkdir -p "${iso_profile_dir}/airootfs/etc"
            cat > "${iso_profile_dir}/airootfs/etc/pacman.conf" <<'PACMAN'
[options]
Architecture = auto

[custom]
SigLevel = Optional
Server = file:///mnt/repo/

[system]
Include = /etc/pacman.d/mirrorlist-artix

[world]
Include = /etc/pacman.d/mirrorlist-artix

[galaxy]
Include = /etc/pacman.d/mirrorlist-artix
PACMAN
            echo "offline" > "${iso_stage_file}"
        else
            log_info "Skipping offline repo (already done)"
        fi
    fi

    local wm_de kernel_choice
    wm_de="$(state_get WM_DE none)"
    kernel_choice="$(state_get KERNEL_CHOICE linux)"

    local needs_chroot_build=0
    local de
    for de in "${DE_CHROOT_BUILD[@]}"; do
        [[ "${wm_de}" == "${de}" ]] && needs_chroot_build=1
    done
    local k
    for k in "${KERNEL_CHROOT_BUILD[@]}"; do
        [[ "${kernel_choice}" == "${k}" ]] && needs_chroot_build=1
    done

    log_info "Refreshing build keys..."
    pacman -S --noconfirm --needed artix-keyring
    pacman-key --populate artix
    pacman-key --recv-keys 78C9C713EAD7BEC69087447332E21894258C6105 --keyserver hkp://keyserver.ubuntu.com 2>/dev/null || true
    pacman-key --lsign-key 78C9C713EAD7BEC69087447332E21894258C6105 2>/dev/null || log_warn "Buildbot key trust failed – build may still work"

    if [[ ${needs_chroot_build} -eq 1 ]]; then
        if [[ "${iso_stage}" == "offline" || "${iso_stage}" == "profile" || "${iso_stage}" == "chroot" ]]; then
            log_info "Non-repo packages detected. Building chroot first..."

            buildiso -p "${profile_name}" -i "${init}" -c -x ${arch_flag} 2>&1 || die "buildiso -x failed"

            local chroot_dir=""
            local search_paths=(
                "/var/lib/artools/buildiso/${profile_name}/artix/rootfs"
                "${workspace}/buildiso/${profile_name}/artix/rootfs"
            )
            for candidate in "${search_paths[@]}"; do
                if [[ -d "${candidate}" && -x "${candidate}/bin/sh" ]]; then
                    chroot_dir="${candidate}"
                    break
                fi
            done
            if [[ -z "${chroot_dir}" ]]; then
                chroot_dir=$(find "${workspace}" -type d -name rootfs -path "*/artix/rootfs" 2>/dev/null | head -n1)
            fi

            local build_tools
            build_tools="$(printf '%s ' $(resolve_iso_build_tools))"

            if [[ -n "${chroot_dir}" && -d "${chroot_dir}" ]]; then
                log_info "Entering chroot at ${chroot_dir} to build non-repo packages..."
                if [[ "${wm_de}" == "mango" ]]; then
                    log_info "Building MangoWM from AUR..."
                    artix-chroot "${chroot_dir}" bash -c "
                        pacman -S --noconfirm --needed ${build_tools}
                        cd /tmp
                        rm -rf mangowm-git
                        git clone https://aur.archlinux.org/mangowm-git.git
                        chown -R nobody: /tmp/mangowm-git
                        su nobody -c 'cd /tmp/mangowm-git && makepkg -si --noconfirm'
                        rm -rf /tmp/mangowm-git
                    " || die "MangoWM build failed"
                fi
                if [[ "${wm_de}" == "vxwm" ]]; then
                    log_info "Building vxwm from source..."
                    artix-chroot "${chroot_dir}" bash -c "
                        pacman -S --noconfirm --needed ${build_tools} libx11 libxft libxinerama freetype2 xorg-server xorg-xinit
                        cd /tmp
                        git clone https://codeberg.org/wh1tepearl/vxwm.git
                        cd vxwm
                        make clean && make && make install
                        cd .. && rm -rf vxwm
                    " || die "vxwm build failed"
                fi
                if [[ "${kernel_choice}" == "linux-bazzite-bin" ]]; then
                    log_info "Building bazzite kernel from AUR..."
                    artix-chroot "${chroot_dir}" bash -c "
                        pacman -S --noconfirm --needed ${build_tools}
                        cd /tmp
                        git clone https://aur.archlinux.org/linux-bazzite-bin.git
                        chown -R nobody: /tmp/linux-bazzite-bin
                        su nobody -c 'cd /tmp/linux-bazzite-bin && makepkg -si --noconfirm --skippgpcheck'
                        rm -rf /tmp/linux-bazzite-bin
                    " || die "Bazzite kernel build failed"
                fi
            else
                die "Chroot directory not found – cannot customize ISO. Artools may have changed paths."
            fi

            log_info "Squashing chroot and generating ISO..."
            buildiso -p "${profile_name}" -i "${init}" -c -sc ${arch_flag} 2>&1 || die "buildiso -sc failed"
            buildiso -p "${profile_name}" -i "${init}" -c -zc ${arch_flag} 2>&1 || die "buildiso -zc failed"
            echo "chroot" > "${iso_stage_file}"
        else
            log_info "Skipping chroot build (already done)"
        fi
    fi

    if [[ "${iso_stage}" == "chroot" || "${iso_stage}" == "offline" || "${iso_stage}" == "profile" || "${iso_stage}" == "iso" ]]; then
        log_info "Building ISO (this may take a while)..."
        local iso_log="${workspace}/iso-build-$(date +%Y%m%d-%H%M%S).log"
        buildiso -p "${profile_name}" -i "${init}" -c ${arch_flag} 2>&1 | tee "${iso_log}"
        local rc=${PIPESTATUS[0]}

        if [[ ${rc} -eq 0 ]]; then
            local iso_file
            iso_file=$(find "${iso_output_dir}" -name '*.iso' -type f 2>/dev/null | head -n1)
            if [[ -n "${iso_file}" ]]; then
                mkdir -p "${user_output_dir}"
                cp "${iso_file}" "${user_output_dir}/"
                log_info "ISO created: ${user_output_dir}/${iso_file##*/}"
                log_info "Build log: ${iso_log}"
                cp "${iso_log}" "${user_output_dir}/" 2>/dev/null || true
                tui_msg_quick "ISO Ready" "ISO created at:\n${user_output_dir}/${iso_file##*/}\n\nBuild log:\n${user_output_dir}/iso-build-*.log"
            else
                log_error "ISO file not found in ${iso_output_dir}"
                die "buildiso completed but no ISO was produced"
            fi
        else
            log_error "ISO build failed. Check log: ${iso_log}"
            cp "${iso_log}" "${ISO_DIR}/" 2>/dev/null || true
            die "buildiso exited with an error"
        fi
        echo "iso" > "${iso_stage_file}"
    else
        log_info "ISO already built — locating existing ISO..."
    fi

    rm -rf /usr/share/artools/iso-profiles/"${profile_name}" 2>/dev/null || true

    rm -f "${iso_stage_file}"

    log_info "Build complete. Locating ISO..."
    local iso_file
    iso_file=$(find "${iso_output_dir}" -name '*.iso' -type f 2>/dev/null | head -n1)

    if [[ -n "${iso_file}" ]]; then
        mkdir -p "${user_output_dir}"
        cp "${iso_file}" "${user_output_dir}/"
        log_info "ISO created: ${user_output_dir}/${iso_file##*/}"
        tui_msg_quick "ISO Ready" "ISO created at:\n${user_output_dir}/${iso_file##*/}"
    else
        log_warn "ISO file not found in ${iso_output_dir}"
        log_warn "Check ${workspace} for the output"
    fi
}