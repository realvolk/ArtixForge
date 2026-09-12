# Privacy Policy

**Artix Installer collects nothing.**

The installer runs entirely on your local machine. It does not:

- Send telemetry or usage data anywhere
- Phone home with your hardware information
- Log your installation choices to any remote server
- Include any analytics, tracking, or monitoring code
- Store your passwords, passphrases, or personal data beyond what is needed to complete the installation

## What Artix Installer stores locally (and how it's handled)

| Data | Location | Fate |
|------|----------|------|
| Installation configuration | `/tmp/artix-installer/state.conf` | Deleted on reboot (tmpfs) |
| Stage progress markers | `/tmp/artix-installer/stages/` | Deleted on reboot (tmpfs) |
| User password hashes | `/tmp/artix-installer/state.conf` (SHA-512 crypt hash) | Deleted on reboot (tmpfs) |
| LUKS passphrase | Memory only, never written to disk | Gone when installer exits |
| Target system config | `/mnt/etc/artix-installer.conf` | Shredded or removed during finalize stage |
| Quick Profile save | `/mnt/etc/artixforge-profile.conf` | Remains on installed system for reuse |
| Installer log | `/mnt/var/log/artix-installer.log` | Remains on the installed system for debugging |
| Build logs (Power User) | `/mnt/artix-poweruser/build/logs/` | Remains on the installed system for debugging |
| Recipe database | `/mnt/usr/share/artix-poweruser/db/local.db` | Remains on the installed system |
| Recipe git history | `/mnt/usr/share/artix-poweruser/recipes/.git/` | Remains on the installed system |
| Per-package feature flags | `/mnt/etc/anvil/package.use/` | Remains on the installed system |
| User patch stacks | `/mnt/etc/anvil/patches/` | Remains on the installed system |
| Kernel config fragments | `/mnt/etc/anvil/kernel.d/` | Remains on the installed system |
| Recovery detection data | `/tmp/artix-installer/state.conf` (reconstructed) | Deleted on reboot (tmpfs) |
| ATA migration backup | `/arch-migration-backup-YYYYMMDD-HHMMSS/` | Stays on disk (root-only, chmod 700); user must delete manually |
| Encrypted state presets | `presets/*.enc` | GPG symmetric (AES256); decrypted only in memory or temp files when loaded |
| Bug report tarball | `/tmp/artixforge-bugreport-*.tar.gz` | Contains install log, state, debug trace, post-stage log, retry log. Stays in /tmp until user deletes or reboot (tmpfs) |
| Host-side logs (debug, post-stage, retry) | `/tmp/artix-installer/logs/` | Deleted on reboot (tmpfs) |
| Post-install script copy | `/root/<script>` on target system | Remains on installed system; user must delete manually if sensitive |
| One-shot service command | Per-init service file on target system | Self-destructs on success; retries on failure |
| Per-user dotfiles | `~/.config` and home directory | Cloned from user-provided URL; remains in user home |

The installed system itself contains no ArtixForge-specific data collection. The installer
removes its own configuration from the target before finishing.

### ATA (Arch to Artix) Migration

The ATA migration performs a full system audit and backup before converting an
Arch Linux installation to Artix. The following data is handled:

| Data | Location | Fate |
|------|----------|------|
| System audit lists | `/tmp/ata-*.txt` | Deleted on reboot (tmpfs) |
| Full system backup | `/arch-migration-backup-YYYYMMDD-HHMMSS/` | Remains on disk (root-only, chmod 700) |
| Network credentials (WiFi PSKs, NM connections) | Backup subdirectory, then restored to `/etc/NetworkManager/`, `/var/lib/iwd/`, `/etc/wpa_supplicant/` | Credential files on target are chmod 600; raw backup retained in backup dir |
| systemd journal export | Backup directory | Plaintext journal retained in backup dir |
| systemd-homed user data | Decrypted and migrated to `/home/<user>/` | Original LUKS home images left in place; user must delete manually |
| AUR package list | Backup directory lists | Retained for reference |
| Flatpak app list | Backup directory lists | Retained for reference |

The ATA backup directory is created with `chmod 700` (root access only). Network
credential subdirectories within the backup are also `chmod 700`. When credentials
are restored to the target system, files are written with `chmod 600`. The raw
backup is retained so the user can verify what was migrated and delete it manually.

The ATA backup is selective: `.cache`, flatpak/docker/container storage,
thumbnails, and build caches are excluded. Only dotfiles, configs, and local
share data are copied.

No data leaves the local machine during ATA migration. The package mapping feature
queries only the local pacman database and configured repositories — no external
API calls are made for system audit or conversion.

## Network access

ArtixForge downloads packages from Artix Linux mirrors and source tarballs from
upstream URLs specified in recipes. These are standard package manager operations
— the same as running `pacman -Syu` or `git clone`. No additional network requests
are made.

The recipe self-healing feature (`heal.bash`) may check upstream URLs (kernel.org,
GitHub API, or source directory listings) to detect newer versions when a download
fails. This only happens during an active build failure — never during normal operation.

The recovery mode rootkit scanner (`rkhunter`) downloads its database updates
from the rkhunter project servers when first run. This is the only optional
third-party network request outside of package management.

The state preset encryption uses local GPG only. No keys or passphrases are
transmitted anywhere. The encrypted preset file is local.

Post-install scripts (`POST_INSTALL_SCRIPT`) and one-shot services
(`POST_INSTALL_ONESHOT`) are user-provided. ArtixForge copies them to the target
system but does not inspect, transmit, or execute them outside the local
installation.

Per-user dotfiles repositories (`USER_${i}_DOTFILES`) are cloned from the URL
the user provides. This is the same as running `git clone` manually — the remote
server sees the same request it would see from any git client.

**gum:** the TUI toolkit makes no network connections. Interactive widgets run
locally via `/dev/tty`. No data leaves the process.

**anvil:** the Power User package manager makes network connections only for
recipe downloads (`anvil sync`, `anvil fetch-recipe`, `anvil fetch-all`),
source downloads during builds, and recipe self-healing during build failures.
These are standard `git clone` and `curl` operations. No telemetry.

**anvil trial:** downloads a source tarball from the user-provided URL to
generate a draft recipe. The URL is user-supplied and the download is
standard `curl`.

**anvil fetch-world:** resolves the full dependency tree from the world file
and downloads sources for each package. Same as `anvil fetch-all` but for
the full tree.

**anvil gc:** garbage collection is purely local — walks the dependency graph
from the world file, marks reachable artifacts, and removes unreachable ones.
No network access.

**anvil audit:** security audit reads local binary files with `readelf`.
No network access.

**anvil estimate:** reads local build statistics from `build/logs/stats/`.
No network access.

**anvil bootstrap:** builds the full world file into a target directory.
No network access beyond source downloads during builds.

**ARM cross-compilation:** downloads ARM kernel sources and toolchain packages
from Artix mirrors and ARMtix repository. Standard pacman operations.

## Third-party services

The installer does not integrate with any third-party analytics, monitoring,
or data collection services. Zero. None.

Chaotic-AUR, CachyOS, and ARMtix repositories may be configured during
installation if the user selects them. Package downloads from those
repositories are standard pacman operations. No additional data is
transmitted beyond the package requests themselves.

## Questions

If you have any questions about privacy, open an issue on
[GitHub](https://github.com/realvolk/ArtixForge/issues).