#!/usr/bin/env bash
set -Eeuo pipefail

KCONFIG_FRAGMENT_DIR="${POWERUSER_DIR}/kernel.d"
USER_KCONFIG_FRAGMENT_DIR="/etc/anvil/kernel.d"

apply_kconfig_fragments() {
    local config_file="${1:-.config}"
    local -a fragments=()

    if [[ -f "${BUILD_DIR}/kconfig.fragment" ]]; then
        fragments+=("${BUILD_DIR}/kconfig.fragment")
    fi

    local frag
    for dir in "${USER_KCONFIG_FRAGMENT_DIR}" "${KCONFIG_FRAGMENT_DIR}"; do
        if [[ -d "${dir}" ]]; then
            while IFS= read -r -d '' frag; do
                fragments+=("${frag}")
            done < <(find "${dir}" -name '*.fragment' -type f -print0 2>/dev/null | sort -z)
        fi
    done

    for frag in "${fragments[@]}"; do
        log_info "  Applying kernel config fragment: $(basename "${frag}")"
        local line
        while IFS= read -r line; do
            [[ -z "${line}" || "${line}" == \#* ]] && continue
            local key="${line%=*}"
            local val="${line#*=}"
            case "${val}" in
                y)  scripts/config --enable "${key#CONFIG_}" 2>/dev/null || true ;;
                m)  scripts/config --module "${key#CONFIG_}" 2>/dev/null || true ;;
                n)  scripts/config --disable "${key#CONFIG_}" 2>/dev/null || true ;;
                *)  scripts/config --set-val "${key#CONFIG_}" "${val}" 2>/dev/null || true ;;
            esac
        done < "${frag}"
    done
}