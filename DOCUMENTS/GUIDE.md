# ArtixForge — Installation Guide

Welcome! This guide explains every option you'll see in the installer.
Don't worry if you don't know what something means – that's what this is for.

---

## 1. Installation Interface

ArtixForge uses a **Terminal UI (TUI)** built on `gum`. The TUI runs in
any terminal and is fully keyboard-driven.

The interface presents sequential menus with clear titles and current values.
At any point you can see what's been configured and make changes.

If you boot an ArtixForge-generated ISO with a desktop environment, open a
terminal and run `sudo ./install` — you'll get the same TUI.

---

## 2. Installation Mode

| Mode | What it does | When to use it |
|------|-------------|----------------|
| Installation | Full guided setup, step by step | First time, clean disk |
| Resume | Continue an interrupted install | The installer crashed or you rebooted |
| Recovery | Scan `/mnt` for an existing system, auto-detect issues, repair | Fixing a damaged installation with smart detection |
| Power User | Build packages from source, Gentoo-style | You want full control over compilation |
| Build ISO | Create a custom Artix live ISO from a profile | You want a personalised rescue or installation disk |
| System Migration | Convert init system or desktop environment on an installed system | Change your mind after installation without reinstalling |

If you're new to Linux or Artix, **Installation** is the simplest way to get a working system.

Advanced modes (Recovery, Power User, Migration, ISO) require the root password.

---

## 3. Disk Selection

Choose the physical drive where Artix will be installed.
`/dev/sda` is usually your primary disk, `/dev/nvme0n1` is an NVMe SSD.

**Warning:** Everything on the selected disk will be permanently erased.

If your disk is an NVMe drive, the installer will automatically enable the `discard` mount option for SSDs where supported. No extra configuration is needed.

---

## 4. Init System

The init system is the first program the kernel starts; it manages all other services.

| Init | Style | Notes |
|------|-------|-------|
| OpenRC | Traditional, well-tested | Artix default – familiar to most users |
| runit | Minimal, fast | Very lightweight, simple design |
| dinit | Modern, parallel startup | Good performance on newer hardware |
| s6 | Process supervision focus | Powerful, but steeper learning curve |
| BusyBox | Ultra-minimal, source-built | Only for experienced users; you'll need to write your own service scripts |

Each init system works well; the choice largely depends on how much control you want and how you prefer to manage services.

---

## 5. Filesystem

Determines how data is organised on the disk.

| Filesystem | Strengths | Weaknesses |
|------------|-----------|------------|
| ext4 | Stable, fast, universally supported | No snapshots or compression |
| btrfs | Snapshots, compression, subvolumes | Can be slightly slower |
| xfs | Excellent for large files, quick recovery | Cannot be shrunk |
| f2fs | Optimised for flash storage (SSD, eMMC) | Not suitable for HDDs |

If you don't have a specific reason to choose otherwise, ext4 is a reliable, zero-maintenance option. btrfs is a great choice if you want snapshots and compression.

---

## 6. Bootloader

The software that loads your operating system when you switch on the computer.

| Bootloader | Description |
|------------|-------------|
| GRUB | The most widely-used bootloader; supports dual-boot, theming, and encrypted partitions. **If you're unsure, use GRUB.** |
| rEFInd | A graphical boot manager that auto-detects installed operating systems. |
| EFIStub | Boots the Linux kernel directly from your UEFI firmware – no separate bootloader needed. Very fast, but requires compatible firmware and manual setup. |
| Limine | Modern, portable, multiprotocol bootloader. Clean config syntax, BTRFS snapshot booting, Windows chainloading. UEFI-only on ArtixForge. |
| U-Boot | ARM board bootloader for aarch64 targets. |

All choices work; GRUB is the most forgiving for beginners and the easiest to troubleshoot.
Limine is a great choice if you want a clean, modern config and BTRFS rollback support.

**UKI (Unified Kernel Image)** is not a bootloader, but an optional feature that bundles the kernel,
initramfs and command line into a single `.efi` file. It works with GRUB, Limine, or EFIStub.
Enable it on the Bootloader page if you want a Secure-Boot-friendly single file.

---

## 7. Kernel

The core of the operating system.

| Kernel | Description | Stability |
|--------|-------------|-----------|
| linux | Stable, general-purpose kernel | Very stable |
| linux-zen | Tweaked for desktop responsiveness | Stable |
| linux-lts | Long-term support; receives only security fixes | Very stable |
| linux-hardened | Security-focused with extra protections | Stable |
| linux-libre | Completely free software (removes non-free firmware) | **May break hardware** – Wi-Fi, Bluetooth, NVIDIA often fail |
| linux-cachyos-* | Performance-optimised kernels | Generally stable |
| linux-bazzite-bin | Gaming-focused, includes extra patches | May occasionally have issues |
| xanmod | Aggressive performance tweaks | May be less stable than mainline |
| tkg | Fully customisable; build with your own configuration | Stability depends entirely on your choices |
| linux-aarch64 | ARM64 kernel from ARMtix | Stable |
| linux-aarch64-lts | ARM64 LTS kernel | Very stable |
| linux-radxa | ARM64 kernel for Radxa boards | Stable |

Standard `linux` is a safe choice. If you do a lot of interactive work or gaming, `linux-zen` or `linux-cachyos-*` may feel snappier. Avoid `linux-libre` unless you are certain your hardware works without proprietary firmware.

---

## 8. Desktop Environment

Your graphical interface.

| DE / WM | Type | Notes |
|---------|------|-------|
| KDE Plasma | Full desktop | Feature-rich, customisable |
| XFCE | Full desktop | Lightweight, traditional |
| LXQt | Full desktop | Very lightweight, modular |
| LXDE | Full desktop | Even lighter, older |
| Cinnamon | Full desktop | Traditional, Windows-like |
| Budgie | Full desktop | Modern, clean design |
| Moksha | Full desktop | Enlightenment-based, community |
| COSMIC | Full desktop | Rust-based, alpha software |
| Hyprland | Wayland compositor | Modern, eye-candy, requires Arch repos |
| Sway | Wayland compositor | i3-compatible, stable |
| Niri | Wayland compositor | Scrollable tiling, experimental |
| i3 | Tiling window manager | Keyboard-driven, very light |
| dwm | Tiling window manager | Minimal, configured via source code |
| IceWM | Stacking window manager | Extremely light, familiar look |
| MangoWM | Wayland compositor | Lightweight, active development |
| MATE | Full desktop | Traditional GNOME 2 fork, actively maintained |
| none | No desktop | You'll start from a terminal |

All of these can produce a comfortable environment. KDE and XFCE are the most popular; Hyprland and Sway are great if you like tinkering.

---

## 9. Display Stack

ArtixForge supports **X.Org** as the display stack. Two variants are available:
**X.Org** (standard) and **X.Org (tearfree)**, which enables the TearFree option by default for the modesetting driver and eliminates screen tearing on systems without a compositor.

Wayland compositors are selected as desktop environments directly, and do not use this option.

---

## 10. Network Stack

How your system connects to the internet.

| Stack | Description |
|-------|-------------|
| NetworkManager | Auto-connects, widely used, easy to manage |
| dhcpcd + iwd | Lightweight, fast, manual configuration |
| ConnMan | Compact, designed for embedded use |
| None | You'll set up networking manually after boot |

NetworkManager is the easiest to live with on a daily-use machine.

---

## 11. Audio Stack

| Stack | Description |
|-------|-------------|
| PipeWire | Modern, low-latency, replaces both PulseAudio and JACK |
| PulseAudio | Older, well-tested, still fully functional |
| None | No sound |

PipeWire is now the standard on most distributions and works great.

---

## 12. Privilege Escalation

How you run commands as root.

| Tool | Description |
|------|-------------|
| sudo | The de-facto standard; feature-rich, well-known |
| doas | Minimalist, inspired by OpenBSD; simpler syntax |

Both are secure. `sudo` is more familiar; `doas` is loved by minimalists.

## 12a. User Accounts

ArtixForge lets you create multiple user accounts during installation.

| Option | What it does |
|--------|-------------|
| Add User | Create a new user with username, password, shell, groups, sudo access, DE, dotfiles |
| Edit User | Modify an existing user's details |
| Remove User | Delete a user account |

For each user you can configure:

- **Username** — must start with a letter, no spaces
- **Password** — hashed before storage, never written to disk in plaintext
- **Shell** — bash, zsh, or fish
- **Groups** — wheel (admin), audio, video, storage, lp, network, optical, scanner, users
- **Sudo access** — yes/no, applies to sudo or doas depending on your privilege escalation choice
- **Desktop environment** — per-user DE override, falls back to system default
- **Dotfiles repository** — URL to a git repo cloned and installed into `~/.config`

At least one user account is required. The first user's name is also used
for AUR package builds and source compilation if those features are enabled.

**Root password** is set separately from user accounts. You can skip setting
a root password if you prefer to use sudo for all administrative tasks.

---

## 13. Coreutils (Power User only)

The basic command-line tools (`ls`, `cp`, `cat`, …).

| Implementation | Description |
|---------------|-------------|
| GNU | Full-featured, standard on most Linux systems |
| BusyBox | Lightweight, fewer options, smaller footprint |
| uutils | Rust rewrite of GNU coreutils, modern |
| ArtixForge | Our own debloated set (based on BusyBox with selectable features) |
| Custom | Write your own recipe – full control |

GNU coreutils are the safest choice for compatibility with scripts and existing habits. BusyBox is perfect for minimal systems. uutils is exciting but still maturing.

---

## 14. Disk Encryption (LUKS)

Encrypts your entire root partition. Requires a passphrase at boot.

LUKS works well with any filesystem. If you also enable LVM, the encryption wraps around the LVM physical volume – this combination (LUKS on LVM) is powerful but the bootloader configuration must be correct, especially with GRUB or EFIStub. The installer handles this automatically, but if you manually edit things later, be careful.

---

## 15. Logical Volume Management (LVM)

Allows you to resize, move, and combine partitions easily without rebooting.

LVM is especially useful on servers or if you need to resize partitions frequently. It adds a small amount of complexity but is transparent once set up.

---

## 16. Power User Mode – Source Compilation

If you selected Power User mode, you can compile packages from source instead of using pre-built binaries. This gives you:

- Custom optimisation flags for your CPU
- The ability to enable/disable specific features
- A kernel built exactly for your hardware (using `localmodconfig` for reliable module detection)

**Warning:** Compiling from source is time-consuming and can fail if dependencies are missing. The installer offers a "fallback kernel" option so you can install a binary kernel if the compilation fails. Be especially careful if you choose to build `glibc` (the C library) – a broken glibc will make your system unbootable.

---

## 16.1. Community Recipes

ArtixForge can download additional recipes from the community repository at
[ArtixForge-recipes](https://github.com/realvolk/ArtixForge-recipes).

Use `anvil sync` to pull the latest recipe list and download new recipes.
By default, only tested OFFICIAL recipes are included. You can enable
COMMUNITY recipes through the "Manage recipe sections" option in `anvil --tui`.

To contribute your own recipes, see the [ArtixForge-recipes](https://github.com/realvolk/ArtixForge-recipes) repository.

If a source download fails during a build (404, checksum mismatch),
ArtixForge can automatically detect newer upstream versions and
heal the recipe. Select "Heal recipe" from the build failure menu.

---

## 17. Quick Install Profiles

Instead of answering every question, you can pick a pre-made profile:

- **Base** – No desktop, minimal system.
- **Plasma** – KDE Plasma desktop.
- **XFCE** – XFCE4 desktop.
- **Cinnamon** – Cinnamon desktop.
- **LXQt** – LXQt desktop.
- **Community GTK** – Community GTK ISO package set.
- **Community Qt** – Community Qt ISO package set.
- **Gaming** – Plasma, linux-zen, Steam, Lutris, DOSBox, MangoHud, GameMode.
- **Server** – No desktop, firewalld, tmux.
- **Minimal** – Bare system, no extras.

Every profile lets you choose your init system (dinit, openrc, runit, s6).

Profiles are a starting point; you can still tweak anything afterwards in the main menu.

You can also **load a custom profile** from a saved configuration file
(e.g., `/etc/artixforge-profile.conf` from a previous installation).

---

## 18. ISO Generation (Build ISO mode)

ArtixForge can build a fully customised Artix live ISO.

When you select **Build ISO** from the main menu, you will be asked:

| Option | What it does |
|--------|-------------|
| Live Desktop | Includes a full desktop environment (KDE, XFCE, etc.) and the ArtixForge installer on the desktop. Boot into a graphical environment, then open a terminal and run the installer. |
| Installer | Boots directly into the ArtixForge TUI. No desktop, no extra packages. Minimal and fast. |

After choosing the boot mode, you can either:

- **Pick a Quick Profile** – Base, Plasma, XFCE, Cinnamon, LXQt, Community GTK, Community Qt, Gaming, Server, Minimal.
- **Customise everything** – Same detailed configuration as a normal installation.
- **Load a saved profile** – Reuse a configuration from a previous installation.

You can also add extra packages to the ISO and choose **Offline ISO** to bundle all packages
so the installer can run without an internet connection.

The built ISO will be placed in `~/ArtixForge-ISO/` along with a build log.
You can burn it to a USB stick or boot it in a virtual machine.

---

## 19. System Migration (Convert init, desktop, or Arch Linux)

If you already have Artix installed and want to change your init system or desktop environment
**without reinstalling**, select **System Migration** from the main menu (run from a live ISO
or from within the installed system).

Migration now includes **explicit target selection** — you'll be asked whether to
auto-mount, use an already-mounted target, or specify a custom mount point.

### Init Migration

Convert between OpenRC, runit, dinit, s6, and even systemd (if you have Arch repos enabled).

The migration will:

- Back up your current init configuration to `/root/init-backup-*`
- Detect all enabled services and map them to the new init system
- Handle custom (non-package) services by saving them separately
- Install the new init packages and enable the appropriate services

Not all service names are identical across init systems. ArtixForge includes mapping tables
for common services; for less common ones, you will receive a warning and the service will
need to be migrated manually.

### Desktop Migration

Convert between any of the supported desktop environments and window managers.

The migration will:

- Back up your user configurations (`.config` and `.local/share` — never `.cache`)
- Dynamically discover installed packages for the source DE
- Remove the old desktop packages with `pacman -Rdd` (no dependency cascade)
- Show you orphaned packages in a checklist for optional removal
- Install the new desktop and its recommended packages
- Optionally change the display manager, display stack, audio stack, and network stack

After migration, reboot to start the new environment.

### ATA (Arch to Artix) — Experimental

Convert an existing Arch Linux installation to Artix Linux without reinstalling.

**This feature is experimental.** Make a full system backup before proceeding.

The migration will:

- Audit your entire system (packages, services, users, configs, credentials)
- Back up everything to `/arch-migration-backup-YYYYMMDD-HHMMSS/` with selective rsync (no caches)
- Convert systemd-specific components:
  - Services → init-specific equivalents
  - Timers → cron jobs (OnCalendar and basic monotonic)
  - PAM modules (`pam_systemd.so` → `pam_elogind.so`)
  - mkinitcpio hooks (`systemd` → `udev`, `sd-encrypt` → `encrypt`)
  - DNS resolver (stub replaced)
  - pacman hooks (systemd-dependent ones quarantined)
  - crypttab entries → kernel command line parameters
  - systemd-boot → GRUB (auto-install)
  - systemd-homed users → standard `/home` users
  - systemd `--user` services → XDG autostart entries
- Preserve and restore:
  - All user files and home directories
  - WiFi passwords and network configurations
  - SSH keys and host configs
  - Firewall rules and cron jobs
  - Flatpaks, AppImages, and Docker containers
- Reinstall all packages from Artix repositories
- Reinstall your desktop environment from Artix repos
- Attempt batch reinstall of AUR packages with your chosen helper
- Rebuild DKMS modules and initramfs

**What does NOT migrate automatically:**

- Snap packages (require systemd — will not function on Artix)
- Complex monotonic systemd timers (best-effort loop script used)
- Custom systemd unit files (backed up, not converted)
- systemd-networkd configurations (backed up, manual NM/ConnMan conversion)

After migration, reboot to start Artix. AUR packages that failed to reinstall
are listed in the backup directory for manual follow-up.

---

## 20. Sanity Warnings

Before the installation begins, the installer will warn you about potentially unsafe choices, such as:

- No fallback kernel when building your own
- No desktop environment selected
- Non-GNU coreutils
- BusyBox init
- No privilege escalation tool
- Offline mode

Read these warnings carefully – they exist because the combination you chose may require manual intervention after installation.

---

## 21. Recovery Mode

If your system fails to boot or behaves unexpectedly, ArtixForge can help.
Boot the live ISO, mount your root partition to `/mnt`, and select
**Recovery** from the main menu.

Recovery will automatically detect your system's configuration:

- Init system, filesystem, bootloader, kernel, desktop environment
- Display manager, network stack, audio stack, coreutils
- Whether LUKS, LVM, UKI, or Power User mode were used
- Broken fstab entries, missing kernels, stale pacman locks
- Packages with missing or corrupted files

You can then choose:

| Option | What it does |
|--------|-------------|
| View system status | Display the full detection report |
| Repair detected issues | Surgically fix only what's broken (fstab, pacman, boot, kernel) |
| Fix everything (nuclear) | Rebuild fstab, reinstall base packages, reinstall kernel, regenerate initramfs and GRUB — everything at once |
| Scan for rootkits | Run rkhunter against the installation |
| Full reinstall | Continue with a fresh installation |
| Repair filesystem corruption | Check and optionally repair the root filesystem (safe or destructive) |
| Untrusted Recovery | Rootkit scan, malware indicator check, optional ClamAV |

After installation, you can also run `anvil recovery` from the installed
system to check and repair source-built packages.

**Filesystem repair** will unmount your root partition and run filesystem-specific
tools. Choose "Safe" for a non-destructive check; "Destructive" to attempt aggressive
repairs that may discard corrupted data. Always back up first.

**Untrusted Recovery** is a read-only threat scan. It does not modify anything,
but the scans themselves may trigger anti-malware alerts on a running system.

---

## Common Questions

**Will this erase my other operating systems?**
Only if you choose the wrong disk. The installer wipes the entire disk you select, so be sure it's the right one.

**Can I dual-boot?**
Yes. Use Manual mode, create partitions for Artix alongside your existing OS, and GRUB will usually detect other systems automatically.

**What if the installer stops or crashes?**
Reboot, start the installer again, and pick **Resume** from the main menu. It will continue from the last completed stage.

**Can I create multiple user accounts?**
Yes. The installer lets you add, edit, and remove users with custom groups, shells, sudo access, per-user DE, and dotfiles. At least one user is required.

**Where can I get help?**
Open an issue on [GitHub](https://github.com/realvolk/ArtixForge/issues) or visit the Artix community forums.

---

## Quick Reference

| If you want… | Consider… |
|--------------|-----------|
| A simple, stable desktop | Installation, ext4, GRUB, linux, KDE, NetworkManager, PipeWire, sudo |
| A snappy gaming machine | Gaming profile, linux-zen, dinit |
| A lightweight laptop | XFCE or LXQt, linux-lts |
| A headless server | Server profile, no desktop, dhcpcd+iwd, doas, LVM |
| A minimal, embedded system | Power User, BusyBox init, linux-lts, BusyBox coreutils |
| Total customisation | Power User, build your own kernel, choose every component yourself |
| A personalised live ISO | Build ISO mode, pick a Quick Profile, enable offline mode |

---

Remember: the best choice is the one that fits *your* needs. This guide is here to explain, not to prescribe. If something goes wrong, the community is here to help.