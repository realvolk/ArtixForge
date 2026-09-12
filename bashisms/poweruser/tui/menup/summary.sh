#!/usr/bin/env bash
set -Eeuo pipefail

tui_poweruser_hw_summary() {
    source "${POWERUSER_DIR}/lib/hwdetect.bash"
    local cpu gpu net storage
    cpu=$(detect_cpu)
    gpu=$(detect_gpu)
    net=$(detect_net)
    storage=$(detect_storage)
    tui_msg "Hardware Detected" \
        "CPU: ${cpu}\nGPU: ${gpu}\nNetwork: ${net}\nStorage: ${storage}"
}

tui_poweruser_pre_summary() {
    local summary=""
    summary+="Profile: $(state_get POWERUSER_PROFILE default)"$'\n'
    summary+="Packages:"$'\n'
    local -a pkgs
    read -ra pkgs <<< "$(state_get POWERUSER_PACKAGES)"
    for pkg in "${pkgs[@]}"; do
        local flag_file="${POWERUSER_DIR}/package.use/${pkg}"
        local features=""
        if [[ -f "${flag_file}" ]]; then
            features=$(grep -v '^#' "${flag_file}" | grep -v '^-' | tr '\n' ' ')
        fi
        if [[ -n "${features}" ]]; then
            summary+="  ${pkg} [${features}]"$'\n'
        else
            summary+="  ${pkg}"$'\n'
        fi
    done
    tui_msg "Power User Build Summary" "${summary}"
}