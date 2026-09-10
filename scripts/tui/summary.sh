#!/usr/bin/env bash
set -Eeuo pipefail

tui_show_summary() {
    local title_color="${GUM_TITLE_COLOR:-212}"

    gum style --border rounded --padding 1 --bold --foreground "${title_color}" "Installation Summary"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Disk:')"       "$(state_get DISK)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Hostname:')"   "$(state_get HOSTNAME artix)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Timezone:')"   "$(state_get TIMEZONE Europe/Belgrade)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Locale:')"     "$(state_get LOCALE en_US.UTF-8)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Keyboard:')"   "$(state_get KEYMAP us)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Microcode:')"  "$(state_get MICROCODE_OVERRIDE auto)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'BTRFS:')"      "$(state_get BTRFS_LAYOUT standard)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Filesystem:')" "$(state_get FS_TYPE ext4)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'LVM:')"        "$(state_get USE_LVM no)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Init:')"       "$(state_get INIT openrc)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Bootloader:')" "$(state_get BOOTLOADER grub)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'UKI:')"        "$(state_get GENERATE_UKI no)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Kernel:')"     "$(state_get KERNEL_CHOICE linux)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Priv Esc:')"   "$(state_get PRIV_ESCALATION sudo)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Power User:')" "$(state_get POWER_USER no)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Desktop:')"    "$(state_get WM_DE none)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Network:')"    "$(state_get NETWORK_STACK dhcpcd+iwd)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'X Stack:')"    "$(state_get X_STACK xorg)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'LUKS:')"       "$(state_get USE_LUKS no)"
    printf '%s %s\n' "$(gum style --bold --foreground "${title_color}" 'Arch Repos:')" "$(state_get ENABLE_ARCH_REPOS no)"

    gum confirm "Proceed with installation?" || exit 0
}