#!/usr/bin/env bash
set -Eeuo pipefail

_tkg_write_config() {
    local cfg_path="${1}"
    cat > "${cfg_path}" <<EOF
_sched="$(state_get TKG_SCHEDULER eevdf)"
_compiler="$(state_get TKG_COMPILER gcc)"
_optlevel="$(state_get TKG_OPTLEVEL 1)"
_processor_opt="$(state_get TKG_PROCESSOR_OPT native)"
_lto_mode="$(state_get TKG_LTO_MODE no)"
_preempt_rt="$(state_get TKG_PREEMPT_RT 0)"
_tickless="$(state_get TKG_TICKLESS 2)"
_timer_freq="$(state_get TKG_TIMER_FREQ 1000)"
_cpu_gov="$(state_get TKG_CPU_GOV ondemand)"
_glitched_base="$(state_get TKG_GLITCHED_BASE false)"
_zenify="$(state_get TKG_ZENIFY false)"
_clear_patches="$(state_get TKG_CLEAR_PATCHES false)"
_openrgb="$(state_get TKG_OPENRGB false)"
_acs_override="$(state_get TKG_ACS_OVERRIDE false)"
_fsync="$(state_get TKG_FSYNC false)"
_mglru="$(state_get TKG_MGLRU false)"
_ntsync="$(state_get TKG_NTSYNC false)"
_nr_cpus="$(state_get TKG_NR_CPUS $(nproc))"
EOF
}

basestrap_build_tkg() {
    log_info "Building TKG kernel inside target chroot..."

    local sched
    sched="$(state_get TKG_SCHEDULER eevdf)"

    local cfg_path="/mnt/tmp/tkg-customization.cfg"
    _tkg_write_config "${cfg_path}"

    local failed_patches=""
    
    artix-chroot /mnt bash -c "
        pacman -S --noconfirm --needed base-devel git bc cpio flex libelf pahole dkms
        
        cd /tmp
        rm -rf linux-tkg linux-custom
        
        git clone --depth 1 https://github.com/Frogging-Family/linux-tkg.git
        
        artix_kver=\$(pacman -Si linux 2>/dev/null | grep Version | awk '{print \$3}' | cut -d- -f1)
        [[ -z \"\${artix_kver}\" ]] && artix_kver=\$(uname -r | cut -d- -f1)
        
        git clone --depth 1 --branch \"v\${artix_kver}\" \
            https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-custom 2>/dev/null || \
        git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-custom
        
        cp /tmp/tkg-customization.cfg /tmp/linux-tkg/customization.cfg
        
        cd linux-custom
        
        kver=\$(make kernelrelease 2>/dev/null || make kernelversion | grep -oP '\d+\.\d+')
        patch_dir=\"/tmp/linux-tkg/linux-tkg-patches/\${kver}\"
        failed_patches_file=\"/tmp/tkg-failed-patches.txt\"
        : > \"\${failed_patches_file}\"
        
        if [[ -d \"\${patch_dir}\" ]]; then
            for patch in \"\${patch_dir}\"/*.patch; do
                patch_name=\$(basename \"\$patch\")
                
                affected_files=\$(grep '^+++' \"\$patch\" 2>/dev/null | sed 's|^+++ [^/]*/||' || true)
                
                if patch -Np1 < \"\$patch\" 2>/dev/null; then
                    continue
                fi
                
                echo \"\${patch_name}\" >> \"\${failed_patches_file}\"
                echo \"Patch \${patch_name} failed — restoring ALL affected files\"
                
                for file in \${affected_files}; do
                    [[ -n \"\${file}\" ]] || continue
                    echo \"  Restoring \${file}\"
                    git checkout \"\${file}\" 2>/dev/null || rm -f \"\${file}\"
                done
            done
        fi
        
        make defconfig
        scripts/config --enable DM_CRYPT
        scripts/config --enable DM_INTEGRITY
        make -j\$(nproc)
        make modules_install
        make install
        
        newest_kernel=\$(find /boot -maxdepth 1 -name 'vmlinuz*' ! -name '*.old' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        if [[ -n \"\${newest_kernel}\" && ! -f /boot/vmlinuz-artixforge-tkg ]]; then
            mv \"\${newest_kernel}\" /boot/vmlinuz-artixforge-tkg
            cp /boot/System.map /boot/System.map-artixforge-tkg 2>/dev/null || true
            kernel_image=/boot/vmlinuz-artixforge-tkg
        elif [[ -f /boot/vmlinuz-artixforge-tkg ]]; then
            kernel_image=/boot/vmlinuz-artixforge-tkg
        else
            kernel_image=\$(ls -1 /boot/vmlinuz* 2>/dev/null | tail -1)
        fi
        [[ -z \"\${kernel_image}\" ]] && { echo \"ERROR: No kernel image found after build\"; exit 1; }

        cat > /etc/mkinitcpio.d/linux-custom.preset <<PRESETEOF
ALL_config=\"/etc/mkinitcpio.conf\"
ALL_kver=\"\${kernel_image}\"
PRESETS=('default')
default_config=\"/etc/mkinitcpio.conf\"
default_image=\"/boot/initramfs-linux-custom.img\"
PRESETEOF
        
        mkinitcpio -P
        
        if [[ -d /boot/grub ]]; then
            grub-mkconfig -o /boot/grub/grub.cfg
        fi
        
        cp \"\${failed_patches_file}\" /tmp/tkg-failed-patches.txt 2>/dev/null || true
    "

    rm -f "${cfg_path}"

    if [[ -f /mnt/tmp/tkg-failed-patches.txt ]]; then
        failed_patches=$(tr '\n' ' ' < /mnt/tmp/tkg-failed-patches.txt)
        rm -f /mnt/tmp/tkg-failed-patches.txt
    fi
    
    if ls /mnt/boot/vmlinuz* &>/dev/null; then
        log_info "TKG kernel built and installed successfully."
        if [[ -n "${failed_patches}" ]]; then
            log_warn "The following TKG patches could not be applied: ${failed_patches}"
            log_warn "This is normal for newer kernels — the default kernel configuration was used for these components."
        fi
    else
        log_error "TKG kernel build failed."
        return 1
    fi
    
    rm -rf /tmp/linux-tkg /tmp/linux-custom
}

basestrap_install_tkg_binary() {
    local sched
    sched="$(state_get TKG_SCHEDULER eevdf)"
    log_info "Downloading TKG binary kernel (${sched})..."

    local api_url="https://api.github.com/repos/Frogging-Family/linux-tkg/releases/latest"
    local release_json
    release_json=$(curl -sL "${api_url}") || {
        log_error "Failed to fetch TKG release info from GitHub"
        return 1
    }

    local kernel_url headers_url
    kernel_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | test("linux[0-9]+-tkg-'"${sched}"'-llvm-[0-9].*-x86_64\\.pkg\\.tar\\.zst")) | .browser_download_url' | grep -v headers | head -n1)
    headers_url=$(echo "${release_json}" | jq -r '.assets[] | select(.name | test("linux[0-9]+-tkg-'"${sched}"'-llvm-headers-.*\\.pkg\\.tar\\.zst")) | .browser_download_url' | head -n1)

    if [[ -z "${kernel_url}" || -z "${headers_url}" ]]; then
        log_error "Could not find TKG binary packages for scheduler: ${sched}"
        return 1
    fi

    log_info "Downloading TKG kernel..."
    curl -L -o /tmp/tkg-kernel.pkg.tar.zst "${kernel_url}" || { log_error "Failed to download TKG kernel"; return 1; }
    curl -L -o /tmp/tkg-headers.pkg.tar.zst "${headers_url}" || { log_error "Failed to download TKG headers"; return 1; }

    log_info "Installing TKG kernel and headers..."
    artix-chroot /mnt pacman -U --noconfirm /tmp/tkg-kernel.pkg.tar.zst /tmp/tkg-headers.pkg.tar.zst || {
        log_error "Failed to install TKG binary packages"
        return 1
    }

    rm -f /tmp/tkg-kernel.pkg.tar.zst /tmp/tkg-headers.pkg.tar.zst
    log_info "TKG binary kernel installed successfully"

    local kver
    kver=$(artix-chroot /mnt ls -1 /boot/vmlinuz-*tkg* 2>/dev/null | head -n1 | sed 's/.*vmlinuz-//')
    if [[ -n "${kver}" ]]; then
        state_set KERNEL_IMAGE "vmlinuz-${kver}"
        state_set INITRAMFS_IMAGE "initramfs-${kver}.img"
    fi
}

basestrap_build_bazzite() {
    log_info "Building linux-bazzite-bin from AUR..."

    local build_dir='/tmp/linux-bazzite-bin'
    rm -rf "${build_dir}"
    git clone 'https://aur.archlinux.org/linux-bazzite-bin.git' "${build_dir}" || {
        log_error "Failed to clone linux-bazzite-bin AUR repo."
        return 1
    }

    pacman -S --noconfirm --needed fakeroot base-devel git mkinitcpio

    mkdir -p /etc/mkinitcpio.d
    cat > /etc/mkinitcpio.d/linux-bazzite.preset <<'PRESET'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-bazzite"
PRESETS=('default')
default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux-bazzite.img"
PRESET

    useradd -m builduser 2>/dev/null || true
    chown -R builduser:builduser "${build_dir}"
    su builduser -c "cd '${build_dir}' && makepkg -s --noconfirm --needed --skippgpcheck" 2>&1 | tee /tmp/bazzite-build.log | while IFS= read -r line; do
        log_info "  ${line}"
    done
    local build_rc=${PIPESTATUS[0]}
    if [[ ${build_rc} -ne 0 ]]; then
        log_error "Failed to build linux-bazzite-bin."
        log_error "Last 20 lines of build log:"
        tail -20 /tmp/bazzite-build.log 2>/dev/null | while IFS= read -r line; do log_error "  ${line}"; done
        return 1
    fi

    pacman -U --noconfirm "${build_dir}"/*.pkg.tar.* || {
        log_error "Failed to install linux-bazzite-bin package."
        return 1
    }
    local kver
    kver=$(ls -1 /usr/lib/modules/ | grep bazzite | sort -V | tail -1)
    if [[ -n "${kver}" && -f "/usr/lib/modules/${kver}/vmlinuz" ]]; then
        cp "/usr/lib/modules/${kver}/vmlinuz" "/mnt/boot/vmlinuz-linux-bazzite"
        cp -a "/usr/lib/modules/${kver}" /mnt/lib/modules/ 2>/dev/null || true
    fi
    rm -rf "${build_dir}"
    log_info "Bazzite kernel installed."
}