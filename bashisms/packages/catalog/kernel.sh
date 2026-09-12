#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA KERNEL_PACKAGES
KERNEL_PACKAGES=(
    [linux]="linux"
    [linux-lts]="linux-lts"
    [linux-hardened]="linux-hardened"
    [linux-zen]="linux-zen"
    [linux-libre]="linux-libre"
    [linux-bazzite-bin]="linux-bazzite-bin"
    [linux-aarch64]="linux-aarch64"
    [linux-aarch64-lts]="linux-aarch64-lts"
)

declare -gA KERNEL_HEADERS
KERNEL_HEADERS=(
    [linux]="linux-headers"
    [linux-lts]="linux-lts-headers"
    [linux-hardened]="linux-hardened-headers"
    [linux-zen]="linux-zen-headers"
    [linux-libre]="linux-libre-headers"
    [linux-aarch64]="linux-aarch64-headers"
    [linux-aarch64-lts]="linux-aarch64-lts-headers"
)

declare -ga KERNEL_LIST
KERNEL_LIST=(
    linux linux-zen linux-lts linux-hardened linux-libre
    linux-cachyos linux-cachyos-bore linux-cachyos-eevdf
    linux-cachyos-bmq linux-cachyos-rt-bore linux-cachyos-hardened
    linux-cachyos-lts linux-cachyos-server linux-cachyos-deckify
    linux-bazzite-bin xanmod tkg
)