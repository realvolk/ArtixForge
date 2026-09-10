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

    local init_pkg="${init}"
    local seatd_suffix="${init}"
    local elogind_suffix="${init}"
    if [[ "${init}" == "busybox" ]]; then
        init_pkg=""
        seatd_suffix=""
        elogind_suffix=""
    fi

    local pkgs=(
        base base-devel linux-firmware bash nano vim "${priv_esc}"
        git curl wget pciutils "${init_pkg}" dbus mkinitcpio
    )

    case "${bootloader}" in
        grub)    pkgs+=(grub os-prober) ;;
        refind)  pkgs+=(refind) ;;
        efistub) ;;
        limine)  pkgs+=(limine) ;;
        uboot)   pkgs+=(uboot-tools) ;;
    esac

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "uefi" ]]; then
        pkgs+=(efibootmgr dosfstools)
    fi

    if [[ "$(state_get TARGET_ARCH '')" == "aarch64" ]]; then
        # ARMtix repository configuration for cross-compilation
        if ! grep -q '^\[armtix\]' /etc/pacman.conf 2>/dev/null; then
            cat <<'EOF' >> /etc/pacman.conf
[armtix]
SigLevel = Never
Server = https://armtix.artixlinux.org/packages/$repo/os/$arch
EOF
        fi
        pkgs=("${pkgs[@]/efibootmgr/}")
        pkgs=("${pkgs[@]/dosfstools/}")
    fi

    [[ -n "${ucode}" ]] && pkgs+=("${ucode}")

    case "${wm_de}" in
        hyprland|mango|niri|sway|cosmic)
            [[ -n "${seatd_suffix}" ]] && pkgs+=(seatd "seatd-${seatd_suffix}") ;;
        *)
            [[ -n "${elogind_suffix}" ]] && pkgs+=("elogind-${elogind_suffix}") ;;
    esac

    case "${user_shell}" in
        bash) ;;
        zsh)  pkgs+=(zsh) ;;
        fish) pkgs+=(fish) ;;
        *)    die "unsupported shell: ${user_shell}" ;;
    esac

    local skip_binary_kernel=0
    [[ "$(state_get POWER_USER no)" == "yes" && "$(state_get KEEP_BINARY_KERNEL yes)" == "no" ]] && skip_binary_kernel=1

    case "${kernel}" in
        linux-aarch64|linux-aarch64-lts|linux-radxa)
            basestrap_kernel_standard pkgs "${skip_binary_kernel}"
            ;;
        linux|linux-zen|linux-lts|linux-hardened)
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

    case "${network_stack}" in
        dhcpcd+iwd)     pkgs+=(dhcpcd iwd "dhcpcd-${init}" "iwd-${init}") ;;
        networkmanager) pkgs+=(networkmanager "networkmanager-${init}") ;;
        connman)        pkgs+=(connman "connman-${init}") ;;
        none) ;;
    esac

    case "${fs_type}" in
        btrfs)
            pkgs+=(btrfs-progs snapper snap-pac grub-btrfs)
            if [[ "$(state_get BOOTLOADER grub)" == "limine" ]]; then
                pkgs+=(limine-snapper-sync)
            fi
            ;;
        ext4)      pkgs+=(e2fsprogs) ;;
        xfs)       pkgs+=(xfsprogs) ;;
        f2fs)      pkgs+=(f2fs-tools) ;;
        *) die "unsupported filesystem: ${fs_type}" ;;
    esac

    if [[ "$(state_get USE_LUKS no)" != "yes" ]]; then
        pkgs+=(artix-grub-theme)
    fi

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        pkgs+=(lvm2 "lvm2-${init}")
    fi

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        pkgs+=(cryptsetup "cryptsetup-${init}")
    fi

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        pkgs+=(eukify)
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
        log_info "Installing Arch repository support..."
        pacman -S --noconfirm --needed artix-archlinux-support
        local arch_mirrorlist='/etc/pacman.d/mirrorlist-arch'
        if [[ ! -f "${arch_mirrorlist}" ]]; then
            install -Dm644 /dev/null "${arch_mirrorlist}"
            cat > "${arch_mirrorlist}" <<'MIRROR_EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
MIRROR_EOF
        fi

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
        log_info "Synchronizing package databases..."
        if ! pacman -Sy --noconfirm; then
            die "Failed to sync package databases — check mirrorlist configuration"
        fi
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

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        log_info "Adding LVM hook to mkinitcpio..."
        if ! artix-chroot /mnt grep -q 'lvm2' /etc/mkinitcpio.conf; then
            artix-chroot /mnt sed -i '/^HOOKS=/s/\(block\)/\1 lvm2/' /etc/mkinitcpio.conf
        fi
        log_info "Enabling LVM boot service..."
        case "${init}" in
            dinit) enable_service_boot lvm2 2>/dev/null || warn_collect "lvm2 service not found for dinit — LVM may need manual activation" ;;
            *)     enable_service_boot lvm 2>/dev/null || warn_collect "lvm service not found for ${init}" ;;
        esac
    fi

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        log_info "Adding encrypt hook to mkinitcpio..."
        if ! artix-chroot /mnt grep -q 'encrypt' /etc/mkinitcpio.conf; then
            artix-chroot /mnt sed -i '/^HOOKS=/s/\(block\)/\1 encrypt/' /etc/mkinitcpio.conf
        fi
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