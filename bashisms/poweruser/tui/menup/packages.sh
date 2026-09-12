#!/usr/bin/env bash
set -Eeuo pipefail

tui_poweruser_select_init() {
    local choice
    choice=$(tui_menu "Init System Override" "Power User init options:" \
        "Keep current (OpenRC/runit/dinit/s6)" \
        "BusyBox init – minimal, source-built") || return 1

    case "${choice}" in
        *BusyBox*) state_set INIT "busybox" ;;
        *) ;;
    esac
}

tui_poweruser_select_packages() {
    local recipes=()
    while IFS=' — ' read -r name desc; do
        recipes+=("${name}")
    done < <(list_recipes)

    [[ ${#recipes[@]} -gt 0 ]] || {
        tui_msg "No Recipes" "No source recipes found."
        return 1
    }

    local selected
    selected=$(tui_checklist "Source Packages" "Select packages to build:" "${recipes[@]}") || return 1

    [[ -n "${selected//[[:space:]]/}" ]] || {
        tui_msg "No Selection" "No packages selected."
        return 1
    }

    state_set POWERUSER_PACKAGES "${selected//$'\n'/ }"

    if [[ " ${selected} " =~ " glibc " ]]; then
        tui_msg "WARNING: glibc Selected" "Building glibc from source is DANGEROUS.\n\nA miscompiled glibc will make your system unbootable.\nKeep the binary package as a fallback.\n\nProceed only if you understand the risks."
    fi
}

tui_poweruser_select_coreutils() {
    local choice
    choice=$(tui_menu "Coreutils" "Select coreutils implementation:" \
        "GNU (default) – standard Artix coreutils" \
        "BusyBox – lightweight multi-call binary" \
        "uutils – Rust rewrite of GNU coreutils" \
        "ArtixForge – debloated minimal coreutils" \
        "Custom – write your own recipe" \
        "None – keep whatever is installed") || return 1

    case "${choice}" in
        GNU*)      state_set COREUTILS "gnu" ;;
        BusyBox*)  state_set COREUTILS "busybox" ;;
        uutils*)   state_set COREUTILS "uutils" ;;
        ArtixForge*) state_set COREUTILS "artix" ;;
        Custom*)
            state_set COREUTILS "custom"
            tui_poweruser_create_recipe
            ;;
        None*)     state_set COREUTILS "none" ;;
    esac
}

tui_poweruser_fallback_kernel() {
    if tui_yesno "Fallback Kernel" "Keep the binary kernel as a fallback?"; then
        state_set KEEP_BINARY_KERNEL "yes"
    else
        state_set KEEP_BINARY_KERNEL "no"
    fi
}