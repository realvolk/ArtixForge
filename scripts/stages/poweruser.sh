#!/usr/bin/env bash
set -Eeuo pipefail

stage_poweruser() {
    if stage_should_skip poweruser; then return 0; fi

    [[ "$(state_get POWER_USER no)" == "yes" ]] || {
        log_warn "Power User mode not enabled, skipping source builds."
        stage_mark_done poweruser
        return 0
    }

    POWERUSER_DIR="${BASE_DIR}/poweruser"
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/deps.bash"
    source "${POWERUSER_DIR}/lib/queue.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"
    source "${POWERUSER_DIR}/lib/cache.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"
    source "${POWERUSER_DIR}/tui/progress.sh"
    source "${SCRIPT_DIR}/tui/core.sh"
    source "${SCRIPT_DIR}/common.sh"

    local profile_name
    profile_name="$(state_get POWERUSER_PROFILE default)"
    load_profile "${profile_name}"

    if [[ -n "${TARGET_ARCH:-}" && "${TARGET_ARCH}" != "x86_64" ]]; then
        log_info "Configuring cross-compilation for ${TARGET_ARCH}..."
        export CROSS_COMPILE="${CROSS_COMPILE:-}"
        export ARCH="${ARCH:-arm64}"
        export TARGET_ARCH
    fi

    if [[ ! -d /mnt/tmp ]]; then
        mkdir -p /mnt/tmp || die "/mnt/tmp does not exist and cannot be created"
    fi
    if [[ ! -w /mnt/tmp ]]; then
        die "/mnt/tmp is not writable. Is /mnt mounted?"
    fi
    log_info "Build target /mnt/tmp is writable"

    local recipe_count
    recipe_count=$(find "${POWERUSER_DIR}/recipes" -name '*.sh' ! -name 'template.sh' | wc -l)
    if [[ ${recipe_count} -eq 0 ]]; then
        log_info "No recipes found. Fetching OFFICIAL/Base from community repository..."
        local list_url="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main/.LIST"
        local repo_base="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main"
        if curl -fsSL "${list_url}" -o /tmp/artix-recipes.list 2>/dev/null; then
            while IFS='|' read -r name section desc; do
                if [[ "${section}" == "OFFICIAL/Base" ]]; then
                    log_info "  Downloading ${name}.sh..."
                    curl -sL "${repo_base}/${section}/${name}.sh" -o "${POWERUSER_DIR}/recipes/${name}.sh" || log_warn "Failed to download ${name}"
                fi
            done < /tmp/artix-recipes.list
            rm -f /tmp/artix-recipes.list
            log_info "Recipes downloaded."
        else
            log_warn "Could not reach community recipe repository. Only local recipes will be available."
        fi
    fi

    local -a selected_pkgs
    read -ra selected_pkgs <<< "$(state_get POWERUSER_PACKAGES)"
    [[ ${#selected_pkgs[@]} -gt 0 ]] || die "No packages selected for source build"

    local pkg
    for pkg in "${selected_pkgs[@]}"; do
        validate_recipe "${pkg}"
    done

    log_info "Resolving dependencies..."
    local -a build_order
    mapfile -t build_order < <(resolve_deps "${selected_pkgs[@]}")

    log_info "Build order: ${build_order[*]}"
    generate_queue "${build_order[@]}"

    check_disk_space 10 "${WORK_DIR}"

    local remaining
    while ! queue_all_done; do
        pkg="$(queue_next)"
        [[ -n "${pkg}" ]] || break

        remaining="$(queue_remaining)"
        log_info "[${pkg}] Building... (${remaining} remaining)"

        build_package "${pkg}"
        local build_rc=$?

        if [[ ${build_rc} -eq 0 ]]; then
            queue_mark "${pkg}" "done"
        else
            queue_mark "${pkg}" "failed"
            if [[ "${pkg}" == "linux" ]]; then
                if tui_yesno "Kernel Failed" "The custom kernel failed to build. Install the binary kernel instead?"; then
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
                    artix-chroot /mnt pacman -S --noconfirm "${kernel_pkg}" "${kernel_pkg}-headers"
                    state_set KEEP_BINARY_KERNEL "yes"
                    queue_mark "${pkg}" "done"
                    continue
                fi
            fi
            recoverable_error "Build failed for ${pkg} – updating ArtixForge may resolve this"
        fi
    done

    mkdir -p /mnt/etc/artix-poweruser
    printf '%s\n' "${selected_pkgs[@]}" > /mnt/etc/artix-poweruser/world.txt
    log_info "World file written to /etc/artix-poweruser/world.txt"

    mkdir -p /mnt/usr/local/bin /mnt/usr/share/artix-poweruser/{lib,tui,recipes,db,profile,build/{sources,artifacts,work,queue,logs}}
    cp "${POWERUSER_DIR}/bin/"* /mnt/usr/local/bin/
    chmod +x /mnt/usr/local/bin/anvil

    cp "${POWERUSER_DIR}/lib"/{common.sh,flags,recipe,validate,builder,cache,rebuild,kconfig,hwdetect}.bash /mnt/usr/share/artix-poweruser/lib/ 2>/dev/null || true
    cp "${POWERUSER_DIR}/lib/common.sh" /mnt/usr/share/artix-poweruser/lib/ 2>/dev/null || true

    cp "${POWERUSER_DIR}/profile"/*.sh /mnt/usr/share/artix-poweruser/profile/
    echo "${profile_name}" > /mnt/usr/share/artix-poweruser/profile/active

    cp "${POWERUSER_DIR}/VERSION" /mnt/usr/share/artix-poweruser/VERSION
    cp "${POWERUSER_DIR}/recipes"/template.sh /mnt/usr/share/artix-poweruser/recipes/

    touch /mnt/usr/share/artix-poweruser/db/local.db
    cp "${POWERUSER_DIR}/db/local.db" /mnt/usr/share/artix-poweruser/db/local.db 2>/dev/null || true

    log_info "anvil and all dependencies installed to target"

    tui_build_timing_summary
    validate_system

    log_info "All source packages built and installed."
    stage_mark_done poweruser
}