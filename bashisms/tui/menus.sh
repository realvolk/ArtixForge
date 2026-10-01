#!/usr/bin/env bash
set -Eeuo pipefail

HUB_DIR="/tmp/artix-installer/hub"
mkdir -p "${HUB_DIR}"
chmod 0700 "${HUB_DIR}"

tui_select_theme() {
    local theme
    while true; do
        theme=$(tui_menu "Theme" "Select colour scheme:" \
            "Forge (default)" "Artix" "Jet Black" "Mono" "Retro") || break
        case "${theme}" in
            "Forge (default)") GUM_TITLE_COLOR=212; GUM_ACCENT_COLOR=34 ;;
            Artix*)            GUM_TITLE_COLOR=39;  GUM_ACCENT_COLOR=117 ;;
            "Jet Black")       GUM_TITLE_COLOR=245; GUM_ACCENT_COLOR=196 ;;
            Mono*)             GUM_TITLE_COLOR=250; GUM_ACCENT_COLOR=255 ;;
            Retro*)            GUM_TITLE_COLOR=3;   GUM_ACCENT_COLOR=11 ;;
        esac
        state_set GUM_TITLE_COLOR "${GUM_TITLE_COLOR}"
        state_set GUM_ACCENT_COLOR "${GUM_ACCENT_COLOR}"
        tui_msg "Theme Preview" "This is how titles and messages will look."
        tui_yesno "Keep Theme?" "Keep this theme?" && break
    done
}

_hub_quote() {
    local v="${1}"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '"%s"' "${v}"
}

_write_config_hub() {
    local f="${1}"
    {
        printf 'hub ArtixForge Configuration\n'
        printf 'action Back\n'
        printf 'action Proceed\n'

        printf 'category system "System"\n'
        printf 'item key=INIT label="Init system" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get INIT openrc)")"
        printf '  choice openrc\n  choice runit\n  choice dinit\n  choice s6\n'

        printf 'item key=FS_TYPE label="Filesystem" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get FS_TYPE ext4)")"
        printf '  choice ext4\n  choice btrfs\n  choice xfs\n  choice f2fs\n'

        printf 'item key=BTRFS_LAYOUT label="BTRFS layout" widget=menu visible_if="FS_TYPE=btrfs" value=%s message="standard: @ and @home. flat: no subvolumes. snapshot: adds @log, @pkg, @snapshots for snapper."\n' \
            "$(_hub_quote "$(state_get BTRFS_LAYOUT standard)")"
        printf '  choice standard\n  choice flat\n  choice snapshot\n'

        printf 'item key=KERNEL_CHOICE label="Kernel" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get KERNEL_CHOICE linux)")"
        for k in linux linux-zen linux-lts linux-hardened linux-libre \
                 linux-cachyos linux-cachyos-bore linux-cachyos-eevdf \
                 linux-cachyos-bmq linux-cachyos-hardened linux-cachyos-lts \
                 linux-cachyos-server linux-cachyos-deckify \
                 linux-bazzite-bin xanmod tkg; do
            printf '  choice %s\n' "${k}"
        done

        printf 'item key=MICROCODE_OVERRIDE label="CPU microcode" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get MICROCODE_OVERRIDE auto)")"
        printf '  choice auto\n  choice intel\n  choice amd\n  choice none\n'

        printf 'item key=PRIV_ESCALATION label="Privilege escalation" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get PRIV_ESCALATION sudo)")"
        printf '  choice sudo\n  choice doas\n'

        printf 'item key=USER_SHELL label="Default shell" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get USER_SHELL bash)")"
        printf '  choice bash\n  choice zsh\n  choice fish\n'

        printf 'item key=ENABLE_AURIS label="Enable AURIS" widget=yesno value=%s message="AURIS provides community-submitted init scripts for all supported init systems."\n' \
            "$(_hub_quote "$(state_get ENABLE_AURIS no)")"

        printf 'category disk "Disk"\n'
        printf 'item key=DISK label="Target disk" widget=menu choices_cmd="lsblk -dpno NAME,SIZE,MODEL -e 7" message="ALL DATA ON THIS DISK WILL BE ERASED." value=%s\n' \
            "$(_hub_quote "$(state_get DISK '')")"

        printf 'item key=USE_LUKS label="LUKS full-disk encryption" widget=yesno value=%s\n' \
            "$(_hub_quote "$(state_get USE_LUKS no)")"
        printf 'item key=LUKS_PASS label="Encryption passphrase" widget=password visible_if="USE_LUKS=yes" message="Asked at every boot unless you enable a keyfile."\n'
        printf 'item key=LUKS_KEYFILE label="Use a keyfile" widget=yesno visible_if="USE_LUKS=yes" value=%s message="On UEFI, the keyfile lives on the unencrypted ESP. Anyone with physical access can extract it and unlock the disk."\n' \
            "$(_hub_quote "$(state_get LUKS_KEYFILE no)")"

        printf 'item key=USE_LVM label="Enable LVM" widget=yesno value=%s\n' \
            "$(_hub_quote "$(state_get USE_LVM no)")"
        printf 'item key=LVM_VG_NAME label="LVM volume group name" widget=input visible_if="USE_LVM=yes" value=%s\n' \
            "$(_hub_quote "$(state_get LVM_VG_NAME vg0)")"

        printf 'item key=SWAP_ENABLED label="Swap" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get SWAP_ENABLED none)")"
        printf '  choice none\n  choice partition\n  choice swapfile\n  choice zram\n  choice zswap\n'
        printf 'item key=SWAP_SIZE label="Swap size in MB" widget=input visible_if="SWAP_ENABLED=partition,swapfile" value=%s\n' \
            "$(_hub_quote "$(state_get SWAP_SIZE 4096)")"
        printf 'item key=ZRAM_PERCENT label="ZRAM percent of RAM (10-100)" widget=input visible_if="SWAP_ENABLED=zram" value=%s\n' \
            "$(_hub_quote "$(state_get ZRAM_PERCENT 50)")"

        printf 'category boot "Boot"\n'
        if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
            printf 'item key=BOOTLOADER label="Bootloader (BIOS: GRUB only)" widget=input value="grub"\n'
        else
            printf 'item key=BOOTLOADER label="Bootloader" widget=menu value=%s\n' \
                "$(_hub_quote "$(state_get BOOTLOADER grub)")"
            printf '  choice grub\n  choice refind\n  choice efistub\n  choice limine\n'

            printf 'item key=GENERATE_UKI label="Generate Unified Kernel Image" widget=yesno value=%s\n' \
                "$(_hub_quote "$(state_get GENERATE_UKI no)")"
            printf 'item key=SIGN_UKI label="Sign UKI for Secure Boot" widget=yesno visible_if="GENERATE_UKI=yes" value=%s\n' \
                "$(_hub_quote "$(state_get SIGN_UKI no)")"
            printf 'item key=SECUREBOOT_DB_KEY label="Secure Boot DB.key path" widget=input visible_if="SIGN_UKI=yes" value=%s\n' \
                "$(_hub_quote "$(state_get SECUREBOOT_DB_KEY /etc/secureboot/DB.key)")"
            printf 'item key=SECUREBOOT_DB_CERT label="Secure Boot DB.crt path" widget=input visible_if="SIGN_UKI=yes" value=%s\n' \
                "$(_hub_quote "$(state_get SECUREBOOT_DB_CERT /etc/secureboot/DB.crt)")"
        fi

        printf 'category desktop "Desktop"\n'
        printf 'item key=WM_DE label="Desktop environment" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get WM_DE none)")"
        for de in none xfce4 lxqt kde lxde mate mango hyprland niri sway \
                  i3wm dwm vxwm icewm cinnamon budgie moksha cosmic; do
            printf '  choice %s\n' "${de}"
        done

        printf 'item key=KDE_PROFILE label="KDE Plasma profile" widget=menu visible_if="WM_DE=kde" value=%s\n' \
            "$(_hub_quote "$(state_get KDE_PROFILE desktop)")"
        printf '  choice minimal\n  choice desktop\n  choice full\n'

        printf 'item key=DISPLAY_MANAGER label="Display manager" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get DISPLAY_MANAGER none)")"
        printf '  choice none\n  choice lightdm\n  choice sddm\n'

        printf 'item key=X_STACK label="Display stack" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get X_STACK xorg)")"
        printf '  choice xorg\n  choice xorg-tearfree\n  choice none\n'

        printf 'category netaudio "Network / Audio"\n'
        printf 'item key=NETWORK_STACK label="Network stack" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get NETWORK_STACK dhcpcd+iwd)")"
        printf '  choice networkmanager\n  choice dhcpcd+iwd\n  choice connman\n  choice none\n'

        printf 'item key=AUDIO_STACK label="Audio stack" widget=menu value=%s\n' \
            "$(_hub_quote "$(state_get AUDIO_STACK pipewire)")"
        printf '  choice pipewire\n  choice pulseaudio\n  choice none\n'

        printf 'category syscfg "System Config"\n'
        printf 'item key=HOSTNAME label="Hostname" widget=input value=%s\n' \
            "$(_hub_quote "$(state_get HOSTNAME artix)")"
        printf 'item key=TIMEZONE label="Timezone" widget=filter choices_cmd="find /usr/share/zoneinfo -type f | sed s|/usr/share/zoneinfo/|| | grep -v -e ^posix/ -e ^right/ -e ^Etc/ -e .tab$ | sort" value=%s\n' \
            "$(_hub_quote "$(state_get TIMEZONE Europe/Belgrade)")"
        printf 'item key=LOCALE label="Locale" widget=filter choices_cmd="grep -E ^[#]?[a-z]{2}_[A-Z]{2}.*UTF-8 /etc/locale.gen | sed s/^#// | awk {print $1} | sort -u" value=%s\n' \
            "$(_hub_quote "$(state_get LOCALE en_US.UTF-8)")"
        printf 'item key=KEYMAP label="Keyboard layout" widget=filter choices_cmd="localectl list-keymaps 2>/dev/null | sort" value=%s\n' \
            "$(_hub_quote "$(state_get KEYMAP us)")"
        printf 'item key=ALLOW_OFFLINE label="Allow offline installation" widget=yesno value=%s\n' \
            "$(_hub_quote "$(state_get ALLOW_OFFLINE no)")"

        printf 'category extras "Extras"\n'
        printf 'item key=EXTRAS label="Extra packages" widget=subhub subhub="extras.hub" message="Opens a package selector with curated categories and a full-catalogue search."\n'

    } > "${f}"
}

_write_extras_hub() {
    local f="${1}"
    local script="${HUB_DIR}/extras-choices.sh"
    local wm_de
    wm_de="$(state_get WM_DE none)"

    local filter="${EXTRAS_SAFETY_FILTER:-}"

    cat > "${script}" <<CHOICES
#!/bin/sh
{
cat <<'CURATED'
git
flatpak
firewalld
bluez
zram-tools
usb_modeswitch
nano
vim
neovim
micro
helix
firefox
chromium
qutebrowser
ranger
lf
nnn
thunar
alacritty
kitty
foot
fastfetch
fzf
zoxide
starship
eza
tmux
btop
htop
nvtop
mpv
feh
swaybg
swaylock
waybar
wofi
fuzzel
hyprpaper
CURATED
pacman -Sl world galaxy 2>/dev/null | awk '{print \$2}' | grep -vE '${filter}' | sort -u
} | awk '!seen[\$0]++'
CHOICES
    chmod 0700 "${script}"

    local wayland_msg=""
    case "${wm_de}" in
        mango)              wayland_msg="MangoWM is a minimal compositor. You'll want a wallpaper, launcher, and status bar." ;;
        hyprland|sway|niri) wayland_msg="${wm_de} needs a few extras for a full desktop: wallpaper, launcher, bar." ;;
    esac

    local hint="Type to filter. Space toggles selection."
    [[ -n "${wayland_msg}" ]] && hint="${wayland_msg}"

    {
        printf 'hub Extras\n'
        printf 'action Back\n'
        printf 'action Proceed\n'
        printf 'category packages "Packages"\n'
        printf 'item key=EXTRAS label="Extra packages" widget=filter choices_cmd="sh %s" value=%s message=%s\n' \
            "${script}" \
            "$(_hub_quote "$(state_get EXTRAS '')")" \
            "$(_hub_quote "${hint}")"
    } > "${f}"
}
_write_users_hub() {
    local f="${1}"
    local slots
    slots="$(state_get USER_COUNT 1)"
    [[ "${slots}" -ge 3 ]] || slots=3

    {
        printf 'hub User Accounts\n'
        printf 'action Back\n'
        printf 'action Proceed\n'

        local i
        for ((i=1; i<=slots; i++)); do
            printf 'category user%d "User %d"\n' "${i}" "${i}"

            printf 'item key=USER_%d_NAME label="Username" widget=input value=%s\n' \
                "${i}" "$(_hub_quote "$(state_get "USER_${i}_NAME" "")")"

            printf 'item key=USER_%d_PASS label="Password" widget=password\n' "${i}"

            printf 'item key=USER_%d_SHELL label="Shell" widget=menu value=%s\n' \
                "${i}" "$(_hub_quote "$(state_get "USER_${i}_SHELL" "/bin/bash")")"
            printf '  choice /bin/bash\n  choice /bin/zsh\n  choice /usr/bin/fish\n'

            printf 'item key=USER_%d_GROUPS label="Groups" widget=input value=%s\n' \
                "${i}" "$(_hub_quote "$(state_get "USER_${i}_GROUPS" "wheel,audio,video,storage")")"

            printf 'item key=USER_%d_SUDO label="Grant sudo access" widget=yesno value=%s\n' \
                "${i}" "$(_hub_quote "$(state_get "USER_${i}_SUDO" "yes")")"

            printf 'item key=USER_%d_DE label="Desktop override (blank = system default)" widget=input value=%s\n' \
                "${i}" "$(_hub_quote "$(state_get "USER_${i}_DE" "")")"

            printf 'item key=USER_%d_DOTFILES label="Dotfiles repo URL" widget=input value=%s\n' \
                "${i}" "$(_hub_quote "$(state_get "USER_${i}_DOTFILES" "")")"
        done

        printf 'category root "Root"\n'
        printf 'item key=SET_ROOT_PASS label="Set a root password" widget=yesno value=no\n'
        printf 'item key=ROOT_PASS label="Root password" widget=password visible_if="SET_ROOT_PASS=yes"\n'

    } > "${f}"
}

_run_config_hub() {
    local in_file="${HUB_DIR}/config.in"
    local extras_file="${HUB_DIR}/extras.hub"
    _write_config_hub "${in_file}"
    _write_extras_hub "${extras_file}"
    chmod 0600 "${in_file}" "${extras_file}"

    if ! tui_hub_apply "${in_file}"; then
        die "Configuration cancelled by user"
    fi
}

_run_users_hub() {
    local in_file="${HUB_DIR}/users.in"
    _write_users_hub "${in_file}"
    chmod 0600 "${in_file}"

    local -A saved_pass
    local saved_root
    local slots i
    slots="$(state_get USER_COUNT 3)"
    [[ "${slots}" -ge 3 ]] || slots=3

    for ((i=1; i<=slots; i++)); do
        saved_pass[${i}]="$(state_get "USER_${i}_PASS" "")"
    done
    saved_root="$(state_get ROOT_PASS "")"

    if ! tui_hub_apply "${in_file}" --check; then
        die "User configuration cancelled by user"
    fi

    for ((i=1; i<=slots; i++)); do
        local up
        up="$(state_get "USER_${i}_PASS" "")"
        if [[ -z "${up}" ]]; then
            state_set "USER_${i}_PASS" "${saved_pass[${i}]:-}"
        else
            state_set "USER_${i}_PASS" "$(generate_password_hash "${up}")"
        fi
    done

    local root_pass
    root_pass="$(state_get ROOT_PASS "")"
    if [[ -z "${root_pass}" ]]; then
        state_set ROOT_PASS "${saved_root}"
    else
        state_set ROOT_PASS "$(generate_password_hash "${root_pass}")"
    fi

    local -a rn=() rp=() rs=() rg=() ru=() rd=() rf=()
    for ((i=1; i<=slots; i++)); do
        local n
        n="$(state_get "USER_${i}_NAME" "")"
        [[ -n "${n}" ]] || continue
        n="${n//[$'\r'$'\n'$'\t' ]/}"
        [[ -n "${n}" ]] || continue
        rn+=("${n}")
        rp+=("$(state_get "USER_${i}_PASS" "")")
        rs+=("$(state_get "USER_${i}_SHELL" "/bin/bash")")
        rg+=("$(state_get "USER_${i}_GROUPS" "wheel,audio,video,storage")")
        ru+=("$(state_get "USER_${i}_SUDO" "yes")")
        rd+=("$(state_get "USER_${i}_DE" "")")
        rf+=("$(state_get "USER_${i}_DOTFILES" "")")
    done

    local n_users="${#rn[@]}"
    if [[ "${n_users}" -eq 0 ]]; then
        state_set USER_COUNT "1"
        state_set USER_1_NAME "artix"
        state_set USER_1_PASS "$(generate_password_hash "artix")"
        state_set USER_1_SHELL "/bin/bash"
        state_set USER_1_GROUPS "wheel,audio,video,storage"
        state_set USER_1_SUDO "yes"
        state_set USER_1_DE ""
        state_set USER_1_DOTFILES ""
        return 0
    fi

    for ((i=1; i<=slots; i++)); do
        if [[ ${i} -le ${n_users} ]]; then
            local k=$((i-1))
            state_set "USER_${i}_NAME"     "${rn[${k}]}"
            state_set "USER_${i}_PASS"     "${rp[${k}]}"
            state_set "USER_${i}_SHELL"    "${rs[${k}]}"
            state_set "USER_${i}_GROUPS"   "${rg[${k}]}"
            state_set "USER_${i}_SUDO"     "${ru[${k}]}"
            state_set "USER_${i}_DE"       "${rd[${k}]}"
            state_set "USER_${i}_DOTFILES" "${rf[${k}]}"
        else
            local f
            for f in NAME PASS SHELL GROUPS SUDO DE DOTFILES; do
                state_set "USER_${i}_${f}" ""
            done
        fi
    done
    state_set USER_COUNT "${n_users}"
}

_post_hub_derive() {
    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        state_set BOOTLOADER "grub"
        state_set GENERATE_UKI "no"
        state_set SIGN_UKI "no"
    fi

    local wm_de kernel required='no' reasons=()
    wm_de="$(state_get WM_DE none)"
    kernel="$(state_get KERNEL_CHOICE linux)"

    if [[ "${wm_de}" == "none" ]]; then
        state_set DISPLAY_MANAGER "none"
        state_set X_STACK "none"
    fi
    if [[ "${wm_de}" != "kde" ]]; then
        state_set KDE_PROFILE "none"
    fi

    case "${wm_de}" in
        none|dwm|i3wm|icewm|hyprland|mango|niri|sway)
            ;;
        *)
            if [[ "$(state_get DISPLAY_MANAGER none)" == "none" ]]; then
                local _dm
                _dm="$(resolve_de_dm "${wm_de}")"
                [[ -n "${_dm}" && "${_dm}" != "none" ]] && state_set DISPLAY_MANAGER "${_dm}"
            fi
            ;;
    esac

    case "${kernel}" in
        linux-bazzite-bin|linux-cachyos-bore|xanmod) required='yes'; reasons+=("Kernel ${kernel}") ;;
    esac
    case "${wm_de}" in
        hyprland|niri|mango|budgie|cinnamon|cosmic|dwm|i3wm)
            required='yes'; reasons+=("${wm_de}") ;;
    esac

    if [[ "${required}" == "yes" ]] && [[ "$(state_get ENABLE_ARCH_REPOS no)" != "yes" ]]; then
        local list
        list=$(printf ' - %s\n' "${reasons[@]}")
        tui_msg "Arch Repositories Required" "Enabling official Arch repositories because:
${list}"
        state_set ENABLE_ARCH_REPOS "yes"
    fi

    local hostname
    hostname="$(state_get HOSTNAME artix)"
    if [[ ! "${hostname}" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*$ ]]; then
        while true; do
            tui_msg "Invalid Hostname" "Hostname must start with a letter or digit and contain only letters, digits, and dashes."
            hostname=$(tui_input "Hostname" "Enter system hostname:" "artix") || { hostname="artix"; break; }
            hostname="${hostname//[$'\r'$'\n'$'\t' ]/}"
            [[ -n "${hostname}" ]] || continue
            [[ "${hostname}" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*$ ]] && break
        done
        state_set HOSTNAME "${hostname}"
    fi

    local swap_size zram_pct
    swap_size="$(state_get SWAP_SIZE 4096)"
    if [[ "$(state_get SWAP_ENABLED none)" == "partition" || "$(state_get SWAP_ENABLED none)" == "swapfile" ]]; then
        if [[ ! "${swap_size}" =~ ^[0-9]+$ ]]; then
            local converted
            converted=$(parse_size_to_mb "${swap_size}")
            if [[ -n "${converted}" && "${converted}" -ge 64 ]]; then
                state_set SWAP_SIZE "${converted}"
            else
                tui_msg "Invalid Swap Size" "Swap size must be a number in MB or a value like 4G / 512M. Minimum 64M."
                state_set SWAP_SIZE 4096
            fi
        elif [[ "${swap_size}" -lt 64 ]]; then
            tui_msg "Invalid Swap Size" "Swap size must be at least 64 MB."
            state_set SWAP_SIZE 4096
        fi
    fi
    zram_pct="$(state_get ZRAM_PERCENT 50)"
    if [[ "$(state_get SWAP_ENABLED none)" == "zram" ]]; then
        if [[ ! "${zram_pct}" =~ ^[0-9]+$ ]] || [[ "${zram_pct}" -lt 10 ]] || [[ "${zram_pct}" -gt 100 ]]; then
            tui_msg "Invalid ZRAM Percent" "ZRAM percent must be between 10 and 100."
            state_set ZRAM_PERCENT 50
        fi
    fi
}

tui_show_sanity_warnings() {
    local warnings=()

    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        warnings+=("BIOS/Legacy boot mode — UEFI features (UKI, EFIStub, rEFInd, Limine) are disabled")
    fi

    [[ "$(state_get BOOTLOADER)" == "efistub" && "${ARTIX_BOOT_MODE:-uefi}" != "bios" ]] && warnings+=("EFIStub needs compatible UEFI firmware")
    [[ "$(state_get BOOTLOADER)" == "uki" ]] && warnings+=("UKI is UEFI-only — BIOS systems not supported")

    [[ "$(state_get KERNEL_CHOICE)" == "linux-libre" ]] && warnings+=("linux-libre removes non-free firmware — hardware may not work")
    [[ "$(state_get KERNEL_CHOICE)" == "tkg" ]] && warnings+=("TKG kernel is compiled from source during installation — may take 20–30 minutes")

    [[ "$(state_get BOOTLOADER)" == "grub" && "$(state_get FS_TYPE)" == "xfs" ]] && warnings+=("GRUB + XFS: ensure bigtime is disabled for compatibility")
    [[ "$(state_get BOOTLOADER)" == "uki" && "$(state_get USE_LUKS)" == "yes" ]] && warnings+=("UKI + LUKS: ensure initramfs includes encrypt hook")

    [[ "$(state_get INIT)" == "busybox" ]] && warnings+=("BusyBox init is minimal — manual service scripts required")
    [[ "$(state_get INIT)" == "busybox" && "$(state_get WM_DE)" != "none" ]] && warnings+=("BusyBox init with a desktop — you'll need to start services manually")
    [[ "$(state_get INIT)" == "busybox" && "$(state_get COREUTILS)" != "busybox" && "$(state_get COREUTILS)" != "artix" ]] && warnings+=("BusyBox init with GNU coreutils — consider BusyBox coreutils for consistency")

    [[ "$(state_get USE_LVM)" == "yes" && "$(state_get BOOTLOADER)" == "grub" ]] && warnings+=("LVM + GRUB: ensure lvm2 hook is in initramfs")
    [[ "$(state_get USE_LVM)" == "yes" && "$(state_get BOOTLOADER)" == "efistub" ]] && warnings+=("LVM + EFIStub: cmdline must reference /dev/mapper paths")
    [[ "$(state_get USE_LVM)" == "yes" && "$(state_get USE_LUKS)" == "yes" ]] && warnings+=("LVM on LUKS: correct crypt device order is critical")

    [[ "$(state_get USE_LUKS)" == "yes" && "$(state_get BOOTLOADER)" == "refind" ]] && warnings+=("LUKS + rEFInd: may require manual boot config")

    [[ "$(state_get COREUTILS)" == "busybox" ]] && warnings+=("BusyBox coreutils — some scripts may need GNU extensions")
    [[ "$(state_get COREUTILS)" == "uutils" ]] && warnings+=("uutils coreutils — Rust-based, may have compatibility gaps")
    [[ "$(state_get COREUTILS)" == "custom" ]] && warnings+=("Custom coreutils — ensure all essential tools are implemented")
    [[ "$(state_get COREUTILS)" != "gnu" && "$(state_get COREUTILS)" != "none" && "$(state_get COREUTILS)" != "" ]] && warnings+=("Non-GNU coreutils: some install scripts may behave unexpectedly")

    [[ "$(state_get WM_DE)" == "cosmic" ]] && warnings+=("COSMIC is alpha software — APIs may change, features may be missing")
    [[ "$(state_get WM_DE)" == "moksha" ]] && warnings+=("Moksha/Enlightenment is community-maintained — limited testing")
    [[ "$(state_get WM_DE)" == "none" ]] && warnings+=("No desktop environment selected")
    [[ "$(state_get WM_DE)" =~ ^(hyprland|niri|sway)$ && "$(state_get X_STACK)" =~ ^xorg(-tearfree)?$ ]] && warnings+=("Wayland compositor selected but X.Org display stack configured")
    [[ "$(state_get WM_DE)" =~ ^(hyprland|niri)$ && "$(state_get ENABLE_ARCH_REPOS)" == "no" ]] && warnings+=("Hyprland/Niri may need Arch repositories for dependencies")
    [[ "$(state_get DISPLAY_MANAGER)" == "none" && "$(state_get WM_DE)" != "none" ]] && warnings+=("No display manager — you'll start the desktop manually")

    [[ "$(state_get NETWORK_STACK)" == "none" ]] && warnings+=("No network stack — you'll configure networking manually")

    [[ "$(state_get POWER_USER)" == "yes" && "$(state_get KEEP_BINARY_KERNEL)" == "no" ]] && warnings+=("No fallback kernel — system may be unbootable if custom kernel fails")
    [[ "$(state_get POWER_USER)" == "yes" && " $(state_get POWERUSER_PACKAGES) " =~ " glibc " ]] && warnings+=("glibc from source is DANGEROUS — a miscompilation breaks everything")
    [[ "$(state_get POWER_USER)" == "yes" && "$(state_get INIT)" == "busybox" ]] && warnings+=("BusyBox init from source — ensure the recipe compiled successfully")

    [[ "$(state_get ALLOW_OFFLINE)" == "yes" ]] && warnings+=("Offline mode — packages may be outdated or missing")

    [[ "$(state_get PRIV_ESCALATION)" == "none" ]] && warnings+=("No privilege escalation tool — you'll need to configure su manually")
    [[ "$(state_get PRIV_ESCALATION)" == "doas" && "$(state_get POWER_USER)" == "yes" ]] && warnings+=("doas + Power User: anvil commands require root; use 'doas anvil ...'")

    if [[ ${#warnings[@]} -gt 0 ]]; then
        local msg
        msg=$(printf ' - %s\n' "${warnings[@]}")
        tui_msg "Sanity Warnings" "${msg}"
    fi
}

_quick_profile_baseline() {
    local init="$1"
    state_set INIT "${init}"
    state_set FS_TYPE "ext4"
    state_set BOOTLOADER "grub"
    state_set KERNEL_CHOICE "linux"
    state_set PRIV_ESCALATION "sudo"
    state_set USE_LUKS "no"
    state_set USE_LVM "no"
    state_set GENERATE_UKI "no"
    state_set ALLOW_OFFLINE "no"
    state_set ENABLE_ARCH_REPOS "no"
    state_set MICROCODE_OVERRIDE "auto"
    state_set KEEP_BINARY_KERNEL "yes"
    state_set COREUTILS "gnu"
    state_set KERNEL_CONFIG_DEPTH "auto"
    state_set NETWORK_STACK "networkmanager"
    state_set AUDIO_STACK "pipewire"
    state_set USER_SHELL "bash"
    state_set EXTRAS ""
}

_quick_profile_infer_de() {
    local profile="$1"
    case "${profile}" in
        base|minimal|server)
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set X_STACK "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            ;;
        plasma|community-qt)
            state_set WM_DE "kde"
            state_set KDE_PROFILE "desktop"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            ;;
        lxqt)
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        xfce)
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        cinnamon)
            state_set WM_DE "cinnamon"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        mate)
            state_set WM_DE "mate"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        community-gtk|lxde)
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set KDE_PROFILE "none"
            ;;
        *)
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set X_STACK "none"
            state_set KDE_PROFILE "none"
            ;;
    esac

    if [[ " $(state_get PROFILE_PACKAGES '') " == *" xorg-server-tearfree "* ]]; then
        state_set X_STACK "xorg-tearfree"
    fi
}

_quick_profile_select_init() {
    local title="$1"
    tui_menu "${title}" "Select init system:" "openrc" "runit" "dinit" "s6"
}

_quick_profile_finalize() {
    state_set QUICK_INSTALL "yes"
    return 0
}

_quick_profile_from_yaml() {
    local -a profiles=()
    mapfile -t profiles < <(iso_profiles_list)
    if [[ "${#profiles[@]}" -eq 0 ]]; then
        log_warn "iso-profiles list empty — falling back"
        return 1
    fi

    local choice
    choice=$(tui_menu "Quick Profile" "Select an iso-profiles profile:" "${profiles[@]}") || return 1
    local profile="${choice}"

    local init
    init=$(_quick_profile_select_init "${profile^} Init") || return 1

    _quick_profile_baseline "${init}"
    _quick_profile_infer_de "${profile}"

    state_set QUICK_PROFILE "${profile}"
    state_set QUICK_INSTALL "yes"

    if ! quick_profile_load "${profile}"; then
        log_warn "Failed to load profile packages for '${profile}'"
        state_set PROFILE_PACKAGES ""
    fi

    _quick_profile_finalize "${profile}"
}

_quick_profile_hardcoded() {
    local profile
    profile=$(tui_menu "Quick Profile" "Select a preset:" \
        "Base – no desktop, minimal system" \
        "Plasma – KDE Plasma desktop" \
        "XFCE – XFCE4 desktop" \
        "Cinnamon – Cinnamon desktop" \
        "LXQt – LXQt desktop" \
        "MATE – MATE desktop" \
        "Community GTK – community GTK ISO package set" \
        "Community Qt – community Qt ISO package set" \
        "Gaming – Plasma, linux-zen, Steam, Lutris, DOSBox" \
        "Server – no desktop, firewalld, tmux" \
        "Minimal – bare system, no extras") || return 1

    state_set PROFILE_PACKAGES ""

    case "${profile}" in
        *Base*)
            state_set QUICK_PROFILE "Base"
            local base_init
            base_init=$(_quick_profile_select_init "Base Init") || return 1
            _quick_profile_baseline "${base_init}"
            state_set PRIV_ESCALATION "doas"
            state_set ENABLE_ARCH_REPOS "no"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            ;;
        *Plasma*)
            state_set QUICK_PROFILE "Plasma"
            local plasma_init
            plasma_init=$(_quick_profile_select_init "Plasma Init") || return 1
            _quick_profile_baseline "${plasma_init}"
            state_set WM_DE "kde"
            state_set KDE_PROFILE "desktop"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git flatpak fastfetch firewalld bluez zram-tools firefox neovim alacritty fzf zoxide starship eza btop htop tmux mpv"
            ;;
        *XFCE*)
            state_set QUICK_PROFILE "XFCE"
            local xfce_init
            xfce_init=$(_quick_profile_select_init "XFCE Init") || return 1
            _quick_profile_baseline "${xfce_init}"
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox neovim alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *Cinnamon*)
            state_set QUICK_PROFILE "Cinnamon"
            local cinnamon_init
            cinnamon_init=$(_quick_profile_select_init "Cinnamon Init") || return 1
            _quick_profile_baseline "${cinnamon_init}"
            state_set WM_DE "cinnamon"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *LXQt*)
            state_set QUICK_PROFILE "LXQt"
            local lxqt_init
            lxqt_init=$(_quick_profile_select_init "LXQt Init") || return 1
            _quick_profile_baseline "${lxqt_init}"
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux"
            ;;
        *MATE*)
            state_set QUICK_PROFILE "MATE"
            local mate_init
            mate_init=$(_quick_profile_select_init "MATE Init") || return 1
            _quick_profile_baseline "${mate_init}"
            state_set WM_DE "mate"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox alacritty fzf zoxide starship eza btop tmux mpv"
            ;;
        *"Community GTK"*)
            state_set QUICK_PROFILE "Community GTK"
            local cgtk_init
            cgtk_init=$(_quick_profile_select_init "Community GTK Init") || return 1
            _quick_profile_baseline "${cgtk_init}"
            state_set WM_DE "xfce4"
            state_set DISPLAY_MANAGER "lightdm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox thunderbird libreoffice gimp inkscape vlc alacritty fzf zoxide starship eza btop tmux flatpak"
            ;;
        *"Community Qt"*)
            state_set QUICK_PROFILE "Community Qt"
            local cqt_init
            cqt_init=$(_quick_profile_select_init "Community Qt Init") || return 1
            _quick_profile_baseline "${cqt_init}"
            state_set WM_DE "lxqt"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git firefox thunderbird libreoffice gimp inkscape vlc alacritty fzf zoxide starship eza btop tmux flatpak"
            ;;
        *Gaming*)
            state_set QUICK_PROFILE "Gaming"
            local gaming_init
            gaming_init=$(_quick_profile_select_init "Gaming Init") || return 1
            _quick_profile_baseline "${gaming_init}"
            state_set KERNEL_CHOICE "linux-zen"
            state_set WM_DE "kde"
            state_set KDE_PROFILE "minimal"
            state_set DISPLAY_MANAGER "sddm"
            state_set X_STACK "xorg"
            state_set EXTRAS "git flatpak fastfetch firewalld firefox alacritty fzf zoxide starship eza btop tmux mpv steam lutris dosbox lact goverlay mangohud gamemode piper solaar"
            ;;
        *Server*)
            state_set QUICK_PROFILE "Server"
            local server_init
            server_init=$(_quick_profile_select_init "Server Init") || return 1
            _quick_profile_baseline "${server_init}"
            state_set PRIV_ESCALATION "doas"
            state_set ENABLE_ARCH_REPOS "no"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            state_set EXTRAS "git firewalld tmux"
            ;;
        *Minimal*)
            state_set QUICK_PROFILE "Minimal"
            local minimal_init
            minimal_init=$(_quick_profile_select_init "Minimal Init") || return 1
            _quick_profile_baseline "${minimal_init}"
            state_set PRIV_ESCALATION "doas"
            state_set ENABLE_ARCH_REPOS "no"
            state_set WM_DE "none"
            state_set DISPLAY_MANAGER "none"
            state_set KDE_PROFILE "none"
            state_set NETWORK_STACK "dhcpcd+iwd"
            state_set AUDIO_STACK "none"
            state_set X_STACK "none"
            ;;
        *)
            return 1
            ;;
    esac

    _quick_profile_finalize "${profile}"
}

tui_quick_install() {
    if ! tui_yesno "Quick Install" "Use a pre-configured profile?"; then
        return 1
    fi

    if iso_profiles_ensure; then
        if tui_yesno "Profile Source" "Use upstream iso-profiles (recommended)?"; then
            if _quick_profile_from_yaml; then
                return 0
            fi
            log_warn "iso-profiles path failed — falling back to built-in presets"
        fi
    fi

    _quick_profile_hardcoded
}

tui_select_poweruser() {
    [[ "$(state_get POWER_USER no)" == "yes" ]] || return 0

    POWERUSER_DIR="${BASE_DIR}/bashisms/poweruser"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/tui/menu_poweruser.sh"

    local recipe_count
    recipe_count=$(find "${POWERUSER_DIR}/recipes" -name '*.sh' ! -name 'template.sh' | wc -l)
    if [[ ${recipe_count} -eq 0 ]]; then
        log_info "No recipes found. Fetching OFFICIAL/Base..."
        local list_url="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main/.LIST"
        local repo_base="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main"
        if curl -fsSL "${list_url}" -o /tmp/artix-recipes.list 2>/dev/null; then
            while IFS='|' read -r name section desc; do
                if [[ "${section}" == "OFFICIAL/Base" ]]; then
                    log_info "  Downloading ${name}.sh..."
                    curl -sL "${repo_base}/${section}/${name}.sh" -o "${POWERUSER_DIR}/recipes/${name}.sh" || log_warn "Failed to download ${name}"
                fi
            done < /tmp/artix-recipes.list
            rm -f /tmp/artix-recipes.list
            log_info "Recipes downloaded."
        fi
    fi

    tui_poweruser_config
}

tui_collect_install_config() {
    if [[ "${ARTIX_BOOT_MODE:-uefi}" == "bios" ]]; then
        tui_msg "BIOS Mode" "Legacy BIOS boot detected. UEFI features (UKI, EFIStub, rEFInd, Limine) are disabled."
    fi

    tui_select_theme

    if tui_quick_install; then
        _run_config_hub
        _run_users_hub
        _post_hub_derive
        tui_show_sanity_warnings
        tui_show_summary
        [[ "$(state_get POWER_USER no)" == "yes" ]] && tui_select_poweruser
        return
    fi

    local quick_vars=(
        QUICK_PROFILE FS_TYPE BOOTLOADER KERNEL_CHOICE INIT PRIV_ESCALATION
        USE_LUKS USE_LVM GENERATE_UKI ALLOW_OFFLINE ENABLE_ARCH_REPOS
        MICROCODE_OVERRIDE KEEP_BINARY_KERNEL COREUTILS KERNEL_CONFIG_DEPTH
        WM_DE KDE_PROFILE DISPLAY_MANAGER NETWORK_STACK AUDIO_STACK X_STACK
        USER_SHELL EXTRAS POWER_USER POWERUSER_PACKAGES POWERUSER_PROFILE
        SWAP_ENABLED SWAP_SIZE LUKS_KEYFILE LUKS_KEYFILE_PATH LUKS_PASS
    )
    local var
    for var in "${quick_vars[@]}"; do
        state_set "${var}" ""
    done
    state_set QUICK_INSTALL "no"

    _run_config_hub
    _run_users_hub
    _post_hub_derive
    tui_show_sanity_warnings
    tui_show_summary
    tui_select_poweruser
}