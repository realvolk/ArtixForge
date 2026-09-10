#!/usr/bin/env bash
set -Eeuo pipefail

fetch_recipe() {
    local name="${1}"
    require_root
    load_sections
    [[ -f "${LOCAL_LIST}" ]] || fetch_list || die "No recipe list available."

    local section
    section=$(awk -F'|' -v pkg="${name}" '$1 == pkg {print $2}' "${LOCAL_LIST}")
    [[ -n "${section}" ]] || { echo "Recipe '${name}' not found in .LIST"; return 1; }

    local allowed=0
    for s in ${ANVIL_SECTIONS}; do
        [[ "${section}" == "${s}" ]] && allowed=1 && break
    done
    [[ ${allowed} -eq 1 ]] || {
        echo "Section '${section}' is not enabled. Enable it with: anvil sections"
        return 1
    }

    local url="${RECIPES_REPO}/${section}/${name}.sh"
    local dest="${POWERUSER_DIR}/recipes/${name}.sh"

    if [[ -f "${dest}" ]]; then
        if ! tui_yesno "Overwrite?" "${name}.sh already exists. Overwrite?"; then
            return 0
        fi
        cp "${dest}" "${POWERUSER_DIR}/recipes.old/${name}.sh.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    fi

    mkdir -p "${POWERUSER_DIR}/recipes.old"
    log_info "Downloading ${name}.sh from ${section}..."
    curl -sL "${url}" -o "${dest}" || { log_error "Failed to download ${url}"; return 1; }
    _recipe_git_commit "fetch ${name} from ${section}"
    echo "Recipe ${name} downloaded to ${dest}"
}

fetch_all_sources() {
    require_root
    load_sections
    [[ -f "${LOCAL_LIST}" ]] || fetch_list || { echo "No recipe list."; return 1; }

    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"

    local IFS='|'
    while read -r name section desc; do
        local allowed=0
        for s in ${ANVIL_SECTIONS}; do
            [[ "${section}" == "${s}" ]] && allowed=1 && break
        done
        [[ ${allowed} -eq 0 ]] && continue
        echo "[*] Fetching sources for ${name}..."
        load_recipe "${name}" 2>/dev/null || {
            log_warn "Recipe ${name} not installed locally — skipping source fetch. Use 'fetch-recipe ${name}' first."
            continue
        }
        fetch_sources "${name}" 2>&1 || log_warn "Failed to fetch ${name}"
    done < "${LOCAL_LIST}"
    echo "[*] All available sources downloaded. You can now build offline."
}

sync_recipes() {
    require_root
    load_sections
    _recipe_git_init
    fetch_list || return 1

    echo "Available recipes (enabled sections: ${ANVIL_SECTIONS}):"
    list_available
    echo ""
    if tui_yesno "Update all?" "Download/update all enabled recipes from the community repo?"; then
        local IFS='|'
        while read -r name section desc; do
            local allowed=0
            for s in ${ANVIL_SECTIONS}; do
                [[ "${section}" == "${s}" ]] && allowed=1 && break
            done
            [[ ${allowed} -eq 0 ]] && continue
            echo "[*] Updating ${name}..."
            local url="${RECIPES_REPO}/${section}/${name}.sh"
            local dest="${POWERUSER_DIR}/recipes/${name}.sh"
            curl -sL "${url}" -o "${dest}" || log_warn "Failed to download ${name}"
        done < "${LOCAL_LIST}"
        echo "All enabled recipes updated."
        _recipe_git_commit "sync recipes"
    fi
}

rebuild_package() {
    local pkg="" target="x86_64" isolated=0
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --target) target="${2}"; shift 2 ;;
            --isolated) isolated=1; shift ;;
            *) pkg="${1}"; shift ;;
        esac
    done

    [[ -n "${pkg}" ]] || { echo "Usage: anvil rebuild [--target arch] [--isolated] <pkg>"; return 1; }
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"
    source "${POWERUSER_DIR}/lib/cache.bash"
    source "${POWERUSER_DIR}/lib/rebuild.bash"

    load_profile "$(cat ${POWERUSER_DIR}/profile/active 2>/dev/null || echo default)"
    resolve_pkg_flags "${pkg}"

    if [[ "${target}" != "x86_64" ]]; then
        local cross_profile="${POWERUSER_DIR}/profile/cross-${target}.sh"
        [[ -f "${cross_profile}" ]] || die "Cross-compilation profile not found: ${cross_profile}"
        source "${cross_profile}"
        export CROSS_COMPILE="${CROSS_COMPILE:-${target}-linux-gnu-}"
        export ARCH="${ARCH:-arm64}"
        ARTIFACTS_DIR="${ARTIFACTS_DIR}/${target}"
        mkdir -p "${ARTIFACTS_DIR}"
    fi

    if [[ ${isolated} -eq 1 ]]; then
        build_package_isolated "${pkg}"
        return $?
    fi

    if ! needs_rebuild "${pkg}"; then
        echo "${pkg} is up-to-date. Nothing to rebuild."
        return 0
    fi

    echo "Rebuilding ${pkg}..."
    build_package "${pkg}"
}

new_recipe() {
    local name="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${name}.sh"
    if [[ -f "${recipe_file}" ]]; then
        echo "Recipe ${name} already exists. Use 'edit' to modify it."
        exit 1
    fi
    cp "${POWERUSER_DIR}/recipes/template.sh" "${recipe_file}"
    ${EDITOR:-nano} "${recipe_file}"
    _recipe_git_commit "create ${name}"
    echo "Recipe ${name} created. Run 'anvil lint ${name}' to validate."
}

edit_recipe() {
    local name="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${name}.sh"
    [[ -f "${recipe_file}" ]] || { echo "Recipe ${name} not found."; exit 1; }
    ${EDITOR:-nano} "${recipe_file}"
    _recipe_git_commit "edit ${name}"
}

edit_config() {
    require_root
    local config_file="/boot/config-$(uname -r)"
    if [[ -f "${config_file}" ]]; then
        ${EDITOR:-nano} "${config_file}"
    else
        echo "No config found at ${config_file}"
        echo "Run 'anvil rebuild linux' to regenerate the kernel and its config."
        exit 1
    fi
    echo "Config edited. Rebuild with: anvil rebuild linux"
}

launch_menuconfig() {
    require_root
    local src_dir="/usr/src/linux-custom"
    if [[ -d "${src_dir}" ]]; then
        cd "${src_dir}"
        make menuconfig
        echo "Config saved. Rebuild with: anvil rebuild linux"
    else
        echo "Kernel source not found at ${src_dir}"
        echo "Run 'anvil fetch-source linux' to download the kernel source."
        exit 1
    fi
}

fetch_source() {
    local pkg="${1}"
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"

    load_recipe "${pkg}"
    fetch_sources "${pkg}"
    local src_dir="/usr/src/linux-custom"
    mkdir -p "${src_dir}"
    cd "${src_dir}"
    export BUILD_DIR="${src_dir}"
    export SOURCES_DIR="${POWERUSER_BUILD_DIR:-/var/cache/artix-poweruser}/sources"
    mkdir -p "${SOURCES_DIR}"
    fetch_sources "${pkg}" 2>/dev/null
    if declare -f prepare >/dev/null 2>&1; then
        prepare
    fi
    echo "Source ready in ${src_dir}"
}

lint_recipe() {
    local name="${1}"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"
    if validate_recipe "${name}" 2>&1; then
        echo "Recipe ${name} is valid."
    else
        echo "Recipe ${name} has errors (see above)."
        exit 1
    fi
}

checksum_recipe() {
    local name="${1}"
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    load_recipe "${name}"
    
    local url filename hash
    for src in "${sources[@]}"; do
        url="${src%%|*}"
        filename="${src##*|}"
        log_info "Fetching ${filename}..."
        curl -L -o "/tmp/${filename}" "${url}" || { log_error "Failed to fetch ${url}"; continue; }
        hash=$(sha256sum "/tmp/${filename}" | cut -d' ' -f1)
        printf '%s|%s|%s\n' "${url}" "${hash}" "${filename}"
        rm -f "/tmp/${filename}"
    done
}

_anvil_diff_recipe() {
    local name="${1}" old_file="${2}" new_file="${3}"

    if [[ ! -f "${old_file}" ]]; then
        _filly_send '{"widget":"msg","params":{"title":"New Recipe: '"${name}"'","message":"This is a new recipe. No diff available."}}' >/dev/null
        return 0
    fi

    local old_content new_content
    old_content=$(cat "${old_file}" | sed 's/"/\\"/g' | tr '\n' ' ')
    new_content=$(cat "${new_file}" | sed 's/"/\\"/g' | tr '\n' ' ')

    local left_widget right_widget
    left_widget=$(printf '{"widget":"msg","params":{"title":"Old: %s","message":"%s"}}' "${name}" "${old_content}")
    right_widget=$(printf '{"widget":"msg","params":{"title":"New: %s","message":"%s"}}' "${name}" "${new_content}")

    local diff_json
    diff_json=$(printf '{"widget":"split_panes","params":{"orientation":"horizontal","first":%s,"second":%s}}' \
        "${left_widget}" "${right_widget}")

    "${FILLY_BIN}" oneshot --input <(printf '%s\n' "${diff_json}") 2>/dev/null >/dev/null
}

upgrade_anvil() {
    require_root
    _recipe_git_init
    local recipe_dir="${POWERUSER_DIR}/recipes"
    local backup_dir="${POWERUSER_DIR}/recipes.old"
    local version_file="${POWERUSER_DIR}/VERSION"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="${backup_dir}/${timestamp}"

    local current_version="unknown"
    [[ -f "${version_file}" ]] && current_version=$(tr -d '[:space:]' < "${version_file}")

    local remote_version=""
    if [[ -d "${recipe_dir}/.git" ]]; then
        remote_version=$(cd "${recipe_dir}" && git ls-remote origin HEAD 2>/dev/null | cut -f1)
        remote_version="${remote_version:0:8}"
    fi

    echo "[*] Installed Power User version: ${current_version}"
    echo "[*] Latest available version: ${remote_version:-unknown}"

    if [[ "${current_version}" == "${remote_version}" ]] && [[ -n "${remote_version}" ]]; then
        echo "[*] Already up-to-date. Nothing to upgrade."
        return 0
    fi

    echo "[*] Backing up current recipes to ${backup_path}..."
    mkdir -p "${backup_path}"
    if compgen -G "${recipe_dir}/*.sh" >/dev/null 2>&1; then
        cp -a "${recipe_dir}"/*.sh "${backup_path}/" 2>/dev/null || true
    fi

    [[ -f "${version_file}" ]] && cp "${version_file}" "${backup_path}/VERSION"

    echo "[*] Pulling latest recipes..."
    if [[ -d "${recipe_dir}/.git" ]]; then
        cd "${recipe_dir}"
        local before after
        before=$(git rev-parse HEAD 2>/dev/null | cut -c1-8 || echo "unknown")
        git pull 2>&1 || { echo "[!] git pull failed."; return 1; }
        after=$(git rev-parse HEAD 2>/dev/null | cut -c1-8 || echo "unknown")
        echo "[*] Updated from ${before} to ${after}"
    else
        echo "[!] Recipe directory is not a git repository. Manual update required."
        return 1
    fi

    if [[ -f "${recipe_dir}/../VERSION" ]]; then
        cp "${recipe_dir}/../VERSION" "${version_file}"
        local new_version
        new_version=$(tr -d '[:space:]' < "${version_file}")
        echo "[*] Power User updated to v${new_version}"
    fi

    echo "[*] Checking for changed recipes..."
    local changed=()
    for recipe in "${recipe_dir}"/*.sh; do
        [[ -f "${recipe}" ]] || continue
        local name
        name=$(basename "${recipe}")
        if [[ -f "${backup_path}/${name}" ]]; then
            if ! cmp -s "${recipe}" "${backup_path}/${name}"; then
                changed+=("${name}")
            fi
        else
            changed+=("${name} (new)")
        fi
    done

    if [[ ${#changed[@]} -gt 0 ]]; then
        echo "[*] Changed or new recipes:"
        for c in "${changed[@]}"; do
            echo "    - ${c}"
        done
        echo ""

        if tui_yesno "Review Changes" "Review diffs for changed recipes?"; then
            for c in "${changed[@]}"; do
                local name="${c% (new)}"
                local is_new=0
                [[ "${c}" == *" (new)" ]] && is_new=1

                local old_file="${backup_path}/${name}"
                local new_file="${recipe_dir}/${name}"

                if [[ ${is_new} -eq 1 ]]; then
                    _filly_send '{"widget":"msg","params":{"title":"New Recipe: '"${name}"'","message":"This recipe was added in this update."}}' >/dev/null
                elif [[ -f "${old_file}" && -f "${new_file}" ]]; then
                    _anvil_diff_recipe "${name}" "${old_file}" "${new_file}"
                fi
            done
        fi

        echo "[*] Old recipes saved to ${backup_path}"
        echo "[*] Run 'anvil rebuild <recipe>' for any changed packages."
    else
        echo "[*] No recipe changes detected."
    fi
    _recipe_git_commit "upgrade from ${current_version}"
}

_recipe_git_init() {
    local recipe_dir="${POWERUSER_DIR}/recipes"
    if [[ ! -d "${recipe_dir}/.git" ]]; then
        cd "${recipe_dir}"
        git init
        git config user.email "anvil@localhost"
        git config user.name "anvil"
        git add -A
        git commit -m "Initial recipe state" 2>/dev/null || true
    fi
}

_recipe_git_commit() {
    local recipe_dir="${POWERUSER_DIR}/recipes"
    local msg="${1:-recipe update}"
    [[ -d "${recipe_dir}/.git" ]] || return 0
    cd "${recipe_dir}"
    git add -A
    git commit -m "${msg}" 2>/dev/null || true
}

anvil_log() {
    local pkg="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${pkg}.sh"
    [[ -f "${recipe_file}" ]] || { echo "Recipe ${pkg} not found."; return 1; }
    local recipe_dir="${POWERUSER_DIR}/recipes"
    [[ -d "${recipe_dir}/.git" ]] || { echo "No git history. Run 'anvil upgrade' first."; return 1; }
    cd "${recipe_dir}"
    git log --oneline -- "${pkg}.sh"
}

anvil_diff() {
    local pkg="${1}"
    local recipe_file="${POWERUSER_DIR}/recipes/${pkg}.sh"
    [[ -f "${recipe_file}" ]] || { echo "Recipe ${pkg} not found."; return 1; }
    local recipe_dir="${POWERUSER_DIR}/recipes"
    [[ -d "${recipe_dir}/.git" ]] || { echo "No git history."; return 1; }
    cd "${recipe_dir}"
    git diff HEAD~1 -- "${pkg}.sh"
}

anvil_rollback_recipe() {
    local pkg="${1}" commit="${2}"
    [[ -n "${pkg}" && -n "${commit}" ]] || { echo "Usage: anvil rollback-recipe <pkg> <commit>"; return 1; }
    local recipe_dir="${POWERUSER_DIR}/recipes"
    [[ -d "${recipe_dir}/.git" ]] || { echo "No git history."; return 1; }
    cd "${recipe_dir}"
    git checkout "${commit}" -- "${pkg}.sh"
    _recipe_git_commit "rollback ${pkg} to ${commit}"
    echo "${pkg} rolled back to ${commit}."
}

anvil_files() {
    local pkg="${1}"
    [[ -n "${pkg}" ]] || { echo "Usage: anvil files <pkg>"; return 1; }
    local entry
    entry=$(grep "^${pkg}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null | tail -n1)
    [[ -n "${entry}" ]] || { echo "Package ${pkg} not found in database."; return 1; }
    local files
    files=$(echo "${entry}" | cut -d'|' -f6)
    printf '%s\n' "${files}" | tr ',' '\n'
}

anvil_verify() {
    local pkg="${1}"
    [[ -n "${pkg}" ]] || { echo "Usage: anvil verify <pkg>"; return 1; }
    require_root
    local entry
    entry=$(grep "^${pkg}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null | tail -n1)
    [[ -n "${entry}" ]] || { echo "Package ${pkg} not found in database."; return 1; }
    local files
    files=$(echo "${entry}" | cut -d'|' -f6)
    local missing=0 total=0
    local f
    while IFS=',' read -ra file_array; do
        for f in "${file_array[@]}"; do
            [[ -z "${f}" ]] && continue
            total=$((total + 1))
            if [[ ! -e "/${f}" ]]; then
                echo "MISSING: /${f}"
                missing=$((missing + 1))
            fi
        done
    done <<< "${files}"
    echo "Total: ${total}, Missing: ${missing}"
    [[ ${missing} -eq 0 ]] && echo "Package ${pkg} is intact."
}

anvil_remove() {
    local pkg="${1}"
    [[ -n "${pkg}" ]] || { echo "Usage: anvil remove <pkg>"; return 1; }
    require_root
    local entry
    entry=$(grep "^${pkg}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null | tail -n1)
    [[ -n "${entry}" ]] || { echo "Package ${pkg} not found in database."; return 1; }
    local files
    files=$(echo "${entry}" | cut -d'|' -f6)
    local count=0
    local f
    while IFS=',' read -ra file_array; do
        for f in "${file_array[@]}"; do
            [[ -z "${f}" ]] && continue
            if [[ -f "/${f}" || -L "/${f}" ]]; then
                rm -f "/${f}"
                count=$((count + 1))
            fi
        done
    done <<< "${files}"

    while IFS=',' read -ra file_array; do
        for f in "${file_array[@]}"; do
            [[ -z "${f}" ]] && continue
            local dir
            dir=$(dirname "/${f}")
            while [[ "${dir}" != "/" ]]; do
                rmdir "${dir}" 2>/dev/null || break
                dir=$(dirname "${dir}")
            done
        done
    done <<< "${files}"

    sed -i "/^${pkg}|/d" "${POWERUSER_DIR}/db/local.db"
    echo "Removed ${pkg} (${count} files)."
}

anvil_fetch_world() {
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/deps.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"

    local world_file="${POWERUSER_DIR}/world"
    [[ -f "${world_file}" ]] || { echo "No world file found at ${world_file}"; return 1; }

    local -a world_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "${pkg}" && "${pkg}" != \#* ]] && world_pkgs+=("${pkg}")
    done < "${world_file}"

    [[ ${#world_pkgs[@]} -gt 0 ]] || { echo "World file is empty."; return 1; }

    log_info "Resolving full dependency tree..."
    local -a all_pkgs
    mapfile -t all_pkgs < <(resolve_deps "${world_pkgs[@]}")

    log_info "Fetching sources for ${#all_pkgs[@]} packages..."
    local pkg
    for pkg in "${all_pkgs[@]}"; do
        resolve_pkg_flags "${pkg}" || { log_warn "Skipping ${pkg} — failed to resolve flags"; continue; }
        log_info "  Fetching sources for ${pkg}..."
        fetch_sources "${pkg}" 2>&1 || log_warn "  Failed to fetch some sources for ${pkg}"
    done

    log_info "All sources downloaded. System can now be built offline."
}

anvil_flag() {
    local pkg="${1}"
    local flag="${2:-}"
    local action="${3:-toggle}"

    [[ -n "${pkg}" ]] || { echo "Usage: anvil flag <pkg> [flag] [on|off]"; return 1; }
    require_root

    local flag_file="${POWERUSER_DIR}/package.use/${pkg}"
    mkdir -p "$(dirname "${flag_file}")"

    if [[ -z "${flag}" ]]; then
        if [[ -f "${flag_file}" ]]; then
            echo "Flags for ${pkg}:"
            grep -v '^#' "${flag_file}" | grep -v '^$' || echo "  (none)"
        else
            echo "No flags set for ${pkg}"
        fi
        return 0
    fi

    if [[ "${action}" == "toggle" ]]; then
        if grep -q "^${flag}\$" "${flag_file}" 2>/dev/null; then
            action="off"
        elif grep -q "^-${flag}\$" "${flag_file}" 2>/dev/null; then
            action="on"
        else
            action="on"
        fi
    fi

    case "${action}" in
        on)
            [[ -f "${flag_file}" ]] && sed -i "/^-${flag}\$/d" "${flag_file}"
            grep -q "^${flag}\$" "${flag_file}" 2>/dev/null || echo "${flag}" >> "${flag_file}"
            echo "Enabled ${flag} for ${pkg}"
            ;;
        off)
            [[ -f "${flag_file}" ]] && sed -i "/^${flag}\$/d" "${flag_file}"
            grep -q "^-${flag}\$" "${flag_file}" 2>/dev/null || echo "-${flag}" >> "${flag_file}"
            echo "Disabled ${flag} for ${pkg}"
            ;;
        *) echo "Unknown action: ${action}"; return 1 ;;
    esac
}

anvil_flag_info() {
    local pkg="${1}" flag="${2}"
    [[ -n "${pkg}" && -n "${flag}" ]] || { echo "Usage: anvil flag info <pkg> <flag>"; return 1; }

    load_recipe "${pkg}"
    local desc="${flag_descriptions[${flag}]:-No description available.}"
    local deps="${feature_depends[${flag}]:-none}"
    local confs="${feature_conflicts[${flag}]:-none}"

    echo "Flag: ${flag}"
    echo "Package: ${pkg}"
    echo "Description: ${desc}"
    echo "Pulls in: ${deps}"
    echo "Conflicts with: ${confs}"
}

anvil_build_interactive() {
    local pkg="${1}"
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"

    resolve_pkg_flags "${pkg}"

    fetch_sources "${pkg}"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    if declare -f prepare >/dev/null 2>&1; then
        prepare
    fi

    local configure_help
    if [[ -f ./configure ]]; then
        configure_help=$(./configure --help 2>/dev/null | grep -E '^\s*--(enable|disable|with|without)-' || true)
    else
        log_warn "No ./configure script found — cannot detect options interactively"
        return 1
    fi

    if [[ -z "${configure_help}" ]]; then
        log_info "No configurable options detected."
        return 0
    fi

    local -a options=()
    while IFS= read -r line; do
        local opt_name opt_desc
        opt_name=$(echo "${line}" | grep -oP '(?<=--)(enable|disable|with|without)-\S+' | head -n1)
        opt_desc=$(echo "${line}" | sed 's/^\s*//')
        [[ -n "${opt_name}" ]] && options+=("${opt_name}" "${opt_desc}")
    done <<< "${configure_help}"

    local selected
    selected=$(_filly_result '{"widget":"checklist","params":{"title":"Configure Options: '"${pkg}"'","message":"Select features to enable","choices":'"$(printf '%s\n' "${options[@]}" | jq -R . | jq -s .)"'}}')

    local flag_file="${POWERUSER_DIR}/package.use/${pkg}"
    mkdir -p "$(dirname "${flag_file}")"
    for opt in ${selected}; do
        local flag_name="${opt#enable-}"
        flag_name="${flag_name#with-}"
        flag_name="${flag_name//-/_}"
        anvil_flag "${pkg}" "${flag_name}" "on"
    done

    log_info "Flags saved. Run 'anvil build ${pkg}' to build with these options."
}

anvil_shell() {
    local pkg="${1}"
    [[ -n "${pkg}" ]] || { echo "Usage: anvil shell <pkg>"; return 1; }
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"

    resolve_pkg_flags "${pkg}"
    apply_pkg_flags

    fetch_sources "${pkg}"
    local pkg_work="${WORK_DIR}/${pkgname}"
    rm -rf "${pkg_work}"
    mkdir -p "${pkg_work}"
    export BUILD_DIR="${pkg_work}"
    export SOURCES_DIR="${SOURCES_DIR}"
    export PKG_DESTDIR="${pkg_work}/pkg"
    mkdir -p "${PKG_DESTDIR}"

    cd "${pkg_work}"
    if declare -f prepare >/dev/null 2>&1; then prepare; fi
    if declare -f configure >/dev/null 2>&1; then configure; fi

    log_info "Entering interactive shell in ${pkg_work}"
    log_info "Source is prepared and configured. Make your changes, then type 'exit'."
    log_info "The build will resume from the 'build' phase on exit."
    bash

    if tui_yesno "Resume Build" "Resume the build from the 'build' phase?"; then
        if ! (cd "${pkg_work}" && build); then
            log_error "Build failed"
            return 1
        fi
        if declare -f package >/dev/null 2>&1; then
            (cd "${pkg_work}" && package)
        fi
        log_info "Build complete. Artifact not cached (manual build)."
    else
        log_info "Shell exited. Work directory preserved at ${pkg_work}"
    fi
}

anvil_trial() {
    local url="${1}"
    [[ -n "${url}" ]] || { echo "Usage: anvil trial <url>"; return 1; }
    require_root

    local trial_dir="${POWERUSER_DIR}/build/trial"
    rm -rf "${trial_dir}"
    mkdir -p "${trial_dir}"
    cd "${trial_dir}"

    local filename="${url##*/}"
    log_info "Downloading ${filename}..."
    curl -L -o "${filename}" "${url}" || die "Download failed"

    log_info "Extracting..."
    tar xf "${filename}" 2>/dev/null || unzip "${filename}" 2>/dev/null || die "Failed to extract"

    local src_dir
    src_dir=$(ls -d */ | head -n1)
    cd "${src_dir}"

    local -a detected_deps=()
    local build_log="${trial_dir}/build.log"

    if [[ -f ./configure ]]; then
        log_info "Running ./configure..."
        ./configure 2>&1 | tee "${build_log}" || true
    fi

    log_info "Attempting build..."
    make -j$(nproc) 2>&1 | tee -a "${build_log}" || true

    while IFS= read -r line; do
        if [[ "${line}" =~ fatal\ error:\ (.*\.h):\ No\ such\ file ]]; then
            local missing_header="${BASH_REMATCH[1]}"
            local pkg
            pkg=$(pacman -Fq "${missing_header}" 2>/dev/null | head -n1)
            [[ -n "${pkg}" ]] && detected_deps+=("${pkg}")
        fi
    done < "${build_log}"

    local recipe_name
    recipe_name=$(basename "${PWD}" | tr ' ' '_' | tr '[:upper:]' '[:lower:]')
    local recipe_file="${POWERUSER_DIR}/recipes/${recipe_name}.sh"

    cat > "${recipe_file}" <<RECIPE
#!/usr/bin/env bash
pkgname=${recipe_name}
pkgver=1.0
pkgrel=1
desc="Auto-generated recipe for ${recipe_name}"
url="${url}"

sources=(
  "${url}|SKIP|${filename}"
)

depends=(${detected_deps[*]:-})
makedepends=(base-devel)

feature_flags=()

prepare() {
  cd "\${BUILD_DIR}"
  tar xf "\${SOURCES_DIR}/${filename}"
  mv "${src_dir%/}" src
}

configure() {
  cd "\${BUILD_DIR}/src"
  [[ -f ./configure ]] && ./configure --prefix=/usr
}

build() {
  cd "\${BUILD_DIR}/src"
  make -j"\${ARTIX_MAKEFLAGS}"
}

package() {
  cd "\${BUILD_DIR}/src"
  make DESTDIR="\${PKG_DESTDIR}" install
}
RECIPE

    log_info "Recipe generated: ${recipe_file}"
    log_info "Detected dependencies: ${detected_deps[*]:-none}"
    echo ""
    echo "Review and edit with: anvil edit ${recipe_name}"
    echo "Build with: anvil rebuild ${recipe_name}"
}

anvil_gc() {
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/deps.bash"

    local world_file="${POWERUSER_DIR}/world"
    [[ -f "${world_file}" ]] || { echo "No world file. Cannot determine what to keep."; return 1; }

    local -a world_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "${pkg}" && "${pkg}" != \#* ]] && world_pkgs+=("${pkg}")
    done < "${world_file}"

    local -a reachable
    mapfile -t reachable < <(resolve_deps "${world_pkgs[@]}")

    local -A keep=()
    local entry pkg
    while IFS='|' read -r pkg rest; do
        keep["${pkg}"]=1
    done < "${POWERUSER_DIR}/db/local.db"

    for pkg in "${reachable[@]}"; do
        keep["${pkg}"]=1
    done

    local removed=0
    for artifact in "${ARTIFACTS_DIR}"/*.pkg.tar.zst; do
        [[ -f "${artifact}" ]] || continue
        local artifact_name
        artifact_name=$(basename "${artifact}" | sed 's/-[0-9].*//')
        if [[ -z "${keep[${artifact_name}]:-}" ]]; then
            rm -f "${artifact}"
            log_info "Removed artifact: $(basename "${artifact}")"
            removed=$((removed + 1))
        fi
    done

    while IFS='|' read -r pkg rest; do
        if [[ -z "${keep[${pkg}]:-}" ]]; then
            sed -i "/^${pkg}|/d" "${POWERUSER_DIR}/db/local.db"
            log_info "Removed db entry: ${pkg}"
            removed=$((removed + 1))
        fi
    done < "${POWERUSER_DIR}/db/local.db"

    for src_dir in "${SOURCES_DIR}"/*; do
        [[ -d "${src_dir}" ]] || continue
        local src_name
        src_name=$(basename "${src_dir}")
        if [[ -z "${keep[${src_name}]:-}" ]]; then
            rm -rf "${src_dir}"
            log_info "Removed sources: ${src_name}"
        fi
    done

    log_info "Garbage collection complete. ${removed} items removed."
}

anvil_bootstrap() {
    local target="${1:-/tmp/anvil-bootstrap}"
    require_root
    source "${POWERUSER_DIR}/lib/common.sh"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/lib/deps.bash"
    source "${POWERUSER_DIR}/lib/queue.bash"
    source "${POWERUSER_DIR}/lib/builder.bash"
    source "${POWERUSER_DIR}/lib/cache.bash"
    source "${POWERUSER_DIR}/lib/validate.bash"

    local world_file="${POWERUSER_DIR}/world"
    [[ -f "${world_file}" ]] || die "No world file found"

    log_info "Bootstrapping Artix system to ${target}..."
    mkdir -p "${target}"/{boot,dev,proc,sys,tmp,etc,var/lib/pacman}

    local -a world_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "${pkg}" && "${pkg}" != \#* ]] && world_pkgs+=("${pkg}")
    done < "${world_file}"

    local -a build_order
    mapfile -t build_order < <(resolve_deps "${world_pkgs[@]}")

    log_info "Build order (${#build_order[@]} packages): ${build_order[*]}"

    local saved_mnt="${POWERUSER_BUILD_DIR}"
    POWERUSER_BUILD_DIR="${target}/artix-poweruser"
    SOURCES_DIR="${POWERUSER_BUILD_DIR}/sources"
    WORK_DIR="${POWERUSER_BUILD_DIR}/work"
    ARTIFACTS_DIR="${POWERUSER_BUILD_DIR}/artifacts"
    mkdir -p "${SOURCES_DIR}" "${WORK_DIR}" "${ARTIFACTS_DIR}"

    generate_queue "${build_order[@]}"

    local pkg
    while ! queue_all_done; do
        pkg=$(queue_next)
        [[ -n "${pkg}" ]] || break
        log_info "[${pkg}] Building... ($(queue_remaining) remaining)"
        build_package "${pkg}" && queue_mark "${pkg}" "done" || queue_mark "${pkg}" "failed"
    done

    POWERUSER_BUILD_DIR="${saved_mnt}"

    log_info "Bootstrap complete. System at ${target}"
    log_info "Configure /etc/fstab, /etc/hostname, and bootloader manually."
}

anvil_audit() {
    local pkg="${1:-}"
    require_root

    if [[ -n "${pkg}" ]]; then
        local entry
        entry=$(grep "^${pkg}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null | tail -n1)
        [[ -n "${entry}" ]] || { echo "Package ${pkg} not found."; return 1; }
        echo "Auditing ${pkg}..."
        local files
        files=$(echo "${entry}" | cut -d'|' -f6)
        local f
        while IFS=',' read -ra file_array; do
            for f in "${file_array[@]}"; do
                [[ -z "${f}" ]] && continue
                [[ -x "/${f}" ]] || continue
                [[ -f "/${f}" ]] || continue
                file "/${f}" 2>/dev/null | grep -q 'ELF' || continue

                local pie=0 relro=0 sp=0
                readelf -h "/${f}" 2>/dev/null | grep -q 'Type:.*DYN' && pie=1
                readelf -l "/${f}" 2>/dev/null | grep -q 'GNU_RELRO' && relro=1
                readelf -s "/${f}" 2>/dev/null | grep -q '__stack_chk_fail' && sp=1

                local flags=""
                [[ ${pie} -eq 1 ]] && flags+="PIE " || flags+="NO-PIE "
                [[ ${relro} -eq 1 ]] && flags+="RELRO " || flags+="NO-RELRO "
                [[ ${sp} -eq 1 ]] && flags+="STACK-PROTECTOR" || flags+="NO-SP"

                printf '%s: %s\n' "/${f}" "${flags}"
            done
        done <<< "${files}"
    else
        echo "Auditing all source-built packages..."
        local entry
        while IFS='|' read -r pkgname rest; do
            anvil_audit "${pkgname}"
        done < "${POWERUSER_DIR}/db/local.db"
    fi
}

anvil_estimate() {
    local world_file="${POWERUSER_DIR}/world"
    [[ -f "${world_file}" ]] || { echo "No world file."; return 1; }

    local -a world_pkgs=()
    while IFS= read -r pkg; do
        [[ -n "${pkg}" && "${pkg}" != \#* ]] && world_pkgs+=("${pkg}")
    done < "${world_file}"

    local total_time=0
    local count=0
    local pkg
    for pkg in "${world_pkgs[@]}"; do
        local stats_file="${LOGS_DIR}/stats/${pkg}.stats"
        if [[ -f "${stats_file}" ]]; then
            local wall_time
            wall_time=$(grep 'wall_time=' "${stats_file}" 2>/dev/null | cut -d'=' -f2)
            if [[ -n "${wall_time}" ]]; then
                total_time=$(echo "${total_time} + ${wall_time}" | bc 2>/dev/null || echo "${total_time}")
                count=$((count + 1))
            fi
        fi
    done

    if [[ ${count} -gt 0 ]]; then
        local avg_time
        avg_time=$(echo "scale=1; ${total_time} / ${count}" | bc 2>/dev/null || echo "0")
        local remaining_pkgs=${#world_pkgs[@]}
        local estimated
        estimated=$(echo "scale=0; ${avg_time} * ${remaining_pkgs} / 60" | bc 2>/dev/null || echo "unknown")
        echo "Based on ${count} previous builds (avg ${avg_time}s each)"
        echo "Estimated time for ${remaining_pkgs} packages: ~${estimated} minutes"
    else
        echo "No build history available. Run a build first."
    fi
}

anvil_world() {
    local subcmd="${1:-status}"
    case "${subcmd}" in
        status)
            local world_file="${POWERUSER_DIR}/world"
            [[ -f "${world_file}" ]] || { echo "No world file."; return 1; }
            echo "World packages:"
            grep -v '^#' "${world_file}" | grep -v '^$' | while read -r pkg; do
                local entry
                entry=$(grep "^${pkg}|" "${POWERUSER_DIR}/db/local.db" 2>/dev/null | tail -n1)
                if [[ -n "${entry}" ]]; then
                    local ver flags
                    ver=$(echo "${entry}" | cut -d'|' -f2)
                    flags=$(echo "${entry}" | cut -d'|' -f5)
                    echo "  ${pkg} ${ver} [${flags:-no flags}]"
                else
                    echo "  ${pkg} (not built)"
                fi
            done
            ;;
        add)
            local pkg="${2}"
            [[ -n "${pkg}" ]] || { echo "Usage: anvil world add <pkg>"; return 1; }
            local world_file="${POWERUSER_DIR}/world"
            grep -q "^${pkg}\$" "${world_file}" 2>/dev/null || echo "${pkg}" >> "${world_file}"
            echo "Added ${pkg} to world."
            ;;
        remove)
            local pkg="${2}"
            [[ -n "${pkg}" ]] || { echo "Usage: anvil world remove <pkg>"; return 1; }
            local world_file="${POWERUSER_DIR}/world"
            sed -i "/^${pkg}\$/d" "${world_file}"
            echo "Removed ${pkg} from world."
            ;;
        build)
            local stage_dir=""
            local jobs=1
            while [[ $# -gt 1 ]]; do
                case "${2}" in
                    --stage) stage_dir="${3}"; shift 2 ;;
                    --jobs) jobs="${3}"; shift 2 ;;
                    *) shift ;;
                esac
            done
            if [[ -n "${stage_dir}" ]]; then
                anvil_world_stage "${stage_dir}"
            elif [[ ${jobs} -gt 1 ]]; then
                local world_file="${POWERUSER_DIR}/world"
                local -a world_pkgs=()
                while IFS= read -r pkg; do
                    [[ -n "${pkg}" && "${pkg}" != \#* ]] && world_pkgs+=("${pkg}")
                done < "${world_file}"
                local -a build_order
                mapfile -t build_order < <(resolve_deps "${world_pkgs[@]}")
                generate_queue "${build_order[@]}"
                build_queue_parallel "${jobs}"
            else
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
                    build_package "${pkg}" && queue_mark "${pkg}" "done" || queue_mark "${pkg}" "failed"
                done
            fi
            ;;
        activate)
            anvil_activate "${2:-/nextroot}"
            ;;
        *)
            echo "Usage: anvil world {status|add|remove|build|activate}"
            return 1
            ;;
    esac
}

cache_clean() {
    require_root
    source "${POWERUSER_DIR}/lib/cache.bash"
    cache_clean
}