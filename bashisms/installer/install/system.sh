#!/usr/bin/env bash
set -Eeuo pipefail

configure_system() {
    local hostname timezone locale keymap
    hostname="$(state_get HOSTNAME artix)"
    timezone="$(state_get TIMEZONE UTC)"
    locale="$(state_get LOCALE en_US.UTF-8)"
    keymap="$(state_get KEYMAP us)"

    [[ -n "${hostname}" ]] && [[ "${hostname}" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*$ ]] || die 'invalid hostname'
    [[ -n "${timezone}" ]] || die 'invalid timezone'
    [[ -n "${locale}" ]] || die 'invalid locale'
    [[ -n "${keymap}" ]] || die 'invalid keymap'

    log_info "Configuring hostname..."
    printf '%s\n' "${hostname}" > /mnt/etc/hostname
    cat <<EOF > /mnt/etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${hostname}.localdomain ${hostname}
EOF

    log_info "Configuring locale..."
    if grep -q "^#${locale}" /mnt/etc/locale.gen; then
        sed -i "s/^#${locale}/${locale}/" /mnt/etc/locale.gen
    elif ! grep -q "^${locale}" /mnt/etc/locale.gen; then
        printf '%s UTF-8\n' "${locale%% *}" >> /mnt/etc/locale.gen
    fi
    artix-chroot /mnt locale-gen || die 'failed to generate locale'
    cat <<EOF > /mnt/etc/locale.conf
LANG=${locale}
EOF

    log_info "Configuring keyboard layout..."
    cat <<EOF > /mnt/etc/vconsole.conf
KEYMAP=${keymap}
EOF

    local wm_de
    wm_de="$(state_get WM_DE none)"
    case "${wm_de}" in
        hyprland|sway|niri|mango)
            log_info "Wayland compositor detected — skipping X11 keymap (compositor handles layout)"
            ;;
        *)
            log_info "Setting X11 keymap..."
            mkdir -p /mnt/etc/X11/xorg.conf.d
            cat > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf <<X11KEY
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${keymap}"
EndSection
X11KEY
            ;;
    esac

    log_info "Configuring timezone..."
    [[ -e "/mnt/usr/share/zoneinfo/${timezone}" ]] || die 'invalid timezone path'
    ln -sf "/usr/share/zoneinfo/${timezone}" /mnt/etc/localtime
    artix-chroot /mnt hwclock --systohc || die 'failed to synchronize hardware clock'

    log_info "System configuration complete."
}