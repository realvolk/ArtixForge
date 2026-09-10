#!/usr/bin/env bash
set -Eeuo pipefail

bootloader_install_uboot() {
    local board="${BOARD_NAME:-unknown}"
    local kernel_image initramfs_image dtb_file

    log_info "Installing U-Boot for ${board}..."

    if ! command -v mkimage >/dev/null 2>&1; then
        die "mkimage not found – install uboot-tools"
    fi

    kernel_image=$(find_kernel_image "${KERNEL_CHOICE:-linux}")
    [[ -n "${kernel_image}" ]] || die "No kernel image found"
    local kver
    kver=$(basename "${kernel_image}" | sed 's/^vmlinuz-//')
    initramfs_image=$(find_initramfs_image "${kver}")
    [[ -n "${initramfs_image}" ]] || die "No initramfs image found"

    dtb_file=$(find /mnt/boot -name "${BOARD_DEVICE_TREE:-*.dtb}" 2>/dev/null | head -n1)
    if [[ -z "${dtb_file}" ]]; then
        log_warn "Device tree ${BOARD_DEVICE_TREE} not found – boot may fail"
    fi

    local boot_script="/tmp/boot.cmd"
    local boot_scr="/tmp/boot.scr"
    cat > "${boot_script}" <<EOF
# U-Boot boot script for ${board}
setenv bootargs console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw

load mmc 0:1 \${kernel_addr_r} $(basename "${kernel_image}")
load mmc 0:1 \${fdt_addr_r} $(basename "${dtb_file}")
load mmc 0:1 \${ramdisk_addr_r} $(basename "${initramfs_image}")

booti \${kernel_addr_r} \${ramdisk_addr_r} \${fdt_addr_r}
EOF

    mkimage -A arm64 -O linux -T script -C none -d "${boot_script}" "${boot_scr}" || die "Failed to create boot.scr"

    local boot_mount="/mnt/boot"
    cp "${kernel_image}" "${boot_mount}/"
    cp "${initramfs_image}" "${boot_mount}/"
    [[ -f "${dtb_file}" ]] && cp "${dtb_file}" "${boot_mount}/"
    cp "${boot_scr}" "${boot_mount}/boot.scr"

    log_info "U-Boot boot script installed to ${boot_mount}/boot.scr"
    log_info "U-Boot binary must be written to the SD card at the correct offset for ${board}"
    log_info "Example: dd if=u-boot.bin of=/dev/mmcblk0 seek=64 conv=fsync"
}