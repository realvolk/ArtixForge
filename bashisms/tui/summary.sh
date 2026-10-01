#!/usr/bin/env bash
set -Eeuo pipefail

tui_show_summary() {
    local title_color="${GUM_TITLE_COLOR:-212}"

    tui_msg "Installation Summary" "$(
        printf '%-12s %s\n' 'Disk:'       "$(state_get DISK)"
        printf '%-12s %s\n' 'Hostname:'   "$(state_get HOSTNAME artix)"
        printf '%-12s %s\n' 'Timezone:'   "$(state_get TIMEZONE Europe/Belgrade)"
        printf '%-12s %s\n' 'Locale:'     "$(state_get LOCALE en_US.UTF-8)"
        printf '%-12s %s\n' 'Keyboard:'   "$(state_get KEYMAP us)"
        printf '%-12s %s\n' 'Microcode:'  "$(state_get MICROCODE_OVERRIDE auto)"
        printf '%-12s %s\n' 'BTRFS:'      "$(state_get BTRFS_LAYOUT standard)"
        printf '%-12s %s\n' 'Filesystem:' "$(state_get FS_TYPE ext4)"
        printf '%-12s %s\n' 'LVM:'        "$(state_get USE_LVM no)"
        printf '%-12s %s\n' 'Init:'       "$(state_get INIT openrc)"
        printf '%-12s %s\n' 'Bootloader:' "$(state_get BOOTLOADER grub)"
        printf '%-12s %s\n' 'UKI:'        "$(state_get GENERATE_UKI no)"
        printf '%-12s %s\n' 'Kernel:'     "$(state_get KERNEL_CHOICE linux)"
        printf '%-12s %s\n' 'Priv Esc:'   "$(state_get PRIV_ESCALATION sudo)"
        printf '%-12s %s\n' 'Power User:' "$(state_get POWER_USER no)"
        printf '%-12s %s\n' 'Desktop:'    "$(state_get WM_DE none)"
        printf '%-12s %s\n' 'Network:'    "$(state_get NETWORK_STACK dhcpcd+iwd)"
        printf '%-12s %s\n' 'X Stack:'    "$(state_get X_STACK xorg)"
        printf '%-12s %s\n' 'LUKS:'       "$(state_get USE_LUKS no)"
        printf '%-12s %s\n' 'Arch Repos:' "$(state_get ENABLE_ARCH_REPOS no)"
    )" || exit 0
}