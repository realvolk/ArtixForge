#!/usr/bin/env bash
set -Eeuo pipefail

BASESTRAP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/basestraps"

source "${BASESTRAP_DIR}/packages.sh"
source "${BASESTRAP_DIR}/target_repos.sh"
source "${BASESTRAP_DIR}/kernel_build.sh"

install_base_system() {
    local init kernel fs_type bootloader network_stack user_shell display_manager wm_de locale keymap timezone microcode_override

    init="$(state_get INIT)"
    kernel="$(state_get KERNEL_CHOICE linux)"
    fs_type="$(state_get FS_TYPE ext4)"
    bootloader="$(state_get BOOTLOADER grub)"
    network_stack="$(state_get NETWORK_STACK dhcpcd+iwd)"
    user_shell="$(state_get USER_SHELL bash)"
    display_manager="$(state_get DISPLAY_MANAGER none)"
    wm_de="$(state_get WM_DE none)"
    locale="$(state_get LOCALE en_US.UTF-8)"
    keymap="$(state_get KEYMAP us)"
    timezone="$(state_get TIMEZONE UTC)"
    microcode_override="$(state_get MICROCODE_OVERRIDE auto)"

    detect_kernel_package "${kernel}"

    case "${wm_de}" in
        budgie|cinnamon|cosmic|hyprland|niri|mango|dwm|i3wm)
            if [[ "$(state_get ENABLE_ARCH_REPOS no)" != "yes" ]]; then
                log_info "${wm_de} requires Arch repositories — auto-enabling"
                state_set ENABLE_ARCH_REPOS "yes"
            fi
            ;;
    esac

    local ucode=''
    if [[ "$(state_get TARGET_ARCH '')" != "aarch64" ]]; then
        ucode='amd-ucode'
        grep -q 'GenuineIntel' /proc/cpuinfo && ucode='intel-ucode'
        case "${microcode_override}" in
            intel) ucode='intel-ucode' ;;
            amd)   ucode='amd-ucode' ;;
            none)  ucode='' ;;
        esac
    fi

    local priv_esc
    priv_esc="$(state_get PRIV_ESCALATION sudo)"

    local -a pkgs=()
    mapfile -t -O "${#pkgs[@]}" pkgs < <(resolve_target_base_packages)
    pkgs+=("${priv_esc}")

    if [[ "${init}" != "busybox" ]]; then
        mapfile -t -O "${#pkgs[@]}" pkgs < <(resolve_init_fallback_packages "${init}")
    fi

    local bl_pkgs
    bl_pkgs="$(resolve_bootloader_packages "${bootloader}")"
    [[ -n "$bl_pkgs" ]] && pkgs+=($bl_pkgs)

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "uefi" ]]; then
        pkgs+=("${BOOTLOADER_EXTRA_EFI[@]}")
    fi

    if [[ "$(state_get TARGET_ARCH '')" == "aarch64" ]]; then
        if ! grep -q '^\[armtix\]' /etc/pacman.conf 2>/dev/null; then
            cat <<'EOF' >> /etc/pacman.conf
[armtix]
SigLevel = Never
Server = https://armtix.artixlinux.org/packages/$repo/os/$arch
EOF
        fi
        local -a filtered=()
        local p
        for p in "${pkgs[@]}"; do
            [[ "${p}" == "efibootmgr" || "${p}" == "dosfstools" ]] && continue
            filtered+=("${p}")
        done
        pkgs=("${filtered[@]}")
    fi

    [[ -n "${ucode}" ]] && pkgs+=("${ucode}")

    local seat_pkg
    seat_pkg="$(resolve_seat_package "${wm_de}")"
    if [[ -n "${seat_pkg}" && "${init}" != "busybox" ]]; then
        pkgs+=("${seat_pkg}" "${seat_pkg}-${init}")
    elif [[ "${init}" != "busybox" ]]; then
        local elogind_pkg
        elogind_pkg="$(resolve_init_elogind "${init}")"
        [[ -n "${elogind_pkg}" ]] && pkgs+=("${elogind_pkg}")
    fi

    local shell_pkgs
    shell_pkgs="$(resolve_target_shell_packages "${user_shell}")"
    [[ -n "$shell_pkgs" ]] && pkgs+=($shell_pkgs)

    local skip_binary_kernel=0
    [[ "$(state_get POWER_USER no)" == "yes" && "$(state_get KEEP_BINARY_KERNEL yes)" == "no" ]] && skip_binary_kernel=1

    case "${kernel}" in
        linux|linux-zen|linux-lts|linux-hardened|linux-aarch64|linux-aarch64-lts)
            basestrap_kernel_standard pkgs "${skip_binary_kernel}"
            ;;
        linux-libre)
            basestrap_kernel_linux_libre pkgs "${skip_binary_kernel}"
            ;;
        linux-cachyos*)
            basestrap_kernel_cachyos pkgs "${skip_binary_kernel}"
            ;;
        linux-bazzite-bin)
            basestrap_kernel_bazzite pkgs "${skip_binary_kernel}"
            ;;
        xanmod)
            basestrap_kernel_xanmod pkgs "${skip_binary_kernel}"
            ;;
        tkg)
            basestrap_kernel_tkg pkgs
            ;;
        *)
            die "unsupported kernel: ${kernel}" ;;
    esac

    local net_pkgs
    net_pkgs="$(resolve_network_packages "${network_stack}" "${init}")"
    [[ -n "$net_pkgs" ]] && pkgs+=($net_pkgs)

    local fs_pkgs
    fs_pkgs="$(resolve_filesystem_packages "${fs_type}")"
    [[ -n "$fs_pkgs" ]] && pkgs+=($fs_pkgs)

    if [[ "${fs_type}" == "btrfs" && "${bootloader}" == "limine" ]]; then
        pkgs+=(limine-snapper-sync)
    fi

    if [[ "$(state_get USE_LUKS no)" != "yes" ]]; then
        pkgs+=(artix-grub-theme)
    fi

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        local lvm_pkgs
        lvm_pkgs="$(resolve_target_storage_packages lvm "${init}")"
        [[ -n "$lvm_pkgs" ]] && pkgs+=($lvm_pkgs)
    fi

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local luks_pkgs
        luks_pkgs="$(resolve_target_storage_packages luks "${init}")"
        [[ -n "$luks_pkgs" ]] && pkgs+=($luks_pkgs)
    fi

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        mapfile -t -O "${#pkgs[@]}" pkgs < <(resolve_target_uki_packages)
    fi

    printf '%s\n' "${pkgs[@]}" > "${PWD}/artix-pkgs.log"

    local debug_log="${PWD}/basestrap-debug.log"
    : > "${debug_log}"

    export GNUPGHOME="${GNUPGHOME:-/etc/pacman.d/gnupg}"
    mkdir -p "${GNUPGHOME}"
    chmod 700 "${GNUPGHOME}"
    log_info "Initializing Artix keyring..."
    pacman-key --init
    pacman-key --populate artix

    if [[ "$(state_get ENABLE_ARCH_REPOS no)" == 'yes' ]]; then
        log_info "Synchronizing package databases..."
        if ! pacman -Sy --noconfirm; then
            die "Failed to sync package databases — check mirrorlist configuration"
        fi

        log_info "Installing Arch repository support..."
        pacman -S --noconfirm --needed artix-archlinux-support

        if ! grep -q '^\[extra\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[extra]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
        if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi

        log_info "Re-synchronizing after adding Arch repos..."
        if ! pacman -Sy --noconfirm; then
            die "Failed to sync package databases after adding Arch repos"
        fi

        log_info "Populating archlinux keyring..."
        pacman-key --populate archlinux || log_warn "Failed to populate archlinux keyring"

        log_info "Installing Arch Linux keyring..."
        pacman -S --noconfirm --needed archlinux-keyring
    fi

    basestrap_repo_auris

    log_info "Starting basestrap..."
    printf '%s\n' "${pkgs[@]}" >> "${debug_log}"
    clean_pacman_lock /mnt/var/lib/pacman/db.lck
    if ! xtrace_safe basestrap /mnt "${pkgs[@]}" \
        2>&1 | tee -a "${debug_log}" \
        | while IFS= read -r line; do
            log_info "${line}"
        done; then
        recoverable_error "basestrap failed – the installer can update itself and retry"
    fi

    [[ -x /mnt/bin/bash ]] || die "/mnt/bin/bash missing after basestrap"
    [[ -f /mnt/etc/os-release ]] || die "target root invalid after basestrap"

    if [[ ! -e /mnt/sbin/init ]]; then
        log_warn "/sbin/init not found — creating init symlink"
        local init_bin
        init_bin="$(state_get INIT openrc)"
        artix-chroot /mnt ln -sf "/usr/bin/${init_bin}" /sbin/init 2>/dev/null || {
            log_error "Failed to create /sbin/init symlink for ${init_bin}"
            die "Init symlink missing — system will not boot"
        }
    fi

    if ! grep -q '^Architecture' /mnt/etc/pacman.conf 2>/dev/null; then
        sed -i '1s/^/[options]\nArchitecture = auto\n\n/' /mnt/etc/pacman.conf
    fi

    if [[ -d /mnt/etc/pacman.d/gnupg ]]; then
        artix-chroot /mnt chown -R root:root /etc/pacman.d/gnupg/ 2>/dev/null || true
        artix-chroot /mnt chmod 755 /etc/pacman.d/gnupg/ 2>/dev/null || true
        [[ -f /mnt/etc/pacman.d/gnupg/pubring.gpg ]] && artix-chroot /mnt chmod 644 /etc/pacman.d/gnupg/pubring.gpg 2>/dev/null || true
        [[ -f /mnt/etc/pacman.d/gnupg/trustdb.gpg ]] && artix-chroot /mnt chmod 644 /etc/pacman.d/gnupg/trustdb.gpg 2>/dev/null || true
        [[ -d /mnt/etc/pacman.d/gnupg/private-keys-v1.d ]] && artix-chroot /mnt chmod 700 /etc/pacman.d/gnupg/private-keys-v1.d/ 2>/dev/null || true
    fi

    case "${kernel}" in
        linux-cachyos*)
            basestrap_target_repo_cachyos
            ;;
        linux-bazzite-bin)
            basestrap_target_repo_bazzite
            ;;
        xanmod)
            basestrap_target_repo_xanmod
            ;;
    esac
    basestrap_target_repo_auris

    if [[ -n "${KERNEL_PACKAGE:-}" ]] && ! pacman -Q "${KERNEL_PACKAGE}" &>/dev/null && [[ "${kernel}" != "tkg" && "${kernel}" != "linux-bazzite-bin" ]]; then
        log_warn "Kernel ${KERNEL_PACKAGE} failed to install. Falling back to linux."
        state_set KERNEL_CHOICE "linux"
        retry_command "kernel fallback" basestrap /mnt linux linux-headers
    fi

    log_info "Configuring locale..."
    artix-chroot /mnt /bin/bash -c "
        grep -q '^${locale} UTF-8' /etc/locale.gen || echo '${locale} UTF-8' >> /etc/locale.gen
        locale-gen
        cat > /etc/locale.conf <<EOF
LANG=${locale}
EOF
    "

    log_info "Configuring keymap..."
    cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=${keymap}
EOF

    log_info "Configuring timezone..."
    artix-chroot /mnt ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
    artix-chroot /mnt hwclock --systohc


    local init="$(state_get INIT openrc)"
    local use_luks use_lvm
    use_luks="$(state_get USE_LUKS no)"
    use_lvm="$(state_get USE_LVM no)"

    if [[ "${use_luks}" == "yes" || "${use_lvm}" == "yes" ]]; then
        log_info "Configuring initramfs storage hooks via drop-in..."

        local hooks=(base udev autodetect microcode modconf kms keyboard keymap consolefont block)

        if [[ "${use_luks}" == "yes" ]]; then
            hooks+=(encrypt)
        fi
        if [[ "${use_lvm}" == "yes" ]]; then
            hooks+=(lvm2)
        fi

        hooks+=(filesystems fsck)

        mkdir -p /mnt/etc/mkinitcpio.conf.d
        cat > /mnt/etc/mkinitcpio.conf.d/artixforge-storage.conf <<EOF
HOOKS=(${hooks[*]})
EOF

        log_info "Storage hooks: ${hooks[*]}"
    fi

    if [[ "${use_lvm}" == "yes" ]]; then
        log_info "Enabling LVM boot service..."
        case "${init}" in
            dinit) enable_service_boot lvm2 2>/dev/null || warn_collect "lvm2 service not found for dinit — LVM may need manual activation" ;;
            *)     enable_service_boot lvm 2>/dev/null || warn_collect "lvm service not found for ${init}" ;;
        esac
    fi

    if [[ "${use_luks}" == "yes" ]]; then
        log_info "Enabling LUKS boot services..."
        case "${init}" in
            dinit)
                warn_collect "dinit handles LUKS via kernel command line — ensure cryptdevice= is in kernel cmdline"
                ;;
            *)
                enable_service_boot dmcrypt 2>/dev/null || warn_collect "dmcrypt service not found for ${init}"
                enable_service_boot device-mapper 2>/dev/null || warn_collect "device-mapper service not found for ${init}"
                ;;
        esac
    fi

    if [[ "${use_luks}" == "yes" || "${use_lvm}" == "yes" ]]; then
        log_info "Regenerating initramfs with storage hooks..."
        artix-chroot /mnt mkinitcpio -P || die "mkinitcpio failed after storage hook configuration"
    fi

    if ! grep -q 'virtio_blk' /mnt/etc/mkinitcpio.conf 2>/dev/null; then
        log_info "Adding virtio_blk to initramfs MODULES..."
        artix-chroot /mnt sed -i 's/^MODULES=(/MODULES=(virtio_blk /' /etc/mkinitcpio.conf
    fi

    if [[ "${kernel}" == 'tkg' ]]; then
        basestrap_build_tkg || die "TKG kernel build failed — cannot continue without a kernel"
    fi

    if [[ "${kernel}" == 'linux-bazzite-bin' ]]; then
        basestrap_build_bazzite || die "Bazzite kernel build failed — cannot continue without a kernel"
        artix-chroot /mnt mkinitcpio -P
        if [[ -d /mnt/boot/grub ]]; then
            artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        fi
    fi

    if [[ -d /mnt/repo ]]; then
        log_info "Offline mode: copying local repository to target..."
        mkdir -p /mnt/mnt/repo
        cp -a /mnt/repo/. /mnt/mnt/repo/ 2>/dev/null || true
        if ! grep -q '\[custom\]' /mnt/etc/pacman.conf 2>/dev/null; then
            cat >> /mnt/etc/pacman.conf <<'EOF'

[custom]
SigLevel = Optional
Server = file:///mnt/repo/
EOF
        fi
        log_info "Target system configured for offline package access"
    fi

    log_info "Base system installation complete."
}