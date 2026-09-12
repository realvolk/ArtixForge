#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${DEBUG:-false}" == "true" || "${ARTIX_DEBUG:-false}" == "true" ]]; then
    exec 19> "/tmp/artix-migration-debug.log"
    export BASH_XTRACEFD=19
    export PS4='+ ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
    set -x
fi

MIGRATIONS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

tui_migration_menu() {
    local choice
    choice=$(tui_menu "System Migration" "What would you like to migrate?" \
        "Init System – convert OpenRC ↔ runit ↔ dinit ↔ s6" \
        "Desktop Environment – swap KDE ↔ XFCE ↔ Sway etc." \
        "Arch Linux → Artix (EXPERIMENTAL)" \
        "Abort") || return 1

    case "${choice}" in
        "Init System"*)
            if [[ -f "${MIGRATIONS_DIR}/inits/common.sh" ]]; then
                source "${MIGRATIONS_DIR}/inits/common.sh"
                tui_init_migration_menu
            else
                tui_msg_quick "Not Available" "Init migration module not found."
            fi
            ;;
        "Desktop Environment"*)
            if [[ -f "${MIGRATIONS_DIR}/des/common.sh" ]]; then
                source "${MIGRATIONS_DIR}/des/common.sh"
                tui_de_migration_menu
            else
                tui_msg_quick "Not Available" "Desktop migration module not found."
            fi
            ;;
        "Arch Linux → Artix"*)
            if tui_yesno "EXPERIMENTAL FEATURE" \
"Arch → Artix migration is EXPERIMENTAL.

It will attempt to convert your entire Arch Linux system
to Artix, preserving user data, configs, and credentials.

WHAT IT DOES:
  • Detects your full system configuration
  • Backs up everything before touching anything
  • Converts systemd services, timers, PAM, hooks, and more
  • Reinstalls your desktop and packages from Artix repos
  • Attempts to reinstall AUR packages automatically

WHAT YOU SHOULD DO FIRST:
  • MAKE A FULL SYSTEM BACKUP (seriously)
  • Close all applications
  • Have a working internet connection
  • Be prepared to fix things manually if needed

This has been built with care, but Arch and Artix have
diverged in ways no script can fully predict.

Proceed at your own risk."; then
                source "${MIGRATIONS_DIR}/ata/ata-migrate.sh"
                ata_migrate_main || true
            fi
            ;;
        *) return 0 ;;
    esac
}