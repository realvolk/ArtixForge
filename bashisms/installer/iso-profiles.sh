#!/usr/bin/env bash
set -Eeuo pipefail

readonly ISO_PROFILES_ROOT="/usr/share/artools/iso-profiles"
readonly ISO_PROFILES_WIP_ROOT="/var/cache/artixforge/iso-profiles-wip"
readonly ISO_PROFILES_ARCHIVE="https://gitea.artixlinux.org/artix/iso-profiles/archive/wip.tar.gz"
readonly ISO_PROFILES_WIP_MAX_AGE=$((7 * 24 * 3600))

ISO_PROFILES_ACTIVE="${ISO_PROFILES_ROOT}"

_iso_profiles_wip_cached() {
    [[ -d "${ISO_PROFILES_WIP_ROOT}/common" && -d "${ISO_PROFILES_WIP_ROOT}/base" ]]
}

_iso_profiles_packaged_available() {
    [[ -d "${ISO_PROFILES_ROOT}/common" && -d "${ISO_PROFILES_ROOT}/base" ]]
}

iso_profiles_available() {
    [[ -d "${ISO_PROFILES_ACTIVE}/common" && -d "${ISO_PROFILES_ACTIVE}/base" ]]
}

iso_profiles_list() {
    local d name
    for d in "${ISO_PROFILES_ACTIVE}"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        case "$name" in
            common|conf|.git) continue ;;
        esac
        [[ -f "${d}/profile.yaml" ]] || continue
        printf '%s\n' "$name"
    done
}

_iso_profiles_fetch_wip() {
    local tarball="/tmp/iso-profiles-wip.tar.gz"
    local extract_dir="/tmp/iso-profiles-wip.$$"

    rm -rf "${tarball}" "${extract_dir}"
    mkdir -p "${extract_dir}"

    if ! curl -fsSL --max-time 60 "${ISO_PROFILES_ARCHIVE}" -o "${tarball}"; then
        rm -rf "${tarball}" "${extract_dir}"
        return 1
    fi

    if ! tar -xzf "${tarball}" -C "${extract_dir}" --strip-components=1; then
        rm -rf "${tarball}" "${extract_dir}"
        return 1
    fi

    if [[ ! -d "${extract_dir}/common" || ! -d "${extract_dir}/base" ]]; then
        log_warn "wip archive extracted but common/ or base/ missing"
        rm -rf "${tarball}" "${extract_dir}"
        return 1
    fi

    mkdir -p "$(dirname "${ISO_PROFILES_WIP_ROOT}")"
    rm -rf "${ISO_PROFILES_WIP_ROOT}"
    mv "${extract_dir}" "${ISO_PROFILES_WIP_ROOT}"
    rm -f "${tarball}"
    return 0
}

iso_profiles_ensure() {
    if _iso_profiles_wip_cached; then
        ISO_PROFILES_ACTIVE="${ISO_PROFILES_WIP_ROOT}"
        log_info "Using cached wip iso-profiles (${ISO_PROFILES_WIP_ROOT})"
        return 0
    fi

    log_info "Fetching upstream iso-profiles (wip)..."
    if _iso_profiles_fetch_wip; then
        ISO_PROFILES_ACTIVE="${ISO_PROFILES_WIP_ROOT}"
        log_info "iso-profiles (wip) cached at ${ISO_PROFILES_WIP_ROOT}"
        return 0
    fi

    log_warn "Failed to fetch wip — falling back to packaged iso-profiles"
    if _iso_profiles_packaged_available; then
        ISO_PROFILES_ACTIVE="${ISO_PROFILES_ROOT}"
        return 0
    fi

    log_error "No iso-profiles available (neither wip nor packaged)"
    return 1
}

iso_profiles_validate() {
    if ! _iso_profiles_wip_cached; then
        log_info "wip cache missing — will be fetched on demand"
        return 0
    fi

    local age
    age=$(( $(date +%s) - $(stat -c %Y "${ISO_PROFILES_WIP_ROOT}" 2>/dev/null || echo 0) ))

    if [[ ${age} -lt ${ISO_PROFILES_WIP_MAX_AGE} ]]; then
        return 0
    fi

    local age_days=$(( age / 86400 ))
    log_info "wip iso-profiles cache is ${age_days} days old"

    if tui_yesno "Update iso-profiles" "Your cached wip iso-profiles is ${age_days} days old.\n\nFetch the latest wip branch now?"; then
        rm -rf "${ISO_PROFILES_WIP_ROOT}"
        if _iso_profiles_fetch_wip; then
            ISO_PROFILES_ACTIVE="${ISO_PROFILES_WIP_ROOT}"
            log_info "wip iso-profiles refreshed"
        else
            log_warn "Refresh failed — using stale cache or falling back to packaged"
            if _iso_profiles_wip_cached; then
                ISO_PROFILES_ACTIVE="${ISO_PROFILES_WIP_ROOT}"
            elif _iso_profiles_packaged_available; then
                ISO_PROFILES_ACTIVE="${ISO_PROFILES_ROOT}"
            fi
        fi
    fi
    return 0
}

quick_profile_load() {
    local profile="$1"
    local init
    init="$(state_get INIT openrc)"

    local common="${ISO_PROFILES_ACTIVE}/common/common.yaml"
    local base="${ISO_PROFILES_ACTIVE}/base/profile.yaml"
    local prof="${ISO_PROFILES_ACTIVE}/${profile}/profile.yaml"

    [[ -f "$common" && -f "$base" && -f "$prof" ]] || {
        log_warn "profile files missing for '${profile}' (root: ${ISO_PROFILES_ACTIVE})"
        return 1
    }

    local -a packages=()
    local -a chunk=()

    mapfile -t chunk < <(yaml_parse_list "$common" "packages-base")
    packages+=("${chunk[@]}")
    mapfile -t chunk < <(yaml_parse_list "$common" "packages-apps")
    packages+=("${chunk[@]}")
    mapfile -t chunk < <(yaml_parse_list "$common" "packages-misc")
    packages+=("${chunk[@]}")
    mapfile -t chunk < <(yaml_parse_list "$common" "packages-init.${init}")
    packages+=("${chunk[@]}")

    mapfile -t chunk < <(yaml_parse_list "$base" "rootfs.packages")
    packages+=("${chunk[@]}")
    mapfile -t chunk < <(yaml_parse_list "$base" "rootfs.packages-init.${init}")
    packages+=("${chunk[@]}")

    mapfile -t chunk < <(yaml_parse_list "$prof" "rootfs.packages")
    packages+=("${chunk[@]}")
    mapfile -t chunk < <(yaml_parse_list "$prof" "rootfs.packages-init.${init}")
    packages+=("${chunk[@]}")

    if [[ "$(yaml_parse_scalar "$prof" "live-session.use-xlibre")" == "true" ]]; then
        mapfile -t chunk < <(yaml_parse_list "$common" "packages-xlibre")
    else
        mapfile -t chunk < <(yaml_parse_list "$common" "packages-xorg")
    fi
    packages+=("${chunk[@]}")

    local -A seen=()
    local -a uniq=()
    local pkg
    for pkg in "${packages[@]}"; do
        [[ -n "$pkg" ]] || continue
        [[ -z "${seen[$pkg]:-}" ]] || continue
        seen[$pkg]=1
        uniq+=("$pkg")
    done

    state_set PROFILE_PACKAGES "${uniq[*]}"
    log_info "Loaded ${#uniq[@]} packages for profile '${profile}' (init: ${init}, root: ${ISO_PROFILES_ACTIVE})"
    return 0
}