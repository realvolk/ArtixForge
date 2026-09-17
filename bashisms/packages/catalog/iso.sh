#!/usr/bin/env bash
set -Eeuo pipefail

declare -ga ISO_BASE_PACKAGES
ISO_BASE_PACKAGES=(
    base base-devel linux-firmware bash nano vim sudo git curl wget pciutils
    mkinitcpio efibootmgr dosfstools gptfdisk parted cryptsetup lvm2
    btrfs-progs xfsprogs f2fs-tools exfat-utils e2fsprogs
    gum artools-base artools-iso artools-pkg openssl rsync grub artix-grub-theme artix-grub-live
    bc cpio pahole libelf ex-vi-compat
)

declare -ga ISO_MICROCODE_PACKAGES
ISO_MICROCODE_PACKAGES=(intel-ucode amd-ucode)

declare -ga ISO_BUILD_TOOLS
ISO_BUILD_TOOLS=(base-devel git)

declare -ga ISO_KERNEL_CHOICES
ISO_KERNEL_CHOICES=(linux linux-zen linux-lts linux-hardened)

declare -ga DE_CHROOT_BUILD
DE_CHROOT_BUILD=(mango vxwm)

declare -ga KERNEL_CHROOT_BUILD
KERNEL_CHROOT_BUILD=(linux-bazzite-bin)