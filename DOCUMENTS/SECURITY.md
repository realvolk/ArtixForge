# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in ArtixForge, please report it privately
to **realvolk** via a private GitHub security advisory or email.

Do not open a public issue for security issues.

## Supported Versions

| Version | Supported |
|---------|-----------|
| v9.4.0.6 | Latest Commits |
| v9.1.1.4 | Latest Stable release |
| < v9.1.1.4 | No |

## Scope

Security concerns include, but are not limited to:

- Password or passphrase exposure in logs, temporary files, or process listings
- Unsafe handling of LUKS passphrases (storage in memory, passing to `cryptsetup`)
- LUKS + LVM combinations where encryption boundaries are incorrectly configured
- LUKS containers created without proper formatting (`luksFormat` bypass)
- LUKS keyfile exposure — keyfile stored in initramfs on encrypted partition, never on unencrypted storage
- Privilege escalation within the installer or the resulting system
- Unsafe package downloads (missing or weak checksum verification)
- Source-compiled packages that introduce vulnerabilities via untrusted upstream sources
- Recipe self-healing fetching from untrusted or unverified upstream URLs
- BusyBox init configurations that leave the system insecure (unprotected ttys, weak shutdown)
- UKI images signed with keys that are not properly protected
- `doas` or `sudo` misconfiguration that grants unintended access
- Custom coreutils recipes that replace security-sensitive binaries (`su`, `passwd`, `mount`)
- State files (`state.conf`, `artix-installer.conf`) that may contain sensitive configuration
- Encrypted state presets — passphrase handling, GPG invocation, decrypted temp files
- Per-user dotfiles repositories — cloning untrusted repos during installation
- Post-install scripts (`POST_INSTALL_SCRIPT`) — running user-provided code as root
- One-shot post-install services (`POST_INSTALL_ONESHOT`) — self-destructing service files that run as root on first boot
- Recovery mode operations that mount, repair, or modify an existing installation
- Recovery mode auto-detection exposing system configuration details
- Rootkit scanning results that may reveal sensitive system information
- `rsync` usage during package installation potentially following unsafe symlinks
- Untrusted recovery: rootkit and malware scan results stored in /tmp
- Filesystem repair: unmounting and modifying the root partition with fsck/xfs_repair/btrfs check
- Third-party repositories (Chaotic-AUR, CachyOS, ARMtix) used during installation — packages are verified where possible
- ATA migration backup directory (`/arch-migration-backup-*`) containing full system state, credentials, and journal exports — must be root-only
- ATA network credential handling — WiFi passwords and NM connections extracted from systemd-networkd, restored with proper 600 permissions
- ATA systemd-homed LUKS images — unlocked with user password, data migrated, original images left in place
- ATA AUR batch reinstall — packages reinstalled from AUR via third-party helper; untrusted PKGBUILDs may execute arbitrary code
- ATA package mapping queries — local pacman database only; no external API calls for version comparison
- ATA systemd-boot → GRUB conversion — EFI boot entries modified; old entries removed via efibootmgr
- gum TUI transport — interactive widgets called directly via `/dev/tty`; passwords from `tui_password` and `tui_password_confirm` pass through gum's stdout, never written to temp files
- gum checklist output — newline-separated results parsed with whitespace stripping before use; `tr -d '[]"'` applied at consumption points to prevent artifact injection into system commands (`useradd -G`, `state_set`)
- Password handling — user and root passwords are hashed with `openssl passwd -6` before being stored to `state.conf`. Plaintext passwords never touch the state file or disk. LUKS passphrases are stored plaintext (required by `cryptsetup`) in the state file, which lives on tmpfs and is lost on reboot
- Bug report tarball — contains install log and state file; state file may contain password hashes and LUKS passphrases. The tarball is written to `/tmp` with default permissions and the user is warned to include it only when reporting issues

## Best Practices

- ArtixForge never writes plaintext passwords to disk. Passwords are hashed with `openssl passwd -6` before being passed to the target system.
- LUKS passphrases are held in memory only during the installation and are not persisted.
- LUKS containers are properly formatted with `luksFormat --type luks2 --pbkdf pbkdf2` for GRUB compatibility.
- LUKS keyfile (`/crypto_keyfile.bin`) is embedded in initramfs with `chmod 000` permissions. It resides only in the initramfs image on the encrypted root partition and is never written to unencrypted storage.
- Recipe sources should use verified checksums. The `SKIP` placeholder is for development only and should never appear in published recipes.
- Recipe self-healing only fetches version information from the same upstream domain as the original recipe source. New URLs are not blindly trusted.
- The installer does not expose network services during installation. Any network configuration (WiFi passwords, static IPs) is applied to the target system, not the live environment.
- Third-party repository signing keys are imported from official sources where available.
- Package installation uses `rsync --keep-dirlinks` to prevent symlink traversal attacks when writing to the target filesystem.
- Post-installation, `anvil` runs with root privileges. Users should audit recipes before building, especially those obtained from third-party sources.
- The installer's state directory (`/tmp/artix-installer/`) lives on a tmpfs and is lost on reboot. The target configuration file (`/mnt/etc/artix-installer.conf`) is shredded or removed during the finalize stage.
- Recovery mode requires explicit user confirmation before modifying any system files. Detection is read-only until the user chooses a repair action.
- Encrypted state presets use GPG symmetric encryption with AES256. The passphrase is passed via `--passphrase-fd 3`, never on the command line. Decrypted content is written to temp files, sourced, and shredded. The passphrase is never stored.
- Per-user dotfiles repositories are cloned from user-provided URLs. The installer does not inspect the contents. Users should only provide URLs they trust.
- Post-install scripts run as root inside the target chroot. The installer copies the script to the target but does not inspect or sanitize it. Users must provide scripts they trust.
- One-shot post-install services run as root on first boot. The service file self-destructs on success and retries on failure. The command is stored in the service file and visible to root.
- gum widget transport reads input from `/dev/tty` directly. Passwords pass through gum's stdout, never through temp files. No widget data is written to disk.
- The bug report tarball can contain sensitive data (password hashes, LUKS passphrases, state file). It is written to `/tmp` with restrictive permissions where possible. Users should be aware of the contents before sharing.
- The advanced features gate requires root password for Recovery, Power User, Migration, and ISO modes. This prevents unauthorized access on shared systems.

### ATA Migration Security

- The ATA backup directory is created with `chmod 700`. Only root can access it.
- Network credentials extracted from systemd-networkd, NetworkManager, iwd, and
  wpa_supplicant configs are stored in an isolated subdirectory with `chmod -R 700`
  during the backup phase. When restored to the target system, credential files
  receive `chmod 600`.
- The ATA backup is selective: `.cache`, flatpak/docker/container storage,
  thumbnails, and build caches are excluded. This reduces the attack surface of
  the backup and prevents sensitive VM/container data from being copied.
- systemd-homed LUKS images are unlocked with the user's password (provided at
  migration time), mounted temporarily, and data is copied to standard `/home`.
  The mapper is closed and the temporary mount removed. Original LUKS home images
  are not deleted — the user must remove them manually.
- systemd journal exports are written as plaintext to the backup directory. Users
  should delete the backup after verifying the migration if journal contents are
  sensitive.
- AUR batch reinstall uses the chosen AUR helper (paru/yay) in `--noconfirm` mode.
  This downloads and executes PKGBUILDs from the AUR. Users should only opt into
  this if they trust their installed AUR packages.
- systemd-boot EFI entries are removed via `efibootmgr` only after GRUB is
  successfully installed and `grub.cfg` is generated. The old `systemd-boot`
  binaries on the ESP are left in place (inert without the EFI entry) for manual
  cleanup.
- The ATA migration does not transmit any data over the network beyond standard
  pacman operations (package downloads from Artix mirrors) and AUR helper
  operations (if opted in). The system audit and package mapping use only local
  queries.