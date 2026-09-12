#!/usr/bin/env bash
set -Eeuo pipefail

readonly ISO_PROFILES_ROOT="/usr/share/artools/iso-profiles"
readonly ISO_PROFILES_ARCHIVE="https://gitea.artixlinux.org/artix/iso-profiles/archive/wip.tar.gz"

iso_profiles_available() {
    [[ -d "${ISO_PROFILES_ROOT}/common" && -d "${ISO_PROFILES_ROOT}/base" ]]
}

iso_profiles_list() {
    local d name
    for d in "${ISO_PROFILES_ROOT}"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        case "$name" in
            common|conf|.git) continue ;;
        esac
        [[ -f "${d}/profile.yaml" ]] || continue
        printf '%s\n' "$name"
    done
}

iso_profiles_ensure() {
    iso_profiles_available && return 0

    log_info "Fetching upstream iso-profiles (wip)..."

    local tarball="/tmp/iso-profiles-wip.tar.gz"
    local extract_dir="/tmp/iso-profiles-wip"

    rm -rf "${tarball}" "${extract_dir}"
    mkdir -p "${extract_dir}"

    if ! curl -fsSL --max-time 60 "${ISO_PROFILES_ARCHIVE}" -o "${tarball}"; then
        log_warn "Failed to fetch iso-profiles from upstream"
        return 1
    fi

    if ! tar -xzf "${tarball}" -C "${extract_dir}" --strip-components=1; then
        log_warn "Failed to extract iso-profiles tarball"
        rm -rf "${tarball}" "${extract_dir}"
        return 1
    fi

    mkdir -p "$(dirname "${ISO_PROFILES_ROOT}")"
    rm -rf "${ISO_PROFILES_ROOT}"
    mv "${extract_dir}" "${ISO_PROFILES_ROOT}"
    rm -f "${tarball}"

    log_info "iso-profiles (wip) installed to ${ISO_PROFILES_ROOT}"
    iso_profiles_available
}

iso_profiles_validate() {
    iso_profiles_available || {
        log_warn "iso-profiles not available — skipping staleness check"
        return 1
    }

    local tarball="/tmp/iso-profiles-validate.tar.gz"
    if ! curl -fsSL --max-time 15 "${ISO_PROFILES_ARCHIVE}" -o "${tarball}" 2>/dev/null; then
        log_info "iso-profiles staleness check skipped (upstream unreachable)"
        rm -f "${tarball}"
        return 0
    fi

    local -a stale=()
    local rel local_hash remote_hash

    for rel in common/common.yaml base/profile.yaml; do
        [[ -f "${ISO_PROFILES_ROOT}/${rel}" ]] || continue

        remote_hash="$(tar -xzOf "${tarball}" --wildcards "*/${rel}" 2>/dev/null | sha256sum | awk '{print $1}')"
        [[ -n "${remote_hash}" ]] || continue

        local_hash="$(sha256sum "${ISO_PROFILES_ROOT}/${rel}" | awk '{print $1}')"
        [[ "${local_hash}" == "${remote_hash}" ]] || stale+=("${rel}")
    done

    rm -f "${tarball}"

    if [[ "${#stale[@]}" -eq 0 ]]; then
        return 0
    fi

    log_warn "iso-profiles differs from upstream wip: ${stale[*]}"
    if tui_yesno "Update iso-profiles" \
        "Your iso-profiles differs from upstream wip:\n\n$(printf '  - %s\n' "${stale[@]}")\n\nUpdate now?"; then
        iso_profiles_ensure || log_warn "Update failed — continuing"
    fi
    return 0
}

quick_profile_load() {
    local profile="$1"
    local init
    init="$(state_get INIT openrc)"

    local common="${ISO_PROFILES_ROOT}/common/common.yaml"
    local base="${ISO_PROFILES_ROOT}/base/profile.yaml"
    local prof="${ISO_PROFILES_ROOT}/${profile}/profile.yaml"

    [[ -f "$common" && -f "$base" && -f "$prof" ]] || {
        log_warn "profile files missing for '${profile}'"
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
    log_info "Loaded ${#uniq[@]} packages for profile '${profile}' (init: ${init})"
    return 0
}