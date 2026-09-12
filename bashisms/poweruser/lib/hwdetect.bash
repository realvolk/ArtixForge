#!/usr/bin/env bash
set -Eeuo pipefail

detect_cpu() {
    local cpu_vendor
    cpu_vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "${cpu_vendor}" in
        GenuineIntel) echo "INTEL" ;;
        AuthenticAMD) echo "AMD" ;;
        *) echo "GENERIC" ;;
    esac
}

detect_gpu() {
    local gpu_info
    gpu_info=$(lspci -mm 2>/dev/null | grep -i 'vga\|3d\|display')
    if echo "${gpu_info}" | grep -qi 'intel'; then
        echo "INTEL"
    elif echo "${gpu_info}" | grep -qi 'amd\|ati'; then
        echo "AMD"
    elif echo "${gpu_info}" | grep -qi 'nvidia'; then
        echo "NVIDIA"
    elif echo "${gpu_info}" | grep -qi 'virtio'; then
        echo "VIRTIO"
    else
        echo "GENERIC"
    fi
}

detect_net() {
    local net_info
    net_info=$(lspci -mm 2>/dev/null | grep -i 'network\|ethernet')
    local result=""
    if echo "${net_info}" | grep -qi 'intel'; then result+="INTEL "; fi
    if echo "${net_info}" | grep -qi 'realtek'; then result+="REALTEK "; fi
    if echo "${net_info}" | grep -qi 'broadcom'; then result+="BROADCOM "; fi
    if echo "${net_info}" | grep -qi 'atheros'; then result+="ATHEROS "; fi
    if echo "${net_info}" | grep -qi 'virtio'; then result+="VIRTIO "; fi
    [[ -z "${result}" ]] && echo "GENERIC" || echo "${result% }"
}

detect_storage() {
    local storage_info
    storage_info=$(lspci -mm 2>/dev/null | grep -i 'sata\|ide\|scsi\|nvme')
    if echo "${storage_info}" | grep -qi 'virtio'; then
        echo "VIRTIO"
    elif echo "${storage_info}" | grep -qi 'nvme'; then
        echo "NVME"
    else
        echo "ATA"
    fi
}

recommendations() {
    local cpu gpu net storage
    cpu=$(detect_cpu)
    gpu=$(detect_gpu)
    net=$(detect_net)
    storage=$(detect_storage)

    case "${cpu}" in
        INTEL)
            echo "CONFIG_MCORE2=y"
            echo "CONFIG_MICROCODE=y"
            echo "CONFIG_MICROCODE_INTEL=y"
            ;;
        AMD)
            echo "CONFIG_MK8SSE3=y"
            echo "CONFIG_MICROCODE=y"
            echo "CONFIG_MICROCODE_AMD=y"
            ;;
    esac

    case "${gpu}" in
        INTEL)   echo "CONFIG_DRM_I915=m" ;;
        AMD)     echo "CONFIG_DRM_AMDGPU=m"
                 echo "CONFIG_DRM_AMDGPU_SI=y"
                 echo "CONFIG_DRM_AMDGPU_CIK=y" ;;
        NVIDIA)  echo "CONFIG_DRM_NOUVEAU=m" ;;
        VIRTIO)  echo "CONFIG_DRM_VIRTIO_GPU=y" ;;
        *)       echo "CONFIG_DRM_VESA=y" ;;
    esac

    for n in ${net}; do
        case "${n}" in
            INTEL)   echo "CONFIG_E1000=y"; echo "CONFIG_E1000E=y" ;;
            REALTEK) echo "CONFIG_R8169=y" ;;
            BROADCOM) echo "CONFIG_TIGON3=y"; echo "CONFIG_BNX2=y" ;;
            ATHEROS) echo "CONFIG_ATL1=y" ;;
            VIRTIO)  echo "CONFIG_VIRTIO_NET=y" ;;
        esac
    done

    case "${storage}" in
        VIRTIO) echo "CONFIG_VIRTIO_BLK=y" ;;
        NVME)   echo "CONFIG_BLK_DEV_NVME=y" ;;
        *)      echo "CONFIG_ATA=y"; echo "CONFIG_SATA_AHCI=y" ;;
    esac

    echo "CONFIG_EXT4_FS=y"
    echo "CONFIG_BTRFS_FS=y"
    echo "CONFIG_XFS_FS=y"
}