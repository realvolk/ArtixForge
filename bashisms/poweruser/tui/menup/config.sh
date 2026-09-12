#!/usr/bin/env bash
set -Eeuo pipefail

tui_poweruser_config() {
    tui_poweruser_select_profile || return 1
    tui_poweruser_tweak_profile

    if tui_yesno "Power User Settings" "Do you want to configure all Power User options?\n\nYes: init, packages, coreutils, kernel config, feature flags\nNo: skip to summary with defaults"; then
        tui_poweruser_select_init
        tui_poweruser_select_packages || {
            state_set POWER_USER "no"
            return 1
        }
        tui_poweruser_select_coreutils
        tui_poweruser_recipe_sections
        tui_poweruser_fallback_kernel
        tui_poweruser_create_recipe
        tui_poweruser_feature_flags
    else
        state_set COREUTILS "gnu"
        [[ -z "$(state_get KEEP_BINARY_KERNEL)" ]] && state_set KEEP_BINARY_KERNEL "yes"
        state_set KERNEL_CONFIG_DEPTH "localmodconfig"
        if [[ -z "$(state_get POWERUSER_PACKAGES)" ]]; then
            state_set POWERUSER_PACKAGES "linux"
        fi
        tui_poweruser_kernel_config "auto"
    fi

    tui_poweruser_hw_summary
    tui_poweruser_pre_summary
}