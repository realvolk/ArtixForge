#!/usr/bin/env bash
set -Eeuo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ISO_DIR}/.." && pwd)}"

generate_offline_package_list() {
    local init="${1}" kernel="${2}"

    local -a pkg_list=()

    pkg_list+=(
        base base-devel linux-firmware bash nano vim sudo git curl wget pciutils
        mkinitcpio efibootmgr dosfstools gptfdisk parted cryptsetup lvm2
        btrfs-progs xfsprogs f2fs-tools exfat-utils e2fsprogs
        gum artools openssl rsync grub artix-grub-theme artix-grub-live
        bc cpio pahole libelf
    )
    pkg_list+=(intel-ucode amd-ucode)
    pkg_list+=("${kernel}" "${kernel}-headers")

    case "${init}" in
        openrc) pkg_list+=(openrc) ;;
        runit)  pkg_list+=(runit) ;;
        dinit)  pkg_list+=(dinit dinit-base dinit-rc) ;;
        s6)     pkg_list+=(s6 s6-rc) ;;
    esac

    pkg_list+=(dbus "dbus-${init}")

    local wm_de
    wm_de="$(state_get WM_DE none)"
    case "${wm_de}" in
        hyprland|sway|niri|mango)
            pkg_list+=(seatd "seatd-${init}") ;;
        *)
            pkg_list+=("elogind-${init}") ;;
    esac

    local priv_esc
    priv_esc="$(state_get PRIV_ESCALATION sudo)"
    pkg_list+=("${priv_esc}")

    local user_shell
    user_shell="$(state_get USER_SHELL bash)"
    case "${user_shell}" in
        zsh)  pkg_list+=(zsh) ;;
        fish) pkg_list+=(fish) ;;
    esac

    local network_stack
    network_stack="$(state_get NETWORK_STACK networkmanager)"
    case "${network_stack}" in
        networkmanager) pkg_list+=(networkmanager "networkmanager-${init}") ;;
        dhcpcd+iwd)     pkg_list+=(dhcpcd iwd "dhcpcd-${init}" "iwd-${init}") ;;
        connman)        pkg_list+=(connman "connman-${init}") ;;
    esac

    local audio_stack
    audio_stack="$(state_get AUDIO_STACK pipewire)"
    case "${audio_stack}" in
        pipewire)   pkg_list+=(pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pavucontrol rtkit) ;;
        pulseaudio) pkg_list+=(pulseaudio pulseaudio-alsa alsa-utils pavucontrol) ;;
    esac

    case "${wm_de}" in
        kde)      pkg_list+=(plasma-desktop dolphin konsole sddm "sddm-${init}") ;;
        xfce)     pkg_list+=(xfce4 xfce4-goodies lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        lxqt)     pkg_list+=(lxqt sddm "sddm-${init}") ;;
        lxde)     pkg_list+=(lxde-common lxde lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        mate)     pkg_list+=(mate mate-extra xdg-desktop-portal-gtk lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        hyprland) pkg_list+=(hyprland swaybg swaylock waybar) ;;
        sway)     pkg_list+=(sway swaybg swaylock waybar) ;;
        niri)     pkg_list+=(niri swaybg swaylock) ;;
        i3wm)     pkg_list+=(i3-wm i3status i3lock dmenu xterm lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        dwm)      pkg_list+=(dwm dmenu xterm lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        vxwm)     pkg_list+=(base-devel git libx11 libxft libxinerama freetype2 xorg-server xorg-xinit) ;;
        icewm)    pkg_list+=(icewm lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        mango)    pkg_list+=(base-devel git) ;;
        cinnamon) pkg_list+=(cinnamon lightdm lightdm-gtk-greeter "lightdm-${init}" xdg-desktop-portal-gtk) ;;
        budgie)   pkg_list+=(budgie-desktop budgie-screensaver budgie-control-center lightdm lightdm-gtk-greeter "lightdm-${init}" xdg-desktop-portal-gtk) ;;
        moksha)   pkg_list+=(moksha enlightenment terminology lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        cosmic)   pkg_list+=(cosmic cosmic-terminal cosmic-text-editor cosmic-files cosmic-settings cosmic-launcher lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
    esac

    local x_stack
    x_stack="$(state_get X_STACK xorg)"
    case "${x_stack}" in
        xorg)          pkg_list+=(xorg-server xorg-xinit xf86-input-libinput xf86-input-evdev) ;;
        xorg-tearfree) pkg_list+=(xorg-server-tearfree xorg-xinit xf86-input-libinput xf86-input-evdev) ;;
    esac

    if [[ -n "$(state_get PROFILE_PACKAGES '')" ]]; then
        local -a profile_pkgs
        read -ra profile_pkgs <<< "$(state_get PROFILE_PACKAGES '')"
        pkg_list+=("${profile_pkgs[@]}")
    fi

    local extras
    extras="$(state_get EXTRAS "")"
    for extra in ${extras}; do
        pkg_list+=("${extra}")
    done

    local iso_extras
    iso_extras="$(state_get ISO_EXTRA_PACKAGES "")"
    for extra in ${iso_extras}; do
        pkg_list+=("${extra}")
    done

    printf '%s\n' "${pkg_list[@]}" | sort -u
}

iso_profile_for_de() {
    local wm_de="$1"
    case "${wm_de}" in
        kde)      printf 'plasma\n' ;;
        xfce)     printf 'xfce\n' ;;
        lxqt)     printf 'lxqt\n' ;;
        lxde)     printf 'lxde\n' ;;
        mate)     printf 'mate\n' ;;
        cinnamon) printf 'cinnamon\n' ;;
        hyprland) printf 'hyprland\n' ;;
        sway)     printf 'sway\n' ;;
        niri)     printf 'niri\n' ;;
        i3wm)     printf 'i3wm\n' ;;
        dwm)      printf 'dwm\n' ;;
        icewm)    printf 'icewm\n' ;;
        mango)    printf 'mango\n' ;;
        budgie)   printf 'budgie\n' ;;
        moksha)   printf 'moksha\n' ;;
        cosmic)   printf 'cosmic\n' ;;
        vxwm)     printf 'base\n' ;;
        *)        printf 'base\n' ;;
    esac
}

generate_artools_profile() {
    local out_dir="${1}" profile_name="${2}" init="${3}" kernel="${4}" boot_mode="${5:-live}"
    local base_profile="${6:-base}"

    local upstream_dir="${ISO_PROFILES_ROOT}/${base_profile}"
    [[ -d "${upstream_dir}" ]] || die "Upstream profile not found: ${base_profile}"

    mkdir -p "${out_dir}"
    cp -a "${upstream_dir}/." "${out_dir}/"
    mkdir -p "${out_dir}/live-overlay" "${out_dir}/airootfs/root" "${out_dir}/airootfs/etc"

    generate_offline_package_list "${init}" "${kernel}" > "${out_dir}/packages-offline.x86_64"

    if [[ "${boot_mode}" == "installer" ]]; then
        log_info "Configuring installer ISO auto-boot..."
        case "${init}" in
            openrc)
                mkdir -p "${out_dir}/live-overlay/etc/local.d"
                cat > "${out_dir}/live-overlay/etc/local.d/artixforge.start" <<'EOF'
#!/bin/sh
clear
printf '\n\e[1;34m  Welcome to ArtixForge Installer\e[0m\n\n'
printf '  The installer will start automatically.\n'
printf '  Press Ctrl+C for a shell.\n\n'
sleep 2
cd /root/ArtixForge && ./install
EOF
                chmod +x "${out_dir}/live-overlay/etc/local.d/artixforge.start"
                ;;
            dinit)
                mkdir -p "${out_dir}/live-overlay/etc/dinit.d"
                cat > "${out_dir}/live-overlay/etc/dinit.d/artixforge" <<'EOF'
type = process
command = /root/ArtixForge/install
restart = false
logfile = /tmp/artixforge-installer.log
EOF
                ;;
            runit)
                mkdir -p "${out_dir}/live-overlay/etc/runit/sv/artixforge"
                cat > "${out_dir}/live-overlay/etc/runit/sv/artixforge/run" <<'EOF'
#!/bin/sh
clear
printf '\n\e[1;34m  Welcome to ArtixForge Installer\e[0m\n\n'
printf '  The installer will start automatically.\n'
printf '  Press Ctrl+C for a shell.\n\n'
sleep 2
exec /root/ArtixForge/install
EOF
                chmod +x "${out_dir}/live-overlay/etc/runit/sv/artixforge/run"
                ;;
            s6)
                log_info "s6 installer mode: cannot auto-launch without compiled service database"
                mkdir -p "${out_dir}/live-overlay/etc"
                cat > "${out_dir}/live-overlay/etc/motd" <<'EOF'

  Welcome to ArtixForge Installer (s6)

  The installer is available at: /root/ArtixForge/install
  Run: cd /root/ArtixForge && ./install

EOF
                ;;
        esac
    fi

    local wm_de x_stack network_stack audio_stack
    wm_de="$(state_get WM_DE none)"
    x_stack="$(state_get X_STACK xorg)"
    network_stack="$(state_get NETWORK_STACK networkmanager)"
    audio_stack="$(state_get AUDIO_STACK pipewire)"

    cat > "${out_dir}/profile-artixforge.yaml" <<YAML
---
live-session:
  user: artix
  password: artix
  autologin: true
  services:
YAML

    case "${network_stack}" in
        networkmanager) echo "    - NetworkManager" >> "${out_dir}/profile-artixforge.yaml" ;;
        connman)        echo "    - connmand" >> "${out_dir}/profile-artixforge.yaml" ;;
    esac
    echo "    - dbus" >> "${out_dir}/profile-artixforge.yaml"
    echo "    - elogind" >> "${out_dir}/profile-artixforge.yaml"

    case "${wm_de}" in
        hyprland|sway|niri|mango)
            echo "    - seatd" >> "${out_dir}/profile-artixforge.yaml" ;;
    esac

    cat >> "${out_dir}/profile-artixforge.yaml" <<YAML
  user-services:
    - dbus
YAML

    case "${audio_stack}" in
        pipewire)
            echo "    - pipewire" >> "${out_dir}/profile-artixforge.yaml"
            echo "    - pipewire-pulse" >> "${out_dir}/profile-artixforge.yaml"
            echo "    - wireplumber" >> "${out_dir}/profile-artixforge.yaml"
            ;;
        pulseaudio)
            echo "    - pulseaudio" >> "${out_dir}/profile-artixforge.yaml"
            ;;
    esac

    cat >> "${out_dir}/profile-artixforge.yaml" <<YAML
  packages-init:
    ${init}:
YAML
    case "${init}" in
        openrc)
            echo "      - artix-live-openrc" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-openrc" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-openrc" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-openrc" >> "${out_dir}/profile-artixforge.yaml"; echo "      - iwd-openrc" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-openrc" >> "${out_dir}/profile-artixforge.yaml"; echo "      - pipewire-pulse-openrc" >> "${out_dir}/profile-artixforge.yaml"; echo "      - wireplumber-openrc" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-openrc" >> "${out_dir}/profile-artixforge.yaml"
            ;;
        dinit)
            echo "      - artix-live-dinit" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-dinit" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-dinit" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-dinit" >> "${out_dir}/profile-artixforge.yaml"; echo "      - iwd-dinit" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-dinit" >> "${out_dir}/profile-artixforge.yaml"; echo "      - pipewire-pulse-dinit" >> "${out_dir}/profile-artixforge.yaml"; echo "      - wireplumber-dinit" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-dinit" >> "${out_dir}/profile-artixforge.yaml"
            ;;
        runit)
            echo "      - artix-live-runit" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-runit" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-runit" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-runit" >> "${out_dir}/profile-artixforge.yaml"; echo "      - iwd-runit" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-runit" >> "${out_dir}/profile-artixforge.yaml"; echo "      - pipewire-pulse-runit" >> "${out_dir}/profile-artixforge.yaml"; echo "      - wireplumber-runit" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-runit" >> "${out_dir}/profile-artixforge.yaml"
            ;;
        s6)
            echo "      - artix-live-s6" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-s6" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-s6" >> "${out_dir}/profile-artixforge.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-s6" >> "${out_dir}/profile-artixforge.yaml"; echo "      - iwd-s6" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-s6" >> "${out_dir}/profile-artixforge.yaml"; echo "      - pipewire-pulse-s6" >> "${out_dir}/profile-artixforge.yaml"; echo "      - wireplumber-s6" >> "${out_dir}/profile-artixforge.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-s6" >> "${out_dir}/profile-artixforge.yaml"
            ;;
    esac

    cp -a "${BASE_DIR}" "${out_dir}/airootfs/root/ArtixForge"
    log_info "ArtixForge copied into ISO at /root/ArtixForge"

    log_info "Artools profile generated: ${out_dir} (base: ${base_profile})"
}