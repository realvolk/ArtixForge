#!/usr/bin/env bash
set -Eeuo pipefail

POWERUSER_BUILD_DIR="${POWERUSER_BUILD_DIR:-/mnt/artix-poweruser}"
SOURCES_DIR="${POWERUSER_BUILD_DIR}/sources"
WORK_DIR="${POWERUSER_BUILD_DIR}/work"
ARTIFACTS_DIR="${POWERUSER_BUILD_DIR}/artifacts"
LOGS_DIR="${POWERUSER_DIR}/build/logs"
STATS_DIR="${LOGS_DIR}/stats"
mkdir -p "${SOURCES_DIR}" "${WORK_DIR}" "${ARTIFACTS_DIR}" "${LOGS_DIR}" "${STATS_DIR}"
BASE_DIR="${BASE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

source "${POWERUSER_DIR}/lib/validate.bash"
source "${POWERUSER_DIR}/lib/common.sh"

build_package() {
    local recipe_name="${1}"
    local log_file="${LOGS_DIR}/${recipe_name}.log"
    local start_time end_time duration

    resolve_pkg_flags "${recipe_name}" || die "Failed to resolve flags for ${recipe_name}"
    resolve_flag_conflicts || die "Flag conflicts in ${recipe_name}"

    local dep_string
    dep_string=$(printf '%s\n' "${depends[@]}" "${makedepends[@]}" | sort -u | tr '\n' ' ')

    local patch_string=""
    if [[ -d "/etc/anvil/patches/${recipe_name}" ]]; then
        patch_string=$(find "/etc/anvil/patches/${recipe_name}" -name '*.patch' -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)
    fi

    local flags_h
    flags_h="$(flags_hash "${dep_string}" "${patch_string}")"
    if grep -q "^${pkgname}|${pkgver}-${pkgrel}|${flags_h}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null; then
        log_info "${pkgname}-${pkgver} already built — skipping"
        return 0
    fi

    validate_recipe "${recipe_name}"

    log_info "Building ${pkgname}-${pkgver}"
    start_time=$(date +%s)

    if [[ ${#makedepends[@]} -gt 0 ]]; then
        log_info "  Installing build dependencies: ${makedepends[*]}"
        pacman -S --noconfirm --needed "${makedepends[@]}" >> "${log_file}" 2>&1 || {
            log_error "Failed installing deps on live system"
            return 1
        }
    fi

    local pkg_work="${WORK_DIR}/${pkgname}"
    rm -rf "${pkg_work}"
    mkdir -p "${pkg_work}"
    local PKG_DESTDIR="${pkg_work}/pkg"
    mkdir -p "${PKG_DESTDIR}"
    export BUILD_DIR="${pkg_work}"
    export SOURCES_DIR PKG_DESTDIR

    local has_skip=0
    for src in "${sources[@]}"; do
        local checksum="${src#*|}"; checksum="${checksum%%|*}"
        [[ "${checksum}" == "SKIP" ]] && has_skip=1 && break
    done
    if [[ ${has_skip} -eq 1 ]]; then
        log_warn "Some sources for ${pkgname} have no checksums — source integrity NOT verified"
        if ! tui_yesno "Unverified Sources" "${pkgname} has sources without SHA256 checksums. Continue anyway?"; then
            die "User aborted due to missing checksums"
        fi
    fi

    log_info "Build started for ${pkgname} — tail -f ${LOGS_DIR}/${recipe_name}.log to watch"

    if ! fetch_sources "${recipe_name}" >> "${log_file}" 2>&1; then
        handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
        return $?
    fi

    if declare -f prepare >/dev/null 2>&1; then
        log_info "  Preparing ${pkgname}..."
        if ! ( cd "${pkg_work}" && prepare ) >> "${log_file}" 2>&1; then
            handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
            return $?
        fi
    fi

    local patch_dir="/etc/anvil/patches/${recipe_name}"
    if [[ -d "${patch_dir}" ]]; then
        log_info "  Applying user patches for ${recipe_name}..."
        local patch_file
        for patch_file in "${patch_dir}"/*.patch; do
            [[ -f "${patch_file}" ]] || continue
            log_info "    Applying $(basename "${patch_file}")..."
            if ! ( cd "${pkg_work}/src" && patch -Np1 < "${patch_file}" ) >> "${log_file}" 2>&1; then
                log_warn "    Patch $(basename "${patch_file}") failed to apply cleanly"
            fi
        done
    fi

    if declare -f configure >/dev/null 2>&1; then
        log_info "  Configuring ${pkgname}..."
        if ! ( cd "${pkg_work}" && configure ) >> "${log_file}" 2>&1; then
            handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
            return $?
        fi
    fi

    if [[ "${use_ccache:-false}" == "true" ]]; then
        command -v ccache &>/dev/null || pacman -S --noconfirm --needed ccache
        export CC="ccache gcc"
        export CXX="ccache g++"
        export CCACHE_DIR="${POWERUSER_DIR}/build/ccache"
        mkdir -p "${CCACHE_DIR}"
        log_info "  ccache enabled (${CCACHE_DIR})"
    fi

    log_info "  Building ${pkgname}..."
    if ! /usr/bin/time -v -o "${STATS_DIR}/${pkgname}.stats" \
        bash -c 'cd "${1}" && build' _ "${pkg_work}" >> "${log_file}" 2>&1; then
        handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
        return $?
    fi

    if declare -f check >/dev/null 2>&1; then
        log_info "  Checking ${pkgname}..."
        if ! ( cd "${pkg_work}" && check ) >> "${log_file}" 2>&1; then
            log_warn "Check phase failed (non-fatal)"
        fi
    fi

    log_info "  Packaging ${pkgname}..."
    if ! ( cd "${pkg_work}" && package ) >> "${log_file}" 2>&1; then
        handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
        return $?
    fi

    if [[ -n "${sub_packages:-}" ]]; then
        local sub
        for sub in "${sub_packages[@]}"; do
            if declare -f "package_${sub}" >/dev/null 2>&1; then
                log_info "  Packaging sub-package: ${sub}"
                local sub_destdir="${pkg_work}/pkg-${sub}"
                mkdir -p "${sub_destdir}"
                if ! ( cd "${pkg_work}" && PKG_DESTDIR="${sub_destdir}" "package_${sub}" ) >> "${log_file}" 2>&1; then
                    handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
                    return $?
                fi
                tar -caf "${ARTIFACTS_DIR}/${sub}-${pkgver}-${pkgrel}-x86_64.pkg.tar.zst" -C "${sub_destdir}" . 2>>"${log_file}" || {
                    log_warn "Failed to create artifact for ${sub}"
                }
                rsync -a --keep-dirlinks "${sub_destdir}/" /mnt/ 2>>"${log_file}" || true
                local sub_file_list
                sub_file_list=$(cd "${sub_destdir}" && find . -type f -o -type l | sed 's|^\./||' | sort | tr '\n' ',' | sed 's/,$//')
                printf '%s|%s-%s|%s|%s|%s|%s\n' \
                    "${sub}" "${pkgver}" "${pkgrel}" "${flags_h}" "$(date -I)" "${selected_features[*]}" "${sub_file_list}" \
                    >> "${POWERUSER_DIR}/db/local.db"
            fi
        done
    fi

    if [[ "${ANVIL_SAFETY_MODE:-}" == "strict" ]]; then
        log_info "  Running safety checks..."
        local failed=0
        while IFS= read -r -d '' binary; do
            if [[ " ${GLOBAL_FEATURES:-} " =~ " pie " ]]; then
                readelf -h "${binary}" 2>/dev/null | grep -q 'Type:.*DYN' || {
                    log_warn "  PIE missing: ${binary}"
                    failed=1
                }
            fi
            if [[ " ${GLOBAL_FEATURES:-} " =~ " relro " ]]; then
                readelf -l "${binary}" 2>/dev/null | grep -q 'GNU_RELRO' || {
                    log_warn "  RELRO missing: ${binary}"
                    failed=1
                }
            fi
            if [[ " ${GLOBAL_FEATURES:-} " =~ " stack-protector " ]]; then
                readelf -s "${binary}" 2>/dev/null | grep -q '__stack_chk_fail' || {
                    log_warn "  Stack protector missing: ${binary}"
                    failed=1
                }
            fi
        done < <(find "${PKG_DESTDIR}" -type f -executable -print0 2>/dev/null)

        if [[ ${failed} -eq 1 ]]; then
            die "Safety checks failed. Rebuild with correct flags or disable ANVIL_SAFETY_MODE."
        fi
        log_info "  Safety checks passed."
    fi

    log_info "  Creating package artifact..."
    tar -caf "${ARTIFACTS_DIR}/${pkgname}-${pkgver}-${pkgrel}-x86_64.pkg.tar.zst" -C "${PKG_DESTDIR}" . 2>>"${log_file}" || {
        log_warn "Failed to create artifact tarball (non-fatal)"
    }

    log_info "  Installing ${pkgname}..."
    if [[ "${pkgname}" == "linux-custom" ]]; then
        mkdir -p /mnt/boot /mnt/usr/lib/modules /mnt/etc/mkinitcpio.d
        cp -a "${PKG_DESTDIR}/boot/." /mnt/boot/ 2>>"${log_file}" || {
            log_error "Failed to copy kernel to /mnt/boot"
            handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
            return 1
        }
        if [[ -d "${PKG_DESTDIR}/lib/modules" ]]; then
            cp -a "${PKG_DESTDIR}/lib/modules/." /mnt/usr/lib/modules/ 2>>"${log_file}" || true
        fi
        cat > /mnt/etc/mkinitcpio.d/linux-custom.preset <<'PRESET'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-custom"
PRESETS=('default')
default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux-custom.img"
PRESET
    else
        if command -v rsync >/dev/null 2>&1; then
            if ! rsync -a --keep-dirlinks "${PKG_DESTDIR}/" /mnt/ 2>>"${log_file}"; then
                log_error "Failed to install ${pkgname} to /mnt"
                handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
                return 1
            fi
        else
            pacman -S --noconfirm --needed rsync 2>/dev/null || true
            if ! rsync -a --keep-dirlinks "${PKG_DESTDIR}/" /mnt/ 2>>"${log_file}"; then
                log_error "Failed to install ${pkgname} to /mnt"
                handle_build_failure "${recipe_name}" "${log_file}" "${pkg_work}"
                return 1
            fi
        fi
    fi

    local file_list
    file_list=$(cd "${PKG_DESTDIR}" && find . -type f -o -type l | sed 's|^\./||' | sort | tr '\n' ',' | sed 's/,$//')

    printf '%s|%s-%s|%s|%s|%s|%s\n' \
        "${pkgname}" "${pkgver}" "${pkgrel}" "${flags_h}" "$(date -I)" "${selected_features[*]}" "${file_list}" \
        >> "${POWERUSER_DIR}/db/local.db"

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    printf '%s|%s|%d\n' "${pkgname}" "success" "${duration}" >> "${LOGS_DIR}/timing.log"
    log_info "  ${pkgname} — done (${duration}s)"
    return 0
}

build_queue_parallel() {
    local max_jobs="${1:-$(nproc)}"
    local -A done_pkgs=()
    local -A running_pids=()
    local pkg

    while ! queue_all_done; do
        local -a ready=()
        while IFS='|' read -r pkg status; do
            [[ "${status}" == "pending" ]] || continue
            local deps_satisfied=1
            load_recipe "${pkg}"
            for dep in "${depends[@]}" "${makedepends[@]}"; do
                [[ -n "${done_pkgs[${dep}]:-}" ]] && continue
                pacman -Q "${dep}" &>/dev/null && continue
                deps_satisfied=0
                break
            done
            [[ ${deps_satisfied} -eq 1 ]] && ready+=("${pkg}")
        done < "${QUEUE_DIR}/status.txt"

        for pkg in "${ready[@]}"; do
            if [[ ${#running_pids[@]} -ge ${max_jobs} ]]; then
                break
            fi
            log_info "[${pkg}] Starting build (parallel, ${#running_pids[@]}/${max_jobs} running)..."
            build_package "${pkg}" &
            running_pids["${pkg}"]=$!
        done

        if [[ ${#running_pids[@]} -gt 0 ]]; then
            local finished_pid
            finished_pid=$(wait -n 2>/dev/null || true)
            for pkg in "${!running_pids[@]}"; do
                if [[ "${running_pids[${pkg}]}" == "${finished_pid}" ]]; then
                    local rc=0
                    wait "${finished_pid}" || rc=$?
                    if [[ ${rc} -eq 0 ]]; then
                        queue_mark "${pkg}" "done"
                        done_pkgs["${pkg}"]=1
                    else
                        queue_mark "${pkg}" "failed"
                        log_error "[${pkg}] Build failed"
                    fi
                    unset running_pids["${pkg}"]
                    break
                fi
            done
        fi
    done

    for pkg in "${!running_pids[@]}"; do
        wait "${running_pids[${pkg}]}" || true
        queue_mark "${pkg}" "failed"
    done
}

handle_build_failure() {
    local recipe_name="${1}" log="${2}" work_dir="${3}"
    log_error "Build failed for ${recipe_name}. Check ${log}"

    while true; do
        local action
        if [[ "${recipe_name}" == "linux" ]]; then
            action=$(tui_menu "Build Failed" "${recipe_name} failed." \
                "Retry" \
                "Skip" \
                "Debug shell" \
                "Repair kernel (recovery mode)" \
                "Update ArtixForge and retry" \
                "Install binary kernel instead" \
                "Heal recipe (auto-detect new version)" \
                "Abort") || action="Abort"
        else
            action=$(tui_menu "Build Failed" "${recipe_name} failed." \
                "Retry" \
                "Skip" \
                "Debug shell" \
                "Update ArtixForge and retry" \
                "Abort") || action="Abort"
        fi

        case "${action}" in
            Retry)
                log_info "Retrying ${recipe_name}..."
                rm -rf "${work_dir}"
                if build_package "${recipe_name}"; then
                    return 0
                fi
                ;;
            Skip)
                log_warn "Skipping ${recipe_name}"
                printf '%s|%s|%d\n' "${recipe_name}" "skipped" 0 >> "${LOGS_DIR}/timing.log"
                return 0
                ;;
            "Debug shell")
                log_info "Dropping to shell in ${work_dir}. Type 'exit' to return."
                ( cd "${work_dir}" && bash )
                ;;
            "Repair kernel (recovery mode)")
                log_info "Running kernel repair..."
                source "${SCRIPT_DIR}/recovery/repair.sh"
                repair_kernel
                if [[ -f /mnt/boot/vmlinuz-linux-custom ]]; then
                    queue_mark "${recipe_name}" "done"
                    return 0
                fi
                log_warn "Repair attempted. You may need to try again or install the binary kernel."
                ;;
            "Update ArtixForge and retry")
                log_info "Updating ArtixForge from GitHub..."
                local update_dir="/tmp/artixforge-update"
                rm -rf "${update_dir}"
                git clone --depth 1 https://github.com/realvolk/ArtixForge.git "${update_dir}" || {
                    log_error "Failed to clone ArtixForge"
                    continue
                }
                cp -a "${update_dir}/." "${BASE_DIR}/"
                rm -rf "${update_dir}"
                log_info "ArtixForge updated. Restarting installer..."
                cd "${BASE_DIR}"
                exec sudo "${BASE_DIR}/install"
                ;;
            "Install binary kernel instead")
                log_info "Installing binary kernel as fallback..."
                local kernel_choice kernel_pkg
                kernel_choice="$(state_get KERNEL_CHOICE linux)"
                case "${kernel_choice}" in
                    linux)          kernel_pkg="linux" ;;
                    linux-zen)      kernel_pkg="linux-zen" ;;
                    linux-lts)      kernel_pkg="linux-lts" ;;
                    linux-hardened) kernel_pkg="linux-hardened" ;;
                    *)              kernel_pkg="linux" ;;
                esac
                artix-chroot /mnt pacman -S --noconfirm "${kernel_pkg}" "${kernel_pkg}-headers" || {
                    log_error "Failed to install binary kernel"
                    continue
                }
                log_info "Binary kernel ${kernel_pkg} installed as fallback"
                state_set KEEP_BINARY_KERNEL "yes"
                printf '%s|%s|%d\n' "${recipe_name}" "binary-fallback" 0 >> "${LOGS_DIR}/timing.log"
                return 0
                ;;
            "Heal recipe (auto-detect new version)")
                log_info "Attempting to heal recipe ${recipe_name}..."
                if [[ -f "${POWERUSER_DIR}/lib/heal.bash" ]]; then
                    source "${POWERUSER_DIR}/lib/heal.bash"
                    if heal_recipe "${recipe_name}"; then
                        log_info "Recipe healed — retrying build..."
                        rm -rf "${work_dir}"
                        if build_package "${recipe_name}"; then
                            return 0
                        fi
                    else
                        log_warn "Heal failed — recipe may need manual intervention"
                    fi
                else
                    log_warn "heal.bash not found — cannot auto-heal"
                fi
                ;;
            Abort)
                die "Build aborted by user"
                ;;
        esac
    done
}

fetch_sources() {
    local recipe_name="${1}"
    load_recipe "${recipe_name}"

    for src in "${sources[@]}"; do
        local url checksum filename
        url="${src%%|*}"
        checksum="${src#*|}"; checksum="${checksum%%|*}"
        filename="${src##*|}"

        local dest="${SOURCES_DIR}/${filename}"
        if [[ -f "${dest}" ]]; then
            local actual
            actual="$(sha256sum "${dest}" | cut -d' ' -f1)"
            if [[ "${actual}" == "${checksum}" ]]; then
                continue
            fi
        fi

        log_info "  Fetching ${filename}..."
        curl_resume "${url}" "${dest}" || { log_error "Download failed: ${url}"; return 1; }

        if [[ -n "${checksum}" && "${checksum}" != "SKIP" ]]; then
            local actual
            actual="$(sha256sum "${dest}" | cut -d' ' -f1)"
            [[ "${actual}" == "${checksum}" ]] || { log_error "Checksum mismatch: ${filename}"; return 1; }
        elif [[ "${checksum}" == "SKIP" ]]; then
            log_warn "Checksum verification SKIPPED for ${filename} — source integrity NOT verified"
        fi
    done
}

build_package_isolated() {
    local recipe_name="${1}"
    local isolated_root="${POWERUSER_DIR}/build/isolated"
    
    log_info "Setting up isolated build environment..."
    mkdir -p "${isolated_root}"
    
    if [[ ! -x "${isolated_root}/bin/sh" ]]; then
        log_info "Bootstrapping minimal rootfs..."
        basestrap "${isolated_root}" base base-devel bash pacman || die "Failed to bootstrap isolated rootfs"
    fi
    
    resolve_pkg_flags "${recipe_name}" || die "Failed to resolve flags"
    
    local -a isolate_pkgs=("${makedepends[@]}")
    if [[ "${use_ccache:-false}" == "true" ]]; then
        isolate_pkgs+=(ccache)
    fi
    
    if [[ ${#isolate_pkgs[@]} -gt 0 ]]; then
        log_info "Installing build dependencies in isolated rootfs..."
        artix-chroot "${isolated_root}" pacman -S --noconfirm --needed "${isolate_pkgs[@]}" || {
            log_error "Failed to install dependencies in isolated rootfs"
            return 1
        }
    fi
    
    mkdir -p "${isolated_root}/tmp/build/sources" "${isolated_root}/tmp/build/work" "${isolated_root}/tmp/build/pkg"
    cp -a "${SOURCES_DIR}/." "${isolated_root}/tmp/build/sources/" 2>/dev/null || true
    cp "${POWERUSER_DIR}/recipes/${recipe_name}.sh" "${isolated_root}/tmp/build/recipe.sh"
    
    for lib in common.sh flags.bash recipe.bash builder.bash validate.bash cache.bash; do
        [[ -f "${POWERUSER_DIR}/lib/${lib}" ]] && cp "${POWERUSER_DIR}/lib/${lib}" "${isolated_root}/tmp/build/"
    done
    
    log_info "Building ${recipe_name} in isolated environment..."
    artix-chroot "${isolated_root}" bash -c "
        export POWERUSER_DIR=/tmp/build
        export BUILD_DIR=/tmp/build/work
        export SOURCES_DIR=/tmp/build/sources
        export PKG_DESTDIR=/tmp/build/pkg
        export ARTIX_CFLAGS='${ARTIX_CFLAGS}'
        export ARTIX_CXXFLAGS='${ARTIX_CXXFLAGS}'
        export ARTIX_LDFLAGS='${ARTIX_LDFLAGS}'
        export ARTIX_MAKEFLAGS='${ARTIX_MAKEFLAGS}'
        export selected_features='${selected_features[*]}'
        
        source /tmp/build/common.sh
        source /tmp/build/flags.bash
        source /tmp/build/recipe.bash
        source /tmp/build/builder.bash
        
        load_recipe /tmp/build/recipe.sh
        fetch_sources /tmp/build/recipe.sh
        
        cd /tmp/build/work
        [[ \"\$(type -t prepare)\" == 'function' ]] && prepare
        [[ \"\$(type -t configure)\" == 'function' ]] && configure
        build
        [[ \"\$(type -t package)\" == 'function' ]] && package
    " || {
        log_error "Isolated build failed"
        return 1
    }
    
    if [[ -d "${isolated_root}/tmp/build/pkg" ]]; then
        rsync -a --keep-dirlinks "${isolated_root}/tmp/build/pkg/" "${PKG_DESTDIR}/" 2>/dev/null || true
        log_info "Isolated build artifacts copied to ${PKG_DESTDIR}"
    fi
    
    log_info "Isolated build complete."
}

anvil_world_stage() {
    local stage_dir="${1:-/nextroot}"
    require_root

    log_info "Building world into ${stage_dir}..."
    mkdir -p "${stage_dir}"

    local saved_mnt="${POWERUSER_BUILD_DIR}"
    POWERUSER_BUILD_DIR="${stage_dir}/artix-poweruser"
    SOURCES_DIR="${POWERUSER_BUILD_DIR}/sources"
    WORK_DIR="${POWERUSER_BUILD_DIR}/work"
    ARTIFACTS_DIR="${POWERUSER_BUILD_DIR}/artifacts"
    mkdir -p "${SOURCES_DIR}" "${WORK_DIR}" "${ARTIFACTS_DIR}"

    local world_file="${POWERUSER_DIR}/world"
    local -a world_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "${pkg}" && "${pkg}" != \#* ]] && world_pkgs+=("${pkg}")
    done < "${world_file}"

    local -a build_order
    mapfile -t build_order < <(resolve_deps "${world_pkgs[@]}")

    generate_queue "${build_order[@]}"

    local pkg
    while ! queue_all_done; do
        pkg=$(queue_next)
        [[ -n "${pkg}" ]] || break
        log_info "[${pkg}] Building... ($(queue_remaining) remaining)"
        resolve_pkg_flags "${pkg}"
        local saved_destdir="${PKG_DESTDIR}"
        PKG_DESTDIR="${stage_dir}"
        build_package "${pkg}" && queue_mark "${pkg}" "done" || queue_mark "${pkg}" "failed"
        PKG_DESTDIR="${saved_destdir}"
    done

    POWERUSER_BUILD_DIR="${saved_mnt}"

    if [[ -f "${stage_dir}/boot/vmlinuz-linux-custom" ]]; then
        log_info "Generating initramfs for staged system..."
        mkdir -p "${stage_dir}/etc/mkinitcpio.d"
        cp /etc/mkinitcpio.conf "${stage_dir}/etc/mkinitcpio.conf" 2>/dev/null || true
        mkinitcpio -k "${stage_dir}/boot/vmlinuz-linux-custom" \
            -c "${stage_dir}/etc/mkinitcpio.conf" \
            -g "${stage_dir}/boot/initramfs-linux-custom.img" || log_warn "mkinitcpio failed"
    fi

    log_info "System staged at ${stage_dir}"
}

anvil_activate() {
    local stage_dir="${1:-/nextroot}"
    require_root
    [[ -d "${stage_dir}/bin" ]] || die "No staged system found at ${stage_dir}"

    if [[ "$(stat -f --format=%T / 2>/dev/null)" == "btrfs" ]]; then
        log_info "BTRFS detected — performing atomic subvolume swap..."
        local current_snap="/.snapshots/pre-anvil-$(date +%Y%m%d-%H%M%S)"
        btrfs subvolume snapshot / "${current_snap}"
        log_info "Current root snapshot saved to ${current_snap}"

        rsync -a --delete --keep-dirlinks "${stage_dir}/" / || die "Rsync failed"
        sync

        log_info "Activation complete. Reboot to use the new system."
        log_info "Rollback: btrfs subvolume set-default ${current_snap}"
    else
        log_info "Non-BTRFS — performing kexec cutover..."
        local kernel="${stage_dir}/boot/vmlinuz-linux-custom"
        local initramfs="${stage_dir}/boot/initramfs-linux-custom.img"
        [[ -f "${kernel}" ]] || kernel=$(find "${stage_dir}/boot" -name 'vmlinuz-*' | head -n1)
        [[ -f "${initramfs}" ]] || initramfs=$(find "${stage_dir}/boot" -name 'initramfs-*.img' | head -n1)

        [[ -f "${kernel}" ]] || die "No kernel found in staged system"
        [[ -f "${initramfs}" ]] || die "No initramfs found in staged system"

        local root_dev
        root_dev=$(findmnt -no SOURCE /)
        local cmdline="root=${root_dev} rw init=/sbin/init"

        log_info "Loading new kernel via kexec..."
        kexec -l "${kernel}" --initrd="${initramfs}" --command-line="${cmdline}" || die "kexec load failed"
        log_info "Kernel loaded. Running kexec -e..."
        sync
        kexec -e
    fi
}

deploy_sd_card() {
    local target_device="${1}"
    local board="${BOARD_NAME:-unknown}"
    [[ -b "${target_device}" ]] || die "Invalid target device: ${target_device}"

    log_info "Deploying to ${target_device} for ${board}..."

    parted -s "${target_device}" mklabel msdos
    parted -s "${target_device}" mkpart primary fat32 1MiB 101MiB
    parted -s "${target_device}" mkpart primary ext4 101MiB 100%
    mkfs.vfat -F32 "${target_device}1"
    mkfs.ext4 -F "${target_device}2"

    local tmp_boot="/tmp/arm-boot-$$"
    local tmp_root="/tmp/arm-root-$$"
    mkdir -p "${tmp_boot}" "${tmp_root}"
    mount "${target_device}1" "${tmp_boot}"
    mount "${target_device}2" "${tmp_root}"

    rsync -a /mnt/ "${tmp_root}/" || die "Failed to copy rootfs"
    cp /mnt/boot/* "${tmp_boot}/" 2>/dev/null || true

    if [[ -f /mnt/usr/share/uboot/${board}/u-boot.bin ]]; then
        dd if="/mnt/usr/share/uboot/${board}/u-boot.bin" of="${target_device}" seek=64 conv=fsync 2>/dev/null || log_warn "U-Boot write failed"
    fi

    umount "${tmp_boot}" "${tmp_root}"
    rmdir "${tmp_boot}" "${tmp_root}"
    log_info "Deployment complete. Insert SD card into ${board} and boot."
}