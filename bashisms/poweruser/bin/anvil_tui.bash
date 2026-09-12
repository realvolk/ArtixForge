#!/usr/bin/env bash
set -Eeuo pipefail

tui_menu() {
    local title="${1}" msg="${2}"
    shift 2
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --height=15 "$@" </dev/tty
}

tui_checklist() {
    local title="${1}" msg="${2}"
    shift 2
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --no-limit --height=15 "$@" </dev/tty
}

tui_msg() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──"
    gum format "${msg}"
    gum confirm "Press Enter to continue" --affirmative="OK" --timeout=0 </dev/tty 2>/dev/null || true
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}" result
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    result=$(gum input --value "${default}" --prompt "> " </dev/tty) || true
    printf '%s' "${result}"
}

tui_yesno() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${GUM_TITLE_COLOR}" "── ${title} ──"
    gum format "${msg}"
    gum confirm </dev/tty
}

tui_manage_sections() {
    load_sections
    local chosen
    chosen=$(tui_checklist "Recipe Sections" "Select which recipe sections to enable:" \
        "OFFICIAL/Base (recommended)" \
        "OFFICIAL/Other (extended, tested)" \
        "COMMUNITY/Base (pending review)" \
        "COMMUNITY/Other (experimental)") || return 0

    ANVIL_SECTIONS="${chosen//$'\n'/ }"
    [[ -z "${ANVIL_SECTIONS}" ]] && ANVIL_SECTIONS="${DEFAULT_SECTIONS}"
    save_sections
    tui_msg "Sections Updated" "Enabled sections: ${ANVIL_SECTIONS}"
}

tui_main() {
    while true; do
        clear
        local action
        action=$(tui_menu "anvil" "Select an action:" \
            "List installed packages" \
            "List available recipes" \
            "Package info" \
            "Rebuild a package" \
            "Create new recipe" \
            "Edit recipe" \
            "Edit kernel config" \
            "Menuconfig" \
            "Fetch kernel source" \
            "Fetch a recipe from repo" \
            "Fetch all sources" \
            "Fetch world sources" \
            "Manage recipe sections" \
            "Lint recipe" \
            "Checksum recipe" \
            "Sync recipes" \
            "Recovery – check & repair source packages" \
            "Upgrade recipes" \
            "Clean cache" \
            "Package files" \
            "Verify package" \
            "Remove package" \
            "Recipe history" \
            "Recipe diff" \
            "Rollback recipe" \
            "Feature flags" \
            "Flag info" \
            "Build shell" \
            "Recipe trial" \
            "Garbage collect" \
            "Bootstrap system" \
            "Security audit" \
            "Build estimate" \
            "World file" \
            "Quit") || break

        case "$action" in
            "List installed packages")
                local installed=$(list_packages 2>/dev/null)
                tui_msg "Installed Packages" "${installed:-No packages installed.}"
                ;;
            "List available recipes")
                local recipes=$(list_recipes 2>/dev/null)
                tui_msg "Available Recipes" "${recipes:-No recipes found.}"
                ;;
            "Package info")
                local pkg_list=$(list_packages 2>/dev/null | awk '{print $1}')
                if [[ -z "$pkg_list" ]]; then
                    tui_msg "No packages" "No source packages installed yet."
                    continue
                fi
                local pkg=$(tui_menu "Select Package" "" $pkg_list) || continue
                local info=$(info_package "$pkg")
                tui_msg "Package Info: $pkg" "$info"
                ;;
            "Rebuild a package")
                local avail=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local to_rebuild=$(tui_menu "Select package" "" $avail) || continue
                rebuild_package "$to_rebuild"
                tui_msg "Rebuild" "$to_rebuild rebuilt."
                ;;
            "Create new recipe")
                local name=$(tui_input "New Recipe" "Package name:") || continue
                [[ -z "$name" ]] && continue
                new_recipe "$name"
                ;;
            "Edit recipe")
                local avail2=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail2" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local to_edit=$(tui_menu "Select recipe" "" $avail2) || continue
                edit_recipe "$to_edit"
                ;;
            "Edit kernel config")
                edit_config
                tui_msg "Config" "Kernel config edited."
                ;;
            "Menuconfig")
                launch_menuconfig
                tui_msg "Menuconfig" "Kernel configuration complete."
                ;;
            "Fetch kernel source")
                fetch_source linux
                tui_msg "Source" "Kernel source ready in /usr/src/linux-custom"
                ;;
            "Fetch a recipe from repo")
                local remote_recipes
                remote_recipes=$(list_available 2>/dev/null | awk '{print $1}')
                if [[ -z "$remote_recipes" ]]; then
                    tui_msg "No recipes" "No recipes available from the community repo."
                    continue
                fi
                local to_fetch=$(tui_menu "Select recipe" "" ${remote_recipes}) || continue
                fetch_recipe "$to_fetch"
                tui_msg "Fetch Recipe" "${to_fetch} downloaded."
                ;;
            "Fetch all sources")
                fetch_all_sources
                tui_msg "Fetch All" "All recipe sources downloaded."
                ;;
            "Fetch world sources")
                anvil_fetch_world
                tui_msg "Fetch World" "All world sources downloaded."
                ;;
            "Manage recipe sections")
                tui_manage_sections
                ;;
            "Lint recipe")
                local avail3=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail3" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local to_lint=$(tui_menu "Select recipe" "" $avail3) || continue
                local lint_result=$(lint_recipe "$to_lint" 2>&1)
                tui_msg "Lint Result: $to_lint" "$lint_result"
                ;;
            "Checksum recipe")
                local avail4=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail4" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local to_checksum=$(tui_menu "Select recipe" "" $avail4) || continue
                local checksum_result=$(checksum_recipe "$to_checksum" 2>&1)
                tui_msg "Checksums: $to_checksum" "${checksum_result}"
                ;;
            "Sync recipes")
                sync_recipes
                tui_msg "Sync" "Recipes synchronized."
                ;;
            "Recovery – check & repair source packages")
                anvil_recovery_status
                if tui_yesno "Repair source packages?" "Attempt to repair all source-built packages?"; then
                    local repaired=()
                    while IFS='|' read -r pkgname _; do
                        [[ -n "${pkgname}" ]] || continue
                        anvil_recovery_repair "${pkgname}" && repaired+=("${pkgname}")
                    done < <(tail -n +2 "${POWERUSER_DIR}/db/local.db" 2>/dev/null)
                    if [[ ${#repaired[@]} -gt 0 ]]; then
                        tui_msg "Recovery Complete" "Repaired: ${repaired[*]}"
                    else
                        tui_msg "Recovery" "No packages were repaired."
                    fi
                fi
                ;;
            "Upgrade recipes")
                upgrade_anvil
                tui_msg "Upgrade" "Recipes upgraded. Old recipes backed up."
                ;;
            "Clean cache")
                cache_clean
                tui_msg "Cache" "Obsolete packages removed."
                ;;
            "Package files")
                local pkg_list2=$(list_packages 2>/dev/null | awk '{print $1}')
                if [[ -z "$pkg_list2" ]]; then
                    tui_msg "No packages" "No source packages installed."
                    continue
                fi
                local files_pkg=$(tui_menu "Select package" "" $pkg_list2) || continue
                local files_result=$(anvil_files "$files_pkg" 2>&1)
                tui_msg "Files: $files_pkg" "$files_result"
                ;;
            "Verify package")
                local pkg_list3=$(list_packages 2>/dev/null | awk '{print $1}')
                if [[ -z "$pkg_list3" ]]; then
                    tui_msg "No packages" "No source packages installed."
                    continue
                fi
                local verify_pkg=$(tui_menu "Select package" "" $pkg_list3) || continue
                local verify_result=$(anvil_verify "$verify_pkg" 2>&1)
                tui_msg "Verify: $verify_pkg" "$verify_result"
                ;;
            "Remove package")
                local pkg_list4=$(list_packages 2>/dev/null | awk '{print $1}')
                if [[ -z "$pkg_list4" ]]; then
                    tui_msg "No packages" "No source packages installed."
                    continue
                fi
                local remove_pkg=$(tui_menu "Select package" "" $pkg_list4) || continue
                if tui_yesno "Remove $remove_pkg" "Really remove this package?"; then
                    anvil_remove "$remove_pkg"
                    tui_msg "Removed" "$remove_pkg removed."
                fi
                ;;
            "Recipe history")
                local avail5=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail5" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local log_pkg=$(tui_menu "Select recipe" "" $avail5) || continue
                local log_result=$(anvil_log "$log_pkg" 2>&1)
                tui_msg "History: $log_pkg" "$log_result"
                ;;
            "Recipe diff")
                local avail6=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail6" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local diff_pkg=$(tui_menu "Select recipe" "" $avail6) || continue
                local diff_result=$(anvil_diff "$diff_pkg" 2>&1)
                tui_msg "Diff: $diff_pkg" "$diff_result"
                ;;
            "Rollback recipe")
                local avail7=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail7" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local rollback_pkg=$(tui_menu "Select recipe" "" $avail7) || continue
                local commit=$(tui_input "Rollback" "Enter commit hash:") || continue
                [[ -z "$commit" ]] && continue
                anvil_rollback_recipe "$rollback_pkg" "$commit"
                tui_msg "Rollback" "$rollback_pkg rolled back to $commit."
                ;;
            "Feature flags")
                local avail8=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail8" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local flag_pkg=$(tui_menu "Select package" "" $avail8) || continue
                local current_flags=$(anvil_flag "$flag_pkg" 2>&1)
                tui_msg "Current Flags: $flag_pkg" "$current_flags"
                local flag_name=$(tui_input "Flag" "Enter flag name:") || continue
                [[ -z "$flag_name" ]] && continue
                local flag_action=$(tui_menu "Action" "Toggle, enable, or disable?" "toggle" "on" "off") || continue
                anvil_flag "$flag_pkg" "$flag_name" "$flag_action"
                tui_msg "Flag" "Flag ${flag_name} ${flag_action} for ${flag_pkg}."
                ;;
            "Flag info")
                local avail9=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail9" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local flag_info_pkg=$(tui_menu "Select package" "" $avail9) || continue
                local flag_info_name=$(tui_input "Flag" "Enter flag name:") || continue
                [[ -z "$flag_info_name" ]] && continue
                local flag_info_result=$(anvil_flag_info "$flag_info_pkg" "$flag_info_name" 2>&1)
                tui_msg "Flag Info: $flag_info_pkg/$flag_info_name" "$flag_info_result"
                ;;
            "Build shell")
                local avail10=$(list_recipes 2>/dev/null | awk '{print $1}')
                if [[ -z "$avail10" ]]; then
                    tui_msg "No recipes" "No recipes found."
                    continue
                fi
                local shell_pkg=$(tui_menu "Select package" "" $avail10) || continue
                anvil_shell "$shell_pkg"
                ;;
            "Recipe trial")
                local trial_url=$(tui_input "Trial" "Enter source tarball URL:") || continue
                [[ -z "$trial_url" ]] && continue
                anvil_trial "$trial_url"
                tui_msg "Trial" "Recipe generated from ${trial_url}."
                ;;
            "Garbage collect")
                if tui_yesno "GC" "Run garbage collection?"; then
                    anvil_gc
                    tui_msg "GC" "Garbage collection complete."
                fi
                ;;
            "Bootstrap system")
                local bootstrap_dir=$(tui_input "Bootstrap" "Target directory:" "/tmp/anvil-bootstrap") || continue
                [[ -z "$bootstrap_dir" ]] && continue
                anvil_bootstrap "$bootstrap_dir"
                tui_msg "Bootstrap" "System built at ${bootstrap_dir}."
                ;;
            "Security audit")
                local audit_result=$(anvil_audit "" 2>&1)
                tui_msg "Security Audit" "$audit_result"
                ;;
            "Build estimate")
                local estimate_result=$(anvil_estimate 2>&1)
                tui_msg "Build Estimate" "$estimate_result"
                ;;
            "World file")
                local world_action=$(tui_menu "World" "Select action:" \
                    "Status" "Add package" "Remove package" "Build" "Activate staged" "Back") || continue
                case "$world_action" in
                    "Status")
                        local world_status=$(anvil_world status 2>&1)
                        tui_msg "World Status" "$world_status"
                        ;;
                    "Add package")
                        local world_add=$(tui_input "World" "Package name:") || continue
                        [[ -z "$world_add" ]] && continue
                        anvil_world add "$world_add"
                        tui_msg "World" "$world_add added."
                        ;;
                    "Remove package")
                        local world_remove=$(tui_input "World" "Package name:") || continue
                        [[ -z "$world_remove" ]] && continue
                        anvil_world remove "$world_remove"
                        tui_msg "World" "$world_remove removed."
                        ;;
                    "Build")
                        if tui_yesno "World Build" "Build all packages in world file?"; then
                            anvil_world build
                            tui_msg "World" "World build complete."
                        fi
                        ;;
                    "Activate staged")
                        local stage_dir=$(tui_input "Activate" "Staged directory:" "/nextroot") || continue
                        [[ -z "$stage_dir" ]] && continue
                        anvil_world activate "$stage_dir"
                        ;;
                esac
                ;;
            "Quit") break ;;
        esac
    done
    clear
}