#!/usr/bin/env bash
set -Eeuo pipefail

generate_common_yaml() {
    local workspace="${1}"
    local common_dir="${workspace}/iso-profiles/common"
    mkdir -p "${common_dir}"
    
    cat > "${common_dir}/common.yaml" <<'COMMONYAML'
---
packages-base:
  - base
  - intel-ucode
  - amd-ucode
  - acpi
  - alsa-firmware
  - b43-fwcutter
  - btrfs-progs
  - crda
  - dhclient
  - diffutils
  - dmraid
  - dosfstools
  - efibootmgr
  - e2fsprogs
  - ecryptfs-utils
  - exfat-utils
  - f2fs-tools
  - grub
  - artix-grub-theme
  - inetutils
  - iptables
  - jfsutils
  - linux
  - linux-firmware
  - linux-headers
  - lsb-release
  - logrotate
  - lsb-release
  - man-db
  - man-pages
  - memtest86+
  - mkinitcpio
  - mkinitcpio-openswap
  - modemmanager
  - nano
  - nbd
  - net-tools
  - ntfs-3g
  - os-prober
  - s-nail
  - sudo
  - sysfsutils
  - texinfo
  - usbutils
  - vi
  - which
  - xfsprogs
  - zsh
packages-apps:
  - powertop
  - inxi
packages-xorg:
  - xorg-server
  - xf86-input-vmmouse
  - xf86-input-wacom  - xf86-video-amdgpu
  - xf86-video-ati
  - xf86-video-dummy
  - xf86-video-fbdev
  - xf86-video-intel
  - xf86-video-nouveau
  - xf86-video-sisusb
  - xf86-video-qxl
  - xf86-video-vesa
  - xf86-video-voodoo
packages-misc:
  - xorg-xhost
  - xorg-xinit
  - xdg-user-dirs
  - xdg-utils
  - wayland
  - xorg-xwayland
  - terminus-font
  - ttf-droid
  - ttf-inconsolata
  - ttf-liberation
  - ttf-roboto
  - ttf-roboto-mono
  - ttf-droid
packages-init:
  dinit:
    - blocaled
    - elogind-dinit
    - dbus-dinit
    - acpid-dinit
    - avahi-dinit
    - bluez-dinit
    - cronie-dinit
    - cryptsetup-dinit
    - dhcpcd-dinit
    - haveged-dinit
    - lvm2-dinit
    - mdadm-dinit
    - nfs-utils-dinit
    - ntp-dinit
    - openssh-dinit
    - power-profiles-daemon-dinit
    - rsync-dinit
    - wpa_supplicant-dinit
  openrc:
    - openrc-settingsd
    - elogind-openrc
    - dbus-openrc
    - acpid-openrc
    - avahi-openrc
    - bluez-openrc
    - cronie-openrc
    - cryptsetup-openrc
    - dhcpcd-openrc
    - haveged-openrc
    - lvm2-openrc
    - mdadm-openrc
    - nfs-utils-openrc
    - ntp-openrc
    - openssh-openrc
    - power-profiles-daemon-openrc
    - rsync-openrc
    - wpa_supplicant-openrc
  runit:
    - blocaled
    - rsm
    - elogind-runit
    - dbus-runit
    - acpid-runit
    - avahi-runit
    - bluez-runit
    - cronie-runit
    - cryptsetup-runit
    - dhcpcd-runit
    - haveged-runit
    - lvm2-runit
    - mdadm-runit
    - nfs-utils-runit
    - ntp-runit
    - openssh-runit
    - power-profiles-daemon-runit
    - rsync-runit
    - wpa_supplicant-runit
  s6:
    - blocaled
    - elogind-s6
    - dbus-s6
    - acpid-s6
    - avahi-s6
    - bluez-s6
    - cronie-s6
    - cryptsetup-s6
    - dhcpcd-s6
    - haveged-s6
    - lvm2-s6
    - mdadm-s6
    - nfs-utils-s6
    - ntp-s6
    - openssh-s6
    - power-profiles-daemon-s6
    - rsync-s6
    - wpa_supplicant-s6
packages-boot:
  - iso-initcpio
COMMONYAML
}

generate_iso_package_list() {
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
        kde)     pkg_list+=(plasma-desktop dolphin konsole sddm "sddm-${init}") ;;
        xfce)    pkg_list+=(xfce4 xfce4-goodies lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        lxqt)    pkg_list+=(lxqt sddm "sddm-${init}") ;;
        lxde)    pkg_list+=(lxde-common lxde lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        hyprland) pkg_list+=(hyprland swaybg swaylock waybar) ;;
        sway)    pkg_list+=(sway swaybg swaylock waybar) ;;
        niri)    pkg_list+=(niri swaybg swaylock) ;;
        i3wm)    pkg_list+=(i3-wm i3status i3lock dmenu xterm lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        dwm)     pkg_list+=(dwm dmenu xterm lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        vxwm)    pkg_list+=(base-devel git libx11 libxft libxinerama freetype2 xorg-server xorg-xinit) ;;
        icewm)   pkg_list+=(icewm lightdm lightdm-gtk-greeter "lightdm-${init}") ;;
        mango)   pkg_list+=(base-devel git) ;;
        cinnamon) pkg_list+=(cinnamon lightdm lightdm-gtk-greeter) ;;
        budgie)   pkg_list+=(budgie-desktop budgie-screensaver budgie-control-center lightdm lightdm-gtk-greeter) ;;
        moksha)   pkg_list+=(moksha enlightenment lightdm lightdm-gtk-greeter) ;;
        cosmic)   pkg_list+=(cosmic cosmic-terminal cosmic-text-editor cosmic-files cosmic-settings cosmic-launcher lightdm lightdm-gtk-greeter) ;;
    esac

    local x_stack
    x_stack="$(state_get X_STACK xorg)"
    if [[ "${x_stack}" == "xorg" ]]; then
        pkg_list+=(xorg-server xorg-xinit xf86-input-libinput xf86-input-evdev)
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

generate_artools_profile() {
    local out_dir="${1}" profile_name="${2}" init="${3}" kernel="${4}" boot_mode="${5:-live}"

    mkdir -p "${out_dir}"/{live-overlay,desktop-overlay,airootfs/etc}
    touch "${out_dir}/live-overlay/keep"

    generate_iso_package_list "${init}" "${kernel}" > "${out_dir}/packages.x86_64"

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

    local -a live_packages=()
    while IFS= read -r pkg; do
        [[ -n "${pkg}" ]] && live_packages+=("${pkg}")
    done < "${out_dir}/packages.x86_64"

    cat > "${out_dir}/profile.yaml" <<YAML
---
live-session:
  user: artix
  password: artix
  autologin: true
  services:
YAML

    case "${network_stack}" in
        networkmanager) echo "    - NetworkManager" >> "${out_dir}/profile.yaml" ;;
        connman)        echo "    - connmand" >> "${out_dir}/profile.yaml" ;;
    esac
    echo "    - dbus" >> "${out_dir}/profile.yaml"
    echo "    - elogind" >> "${out_dir}/profile.yaml"
    
    case "${wm_de}" in
        hyprland|sway|niri|mango)
            echo "    - seatd" >> "${out_dir}/profile.yaml" ;;
    esac

    cat >> "${out_dir}/profile.yaml" <<YAML
  user-services:
    - dbus
YAML

    case "${audio_stack}" in
        pipewire)
            echo "    - pipewire" >> "${out_dir}/profile.yaml"
            echo "    - pipewire-pulse" >> "${out_dir}/profile.yaml"
            echo "    - wireplumber" >> "${out_dir}/profile.yaml"
            ;;
        pulseaudio)
            echo "    - pulseaudio" >> "${out_dir}/profile.yaml"
            ;;
    esac

    cat >> "${out_dir}/profile.yaml" <<YAML
livefs:
  packages:
YAML
    for pkg in "${live_packages[@]}"; do
        echo "    - ${pkg}" >> "${out_dir}/profile.yaml"
    done

    cat >> "${out_dir}/profile.yaml" <<YAML
  packages-init:
    ${init}:
YAML
    case "${init}" in
        openrc)
            echo "      - artix-live-openrc" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-openrc" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-openrc" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-openrc" >> "${out_dir}/profile.yaml"; echo "      - iwd-openrc" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-openrc" >> "${out_dir}/profile.yaml"; echo "      - pipewire-pulse-openrc" >> "${out_dir}/profile.yaml"; echo "      - wireplumber-openrc" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-openrc" >> "${out_dir}/profile.yaml"
            ;;
        dinit)
            echo "      - artix-live-dinit" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-dinit" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-dinit" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-dinit" >> "${out_dir}/profile.yaml"; echo "      - iwd-dinit" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-dinit" >> "${out_dir}/profile.yaml"; echo "      - pipewire-pulse-dinit" >> "${out_dir}/profile.yaml"; echo "      - wireplumber-dinit" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-dinit" >> "${out_dir}/profile.yaml"
            ;;
        runit)
            echo "      - artix-live-runit" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-runit" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-runit" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-runit" >> "${out_dir}/profile.yaml"; echo "      - iwd-runit" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-runit" >> "${out_dir}/profile.yaml"; echo "      - pipewire-pulse-runit" >> "${out_dir}/profile.yaml"; echo "      - wireplumber-runit" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-runit" >> "${out_dir}/profile.yaml"
            ;;
        s6)
            echo "      - artix-live-s6" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "networkmanager" ]] && echo "      - networkmanager-s6" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "connman" ]] && echo "      - connman-s6" >> "${out_dir}/profile.yaml"
            [[ "${network_stack}" == "dhcpcd+iwd" ]] && { echo "      - dhcpcd-s6" >> "${out_dir}/profile.yaml"; echo "      - iwd-s6" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pipewire" ]] && { echo "      - pipewire-s6" >> "${out_dir}/profile.yaml"; echo "      - pipewire-pulse-s6" >> "${out_dir}/profile.yaml"; echo "      - wireplumber-s6" >> "${out_dir}/profile.yaml"; }
            [[ "${audio_stack}" == "pulseaudio" ]] && echo "      - pulseaudio-s6" >> "${out_dir}/profile.yaml"
            ;;
    esac

    cat >> "${out_dir}/profile.yaml" <<YAML
rootfs:
  packages: []
YAML

    mkdir -p "${out_dir}/airootfs/root"
    cp -a "${BASE_DIR}" "${out_dir}/airootfs/root/ArtixForge"
    log_info "ArtixForge copied into ISO at /root/ArtixForge"

    log_info "Artools profile generated: ${out_dir}"
}