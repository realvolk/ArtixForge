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