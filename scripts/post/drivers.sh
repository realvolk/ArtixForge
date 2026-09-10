#!/usr/bin/env bash
set -Eeuo pipefail

[[ -f /etc/artix-installer.conf ]] && source /etc/artix-installer.conf
if [[ -f ./scripts/install/services.sh ]]; then
    source ./scripts/install/services.sh
elif [[ -f /usr/local/lib/artix-installer/services.sh ]]; then
    source /usr/local/lib/artix-installer/services.sh
fi

get_gpu_vendor() {
    local vendors
    vendors=$(lspci -nn 2>/dev/null | awk '/VGA|3D/' | grep -oiE 'nvidia|intel|amd')
    if   grep -qi nvidia <<<"${vendors}"; then printf 'nvidia\n'
    elif grep -qi amd    <<<"${vendors}"; then printf 'amd\n'
    elif grep -qi intel  <<<"${vendors}"; then printf 'intel\n'
    else printf 'unknown\n'
    fi
}

get_gpu_info() {
    lspci -nn 2>/dev/null | awk -F': ' '/VGA|3D/ {print $3}' | xargs || true
}

get_pci_id() {
    local raw
    raw=$(lspci -n 2>/dev/null | awk '/0300|0302/ {print $3}' | awk -F':' '{print $2}' | head -n1 || true)
    if [[ "${raw}" =~ ^[0-9a-fA-F]{4}$ ]]; then
        printf '%s\n' "${raw}"
    else
        printf ''
    fi
}

detect_vm() {
    local vm
    vm=$(grep -h -oiE 'vmware|qemu|kvm|oracle|virtualbox|vbox' /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor 2>/dev/null | head -n1)
    if [[ -z "${vm}" ]]; then
        if grep -qE '^flags\b.*\bhypervisor\b' /proc/cpuinfo 2>/dev/null; then
            vm='kvm'
        fi
    fi
    if [[ -n "${vm}" ]]; then
        vm="${vm,,}"
        [[ "${vm}" == "vbox" ]] && vm='virtualbox'
        echo "${vm}"
    else
        echo 'none'
    fi
}
export -f get_gpu_vendor get_gpu_info get_pci_id detect_vm

install_drivers() {
    local pkgs=() rc=0 initramfs_tool='mkinitcpio'
    local gpu_vendor gpu_info pci_id vm_type wm_de kernel_choice
    gpu_vendor=$(get_gpu_vendor | tr -d '[:space:]')
    gpu_vendor="${gpu_vendor:-unknown}"
    gpu_info=$(get_gpu_info)
    gpu_info="${gpu_info:-Unknown}"
    pci_id=$(get_pci_id)
    vm_type=$(detect_vm)
    wm_de="$(state_get WM_DE none | tr -d '[:space:]')"
    kernel_choice="$(state_get KERNEL_CHOICE linux | tr -d '[:space:]')"

    mkdir -p /root/ArtixForge
    : > /root/ArtixForge/drivers-debug.log

    case "${kernel_choice}" in
        linux)                   pkgs+=(linux-headers) ;;
        linux-lts)               pkgs+=(linux-lts-headers) ;;
        linux-hardened)          pkgs+=(linux-hardened-headers) ;;
        linux-zen)               pkgs+=(linux-zen-headers) ;;
        linux-cachy*|linux-cachyos*)
            pacman -Si linux-cachyos-headers >/dev/null 2>&1 && pkgs+=(linux-cachyos-headers) ;;
        linux-bazzite-bin|bazzite) initramfs_tool='dracut' ;;
        xanmod)
            local installed_kernel kernel_headers
            installed_kernel=$(pacman -Q | grep -oP 'linux-xanmod-x64v[2-4]' | head -n1)
            if [[ -n "${installed_kernel}" ]]; then
                kernel_headers="${installed_kernel}-headers"
            else
                kernel_headers="linux-xanmod-headers"
            fi
            pkgs+=("${kernel_headers}")
            ;;
        tkg) ;;
    esac

    {
        log_info "GPU detected: ${gpu_info}"
        log_info "Virtualization: ${vm_type}"
        log_info "Kernel: ${kernel_choice}"

        if [[ "${vm_type}" != 'none' ]]; then
            log_info "VM detected. Installing guest drivers..."
            case "${vm_type}" in
                kvm|qemu)
                    pkgs+=(spice-vdagent qemu-guest-agent xf86-video-qxl)
                    ;;
                vmware)
                    pkgs+=(open-vm-tools xf86-video-vmware)
                    ;;
                oracle|virtualbox)
                    pkgs+=(virtualbox-guest-utils)
                    ;;
            esac
        fi

        if [[ "${gpu_vendor}" == 'nvidia' && -n "${pci_id}" ]]; then
            if (( 16#${pci_id} >= 16#1e00 )); then
                log_info "Newer NVIDIA → nvidia-open-dkms"
                pkgs+=(nvidia-open-dkms nvidia-utils mesa)
            else
                log_info "Older NVIDIA → proprietary"
                pkgs+=(nvidia-dkms nvidia-utils nvidia-settings mesa)
            fi
        elif [[ "${gpu_vendor}" == 'intel' ]]; then
            log_info "Intel GPU detected."
            pkgs+=(xf86-video-intel intel-media-driver mesa vulkan-intel)
        elif [[ "${gpu_vendor}" == 'amd' ]]; then
            log_info "AMD GPU detected."
            pkgs+=(xf86-video-amdgpu mesa vulkan-radeon)
        else
            log_info "Unknown GPU → VESA fallback"
            pkgs+=(mesa xf86-video-vesa)
        fi

        pkgs+=(xorg-server)

        case "${wm_de}" in hyprland|niri|sway) pkgs+=(xorg-xwayland) ;; esac

        log_info "Final package list:"
        printf ' - %s\n' "${pkgs[@]}"

        log_info "Installing: ${pkgs[*]}"
        export COLUMNS=80 LINES=24 TERM=dumb

        clean_pacman_lock
        if retry_command "driver install" pacman --color=never --noconfirm --needed -S "${pkgs[@]}"; then
            rc=0
        else
            rc=$?
            log_error "Driver installation failed (rc=${rc})"
        fi

        if [[ ${rc} -eq 0 && "${gpu_vendor}" == 'nvidia' ]]; then
            log_info "Regenerating initramfs after NVIDIA..."
            if [[ "${initramfs_tool}" == 'dracut' ]]; then
                dracut --regenerate-all --force || rc=$?
            else
                mkinitcpio -P || rc=$?
            fi
        fi

        if [[ "${vm_type}" == 'kvm' || "${vm_type}" == 'qemu' ]]; then
            enable_service qemu-guest-agent || log_warn "Failed to enable qemu-guest-agent"
        fi

        if [[ ${rc} -eq 0 ]]; then
            log_info "Driver installation complete."
        else
            log_error "Driver installation failed."
        fi
    } >> /root/ArtixForge/drivers-debug.log 2>&1

    if [[ ${rc} -ne 0 && "${gpu_vendor}" == 'nvidia' ]]; then
        log_error "NVIDIA failed. Trying nouveau fallback..."
        {
            export COLUMNS=80 LINES=24 TERM=dumb
            modprobe -r nvidia nvidia_modeset nvidia_uvm nvidia_drm 2>/dev/null || true
            dkms remove nvidia --all 2>/dev/null || true
            retry_command "nouveau fallback" pacman --color=never --noconfirm --needed -S xf86-video-nouveau mesa
            rc=$?
        } >> /root/ArtixForge/drivers-debug.log 2>&1
    fi

    return "${rc}"
}