#!/usr/bin/env bash
set -Eeuo pipefail

MIG_ROOT=""

_verify_migration_root() {
    local root="${1}"
    [[ -d "${root}" ]] || return 1
    [[ -f "${root}/etc/os-release" ]] || return 1
    [[ -x "${root}/usr/bin/pacman" ]] || return 1
    [[ -d "${root}/var/lib/pacman" ]] || return 1
    return 0
}

_verify_running_system() {
    [[ -f /etc/os-release ]] || return 1
    [[ -x /usr/bin/pacman ]] || return 1
    [[ -d /var/lib/pacman ]] || return 1
    return 0
}

ensure_migration_root() {
    local persisted_root
    persisted_root="$(state_get MIG_ROOT "")"

    if [[ -n "${persisted_root}" ]]; then
        if _verify_migration_root "${persisted_root}"; then
            MIG_ROOT="${persisted_root}"
            export MIG_ROOT
            log_info "Migration target (resumed): ${MIG_ROOT}"
            return 0
        fi
        log_warn "Persisted migration root ${persisted_root} is no longer valid."
    fi

    local on_live_iso=false
    [[ -d /run/artix/sfs/rootfs ]] && on_live_iso=true
    [[ -f /run/artix/live ]] && on_live_iso=true

    if [[ "${on_live_iso}" == true ]]; then
        tui_msg "Live ISO Detected" "Migration requires the target system to be mounted."
        local mount_choice
        mount_choice=$(tui_menu "Target Selection" "How do you want to locate the target system?" \
            "Auto-mount (LUKS/LVM/plain)" \
            "Use /mnt (already mounted)" \
            "Specify mount point") || { tui_msg_quick "Cancelled" "Migration cancelled."; exit 0; }

        case "${mount_choice}" in
            "Auto-mount"*)
                recovery_mount_all || { tui_msg_quick "Mount Failed" "Could not mount target system."; exit 1; }
                MIG_ROOT="/mnt"
                ;;
            "Use /mnt"*)
                _verify_migration_root "/mnt" || { tui_msg "Invalid Target" "/mnt is not a valid Artix installation."; exit 1; }
                MIG_ROOT="/mnt"
                ;;
            "Specify"*)
                MIG_ROOT=$(tui_input "Mount Point" "Enter the mount point of the target system:" "/mnt") || exit 1
                [[ -n "${MIG_ROOT}" ]] || exit 1
                _verify_migration_root "${MIG_ROOT}" || { tui_msg "Invalid Target" "${MIG_ROOT} is not a valid Artix installation."; exit 1; }
                ;;
        esac
    else
        local choice
        choice=$(tui_menu "Migration Target" "Which system do you want to migrate?" \
            "This running system" \
            "A mounted installation") || { tui_msg_quick "Cancelled" "Migration cancelled."; exit 0; }

        case "${choice}" in
            "This running"*)
                MIG_ROOT=""
                _verify_running_system || { tui_msg "Invalid System" "This does not appear to be a valid Artix installation."; exit 1; }
                ;;
            "A mounted"*)
                MIG_ROOT=$(tui_input "Mount Point" "Enter the mount point of the target system:" "/mnt") || exit 1
                [[ -n "${MIG_ROOT}" ]] || exit 1
                _verify_migration_root "${MIG_ROOT}" || { tui_msg "Invalid Target" "${MIG_ROOT} is not a valid Artix installation."; exit 1; }
                ;;
        esac
    fi

    export MIG_ROOT
    state_set MIG_ROOT "${MIG_ROOT}"
    log_info "Migration target: ${MIG_ROOT:-running system}"
}

# Run immediately so MIG_ROOT is ready for all functions
ensure_migration_root

_chroot() {
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" "$@"
    else
        "$@"
    fi
}

_pacman_Q() {
    if [[ -n "${MIG_ROOT}" ]]; then
        pacman --root "${MIG_ROOT}" -Q "$@" 2>/dev/null
    else
        pacman -Q "$@" 2>/dev/null
    fi
}

declare -A DE_PACKAGES
DE_PACKAGES=(
    ["kde"]="plasma-desktop dolphin konsole kde-applications"
    ["kde-minimal"]="plasma-desktop dolphin konsole"
    ["xfce"]="xfce4 xfce4-goodies"
    ["lxqt"]="lxqt"
    ["lxde"]="lxde-common lxde"
    ["mate"]="mate mate-extra xdg-desktop-portal-gtk"
    ["hyprland"]="hyprland swaybg swaylock waybar"
    ["sway"]="sway swaybg swaylock waybar"
    ["niri"]="niri swaybg swaylock"
    ["i3wm"]="i3-wm i3status i3lock dmenu xterm"
    ["dwm"]="dwm dmenu xterm"
    ["vxwm"]="vxwm"
    ["icewm"]="icewm"
    ["mango"]="mangowm"
    ["cinnamon"]="cinnamon lightdm lightdm-gtk-greeter"
    ["budgie"]="budgie-desktop budgie-screensaver budgie-control-center lightdm lightdm-gtk-greeter"
    ["moksha"]="moksha enlightenment terminology lightdm lightdm-gtk-greeter"
    ["cosmic"]="cosmic cosmic-terminal cosmic-text-editor cosmic-files cosmic-settings cosmic-launcher lightdm lightdm-gtk-greeter"
    ["none"]=""
)

declare -A DE_DISPLAY_MANAGER
DE_DISPLAY_MANAGER=(
    ["kde"]="sddm"
    ["xfce"]="lightdm"
    ["lxqt"]="sddm"
    ["lxde"]="lightdm"
    ["mate"]="lightdm"
    ["hyprland"]="none"
    ["sway"]="none"
    ["niri"]="none"
    ["i3wm"]="lightdm"
    ["dwm"]="lightdm"
    ["vxwm"]="none"
    ["icewm"]="lightdm"
    ["mango"]="none"
    ["cinnamon"]="lightdm"
    ["budgie"]="lightdm"
    ["moksha"]="lightdm"
    ["cosmic"]="lightdm"
    ["none"]="none"
)

declare -A DM_PACKAGES
DM_PACKAGES=(
    ["sddm-openrc"]="sddm sddm-openrc"
    ["sddm-runit"]="sddm sddm-runit"
    ["sddm-dinit"]="sddm sddm-dinit"
    ["sddm-s6"]="sddm sddm-s6"
    ["lightdm-openrc"]="lightdm lightdm-gtk-greeter lightdm-openrc"
    ["lightdm-runit"]="lightdm lightdm-gtk-greeter lightdm-runit"
    ["lightdm-dinit"]="lightdm lightdm-gtk-greeter lightdm-dinit"
    ["lightdm-s6"]="lightdm lightdm-gtk-greeter lightdm-s6"
)

declare -A AUDIO_PACKAGES
AUDIO_PACKAGES=(
    ["pipewire"]="pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pavucontrol rtkit pipewire-jack"
    ["pulseaudio"]="pulseaudio pulseaudio-alsa alsa-utils pavucontrol"
    ["none"]=""
)

declare -A X_PACKAGES
X_PACKAGES=(
    ["xorg"]="xorg-server xorg-xinit xorg-xset xorg-xrandr xf86-input-libinput xf86-input-evdev"
    ["wayland"]=""
    ["none"]=""
)

declare -A NETWORK_PACKAGES
NETWORK_PACKAGES=(
    ["networkmanager-openrc"]="networkmanager networkmanager-openrc"
    ["networkmanager-runit"]="networkmanager networkmanager-runit"
    ["networkmanager-dinit"]="networkmanager networkmanager-dinit"
    ["networkmanager-s6"]="networkmanager networkmanager-s6"
    ["dhcpcd+iwd-openrc"]="dhcpcd iwd dhcpcd-openrc iwd-openrc"
    ["dhcpcd+iwd-runit"]="dhcpcd iwd dhcpcd-runit iwd-runit"
    ["dhcpcd+iwd-dinit"]="dhcpcd iwd dhcpcd-dinit iwd-dinit"
    ["dhcpcd+iwd-s6"]="dhcpcd iwd dhcpcd-s6 iwd-s6"
    ["connman-openrc"]="connman connman-openrc"
    ["connman-runit"]="connman connman-runit"
    ["connman-dinit"]="connman connman-dinit"
    ["connman-s6"]="connman connman-s6"
    ["none"]=""
)

declare -A EXTRA_PACKAGES
EXTRA_PACKAGES=(
    ["git"]="git"
    ["flatpak"]="flatpak"
    ["fastfetch"]="fastfetch"
    ["firewalld"]="firewalld"
    ["bluez"]="bluez"
    ["zram-tools"]="zram-tools"
    ["fzf"]="fzf"
    ["zoxide"]="zoxide"
    ["starship"]="starship"
    ["eza"]="eza"
    ["btop"]="btop"
    ["htop"]="htop"
    ["nvtop"]="nvtop"
    ["tmux"]="tmux"
    ["nano"]="nano"
    ["vim"]="vim"
    ["neovim"]="neovim"
    ["micro"]="micro"
    ["helix"]="helix"
    ["firefox"]="firefox"
    ["chromium"]="chromium"
    ["qutebrowser"]="qutebrowser"
    ["ranger"]="ranger"
    ["lf"]="lf"
    ["nnn"]="nnn"
    ["thunar"]="thunar"
    ["alacritty"]="alacritty"
    ["kitty"]="kitty"
    ["foot"]="foot"
    ["mpv"]="mpv"
    ["feh"]="feh"
)

detect_current_de()   { detect_desktop >/dev/null 2>&1; state_get WM_DE none; }
detect_current_dm()   { detect_display_manager >/dev/null 2>&1; state_get DISPLAY_MANAGER none; }
detect_current_x()    { detect_xstack >/dev/null 2>&1; state_get X_STACK none; }
detect_current_audio(){ detect_audio_stack >/dev/null 2>&1; state_get AUDIO_STACK none; }
detect_current_network(){ detect_network_stack >/dev/null 2>&1; state_get NETWORK_STACK none; }
detect_current_init() { detect_init >/dev/null 2>&1; state_get INIT openrc; }

_installed_de_packages() {
    local de="$1"
    local pattern=""
    case "$de" in
        kde)      pattern='^(plasma|plasma-|kwin|kde-|sddm|dolphin|konsole|kate|okular|gwenview|spectacle|discover|drkonqi|bluedevil|xdg-desktop-portal-kde)' ;;
        xfce)     pattern='^(xfce4|xfce4-|xfdesktop|xfwm4|thunar|tumbler|ristretto|mousepad|orage)' ;;
        lxqt)     pattern='^(lxqt|lxqt-|pcmanfm-qt|qterminal|sddm)' ;;
        lxde)     pattern='^(lxde|lxde-|lxsession|pcmanfm)' ;;
        mate)     pattern='^(mate|mate-|caja|pluma|engrampa|atril|marco|eom)' ;;
        hyprland) pattern='^(hyprland|hypr|xdg-desktop-portal-hyprland)' ;;
        sway)     pattern='^(sway|swaybg|swaylock|swayidle|wofi|waybar)' ;;
        niri)     pattern='^(niri|fuzzel)' ;;
        i3wm)     pattern='^(i3-wm|i3status|i3lock|dmenu)' ;;
        dwm)      pattern='^(dwm|dmenu)' ;;
        vxwm)     pattern='^(vxwm)' ;;
        icewm)    pattern='^(icewm|icewm-)' ;;
        mango)    pattern='^(mangowm|mangowm-)' ;;
        cinnamon) pattern='^(cinnamon|cinnamon-|muffin|nemo)' ;;
        budgie)   pattern='^(budgie|budgie-|gnome-shell)' ;;
        moksha)   pattern='^(moksha|enlightenment|terminology)' ;;
        cosmic)   pattern='^(cosmic)' ;;
        *)        return 0 ;;
    esac

    _chroot pacman -Qq 2>/dev/null | grep -E "${pattern}" || true
}

backup_de_config() {
    local backup_dir="${MIG_ROOT}/root/de-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    for user_home in "${MIG_ROOT}"/home/*; do
        local user="${user_home##*/}"
        [[ -d "$user_home" ]] || continue

        if [[ -d "$user_home/.config" ]]; then
            cp -a "$user_home/.config" "$backup_dir/$user-config" 2>/dev/null || true
        fi
        if [[ -d "$user_home/.local/share" ]]; then
            mkdir -p "$backup_dir/$user-local"
            cp -a "$user_home/.local/share" "$backup_dir/$user-local/share" 2>/dev/null || true
        fi
    done

    [[ -d "${MIG_ROOT}/etc/sddm.conf.d" ]] && cp -a "${MIG_ROOT}/etc/sddm.conf.d" "$backup_dir/sddm.conf.d" 2>/dev/null || true
    [[ -d "${MIG_ROOT}/etc/lightdm" ]] && cp -a "${MIG_ROOT}/etc/lightdm" "$backup_dir/lightdm" 2>/dev/null || true
    [[ -d "${MIG_ROOT}/etc/X11/xorg.conf.d" ]] && cp -a "${MIG_ROOT}/etc/X11/xorg.conf.d" "$backup_dir/xorg.conf.d" 2>/dev/null || true

    local backup_size
    backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Configs backed up to $backup_dir (${backup_size})"
}

remove_packages() {
    local pkgs="$1"
    [[ -n "$pkgs" ]] || return 0
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" pacman -Rdd --noconfirm $pkgs 2>/dev/null || true
    else
        pacman -Rdd --noconfirm $pkgs 2>/dev/null || true
    fi
}

install_packages() {
    local pkgs="$1"
    [[ -n "$pkgs" ]] || return 0
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" pacman -S --noconfirm --needed $pkgs 2>/dev/null || log_warn "Failed to install some packages"
    else
        pacman -S --noconfirm --needed $pkgs 2>/dev/null || log_warn "Failed to install some packages"
    fi
}

_enable_service() {
    local svc="$1"
    if [[ -n "${MIG_ROOT}" ]]; then
        artix-chroot "${MIG_ROOT}" bash -c "source /usr/local/lib/artix-installer/services.sh 2>/dev/null || source /root/ArtixForge/scripts/install/services.sh; export INIT='${INIT}'; enable_service '${svc}'" 2>/dev/null || log_warn "Could not enable $svc service"
    else
        enable_service "$svc" 2>/dev/null || log_warn "Could not enable $svc service"
    fi
}

_prepare_target_repo() {
    local de="${1}"
    case "${de}" in
        mango)
            log_info "Setting up Chaotic-AUR on target for MangoWM..."
            if [[ -n "${MIG_ROOT}" ]]; then
                artix-chroot "${MIG_ROOT}" bash -c "
                    export GNUPGHOME=/etc/pacman.d/gnupg
                    mkdir -p \"\${GNUPGHOME}\"
                    chmod 700 \"\${GNUPGHOME}\"
                    pacman-key --init
                    pacman-key --populate artix archlinux
                    pacman-key --recv-key 3056513887B78AEB --keyserver hkp://keyserver.ubuntu.com
                    pacman-key --lsign-key 3056513887B78AEB
                    pacman -U --noconfirm https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst
                    grep -q '^\[chaotic-aur\]' /etc/pacman.conf || cat >> /etc/pacman.conf <<'REPO_EOF'
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
REPO_EOF
                    pacman -Sy --noconfirm
                " || log_warn "Chaotic-AUR setup failed"
            else
                export GNUPGHOME="/etc/pacman.d/gnupg"
                mkdir -p "${GNUPGHOME}"
                chmod 700 "${GNUPGHOME}"
                pacman-key --init
                pacman-key --populate artix archlinux
                pacman-key --recv-key 3056513887B78AEB --keyserver hkp://keyserver.ubuntu.com
                pacman-key --lsign-key 3056513887B78AEB
                pacman -U --noconfirm https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst
                grep -q '^\[chaotic-aur\]' /etc/pacman.conf || cat >> /etc/pacman.conf <<'REPO_EOF'
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
REPO_EOF
                pacman -Sy --noconfirm
            fi
            ;;
    esac
}

_repair_pacman_db() {
    log_info "Checking target pacman database integrity..."
    
    detect_pacman_health

    local issues
    issues=$(state_get PACMAN_ISSUES none)
    
    if [[ "${issues}" != "none" ]]; then
        log_warn "Pacman issues detected: ${issues}"
        log_warn "This means something got corrupted, usually."
        if tui_yesno "Pacman Issues" "The target system has pacman database issues. Repair now?"; then
            repair_pacman
        fi
    else
        log_info "Pacman database is healthy."
    fi
}

prompt_migration_choices() {
    local current_dm current_x current_audio current_network current_init
    current_dm=$(detect_current_dm)
    current_x=$(detect_current_x)
    current_audio=$(detect_current_audio)
    current_network=$(detect_current_network)
    current_init=$(detect_current_init)

    local dm_choice x_choice audio_choice network_choice extras_choice

    dm_choice=$(tui_menu "Display Manager" "Current: $current_dm\nSelect display manager:" \
        "Keep current ($current_dm)" "SDDM" "LightDM" "None") || dm_choice="Keep current"
    dm_choice="${dm_choice,,}"
    case "$dm_choice" in
        "sddm") dm_choice="sddm" ;;
        "lightdm") dm_choice="lightdm" ;;
        "none") dm_choice="none" ;;
        "keep current"*) dm_choice="current" ;;
        *) dm_choice="current" ;;
    esac
    state_set DE_MIG_DM "${dm_choice}"

    x_choice=$(tui_menu "Display Stack" "Current: $current_x\nSelect display stack:" \
        "Keep current ($current_x)" "xorg" "wayland") || x_choice="Keep current"
    x_choice="${x_choice,,}"
    case "$x_choice" in
        "xorg") x_choice="xorg" ;;
        "wayland") x_choice="wayland" ;;
        "keep current"*) x_choice="current" ;;
        *) x_choice="current" ;;
    esac
    state_set DE_MIG_X "${x_choice}"

    audio_choice=$(tui_menu "Audio Stack" "Current: $current_audio\nSelect audio stack:" \
        "Keep current ($current_audio)" "pipewire" "pulseaudio" "none") || audio_choice="Keep current"
    audio_choice="${audio_choice,,}"
    case "$audio_choice" in
        "pipewire") audio_choice="pipewire" ;;
        "pulseaudio") audio_choice="pulseaudio" ;;
        "none") audio_choice="none" ;;
        "keep current"*) audio_choice="current" ;;
        *) audio_choice="current" ;;
    esac
    state_set DE_MIG_AUDIO "${audio_choice}"

    network_choice=$(tui_menu "Network Stack" "Current: $current_network\nSelect network stack:" \
        "Keep current ($current_network)" "NetworkManager" "dhcpcd+iwd" "ConnMan" "None") || network_choice="Keep current"
    network_choice="${network_choice,,}"
    case "$network_choice" in
        "networkmanager") network_choice="networkmanager" ;;
        "dhcpcd+iwd") network_choice="dhcpcd+iwd" ;;
        "connman") network_choice="connman" ;;
        "none") network_choice="none" ;;
        "keep current"*) network_choice="current" ;;
        *) network_choice="current" ;;
    esac
    state_set DE_MIG_NETWORK "${network_choice}"

    local extras_list=()
    for extra in "${!EXTRA_PACKAGES[@]}"; do extras_list+=("$extra"); done
    extras_choice=$(tui_checklist "Extras" "Select extra packages to ensure are installed:" "${extras_list[@]}") || true
    state_set DE_MIG_EXTRAS "${extras_choice}"
}

apply_migration_choices() {
    local dm_choice x_choice audio_choice network_choice extras_choice init
    dm_choice="$(state_get DE_MIG_DM "current")"
    x_choice="$(state_get DE_MIG_X "current")"
    audio_choice="$(state_get DE_MIG_AUDIO "current")"
    network_choice="$(state_get DE_MIG_NETWORK "current")"
    extras_choice="$(state_get DE_MIG_EXTRAS "")"
    init=$(detect_current_init)
    export INIT="${init}"

    if [[ "$dm_choice" != "current" ]]; then
        if [[ "$dm_choice" != "none" ]]; then
            local key="${dm_choice}-${init}"
            install_packages "${DM_PACKAGES[$key]:-}"
            _enable_service "${dm_choice}"
        else
            remove_packages "sddm sddm-openrc sddm-runit sddm-dinit sddm-s6 lightdm lightdm-gtk-greeter lightdm-openrc lightdm-runit lightdm-dinit lightdm-s6 sonic-login-manager sonic-login-manager-openrc sonic-login-manager-runit sonic-login-manager-dinit sonic-login-manager-s6 gdm"
        fi
    fi

    if [[ "$x_choice" != "current" ]]; then
        if [[ "$x_choice" == "xorg" ]]; then
            remove_packages "xlibre-xserver xlibre-xserver-common xlibre-input-libinput xlibre-input-evdev"
        fi
        install_packages "${X_PACKAGES[$x_choice]:-}"
    fi

    if [[ "$audio_choice" != "current" ]]; then
        remove_packages "pipewire pipewire-pulse pipewire-alsa wireplumber pipewire-jack pulseaudio pulseaudio-alsa"
        install_packages "${AUDIO_PACKAGES[$audio_choice]:-}"
    fi

    if [[ "$network_choice" != "current" ]]; then
        remove_packages "networkmanager networkmanager-openrc networkmanager-runit networkmanager-dinit networkmanager-s6"
        remove_packages "dhcpcd iwd dhcpcd-openrc dhcpcd-runit dhcpcd-dinit dhcpcd-s6 iwd-openrc iwd-runit iwd-dinit iwd-s6"
        remove_packages "connman connman-openrc connman-runit connman-dinit connman-s6"

        if [[ "$network_choice" != "none" ]]; then
            local key="${network_choice}-${init}"
            install_packages "${NETWORK_PACKAGES[$key]:-}"
            case "$network_choice" in
                networkmanager) _enable_service NetworkManager ;;
                dhcpcd+iwd) _enable_service dhcpcd; _enable_service iwd ;;
                connman) _enable_service connmand ;;
            esac
        fi
    fi

    if [[ -n "$extras_choice" ]]; then
        local pkg_list=""
        for extra in $extras_choice; do
            local p="${EXTRA_PACKAGES[$extra]:-}"
            if [[ -n "$p" ]]; then
                pkg_list+=" $p"
            fi
        done
        pkg_list="${pkg_list# }"
        install_packages "$pkg_list"
    fi
}

detect_de_conflicts() {
    local source_de="${1}" target_de="${2}"
    local conflicts=""
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        conflicts+="Current desktop session is running. Migration may cause instability.\n"
    fi
    local source_dm target_dm
    source_dm="${DE_DISPLAY_MANAGER[$source_de]:-none}"
    target_dm="${DE_DISPLAY_MANAGER[$target_de]:-none}"
    if [[ "$source_dm" != "$target_dm" ]]; then
        conflicts+="Display manager will change: $source_dm → $target_dm\n"
    fi
    local source_is_wayland=0 target_is_wayland=0
    [[ "$source_de" =~ ^(hyprland|sway|niri)$ ]] && source_is_wayland=1
    [[ "$target_de" =~ ^(hyprland|sway|niri)$ ]] && target_is_wayland=1
    if [[ $source_is_wayland -ne $target_is_wayland ]]; then
        conflicts+="Display protocol will change (Wayland ↔ X11)\n"
    fi
    printf '%b' "$conflicts"
}

run_de_migration() {
    local source_de="${1}" target_de="${2}"
    [[ "$source_de" != "$target_de" ]] || die "Source and target DE are the same: $source_de"

    if [[ "$source_de" == "sonicde" ]]; then
        tui_msg "Unsupported Desktop" \
            "SonicDE is no longer supported.\n\nYou can migrate away from it, but it cannot be installed or repaired."
    fi

    local migration_stage_file="/tmp/artix-installer/migration-stage.conf"
    local migration_stage
    migration_stage="$(cat "${migration_stage_file}" 2>/dev/null || echo "init")"
    log_info "Migration stage: ${migration_stage}"

    local -A stage_names=(
        ["init"]="Starting"
        ["backup"]="User configs backed up"
        ["repos"]="Repositories configured"
        ["remove"]="Old desktop removed"
        ["install"]="New desktop installed"
        ["apply"]="Display/audio/network choices applied"
        ["finalize"]="Finalizing"
    )

    if [[ "${migration_stage}" != "init" && "${migration_stage}" != "finalize" ]]; then
        tui_msg "Failed Migration Detected" \
            "A previous migration attempt was interrupted at stage: ${migration_stage}.\n\n
You can:\n
  • Resume – continue from where it stopped\n
  • Start Fresh – remove both desktop environments and perform a clean migration"
        
        if ! tui_yesno "Resume Migration?" "Resume the interrupted migration?"; then
            log_info "User chose to start fresh — removing both desktop environments..."
            if [[ "$source_de" != "none" ]]; then
                remove_packages "${DE_PACKAGES[$source_de]:-}" 2>/dev/null || true
            fi
            if [[ "$target_de" != "none" ]]; then
                remove_packages "${DE_PACKAGES[$target_de]:-}" 2>/dev/null || true
            fi
            rm -f "${migration_stage_file}"
            migration_stage="init"
            log_info "Both desktop environments removed. Starting clean migration."
        fi
    fi
    _repair_pacman_db

    if [[ "$target_de" == "kde" ]]; then
        local kde_profile
        kde_profile=$(tui_menu "KDE Profile" "Select KDE Plasma profile:" \
            "minimal – plasma-desktop, dolphin, konsole" \
            "desktop – plasma, no extra apps" \
            "full – plasma + kde-applications") || kde_profile="desktop"
        case "${kde_profile}" in
            minimal*)  DE_PACKAGES["kde"]="plasma-desktop dolphin konsole xdg-desktop-portal-kde" ;;
            desktop*)  DE_PACKAGES["kde"]="plasma xdg-desktop-portal-kde" ;;
            full*)     DE_PACKAGES["kde"]="plasma kde-applications xdg-desktop-portal-kde" ;;
        esac
    fi

    local conflicts
    conflicts=$(detect_de_conflicts "$source_de" "$target_de")
    if [[ -n "$conflicts" ]]; then
        tui_msg "Migration Warnings" "The following conflicts were detected:\n\n${conflicts}\n\nProceed with caution."
        if ! tui_yesno "Continue?" "Are you sure you want to proceed with the migration?"; then
            log_info "Migration cancelled."
            return 0
        fi
    fi

    if [[ "${migration_stage}" == "init" || "${migration_stage}" == "backup" ]]; then
        log_info "Backing up user configs..."
        backup_de_config
        echo "backup" > "${migration_stage_file}"
    else
        log_info "Skipping backup (already done)"
    fi

    if [[ "${migration_stage}" == "backup" || "${migration_stage}" == "repos" ]]; then
        if [[ "$target_de" == "mango" ]]; then
            _prepare_target_repo "$target_de"
        fi
        echo "repos" > "${migration_stage_file}"
    else
        log_info "Skipping repo setup (already done)"
    fi

    if [[ "${migration_stage}" == "repos" || "${migration_stage}" == "backup" || "${migration_stage}" == "init" ]]; then
        if [[ "$source_de" == "none" ]]; then
            local default_dm="${DE_DISPLAY_MANAGER[$target_de]:-none}"
            state_set DE_MIG_DM "$default_dm"
            state_set DE_MIG_X "$(detect_current_x)"
            state_set DE_MIG_AUDIO "$(detect_current_audio)"
            state_set DE_MIG_NETWORK "$(detect_current_network)"
            state_set DE_MIG_EXTRAS ""
        else
            prompt_migration_choices
        fi
    fi

    if [[ "${migration_stage}" == "repos" || "${migration_stage}" == "backup" || "${migration_stage}" == "remove" ]]; then
        if [[ "$source_de" != "none" ]]; then
            log_info "Removing $source_de packages..."

            local source_packages
            if [[ "$source_de" == "sonicde" ]]; then
                source_packages="sonicde-meta sonic-login-manager sonic-login-manager-openrc sonic-login-manager-runit sonic-login-manager-dinit sonic-login-manager-s6"
                remove_packages "$source_packages"
                if [[ -n "${MIG_ROOT}" ]]; then
                    artix-chroot "${MIG_ROOT}" sed -i '/^\[sonicde\]/,/^\[/d' /etc/pacman.conf
                    artix-chroot "${MIG_ROOT}" pacman -Syy --noconfirm 2>/dev/null || true
                else
                    sed -i '/^\[sonicde\]/,/^\[/d' /etc/pacman.conf
                    pacman -Syy --noconfirm 2>/dev/null || true
                fi
            else
                source_packages=$(_installed_de_packages "$source_de")
                if [[ -n "$source_packages" ]]; then
                    remove_packages "$source_packages"
                else
                    log_warn "No $source_de packages detected for removal."
                fi
            fi

            local orphan_list
            orphan_list=$(_chroot pacman -Qtdq 2>/dev/null || true)
            if [[ -n "$orphan_list" ]]; then
                local orphans_array=()
                while IFS= read -r pkg; do
                    [[ -n "$pkg" ]] && orphans_array+=("$pkg")
                done <<< "$orphan_list"

                tui_msg_quick "Orphaned Packages" "The following packages are now orphaned:\n\n${orphan_list}"

                local to_remove
                to_remove=$(tui_checklist "Remove Orphans" "Select orphaned packages to remove:" "${orphans_array[@]}") || true

                if [[ -n "$to_remove" ]]; then
                    remove_packages "$to_remove"
                else
                    log_info "No orphaned packages selected for removal."
                fi
            fi
        fi
        echo "remove" > "${migration_stage_file}"
    else
        log_info "Skipping source removal (already done)"
    fi

    if [[ "${migration_stage}" == "remove" || "${migration_stage}" == "install" ]]; then
        if [[ "$target_de" != "none" ]]; then
            log_info "Installing $target_de packages..."
            install_packages "${DE_PACKAGES[$target_de]:-}"
        fi
        echo "install" > "${migration_stage_file}"
    else
        log_info "Skipping target install (already done)"
    fi

    if [[ "${migration_stage}" == "install" || "${migration_stage}" == "apply" ]]; then
        log_info "MIG_ROOT=${MIG_ROOT:-empty}"
        apply_migration_choices
        echo "apply" > "${migration_stage_file}"
    else
        log_info "Skipping choice application (already done)"
    fi

    if [[ "${migration_stage}" == "apply" || "${migration_stage}" == "finalize" ]]; then
        if [[ -x "${MIG_ROOT}/usr/bin/mkinitcpio" ]]; then
            _chroot mkinitcpio -P 2>/dev/null || true
        fi
        echo "finalize" > "${migration_stage_file}"
    else
        log_info "Skipping finalization (already done)"
    fi

    rm -f "${migration_stage_file}"

    log_info "Desktop migration complete."
    log_info "You should reboot for all changes to take effect."
    if tui_yesno "Reboot" "Reboot now?"; then
        reboot
    fi
}

tui_de_migration_menu() {
    local current_de
    current_de=$(detect_current_de)
    tui_msg_quick "Current Desktop" "Detected desktop environment: ${current_de}"

    local source_de target_de
    source_de=$(tui_menu "Source Desktop" "Select desktop to migrate FROM:" \
        "kde" "sonicde" "xfce" "lxqt" "lxde" "mate" "hyprland" "sway" "niri" \
        "i3wm" "dwm" "vxwm" "icewm" "mango" "none") || return 1

    target_de=$(tui_menu "Target Desktop" "Select desktop to migrate TO:" \
        "kde" "xfce" "lxqt" "lxde" "mate" "hyprland" "sway" "niri" \
        "i3wm" "dwm" "vxwm" "icewm" "mango" "none") || return 1

    [[ "$source_de" != "$target_de" ]] || die "Source and target are the same."

    run_de_migration "$source_de" "$target_de"
}