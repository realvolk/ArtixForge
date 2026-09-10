#!/usr/bin/env bash
set -Eeuo pipefail

readonly ISO_PROFILES_ROOT="/usr/share/artools/iso-profiles"
readonly ISO_PROFILES_UPSTREAM="https://gitea.artixlinux.org/artix/iso-profiles/raw/branch/wip"

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

iso_profiles_validate() {
    iso_profiles_available || {
        log_warn "iso-profiles package not installed"
        return 1
    }

    local rel local_path remote_hash local_hash
    local -a stale=()
    local -a unreachable=()

    for rel in common/common.yaml base/profile.yaml; do
        local_path="${ISO_PROFILES_ROOT}/${rel}"
        [[ -f "$local_path" ]] || continue

        remote_hash="$(curl -fsSL --max-time 5 "${ISO_PROFILES_UPSTREAM}/${rel}" 2>/dev/null | sha256sum | awk '{print $1}')"
        if [[ "$remote_hash" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
            unreachable+=("$rel")
            continue
        fi

        local_hash="$(sha256sum "$local_path" | awk '{print $1}')"
        [[ "$local_hash" == "$remote_hash" ]] || stale+=("$rel")
    done

    if [[ "${#unreachable[@]}" -gt 0 ]]; then
        log_info "iso-profiles staleness check skipped (upstream unreachable)"
        return 0
    fi

    if [[ "${#stale[@]}" -eq 0 ]]; then
        return 0
    fi

    log_warn "iso-profiles differs from upstream wip: ${stale[*]}"
    if tui_yesno "Update iso-profiles" \
        "Your iso-profiles package differs from upstream wip:\n\n$(printf '  - %s\n' "${stale[@]}")\n\nUpdate now?"; then
        pacman -S --noconfirm iso-profiles || log_warn "Update failed — continuing"
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