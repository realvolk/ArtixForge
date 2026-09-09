#!/usr/bin/env bash
set -Eeuo pipefail

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
    [[ "$(state_get WM_DE)" =~ ^(hyprland|niri|sway)$ && "$(state_get X_STACK)" == "xorg" ]] && warnings+=("Wayland compositor selected but X.Org display stack configured")
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