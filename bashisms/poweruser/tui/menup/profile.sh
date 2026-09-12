#!/usr/bin/env bash
set -Eeuo pipefail

tui_poweruser_select_profile() {
    local profile
    profile=$(tui_menu "Compilation Profile" "Choose optimization level:" \
        "default — balanced, safe optimizations" \
        "safe — conservative flags, maximum stability" \
        "performance — aggressive optimizations" \
        "hardened — security-focused flags") || return 1
    profile="${profile%% *}"
    state_set POWERUSER_PROFILE "${profile}"
    tui_poweruser_profile_preview "${profile}"
}

tui_poweruser_profile_preview() {
    local profile="${1}"
    local profile_file="${POWERUSER_DIR}/profile/${profile}.sh"
    source "${profile_file}"
    tui_msg "Profile: ${profile}" \
        "CFLAGS: ${ARTIX_CFLAGS}\nCXXFLAGS: ${ARTIX_CXXFLAGS}\nLDFLAGS: ${ARTIX_LDFLAGS}\nMAKEFLAGS: -j${ARTIX_MAKEFLAGS}\nGlobal Features: ${GLOBAL_FEATURES:-none}"
}

tui_poweruser_tweak_profile() {
    if ! tui_yesno "Tweak Flags?" "Would you like to customize the compilation flags?"; then
        return 0
    fi

    local profile_name
    profile_name="$(state_get POWERUSER_PROFILE default)"
    local profile_file="${POWERUSER_DIR}/profile/${profile_name}.sh"
    source "${profile_file}"

    local current_cflags="${ARTIX_CFLAGS}"
    local current_cxxflags="${ARTIX_CXXFLAGS}"
    local current_ldflags="${ARTIX_LDFLAGS}"
    local current_makeflags="${ARTIX_MAKEFLAGS}"
    local current_global_features="${GLOBAL_FEATURES:-}"

    local new_cflags new_cxxflags new_ldflags new_makeflags new_global_features
    new_cflags=$(tui_input "CFLAGS" "Enter CFLAGS:" "${current_cflags}") || return 0
    new_cxxflags=$(tui_input "CXXFLAGS" "Enter CXXFLAGS:" "${current_cxxflags}") || return 0
    new_ldflags=$(tui_input "LDFLAGS" "Enter LDFLAGS:" "${current_ldflags}") || return 0
    new_makeflags=$(tui_input "MAKEFLAGS" "Enter MAKEOPTS (-j):" "${current_makeflags}") || return 0
    new_global_features=$(tui_input "Global Features" "Space-separated flags (e.g. pie relro stack-protector):" "${current_global_features}") || return 0

    export ARTIX_CFLAGS="${new_cflags:-${current_cflags}}"
    export ARTIX_CXXFLAGS="${new_cxxflags:-${current_cxxflags}}"
    export ARTIX_LDFLAGS="${new_ldflags:-${current_ldflags}}"
    export ARTIX_MAKEFLAGS="${new_makeflags:-${current_makeflags}}"
    GLOBAL_FEATURES="${new_global_features:-${current_global_features}}"
    export GLOBAL_FEATURES

    if [[ "${ARTIX_CFLAGS}" == *"Usage:"* ]] || [[ "${ARTIX_CFLAGS}" == *"--help"* ]]; then
        log_warn "Invalid flag input detected, keeping current profile"
        return 0
    fi

    mkdir -p "${POWERUSER_DIR}/profile"
    cat > "${POWERUSER_DIR}/profile/custom.sh" <<EOF
#!/usr/bin/env bash
ARTIX_CFLAGS="${ARTIX_CFLAGS}"
ARTIX_CXXFLAGS="${ARTIX_CXXFLAGS}"
ARTIX_LDFLAGS="${ARTIX_LDFLAGS}"
ARTIX_MAKEFLAGS="${ARTIX_MAKEFLAGS}"
GLOBAL_FEATURES="${GLOBAL_FEATURES}"
EOF

    state_set POWERUSER_PROFILE "custom"
    tui_msg "Flags Saved" "Custom flags saved as 'custom' profile."
}