#!/usr/bin/env bash
set -Eeuo pipefail

tui_build_timing_summary() {
    local timing_file="${POWERUSER_DIR}/build/logs/timing.log"
    [[ -f "${timing_file}" ]] || return

    local summary=""
    while IFS='|' read -r pkg status duration; do
        local icon="✓"
        [[ "${status}" == "skipped" ]] && icon="→"
        [[ "${status}" == "failed" ]] && icon="✗"
        summary+="${icon} ${pkg} — ${duration}s (${status})"$'\n'
    done < "${timing_file}"

    tui_msg_quick "Build Timing Summary" "${summary}"
}