#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA FILESYSTEM_TOOLS
FILESYSTEM_TOOLS=(
    [ext4]="e2fsprogs"
    [btrfs]="btrfs-progs snapper snap-pac grub-btrfs"
    [xfs]="xfsprogs"
    [f2fs]="f2fs-tools"
)

declare -gA FILESYSTEM_TOOLS_EFI
FILESYSTEM_TOOLS_EFI="dosfstools"

declare -ga FS_LIST
FS_LIST=(ext4 btrfs xfs f2fs)

declare -ga BTRFS_LAYOUT_LIST
BTRFS_LAYOUT_LIST=(standard flat snapshot)

declare -ga SWAP_LIST
SWAP_LIST=(none partition swapfile zram zswap)