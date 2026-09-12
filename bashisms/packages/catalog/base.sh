#!/usr/bin/env bash
set -Eeuo pipefail

declare -ga TARGET_BASE_PACKAGES
TARGET_BASE_PACKAGES=(
    base base-devel linux-firmware bash nano vim
    git curl wget pciutils dbus mkinitcpio
)

declare -gA TARGET_SHELL_PACKAGES
TARGET_SHELL_PACKAGES=(
    [zsh]="zsh"
    [fish]="fish"
)

declare -gA TARGET_STORAGE_PACKAGES
TARGET_STORAGE_PACKAGES=(
    [lvm]="lvm2"
    [luks]="cryptsetup"
)

declare -ga TARGET_UKI_PACKAGES
TARGET_UKI_PACKAGES=(eukify)