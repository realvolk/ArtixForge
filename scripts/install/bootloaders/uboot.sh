#!/usr/bin/env bash
set -Eeuo pipefail

bootloader_install_uboot() {
    log_info "Installing U-Boot..."
    
    local board_name uboat_target
    board_name="$(state_get BOARD_NAME '')"
    uboat_target="$(state_get UBOOT_TARGET '')"
    
    if [[ -z "${board_name}" ]]; then
        die "No board selected for U-Boot installation"
    fi
    
    log_info "Board: ${board_name}"
    
    local kernel_choice kernel_image initramfs_image
    kernel_choice="$(state_get KERNEL_CHOICE linux-aarch64)"
    kernel_image=$(find_kernel_image "${kernel_choice}" "/mnt/boot")
    [[ -n "${kernel_image}" ]] || die "No kernel image found for U-Boot"
    
    initramfs_image=$(find_initramfs_image "${kernel_choice#linux-}" "/mnt/boot")
    [[ -n "${initramfs_image}" ]] || die "No initramfs image found for U-Boot"
    
    local boot_part="/mnt/boot"
    mkdir -p "${boot_part}"
    
    log_info "Copying kernel and initramfs to boot partition..."
    cp "${kernel_image}" "${boot_part}/"
    cp "${initramfs_image}" "${boot_part}/"
    
    local kernel_name initramfs_name
    kernel_name=$(basename "${kernel_image}")
    initramfs_name=$(basename "${initramfs_image}")
    
    local device_tree=""
    if [[ -n "$(state_get BOARD_DEVICE_TREE '')" ]]; then
        device_tree="$(state_get BOARD_DEVICE_TREE)"
        if [[ -f "/mnt/usr/lib/linux-${kernel_choice#linux-}/dtbs/${device_tree}" ]]; then
            cp "/mnt/usr/lib/linux-${kernel_choice#linux-}/dtbs/${device_tree}" "${boot_part}/"
            device_tree=$(basename "${device_tree}")
            log_info "Device tree copied: ${device_tree}"
        else
            log_warn "Device tree not found: ${device_tree}"
            device_tree=""
        fi
    fi
    
    local root_uuid
    root_uuid=$(blkid -s UUID -o value "$(findmnt -no SOURCE /mnt)")
    [[ -n "${root_uuid}" ]] || root_uuid=""
    
    local boot_cmd="root=UUID=${root_uuid} rw"
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        boot_cmd="cryptdevice=UUID=${root_uuid}:cryptroot root=/dev/mapper/cryptroot rw"
    fi
    
    log_info "Generating boot.scr..."
    local boot_cmd_file="/tmp/boot.cmd.$$"
    cat > "${boot_cmd_file}" <<BOOTCMD
setenv bootargs '${boot_cmd}'
load mmc 0:1 \${kernel_addr_r} ${kernel_name}
load mmc 0:1 \${ramdisk_addr_r} ${initramfs_name}
BOOTCMD

    if [[ -n "${device_tree}" ]]; then
        cat >> "${boot_cmd_file}" <<BOOTCMD
load mmc 0:1 \${fdt_addr_r} ${device_tree}
booti \${kernel_addr_r} \${ramdisk_addr_r} \${fdt_addr_r}
BOOTCMD
    else
        cat >> "${boot_cmd_file}" <<BOOTCMD
booti \${kernel_addr_r} \${ramdisk_addr_r}
BOOTCMD
    fi
    
    mkimage -T script -C none -n "ArtixForge boot script" -d "${boot_cmd_file}" "${boot_part}/boot.scr" || {
        log_error "Failed to generate boot.scr with mkimage"
        rm -f "${boot_cmd_file}"
        return 1
    }
    rm -f "${boot_cmd_file}"
    
    log_info "U-Boot boot script written to ${boot_part}/boot.scr"
    log_info "U-Boot installation complete."
}