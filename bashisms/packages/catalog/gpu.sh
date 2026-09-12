#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA GPU_PACKAGES
GPU_PACKAGES=(
    [nvidia-new]="nvidia-open-dkms nvidia-utils mesa"
    [nvidia-old]="nvidia-dkms nvidia-utils nvidia-settings mesa"
    [intel]="xf86-video-intel intel-media-driver mesa vulkan-intel"
    [amd]="xf86-video-amdgpu mesa vulkan-radeon"
    [unknown]="mesa xf86-video-vesa"
)

declare -gA VM_GUEST_PACKAGES
VM_GUEST_PACKAGES=(
    [kvm]="qemu-guest-agent vulkan-virtio"
    [vmware]="open-vm-tools xf86-video-vmware"
    [virtualbox]="virtualbox-guest-utils"
)