#!/usr/bin/env bash
set -Eeuo pipefail

ISO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd -- "${ISO_DIR}/../.." && pwd)}"

generate_offline_package_list() {
    local init="${1}" kernel="${2}"

    local -a pkg_list=()

    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_iso_base_packages)
    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_iso_microcode_packages)

    pkg_list+=("${kernel}" "${kernel}-headers")

    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_init_fallback_packages "${init}")
    pkg_list+=(dbus "dbus-${init}")

    local wm_de
    wm_de="$(state_get WM_DE none)"

    local seat_pkg
    seat_pkg="$(resolve_seat_package "${wm_de}")"
    if [[ -n "${seat_pkg}" ]]; then
        pkg_list+=("${seat_pkg}" "${seat_pkg}-${init}")
    else
        local elogind_pkg
        elogind_pkg="$(resolve_init_elogind "${init}")"
        [[ -n "${elogind_pkg}" ]] && pkg_list+=("${elogind_pkg}")
    fi

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
    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_network_packages "${network_stack}" "${init}")

    local audio_stack
    audio_stack="$(state_get AUDIO_STACK pipewire)"
    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_audio_packages "${audio_stack}")
    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_audio_service_packages "${audio_stack}" "${init}")

    local kde_profile
    kde_profile="$(state_get KDE_PROFILE desktop)"
    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_de_packages "${wm_de}" "${init}" "${kde_profile}")

    local x_stack
    x_stack="$(state_get X_STACK xorg)"
    mapfile -t -O "${#pkg_list[@]}" pkg_list < <(resolve_xstack_packages "${x_stack}")

    if [[ -n "$(state_get PROFILE_PACKAGES '')" ]]; then
        local -a profile_pkgs
        read -ra profile_pkgs <<< "$(state_get PROFILE_PACKAGES '')"
        pkg_list+=("${profile_pkgs[@]}")
    fi

    local extras
    extras="$(state_get EXTRAS "")"
    local extra
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

    local wm_de x_stack network_stack audio_stack kde_profile
    wm_de="$(state_get WM_DE none)"
    x_stack="$(state_get X_STACK xorg)"
    network_stack="$(state_get NETWORK_STACK networkmanager)"
    audio_stack="$(state_get AUDIO_STACK pipewire)"
    kde_profile="$(state_get KDE_PROFILE desktop)"

    cat > "${out_dir}/profile-artixforge.yaml" <<YAML
---
live-session:
  user: artix
  password: artix
  autologin: true
  services:
YAML

    local net_svc
    net_svc="$(resolve_network_services "${network_stack}")"
    local svc
    for svc in ${net_svc}; do
        printf '    - %s\n' "${svc}" >> "${out_dir}/profile-artixforge.yaml"
    done
    echo "    - dbus" >> "${out_dir}/profile-artixforge.yaml"

    if [[ -n "$(resolve_seat_package "${wm_de}")" ]]; then
        echo "    - seatd" >> "${out_dir}/profile-artixforge.yaml"
    else
        echo "    - elogind" >> "${out_dir}/profile-artixforge.yaml"
    fi

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

    printf '      - artix-live-%s\n' "${init}" >> "${out_dir}/profile-artixforge.yaml"

    local net_pkgs
    net_pkgs="$(resolve_network_packages "${network_stack}" "${init}")"
    local pkg
    for pkg in ${net_pkgs}; do
        printf '      - %s\n' "${pkg}" >> "${out_dir}/profile-artixforge.yaml"
    done

    local audio_svc_pkgs
    audio_svc_pkgs="$(resolve_audio_service_packages "${audio_stack}" "${init}")"
    for pkg in ${audio_svc_pkgs}; do
        printf '      - %s\n' "${pkg}" >> "${out_dir}/profile-artixforge.yaml"
    done

    cp -a "${BASE_DIR}" "${out_dir}/airootfs/root/ArtixForge"
    log_info "ArtixForge copied into ISO at /root/ArtixForge"

    log_info "Artools profile generated: ${out_dir} (base: ${base_profile})"
}