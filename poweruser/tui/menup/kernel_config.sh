#!/usr/bin/env bash
set -Eeuo pipefail

tui_poweruser_kernel_depth() {
    local depth
    depth=$(tui_menu "Kernel Configuration" "How much control do you want?" \
        "localmodconfig – compile only currently loaded modules (recommended)" \
        "Auto-detection – hardware pre-filled, review & adjust" \
        "Manual – blank checklist, pick everything yourself" \
        "menuconfig – full ncurses kernel editor") || return 1
    case "${depth}" in
        localmodconfig*) state_set KERNEL_CONFIG_DEPTH "localmodconfig" ;;
        Auto*)   state_set KERNEL_CONFIG_DEPTH "auto" ;;
        Manual*) state_set KERNEL_CONFIG_DEPTH "manual" ;;
        menuconfig*) state_set KERNEL_CONFIG_DEPTH "menuconfig" ;;
    esac
}

tui_poweruser_kernel_config() {
    local mode="${1:-auto}"
    source "${POWERUSER_DIR}/lib/hwdetect.bash"
    local cpu gpu net storage
    cpu=$(detect_cpu)
    gpu=$(detect_gpu)
    net=$(detect_net)
    storage=$(detect_storage)

    local gpu_choices
    if [[ "${mode}" == "auto" ]]; then
        local gpu_defaults=()
        case "${gpu}" in
            INTEL)   gpu_defaults=("intel (i915)") ;;
            AMD)     gpu_defaults=("amd (amdgpu)") ;;
            NVIDIA)  gpu_defaults=("nvidia (nouveau)") ;;
            VIRTIO)  gpu_defaults=("virtio (virtio-gpu)") ;;
            *)       gpu_defaults=("vesa (basic)") ;;
        esac
        gpu_choices=$(tui_checklist "GPU Drivers" "Select GPU support:" \
            --selected="${gpu_defaults[*]}" \
            "intel (i915)" "amd (amdgpu)" "nvidia (nouveau)" \
            "virtio (virtio-gpu)" "vesa (basic)" "simpledrm (simple framebuffer)") || true
    else
        gpu_choices=$(tui_checklist "GPU Drivers" "Select GPU support:" \
            "intel (i915)" "amd (amdgpu)" "nvidia (nouveau)" \
            "virtio (virtio-gpu)" "vesa (basic)" "simpledrm (simple framebuffer)") || true
    fi
    state_set KERNEL_ADV_GPU "$(echo "${gpu_choices}" | sed 's/ .*//')"

    local net_choices
    if [[ "${mode}" == "auto" ]]; then
        local net_defaults=()
        for n in ${net}; do
            case "${n}" in
                INTEL)   net_defaults+=("intel (e1000/e1000e)") ;;
                REALTEK) net_defaults+=("realtek (r8169)") ;;
                BROADCOM) net_defaults+=("broadcom (tg3/bnx2)") ;;
                ATHEROS) net_defaults+=("atheros (atl1)") ;;
                VIRTIO)  net_defaults+=("virtio (virtio-net)") ;;
            esac
        done
        net_choices=$(tui_checklist "Network" "Select network drivers:" \
            --selected="${net_defaults[*]}" \
            "intel (e1000/e1000e)" "realtek (r8169)" "broadcom (tg3/bnx2)" \
            "atheros (atl1)" "virtio (virtio-net)" \
            "intel-wifi (iwlwifi)" "ath-wifi (ath9k/10k)" \
            "realtek-wifi (rtl8xxxu)" "bt (Bluetooth)") || true
    else
        net_choices=$(tui_checklist "Network" "Select network drivers:" \
            "intel (e1000/e1000e)" "realtek (r8169)" "broadcom (tg3/bnx2)" \
            "atheros (atl1)" "virtio (virtio-net)" \
            "intel-wifi (iwlwifi)" "ath-wifi (ath9k/10k)" \
            "realtek-wifi (rtl8xxxu)" "bt (Bluetooth)") || true
    fi
    state_set KERNEL_ADV_NET "$(echo "${net_choices}" | sed 's/ .*//')"

    local fs_choices
    if [[ "${mode}" == "auto" ]]; then
        local fs_defaults=("ext4 (built-in)")
        local fs_type
        fs_type="$(state_get FS_TYPE ext4)"
        case "${fs_type}" in
            btrfs) fs_defaults+=("btrfs (built-in)") ;;
            xfs)   fs_defaults+=("xfs (built-in)") ;;
            f2fs)  fs_defaults+=("f2fs (module)") ;;
            exfat) fs_defaults+=("exfat (module)") ;;
        esac
        fs_choices=$(tui_checklist "Filesystems" "Select filesystem support:" \
            --selected="${fs_defaults[*]}" \
            "ext4 (built-in)" "btrfs (built-in)" "xfs (built-in)" \
            "f2fs (module)" "exfat (module)" "ntfs3 (module)" "overlay (module)") || true
    else
        fs_choices=$(tui_checklist "Filesystems" "Select filesystem support:" \
            "ext4 (built-in)" "btrfs (built-in)" "xfs (built-in)" \
            "f2fs (module)" "exfat (module)" "ntfs3 (module)" "overlay (module)") || true
    fi
    state_set KERNEL_ADV_FS "$(echo "${fs_choices}" | sed 's/ .*//')"

    local snd_choices
    snd_choices=$(tui_checklist "Sound" "Select audio support:" \
        "intel-hda (Intel HDA)" "amd-hda (AMD HDA)" "usb-audio (USB audio)") || true
    state_set KERNEL_ADV_SOUND "$(echo "${snd_choices}" | sed 's/ .*//')"

    local usb_choices
    if [[ "${mode}" == "auto" ]]; then
        usb_choices=$(tui_checklist "USB Support" "Select USB options:" \
            --selected="hid (USB HID)" \
            "storage (usb-storage)" "hid (USB HID)" "serial (USB serial)") || true
    else
        usb_choices=$(tui_checklist "USB Support" "Select USB options:" \
            "storage (usb-storage)" "hid (USB HID)" "serial (USB serial)") || true
    fi
    state_set KERNEL_ADV_USB "$(echo "${usb_choices}" | sed 's/ .*//')"

    local sec_choices
    sec_choices=$(tui_checklist "Security" "Select security features:" \
        "selinux" "apparmor" "lockdown") || true
    state_set KERNEL_ADV_SECURITY "$(echo "${sec_choices}" | sed 's/ .*//')"

    local virt_choices
    if [[ "${mode}" == "auto" ]]; then
        local virt_defaults=()
        if [[ "${gpu}" == "VIRTIO" || "${net}" =~ "VIRTIO" || "${storage}" == "VIRTIO" ]]; then
            virt_defaults=("kvm (KVM)")
        fi
        virt_choices=$(tui_checklist "Virtualization" "Select virtualization support:" \
            --selected="${virt_defaults[*]}" \
            "kvm (KVM)" "vhost (vhost-net)") || true
    else
        virt_choices=$(tui_checklist "Virtualization" "Select virtualization support:" \
            "kvm (KVM)" "vhost (vhost-net)") || true
    fi
    state_set KERNEL_ADV_VIRT "$(echo "${virt_choices}" | sed 's/ .*//')"

    local dbg_choices
    dbg_choices=$(tui_checklist "Debug & Tracing" "Select debugging features:" \
        "ftrace" "perf" "kprobes" "ebpf") || true
    state_set KERNEL_ADV_DEBUG "$(echo "${dbg_choices}" | sed 's/ .*//')"

    local preempt
    preempt=$(tui_menu "Preemption Model" "Select preemption model:" \
        "voluntary (Desktop)" "full (Low-Latency Desktop)" "rt (Real-Time)") || true
    case "${preempt}" in
        voluntary*) state_set KERNEL_PREEMPT "voluntary" ;;
        full*)      state_set KERNEL_PREEMPT "full" ;;
        rt*)        state_set KERNEL_PREEMPT "rt" ;;
    esac

    local timer
    timer=$(tui_menu "Timer Frequency" "Select kernel timer frequency (Hz):" \
        "100" "250" "300" "1000") || true
    state_set KERNEL_TIMER "${timer}"

    local gov
    gov=$(tui_menu "CPU Governor" "Select default CPU frequency governor:" \
        "schedutil" "ondemand" "performance") || true
    state_set KERNEL_GOVERNOR "${gov}"
}

tui_poweruser_feature_flags() {
    local -a pkgs
    read -ra pkgs <<< "$(state_get POWERUSER_PACKAGES)"
    for pkg in "${pkgs[@]}"; do
        local recipe_file="${POWERUSER_DIR}/recipes/${pkg}.sh"
        [[ -f "${recipe_file}" ]] || continue
        local -a flags=()
        source "${recipe_file}" 2>/dev/null || true
        if [[ "$(declare -p feature_flags 2>/dev/null)" =~ "declare -a" ]]; then
            flags=("${feature_flags[@]}")
        fi
        if [[ ${#flags[@]} -gt 0 ]]; then
            local chosen
            chosen=$(tui_checklist "${pkg} — Feature Flags" "Select features:" "${flags[@]}") || true
            local flag_file="${POWERUSER_DIR}/package.use/${pkg}"
            mkdir -p "$(dirname "${flag_file}")"
            : > "${flag_file}"
            for flag in ${chosen}; do
                echo "${flag}" >> "${flag_file}"
            done
        fi

        if [[ "${pkg}" == "linux" ]]; then
            tui_poweruser_kernel_depth
            local depth
            depth="$(state_get KERNEL_CONFIG_DEPTH auto)"
            if [[ "${depth}" == "auto" ]]; then
                tui_poweruser_kernel_config "auto"
                if tui_yesno "Fine-Tune?" "Review the full blank checklist?"; then
                    tui_poweruser_kernel_config "manual"
                fi
                if tui_yesno "menuconfig?" "Drop into make menuconfig?"; then
                    state_set KERNEL_CONFIG_DEPTH "menuconfig"
                fi
            elif [[ "${depth}" == "manual" ]]; then
                tui_poweruser_kernel_config "manual"
                if tui_yesno "menuconfig?" "Drop into make menuconfig?"; then
                    state_set KERNEL_CONFIG_DEPTH "menuconfig"
                fi
            fi
        fi
    done
}