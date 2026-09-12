#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA BOOTLOADER_PACKAGES
BOOTLOADER_PACKAGES=(
    [grub]="grub os-prober"
    [refind]="refind"
    [efistub]=""
    [limine]="limine"
    [uboot]="uboot-tools"
)

declare -ga BOOTLOADER_EXTRA_EFI
BOOTLOADER_EXTRA_EFI=(efibootmgr dosfstools)