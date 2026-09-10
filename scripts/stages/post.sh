#!/usr/bin/env bash
set -Eeuo pipefail

stage_post() {
    if stage_should_skip post; then return 0; fi

    local init network_stack wm_de x_stack kernel_choice audio_stack extras fs_type user_name log_file rc=0
    init="$(state_get INIT)"
    network_stack="$(state_get NETWORK_STACK)"
    wm_de="$(state_get WM_DE)"
    x_stack="$(state_get X_STACK xorg)"
    kernel_choice="$(state_get KERNEL_CHOICE linux)"
    audio_stack="$(state_get AUDIO_STACK pipewire)"
    extras="$(state_get EXTRAS '')"
    fs_type="$(state_get FS_TYPE ext4)"
    user_name="$(state_get USER_NAME)"
    log_file='/tmp/post-stage.log'

    log_info "Preparing installer environment..."
    mkdir -p /mnt/root
    rm -rf /mnt/root/ArtixForge
    cp -r "${BASE_DIR}" /mnt/root/ArtixForge

    [[ -x /mnt/bin/bash ]] || die "chroot environment missing /bin/bash"
    [[ -f /mnt/etc/os-release ]] || die "invalid target root filesystem"

    log_info "Entering chroot environment..."

    export GUM_TITLE_COLOR="$(state_get GUM_TITLE_COLOR 212)"
    export GUM_ACCENT_COLOR="$(state_get GUM_ACCENT_COLOR 34)"
    export SWAP_ENABLED="$(state_get SWAP_ENABLED none)"
    export SWAP_SIZE="$(state_get SWAP_SIZE 0)"
    export ZRAM_PERCENT="$(state_get ZRAM_PERCENT 50)"

    if artix-chroot /mnt /bin/bash <<EOF
set -Eeuo pipefail

export INIT="${init}"
export NETWORK_STACK="${network_stack}"
export WM_DE="${wm_de}"
export X_STACK="${x_stack}"
export KERNEL_CHOICE="${kernel_choice}"
export AUDIO_STACK="${audio_stack}"
export EXTRAS="${extras}"
export USER_NAME="${user_name}"
export FS_TYPE="${fs_type}"
export GUM_TITLE_COLOR="${GUM_TITLE_COLOR}"
export GUM_ACCENT_COLOR="${GUM_ACCENT_COLOR}"
export SWAP_ENABLED="${SWAP_ENABLED}"
export SWAP_SIZE="${SWAP_SIZE}"
export ZRAM_PERCENT="${ZRAM_PERCENT}"

cd /root/ArtixForge || exit 1

source ./scripts/state.sh
source ./scripts/common.sh
source ./scripts/tui/core.sh
source ./scripts/install/services.sh
source ./scripts/post/drivers.sh
source ./scripts/post/networking.sh
source ./scripts/post/desktop.sh
source ./scripts/post/audio.sh
source ./scripts/post/extras.sh

log_info "Configuring networking..."
setup_networking

log_info "Installing drivers..."
install_drivers

log_info "Installing desktop environment..."
install_desktop

log_info "Configuring audio..."
setup_audio

log_info "Installing extras..."
install_extras

if [[ "\${FS_TYPE}" == 'btrfs' ]]; then
    log_info "Setting up snapper for BTRFS snapshots..."
    snapper -c root create-config / 2>/dev/null || log_warn "snapper config may already exist"
    snapper -c root set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes 2>/dev/null || true
    enable_service snapper-timeline 2>/dev/null || true
    enable_service snapper-cleanup 2>/dev/null || true
fi

if [[ "\${FS_TYPE}" == "xfs" ]]; then
    root_device=''
    root_device=\$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [[ -n "\${root_device}" ]]; then
        log_info "Checking XFS bigtime support on \${root_device}..."
        if ! xfs_db -r -c "version" "\${root_device}" 2>/dev/null | grep -q bigtime; then
            log_warn "XFS timestamps will end in 2038."
            log_warn "Run 'xfs_admin -O bigtime=1 \${root_device}' from rescue to upgrade."
        fi
    fi
fi

if [[ "\${SWAP_ENABLED}" == "zram" ]]; then
    log_info "Setting up zram at \${ZRAM_PERCENT}% of RAM..."
    pacman -S --noconfirm --needed zramen 2>/dev/null || log_warn "zramen package not found"
    echo "ZRAM_PERCENTAGE=\${ZRAM_PERCENT}" > /etc/default/zramen 2>/dev/null || true
    enable_service zramen 2>/dev/null || log_warn "zramen service not found for init — enable manually after boot"
fi

if [[ "\${SWAP_ENABLED}" == "zswap" ]]; then
    log_info "Enabling zswap in kernel parameters..."
    if [[ -f /etc/default/grub ]] && ! grep -q 'zswap.enabled=1' /etc/default/grub 2>/dev/null; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=20"/' /etc/default/grub
    fi
fi

if [[ "\${SWAP_ENABLED}" == "swapfile" ]]; then
    log_info "Creating swapfile of \${SWAP_SIZE}MB..."
    dd if=/dev/zero of=/swapfile bs=1M count="\${SWAP_SIZE}" status=none 2>/dev/null || true
    chmod 600 /swapfile
    mkswap /swapfile 2>/dev/null || log_warn "Failed to create swapfile"
    swapon /swapfile 2>/dev/null || true
    echo '/swapfile none swap defaults 0 0' >> /etc/fstab
fi

log_info "Post-install configuration complete."
EOF
    then
        rc=0
    else
        rc=$?
        log_error "Post-install stage failed with exit code: ${rc}"
    fi

    if [[ ${rc} -ne 0 ]]; then
        if [[ -f /mnt/root/ArtixForge/drivers-debug.log ]]; then
            cp /mnt/root/ArtixForge/drivers-debug.log /tmp/drivers-debug.log 2>/dev/null || true
        fi
        tui_msg "Post Installation Failed" \
            "The post-install stage failed.\n\nLogs:\n- ${log_file}\n- /tmp/drivers-debug.log\n\nThe installation was NOT marked complete."
        return ${rc}
    fi

    touch /mnt/root/.artix-post-complete
    stage_mark_done post
}