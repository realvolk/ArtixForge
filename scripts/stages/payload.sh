#!/usr/bin/env bash
set -Eeuo pipefail

_payload_apply() {
    local src="$1"
    [[ -d "$src" ]] || return 0

    local -a skip_paths=(
        "etc/hostname"
        "etc/hosts"
        "etc/issue"
        "etc/issue.live"
        "etc/motd"
        "etc/fstab"
        "etc/default/grub"
        "etc/vconsole.conf"
        "etc/locale.conf"
        "etc/lightdm/lightdm.conf"
        "etc/sddm.conf"
        "etc/sddm.conf.d"
        "etc/local.d"
        "etc/init.d"
        "etc/conf.d"
        "etc/runlevels"
        "etc/mkinitcpio.conf"
        "etc/mkinitcpio.conf.d"
        "etc/mkinitcpio.conf.mod"
        "etc/modprobe.d"
        "etc/passwd"
        "etc/shadow"
        "etc/group"
        "etc/gshadow"
        "etc/bash"
        "root"
    )

    local entry rel skip pat
    while IFS= read -r -d '' entry; do
        rel="${entry#./}"
        skip=0
        for pat in "${skip_paths[@]}"; do
            if [[ "${rel}" == "${pat}" || "${rel}" == "${pat}/"* ]]; then
                skip=1
                break
            fi
        done
        [[ ${skip} -eq 1 ]] && continue

        cp -rL --preserve=mode,timestamps "${src}/${entry}" /mnt/ 2>/dev/null || \
            log_warn "Failed to copy overlay path: ${rel}"
    done < <(cd "$src" && find . -mindepth 1 -maxdepth 1 -print0)
}

_payload_filter_caches() {
    find /mnt/etc/skel /mnt/root \
        -type d \( -name '.cache' -o -path '*/.config/dconf' \) \
        -prune -exec rm -rf {} + 2>/dev/null || true
    find /mnt/etc/skel /mnt/root \
        -type f -path '*/.local/share/Trash/*' \
        -delete 2>/dev/null || true
}

_payload_apply_final() {
    local profile
    profile="$(state_get QUICK_PROFILE '')"
    [[ -n "${profile}" ]] || return 0
    [[ -d "${ISO_PROFILES_ROOT}/${profile}/root-overlay" ]] || return 0

    log_info "Re-applying payload overlays (final pass)..."

    _payload_apply "${ISO_PROFILES_ROOT}/common/root-overlay"
    _payload_apply "${ISO_PROFILES_ROOT}/common/community/root-overlay"

    case "${profile}" in
        community-gtk|mate|cinnamon|xfce|lxde)
            _payload_apply "${ISO_PROFILES_ROOT}/common/gtk/root-overlay" ;;
        community-qt|plasma|lxqt)
            _payload_apply "${ISO_PROFILES_ROOT}/common/qt/root-overlay" ;;
    esac

    _payload_apply "${ISO_PROFILES_ROOT}/${profile}/root-overlay"

    _payload_filter_caches

    log_info "Final overlay pass complete."
}

stage_payload() {
    if stage_should_skip payload; then return 0; fi

    local profile
    profile="$(state_get QUICK_PROFILE '')"
    [[ -n "$profile" ]] || {
        log_info "No Quick Profile selected — skipping payload"
        stage_mark_done payload
        return 0
    }

    iso_profiles_available || {
        log_warn "iso-profiles unavailable — skipping payload"
        stage_mark_done payload
        return 0
    }

    local root="${ISO_PROFILES_ROOT}/${profile}/root-overlay"
    if [[ ! -d "$root" ]]; then
        log_warn "No root-overlay for profile '${profile}'"
        stage_mark_done payload
        return 0
    fi

    log_info "Applying payload overlay for profile: ${profile}"

    _payload_apply "${ISO_PROFILES_ROOT}/common/root-overlay"       || die "common overlay failed"
    _payload_apply "${ISO_PROFILES_ROOT}/common/community/root-overlay" || die "community overlay failed"

    case "$profile" in
        community-gtk|mate|cinnamon|xfce|lxde)
            _payload_apply "${ISO_PROFILES_ROOT}/common/gtk/root-overlay" || die "gtk overlay failed"
            ;;
        community-qt|plasma|lxqt)
            _payload_apply "${ISO_PROFILES_ROOT}/common/qt/root-overlay"  || die "qt overlay failed"
            ;;
    esac

    _payload_apply "$root" || die "profile overlay failed"

    _payload_filter_caches

    install -Dm644 /dev/null "/mnt/.artixforge-payload-${profile}"
    log_info "Synchronizing target package databases after overlay..."
    artix-chroot /mnt pacman -Sy --noconfirm || log_warn "Failed to sync target databases after overlay"

    if grep -q '^\[extra\]' /mnt/etc/pacman.conf 2>/dev/null; then
        log_info "Arch repos present in target — installing keyring support..."
        artix-chroot /mnt pacman -S --noconfirm --needed artix-archlinux-support \
            || log_warn "Failed to install artix-archlinux-support"
    fi

    stage_mark_done payload
}

