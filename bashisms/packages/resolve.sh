#!/usr/bin/env bash
set -Eeuo pipefail

_resolve_substitute_init() {
    local init="$1"
    shift
    local pkg
    for pkg in "$@"; do
        printf '%s\n' "${pkg//@init@/${init}}"
    done
}

resolve_de_packages() {
    local de="$1" init="$2" kde_profile="${3:-desktop}"
    local key="${de}"
    [[ "${de}" == "kde" ]] && key="kde-${kde_profile}"
    local raw="${DE_PACKAGES[${key}]:-}"
    [[ -n "${raw}" ]] || return 0
    read -ra pkgs <<< "${raw}"
    _resolve_substitute_init "${init}" "${pkgs[@]}"
}

resolve_de_dm() {
    local key="${1:-}"
    [[ -n "${key}" ]] || { printf 'none\n'; return 0; }
    printf '%s\n' "${DE_DISPLAY_MANAGER[${key}]:-none}"
}

resolve_de_display_server() {
    local key="${1:-}"
    [[ -n "${key}" ]] || { printf 'xorg\n'; return 0; }
    printf '%s\n' "${DE_DISPLAY_SERVER[${key}]:-xorg}"
}

resolve_de_toolkit() {
    local key="${1:-}"
    [[ -n "${key}" ]] || { printf 'gtk\n'; return 0; }
    printf '%s\n' "${DE_TOOLKIT[${key}]:-gtk}"
}

resolve_de_pretty_name() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${DE_PRETTY_NAME[${key}]:-${key}}"
}

resolve_de_profile() {
    local key="${1:-}"
    [[ -n "${key}" ]] || { printf 'base\n'; return 0; }
    printf '%s\n' "${DE_TO_PROFILE[${key}]:-base}"
}

resolve_profile_toolkit() {
    local key="${1:-}"
    [[ -n "${key}" ]] || { printf 'gtk\n'; return 0; }
    printf '%s\n' "${PROFILE_TOOLKIT[${key}]:-gtk}"
}

resolve_seat_package() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${DE_SEAT_PACKAGE[${key}]:-}"
}

resolve_kernel_headers() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${KERNEL_HEADERS[${key}]:-}"
}

resolve_kernel_image() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${KERNEL_PACKAGES[${key}]:-}"
}

resolve_de_installed_packages() {
    local de="$1" root="${2:-}"
    local pattern="${DE_DETECT_PATTERN[${de}]:-}"
    [[ -n "${pattern}" ]] || return 0
    if [[ -n "${root}" ]]; then
        pacman --root "${root}" -Qq 2>/dev/null | grep -E "${pattern}" || true
    else
        pacman -Qq 2>/dev/null | grep -E "${pattern}" || true
    fi
}

resolve_detect_current_de() {
    local root="${1:-}"
    local de
    for de in "${DE_DETECT_ORDER[@]}"; do
        if [[ -n "$(resolve_de_installed_packages "${de}" "${root}")" ]]; then
            printf '%s\n' "${de}"
            return 0
        fi
    done
    printf 'none\n'
}

resolve_init_packages() {
    local init="$1"
    local raw="${INIT_PACKAGES[${init}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_init_elogind() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${INIT_ELOGIND[${key}]:-}"
}

resolve_service_map() {
    local src="$1" tgt="$2" svc="$3"
    [[ -n "${svc}" ]] || return 1
    local table="SERVICE_MAP_${src^^}_${tgt^^}"
    declare -p "$table" &>/dev/null || return 1
    local -n ref="$table"
    local mapped="${ref[$svc]:-}"
    [[ -n "$mapped" ]] || return 1
    printf '%s\n' "$mapped"
}

resolve_init_fallback_packages() {
    local init="$1"
    local raw="${INIT_FALLBACK_PACKAGES[${init}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_kernel_packages() {
    local kernel="$1"
    local pkg="${KERNEL_PACKAGES[${kernel}]:-}"
    local hdr="${KERNEL_HEADERS[${kernel}]:-}"
    [[ -n "${pkg}" ]] && printf '%s\n' "${pkg}"
    [[ -n "${hdr}" ]] && printf '%s\n' "${hdr}"
}

resolve_xstack_packages() {
    local stack="$1"
    local raw="${X_STACK_PACKAGES[${stack}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_gpu_packages() {
    local vendor="$1" pci_id="${2:-}"
    local key="${vendor}"
    if [[ "${vendor}" == "nvidia" && -n "${pci_id}" ]]; then
        if (( 16#${pci_id} >= 16#1e00 )); then
            key="nvidia-new"
        else
            key="nvidia-old"
        fi
    fi
    local raw="${GPU_PACKAGES[${key}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_vm_packages() {
    local vm="$1"
    local raw="${VM_GUEST_PACKAGES[${vm}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_audio_packages() {
    local stack="$1"
    local raw="${AUDIO_PACKAGES[${stack}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_audio_service_packages() {
    local stack="$1" init="$2"
    local key="${stack}-${init}"
    local raw="${AUDIO_SERVICE_PACKAGES[${key}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_network_packages() {
    local stack="$1" init="$2"
    local raw="${NETWORK_PACKAGES[${stack}]:-}"
    [[ -n "${raw}" ]] || return 0
    read -ra pkgs <<< "${raw}"
    _resolve_substitute_init "${init}" "${pkgs[@]}"
}

resolve_network_services() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${NETWORK_SERVICES[${key}]:-}"
}

resolve_bootloader_packages() {
    local bl="$1"
    local raw="${BOOTLOADER_PACKAGES[${bl}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_filesystem_packages() {
    local fs="$1"
    local raw="${FILESYSTEM_TOOLS[${fs}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_userspawn_packages() {
    local init="$1"
    local raw="${USERSPAWN_PACKAGES[${init}]:-}"
    [[ -n "${raw}" ]] || return 0
    printf '%s\n' ${raw}
}

resolve_ata_base_packages() {
    printf '%s\n' "${ATA_BASE_PACKAGES[@]}"
}

resolve_systemd_unit_package() {
    local unit="$1" target_init="$2"
    local base_unit="${unit%.service}"
    base_unit="${base_unit%.target}"
    base_unit="${base_unit%.timer}"
    base_unit="${base_unit%.socket}"
    base_unit="${base_unit%@*}"

    local svc_file=""
    local path ext
    for path in /usr/lib/systemd/system /etc/systemd/system; do
        for ext in service target timer socket; do
            if [[ -f "${path}/${base_unit}.${ext}" ]]; then
                svc_file="${path}/${base_unit}.${ext}"
                break 2
            fi
        done
    done

    local pkg=""
    if [[ -n "${svc_file}" ]]; then
        pkg="$(pacman -Qo "${svc_file}" 2>/dev/null | awk '{print $5}' | cut -d/ -f1)" || true
    fi
    [[ -z "${pkg}" ]] && pkg="${base_unit}"

    if pacman -Si "${pkg}" 2>/dev/null | grep -q 'Repository'; then
        printf '%s\n' "${pkg}"
        return 0
    fi

    local suffix
    for suffix in "-${target_init}" -openrc -runit -dinit -s6; do
        if pacman -Si "${pkg}${suffix}" 2>/dev/null | grep -q 'Repository'; then
            printf '%s\n' "${pkg}${suffix}"
            return 0
        fi
    done

    return 1
}

resolve_iso_base_packages() {
    printf '%s\n' "${ISO_BASE_PACKAGES[@]}"
}

resolve_iso_microcode_packages() {
    printf '%s\n' "${ISO_MICROCODE_PACKAGES[@]}"
}

resolve_iso_build_tools() {
    printf '%s\n' "${ISO_BUILD_TOOLS[@]}"
}

resolve_target_base_packages() {
    printf '%s\n' "${TARGET_BASE_PACKAGES[@]}"
}

resolve_target_shell_packages() {
    local key="${1:-}"
    [[ -n "${key}" ]] || return 0
    printf '%s\n' "${TARGET_SHELL_PACKAGES[${key}]:-}"
}

resolve_target_storage_packages() {
    local tool="$1" init="$2"
    local raw="${TARGET_STORAGE_PACKAGES[${tool}]:-}"
    [[ -n "${raw}" ]] || return 0
    read -ra pkgs <<< "${raw}"
    _resolve_substitute_init "${init}" "${pkgs[@]}"
}

resolve_target_uki_packages() {
    printf '%s\n' "${TARGET_UKI_PACKAGES[@]}"
}