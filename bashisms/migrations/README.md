# System Migration

In-place migration of init systems, desktop environments, and full operating
system conversion for Artix Linux.

---

## Usage

From the ArtixForge installer main menu, select **System Migration**, then
choose the migration type.

---

# ATA (Arch to Artix)

Full conversion of an Arch Linux installation to Artix Linux, preserving user
data, configurations, credentials, and installed software.

**ATA is experimental.**  It attempts to automate as much of the migration as
possible, but Arch and Artix have diverged in ways no script can fully predict.
Always make a full backup before proceeding.

---

## What Gets Migrated Automatically

- All pacman packages, with version mismatch warnings and manual selection
- Desktop environment and display manager (reinstalled from Artix repos)
- User files and home directories (untouched)
- System configurations (`/etc/fstab`, `/etc/hostname`, locale, keymap, timezone)
- Enabled systemd services → init-specific equivalents
- WiFi passwords and network configurations (with 600 permissions)
- SSH host keys and configurations
- Firewall rules (iptables/nftables)
- Cron jobs (system and per-user)
- Pacman hooks (systemd-dependent ones disabled and quarantined)
- PAM modules (`pam_systemd.so` → `pam_elogind.so`)
- mkinitcpio hooks (`systemd` → `udev`, `sd-encrypt` → `encrypt`, etc.)
- systemd timers → cron (OnCalendar + basic monotonic)
- crypttab entries → kernel command line parameters
- DNS resolver (`systemd-resolved` stub replaced)
- systemd-boot → GRUB (auto-install)
- Flatpaks (remotes and app list preserved)
- DKMS modules (auto-rebuild on next boot)
- systemd-homed users (unlocked and migrated to standard `/home`)
- systemd `--user` services → XDG autostart
- AUR packages (batch reinstall attempted with chosen helper)

## What Needs Manual Intervention

- Complex monotonic systemd timers (best-effort loop script used)
- Snap packages (require systemd — will not function on Artix)
- Custom systemd unit files (backed up, not converted)
- systemd-networkd configurations (backed up, manual NM/ConnMan conversion)
- AUR packages that hard-depend on `systemd` (flagged during batch reinstall)

## What Gets Backed Up

- All of `/home` for every user
- `/etc` (full copy)
- `/boot`
- `/usr/local`
- Pacman database (`/var/lib/pacman`)
- System journal (text export)
- Network credentials (isolated, 700 permissions)
- All detection lists and audit files

Backups are stored under `/arch-migration-backup-YYYYMMDD-HHMMSS/` with
restrictive permissions.

---

# Init Systems

All 16 init system combinations are supported. Each pair maps known services
between init systems and preserves custom services for manual review.

| Source | Target | Method |
|----------|----------|----------|
| openrc | dinit | Direct |
| openrc | runit | Direct |
| openrc | s6 | Direct |
| dinit | openrc | Direct |
| runit | openrc | Direct |
| s6 | openrc | Direct |
| systemd | openrc | Direct |
| dinit | runit | Hub (via OpenRC) |
| dinit | s6 | Hub (via OpenRC) |
| runit | dinit | Hub (via OpenRC) |
| runit | s6 | Hub (via OpenRC) |
| s6 | dinit | Hub (via OpenRC) |
| s6 | runit | Hub (via OpenRC) |

> **Hub Pattern:**  
> Non-OpenRC migrations are performed through OpenRC automatically. This
> eliminates the need for dedicated migration scripts for every possible init
> pair.

---

## What Gets Migrated

- Full removal of the current init system
- Full installation of the target init system
- Service mapping for known services
- Custom services backed up to `/root/init-backup-*/`

---

## What Does NOT Get Migrated

- Custom services not owned by any package
  - Backed up to `/root/init-backup-*/`
- One-shot scripts
- User-created runit service directories
- User-created dinit service definitions
- User-created s6 service directories

---

# Desktop Environments

All supported desktop environments and window managers can be migrated in any
direction.

Migration is handled by four generic scripts:

| Script | Purpose |
|----------|----------|
| `any-to.sh` | Detect current desktop and prompt for target |
| `none-to.sh` | Install a desktop environment on a headless system |
| `any-to-none.sh` | Remove all desktop packages |
| `common.sh` | Generic fallback for any migration pair |

---

## What Gets Migrated

- Full removal of the current desktop environment
- Full installation of the target desktop environment
- Display manager selection:
  - SDDM
  - LightDM
  - None
- Display stack selection:
  - Xorg
  - Wayland
- Audio stack selection:
  - PipeWire
  - PulseAudio
  - None
- Network stack selection:
  - NetworkManager
  - dhcpcd + iwd
  - ConnMan
  - None
- Extra packages (optional checklist):
  - git, flatpak, fastfetch, firewalld, bluez, zram-tools
  - fzf, zoxide, starship, eza, btop, htop, nvtop, tmux
  - nano, vim, neovim, micro, helix
  - firefox, chromium, qutebrowser
  - ranger, lf, nnn, thunar
  - alacritty, kitty, foot
  - mpv, feh

All display manager, network, and audio packages are installed with the
correct init-specific suffixes (e.g. `sddm-dinit`, `networkmanager-openrc`).

---

## What Gets Backed Up

For all local users:

- `~/.config`
- `~/.local`
- `~/.cache`

System configuration:

- `/etc/sddm.conf.d`
- `/etc/lightdm`
- `/etc/X11/xorg.conf.d`
- `/etc/NetworkManager`
- `/etc/iwd`
- `/etc/dhcpcd.conf`

---

# Warnings

## Init Migration

- A reboot is required after migration.
- If the system fails to boot:
  1. Select the previous kernel from your bootloader.
  2. Reinstall the previous init system.

## Desktop Migration

- Running a migration from an active X11 or Wayland session may cause
  instability.
- It is strongly recommended to perform migrations from:
  - A TTY
  - The Artix live ISO

## ATA (Arch to Artix)

- **Make a full system backup before proceeding.**
- This is an experimental feature.
- Some systemd features have no direct Artix equivalent.
- AUR packages that depend on systemd may fail to reinstall.
- Snap packages will not function after migration.
- Always have a bootable Artix ISO ready in case manual repair is needed.

---

# Migration Scripts

All pair-specific migration scripts follow the same pattern. 
Generic scripts (`any-to.sh`, `none-to.sh`, `any-to-none.sh`) detect the
current desktop environment automatically and prompt for the target.

To add a new desktop environment or window manager:

1. Add its package list to `DE_PACKAGES` in `common.sh`
2. Add its default display manager to `DE_DISPLAY_MANAGER` in `common.sh`
3. Create a pair script if a direct migration path is desired (optional)
4. The generic scripts handle all other combinations automatically

---

## Custom Services

- Custom services always require manual review after migration.

## Backups

- Backups are stored under `/root/` with timestamps.
- ATA backups are stored under `/arch-migration-backup-YYYYMMDD-HHMMSS/`.
- Backups are **not restored automatically** for init and desktop migrations.
- ATA automatically restores user data and selected configurations.
- Manual restoration is available if needed.

---

## Summary

### ATA (Arch to Artix)

- Full system conversion from Arch Linux to Artix
- Preserves user data, credentials, configurations, and installed software
- Converts systemd-specific components automatically where possible
- Backs up everything before touching anything
- Experimental — always have a backup and a bootable Artix ISO

### Init Migration

- Supports all 16 init system combinations
- Preserves known services with automatic mapping
- Backs up unsupported custom services
- Uses an OpenRC hub model for non-direct conversions

### Desktop Migration

- Supports migration between any of the 13 supported desktop environments
  and window managers
- Preserves user configuration through automatic backups
- Allows interactive selection of display manager, display stack, audio
  stack, and network stack
- Allows optional selection of extra packages to install
- All packages are installed with correct init-specific suffixes
- Supports installation, replacement, or complete removal of graphical
  environments