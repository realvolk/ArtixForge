# Changelog

## v9.4.0.2 (2026-09-10) — ArtixForge

### Fixed
- **LVM partition type code assignment** — `partition.sh` now sets the GPT type code to `8e00` (Linux LVM) using the known partition number instead of querying `lsblk -no PARTN`; the previous command produced `Could not change partition N's type code to !` when `lsblk` returned an empty or non-numeric value, silently failing the type code change

## v9.4.0.1 (2026-09-10) — ArtixForge

### Fixed
- **GRUB `dm-mod` module name** — replaced invalid GRUB module `dm-mod` with `dm`; the kernel module is `dm-mod.ko`, the GRUB module is `dm.mod`, and `dm` alone is correct in `--modules` and `GRUB_PRELOAD_MODULES`
- **GRUB module list restructured** — build `grub_modules` and `grub_preload` arrays conditionally based on `USE_LVM` and `USE_LUKS` instead of three separate if/elif branches
- **LUKS+LVM GRUB modules** — `cryptodisk` and `luks` are the correct GRUB modules for LUKS support; `lvm` for LVM; combination now yields `part_gpt part_msdos fat ext2 lvm cryptodisk luks`
- **Initramfs hook order for LUKS+LVM** — replaced fragile `sed` edits of `/etc/mkinitcpio.conf` with an `/etc/mkinitcpio.conf.d/artixforge-storage.conf` drop-in that declares the complete `HOOKS` array; eliminates pattern matching failures and guarantees `block encrypt lvm2 filesystems` order
- **Initramfs regeneration after hook changes** — `mkinitcpio -P` now runs immediately after the storage drop-in is written and fails hard if initramfs generation fails; previously the initramfs was baked into the UKI without `encrypt` or `lvm2` hooks, causing boot to drop to emergency shell with `device '/dev/vg0/root' not found`
- **Stale UKI EFI boot entries** — `bootloader.sh` now deletes existing `Artix Linux (UKI)` and `Artix Linux (UKI Signed)` entries scoped to the target ESP's PARTUUID before creating new ones; prevents duplicate entries across reinstall attempts
- **User JSON parsing** — `configure_users` and `state_save` now guard the `jq`-based user parsing behind a `^\[.*\]$` regex check; plain integer `USER_COUNT` values no longer trigger `jq: Cannot index number with number` errors; JSON array format still supported for backward and future FILLY compatibility
- **`recoverable_error` self-update** — detects current git branch before cloning, validates `install` exists in the fetched payload before wiping `${BASE_DIR}`, `chmod +x` after copy, and removed `sudo` from the exec (installer already runs as root)
- **Self-copy to `/tmp/artix-run`** — `rm -rf` before copy prevents stale runtime files when target directory already exists
- **`source_tree recovery` during install** — removed; recovery code no longer sources into installer context, which was shadowing `service_exists` with the recovery variant and causing `enable_service_boot lvm2` to return false for valid services

### Changed
- **Quick Profiles** — removed AUR-only packages (`heroic-games-launcher`, `fs-uae`, `antimicrox`, `openrgb`, `timidity++`) from Gaming profile
- **`tui_show_summary`** — rewritten with per-line `printf` calls; previous `printf -v` with multiline gum substitutions collapsed output to a single line
- **`tui_quick_install`** — now calls `tui_configure_users` for full multi-user flow with per-user DE and dotfiles support, replacing the legacy single-user functions whose data was discarded by `configure_users`
- **`*Community GTK*` / `*Community Qt*` case patterns** — quoted to prevent bash `case` syntax error from unquoted space in pattern
- **`recoverable_error` branch detection** — clones the current working branch instead of hardcoded `main`

## v9.4.0.0 (2026-09-09) — ArtixForge

### Added
- **State file linting** — `lint_state` validates required keys, disk existence, filesystem/init/bootloader/privilege escalation/display stack values, and user/root password presence before pipeline
- **State preset inheritance** — `state_load_preset` with one-level `BASE_STATE` support and relative path resolution
- **State templating** — `state_resolve_templates` resolves `${KEY}` references via bash indirect expansion, no eval, max 10 iterations
- **Encrypted state presets** — `state_encrypt_preset` and `state_decrypt_preset` with GPG AES256, magic header, passphrase via fd 3
- **Per-user desktop environments** — `USER_${i}_DE` state key, persisted through state, applied with fallback to system `WM_DE`, seat group for Wayland
- **Per-user dotfiles repositories** — `USER_${i}_DOTFILES` state key, `_clone_dotfiles` clones repo and installs configs
- **Post-install script injection** — `POST_INSTALL_SCRIPT` validated before pipeline, copied to target, run in chroot
- **One-shot post-install services** — `POST_INSTALL_ONESHOT` writes self-destructing per-init service that retries on failure
- **Bug report generator** — `_generate_bug_report` collects logs, state, stage markers, system info into tarball on failure
- **Advanced features gate** — `_verify_root_password` required for Recovery, Power User, Migration, ISO
- **Migration target selection** — `ensure_migration_root` in both DE and init migrations, prompts for auto-mount/already-mounted/custom mount, validates target, persists `MIG_ROOT`
- **DE migration dynamic package discovery** — `_installed_de_packages` queries installed packages by DE pattern
- **DE migration user-visible orphan removal** — `tui_checklist` for orphaned packages
- **ARM aarch64 support** — kernels, kernel config fragments, cross-compilation profiles, U-Boot bootloader, ARMtix repository
- **Power User feature flag system** — `feature_depends_*`, `feature_conflicts_*`, `flag_desc_*`, per-package flags in `/etc/anvil/package.use/`, conflict detection
- **Power User world file lifecycle** — `anvil world {status|add|remove|build|activate}`
- **Power User package management** — `anvil files`, `anvil verify`, `anvil remove`, `anvil log`, `anvil diff`, `anvil rollback-recipe`
- **Power User build infrastructure** — ccache, sub-packages, file inventory, build stats, parallel builds, isolated builds
- **Power User kernel config fragments** — `kconfig_fragments.bash` replaces monolithic `kconfig.bash`
- **Power User user patch stacks** — `/etc/anvil/patches/<pkgname>/`
- **Power User recipe generation** — `anvil trial <url>`
- **Power User garbage collection** — `anvil gc`
- **Power User security audit** — `anvil audit [pkg]` with PIE/RELRO/stack protector checks
- **Power User build estimate** — `anvil estimate`
- **Power User full-system bootstrap** — `anvil bootstrap [dir]`
- **Power User interactive build shell** — `anvil shell <pkg>`
- **Power User TKG binary kernel** — `basestrap_install_tkg_binary` downloads prebuilt TKG from GitHub releases
- **Power User TKG config generation** — `_tkg_write_config` writes `customization.cfg` from state keys
- **Installation preset saving** — save configuration as reusable preset after successful install
- **Post-install validation** — finalize stage runs recovery health checks before unmounting
- **Warnings collector** — `warn_collect` aggregates non-fatal warnings for final report

### Changed
- **License changed to IRX License 1.0** — replaced Forge Attribution License 1.0
- **GUI removed** — no `DISPLAY`/`WAYLAND_DISPLAY` check, no `--non-interactive` flag, TUI-only
- **SonicDE removed as target** — removed from DE arrays, TUI choices, ISO lists; detection preserved for migration away
- **xlibre removed as target** — removed from X_PACKAGES, TUI choices, ISO common.yaml, drivers; xorg only; detection preserved
- **Display stack simplified** — X.Org only
- **Quick Profiles rewritten** — Base, Plasma, XFCE, Cinnamon, LXQt, Community GTK, Community Qt, Gaming, Server, Minimal
- **DE migration `remove_packages`** — switched to `pacman -Rdd`, no dependency cascade
- **DE migration backup selective** — never copies `.cache` or `.local/cache`
- **Init migration service listing fixed** — dinit/runit/s6/systemd listing corrected
- **Init migration service mapping expanded** — `logind` → `elogind` in all tables, bare systemd names
- **Init migration `cold_reboot` fixed** — uses `${MIG_ROOT:-/}`
- **ATA backup selective** — rsync with excludes for caches, build dirs, container storage
- **ATA user service detection per-user** — iterates all users, not just root
- **ATA homed migration uses saved list** — reads `/tmp/ata-homed.txt`
- **ATA desktop detection lookup table** — associative array replaces elif chain
- **ATA `has_homed` persisted** — `ATA_HAS_HOMED` state key
- **ATA network credentials use actual interface** — queries `ip link`
- **ATA timer conversion fetches config once** — `systemctl cat` once per timer
- **ATA resolv.conf detection checks active systemd-resolved**
- **State migration keys persisted** — all migration and post-install keys in `state_save`
- **Multi-DE installation** — collects unique DEs from system and per-user keys, installs all in one transaction
- **CachyOS CPU detection by flags** — `/proc/cpuinfo` AVX2/AVX512 replaces ld-linux parsing
- **GRUB LVM modules array** — `--modules "part_gpt part_msdos fat lvm dm-mod ext2"`, `--removable`
- **Services soft-fail** — `enable_service` and `enable_service_boot` use `warn_collect` instead of error
- **Swap configuration expanded** — `none`, `partition`, `swapfile`, `zram`, `zswap`
- **BTRFS mount optimized** — `mount -o remount` instead of unmount/remount
- **Power User engine overhauled** — feature flags, world file, ccache, sub-packages, file inventory, stats
- **Power User profiles add GLOBAL_FEATURES** — default/safe/performance/hardened each declare feature defaults
- **anvil CLI expanded** — 30+ subcommands

### Removed
- **GUI backend** — `forge-gui`, `--non-interactive`, `scripts/noninteractive.sh`
- **SonicDE install path** — repo setup, DM install, service enable
- **xlibre install path** — all xlibre package references
- **`_cleanup_target_repo` in DE migration** — inline SonicDE cleanup only
- **`poweruser/lib/kconfig.bash`** — replaced by `kconfig_fragments.bash`

### Fixed
- **KDE→XFCE regression** — dynamic package discovery + `-Rdd` + selective backup
- **`install` bug report syntax error**
- **SonicDE and xlibre removed from migration targets** — detection preserved
- **Service listing per-init quirks** — dinit sed corruption, runit symlink filtering, s6 bundle listing
- **`cold_reboot` trailing slash**
- **ATA backup disk exhaustion** — caches no longer copied
- **ATA user services only root queried**
- **ATA homed detection after homectl removal**
- **ATA desktop detection false negatives**
- **ATA resume losing `has_homed`**
- **ATA hardcoded wireless interface**
- **ATA timer conversion subprocess explosion**
- **ATA systemd-resolved active but not symlink**
- **State migration keys dropped on save**
- **Duplicate lightdm packages in DE install**
- **GRUB LVM argument splitting**
- **Services hard-failing on missing init packages**
- **CachyOS v4 false positive on Intel 12th gen+**
- **Architecture header missing on target pacman.conf for CachyOS v3/v4**

####  artist

## v9.2.4.2 (2026-06-26) — ArtixForge

### Fixed
- **Default user fallback** — `configure_users` now guarantees at least one user exists even if the GUI users page is skipped; creates default `artix` user when `USER_COUNT` is 0
- **`user_count` variable scope** — safety net now runs before `user_count` is captured, preventing loop from iterating zero times

## v9.2.4.1 (2026-06-26) — ArtixForge

### Added
- **Multi-user support** — users can be added, edited, and removed in both TUI and GUI; each user gets configurable shell, groups, and sudo/doas access
- **User management TUI** — `tui_configure_users` with add/edit/remove dialogs, group checklist (wheel, audio, video, storage, lp, network, optical, scanner, users), shell selection, and sudo toggle
- **User management GUI** — `InstallerApp.create_users_page` with listbox, add/edit/remove buttons, and full user dialog with password hashing, group checkboxes, and sudo switch
- **Installation report** — `/root/artixforge-install-report.txt` written during finalize stage with system config, hardware detection, user accounts, disk layout, and support link
- **Multi-user state keys** — `USER_COUNT`, `USER_${i}_NAME`, `USER_${i}_PASS`, `USER_${i}_SHELL`, `USER_${i}_GROUPS`, `USER_${i}_SUDO` persisted through state, handoff, and post-install

### Changed
- `install_desktop` exports `USER_NAME` from first user for AUR/source build compatibility
- `stage_finalize` writes installation report before sync/unmount


## v9.2.4.0 (2026-06-25) — ArtixForge

### Changed
- **GTK4 GUI modernized** — complete rewrite of all `artixgui/` pages using `Adw.NavigationView`, `Adw.PreferencesGroup`, and `Adw.ActionRow`; card-based mode selection, proper header bars, and smooth page transitions
- **GUI architecture** — `Gtk.Window` + `Gtk.Stack` replaced with `Adw.Application` + `Adw.NavigationView`; manual page tracking removed in favor of native push/pop navigation
- **Progress window** — embedded as `ProgressPage` widget instead of standalone pop-up; result screen uses `Adw.StatusPage` instead of `Gtk.MessageDialog`
- **`forge-gui` version** — bumped to 0.5.0

## v9.2.3.1 (2026-06-25) — ArtixForge

### Removed
- **ZFS leftovers** — `zfs_basestrap.sh` and all `fs_type == zfs` conditionals removed after ZFS was dropped in v9.1.0.0
- **bcachefs leftovers** — dead experimental code paths removed
- **`require_efi` function** — superseded by `detect_boot_mode`, no longer called anywhere

## v9.2.3.0 (2026-06-24) — ArtixForge

### Added
- **ATA minimum viable system check** — verifies kernel, init, session manager, coreutils, dbus, pacman, and network stack are installed after package replacement; installs any missing critical packages with init-appropriate suffixes
- **ATA boot chain verification** — checks for `/boot/vmlinuz-linux` existence after all install phases and forces kernel reinstall if missing
- **ATA resume init fallback** — if state file is missing `INIT` on resume, prompts user to re-select init system instead of aborting

### Changed
- `ata_build_package_map` — `pacman -Si` queries now use `head -n1` to prevent multi-line output from packages in multiple repos, fixing ghost version-mismatch entries in the service checklist
- `ata_convert_mkinitcpio_presets` — now uncomments default/fallback image lines instead of leaving them commented out from Arch's preset format
- `ata_restore_user_data` — uses `realpath` comparison to skip copy when backup and live paths resolve to the same location, eliminating "cannot copy directory into itself" warnings
- Cache clearing now uses direct `rm -rf` on `/var/cache/pacman/pkg/*` and `/var/lib/pacman/sync/*` instead of `_pacman -Scc`, preventing interactive prompt hangs
- `ata_convert_timesyncd` — cascading fallback from `ntp-*` to `chrony-*` packages with proper error handling
- Network packages in critical check include init-specific suffixes (`networkmanager-dinit`, `dhcpcd-openrc`, etc.)
- `state_save` called at end of `init` stage to persist all configuration for resume

### Fixed
- Interactive `[Y/n]` prompts during cache cleaning no longer hang the migration indefinitely
- `mkinitcpio` preset files no longer left fully commented-out after migration, allowing initramfs generation
- `cp: cannot copy a directory into itself` warnings eliminated during user data restore
- Ghost checklist entries like `1.56.1-1 →` removed from service migration menu
- System no longer boots without network stack or session manager installed

## v9.2.2.5 (2026-06-24) — ArtixForge

### Added
- **ATA archlinux-keyring preservation** — keyring reinstalled and repopulated after repo switch and again after package replacement, ensuring Arch-signed packages verify correctly throughout the migration
- **Signature error detection in retry_command** — pacman signature failures now trigger `recoverable_error` immediately instead of wasting retries on a broken keyring; network errors are distinguished and logged separately
- **mkinitcpio and bootloader fallback** — `services` stage continues with warnings if initramfs rebuild or bootloader update fail, rather than aborting the entire migration

### Changed
- `retry_command` in `scripts/common.sh` now parses command output for signature errors (`signature.*invalid`, `PGP.*invalid`, `unknown trust`) and network errors (`could not resolve`, `failed retrieving`) and responds accordingly
- `ata_convert_timesyncd` uses `_pacman` for chroot-aware package installation and returns cleanly if no NTP package is available
- Keyring population added to both `repos` stage (after `install_artix_keyring`) and `install` stage (after `reinstall_artix_packages`)

### Fixed
- `archlinux-keyring` no longer removed during package replacement, preventing "signature from Artix Buildbot is invalid" and "PGP invalid or corrupted signatures" errors for packages from Arch repositories
- NTP installation failure no longer cascades into unrecoverable error — warns and continues
- `mkinitcpio` failure no longer blocks migration completion — warns and continues with manual repair note

## v9.2.2.4 (2026-06-24) — ArtixForge

### Added
- **ATA universal DNS safety net** — working resolver guaranteed before any stage logic runs, even when resuming from an interrupted migration after reboot
- **ATA install-stage DNS guard** — resolver checked and created if missing before package downloads in the install stage
- **ATA service map empty-line filtering** — empty lines and non-service/target/socket/timer units excluded from migration checklist

### Changed
- `state_save` now called at the end of the `init` stage to persist `INIT`, `ATA_AUR_HELPER`, `WM_DE`, `ENABLE_ARCH_REPOS` and all other configuration to disk
- `ata_migrate_main` explicitly reloads state on resume to populate `target_init`, `backup_dir`, and `de` from saved configuration
- DNS resolver creation uses atomic `.tmp` write + `mv -f` to eliminate any window where `/etc/resolv.conf` doesn't exist

### Fixed
- Resume from `install` stage no longer fails with "No init system was selected" — `target_init` now correctly loaded from persisted state
- DNS resolution failures after reboot no longer block resumed migrations — resolver created before any network operations
- Service migration checklist no longer shows version numbers or empty entries from malformed package map lines

## v9.2.2.3 (2026-06-24) — ArtixForge

### Added
- **ATA DNS provider selection** — users can choose Cloudflare, Google, Quad9, copy from backup, or enter a custom DNS when systemd-resolved is replaced
- **ATA pre-flight network check** — migration aborts early with a clear message if no internet connection is detected

### Changed
- **ATA DNS replacement now atomic** — writes to `.tmp` file then `mv -f` over `/etc/resolv.conf`, eliminating the window where no resolver exists
- **ATA DNS replacement stops systemd-resolved first** — prevents the daemon from regenerating the stub after it's removed
- **ATA missing init handling** — uses `die` instead of `return 1` for consistent error messaging

### Fixed
- `/etc/resolv.conf` no longer disappears during conversion stage, preventing "could not resolve host" errors during package downloads
- Users in countries or networks where Cloudflare DNS is blocked can select an alternative provider

## v9.2.2.2 (2026-06-24) — ArtixForge

### Added
- **ATA DNS backup/restore** — original `/etc/resolv.conf` contents saved before conversion stage and restored if the file is removed or broken; fallback to Cloudflare DNS if no backup exists
- **ATA DNS pre-flight check** — `repos` stage verifies `/etc/resolv.conf` exists and is non-empty before any package downloads

### Changed
- **ATA service map skip list** — expanded from 18 to 95+ entries covering all systemd-internal units, targets, sockets, timers, and core binaries; added regex catch-all for any remaining `systemd-*` patterns and unit types (`.target`, `.socket`, `.timer`, `.mount`, `.automount`, `.path`, `.slice`, `.scope`)
- **ATA package mapping order** — `ata_build_package_map` and `ata_show_migration_list` now run after `prepare_artix_repos` so pacman queries hit Artix mirrors, eliminating false "NO ARTIX EQUIVALENT" for packages that exist in Artix repos
- **ATA missing init handling** — empty `target_init` now calls `die` instead of `return 1` for consistent error messaging

### Fixed
- `NetworkManager`, `lightdm`, and other common services no longer incorrectly show as having no Artix equivalent
- `getty@.service`, `remote-fs.target`, `systemd-userdbd.service` and all other systemd-internal units excluded from migration checklist
- DNS resolution failures during `cache_artix_packages` caused by `ata_convert_resolv_conf` removing the `systemd-resolved` stub before restoring a working resolver

## v9.2.2.1 (2026-06-24) — ArtixForge

### Fixed
- **ATA desktop detection** — Arch package names now queried directly after recovery detection, fixing `WM_DE=none` on systems with KDE, XFCE, Cinnamon, Budgie, GNOME, LXQt, LXDE, Hyprland, Sway, Niri, i3, dwm, IceWM, or MATE installed
- **ATA backup directory creation** — `mkdir -p` now ensures target directory exists before copying user homes; users with systemd-homed images or missing home directories are handled gracefully instead of failing with "no such file or directory"
- **ATA service map filtering** — 18 systemd-internal units (`getty@.service`, `systemd-journald.service`, etc.) now excluded from the migration checklist, preventing confusing entries like "getty → systemd"

### Changed
- `ata_backup_all` skips users with no home directory instead of failing, and logs systemd-homed users for later migration
- `ata_build_package_map` uses a skip-units filter list for cleaner service migration UI

## v9.2.2.0 (2026-06-24) — ArtixForge

### Added
- **ATA stage-based resume** — migration progress tracked via `migration-stage.conf` through init, backup, convert, repos, install, services, and finalize stages; interrupted migrations can be resumed or restarted fresh
- **ATA network retry wrapping** — all critical `pacman -S` calls wrapped in `retry_command` with 3 attempts and exponential backoff (5s/10s/20s)
- **ATA cache clearing** — package cache wiped before install phase to prevent corrupted partial downloads from poisoning retries
- **ATA chroot mount guards** — `/proc`, `/sys`, and `/dev` verified mounted before `mkinitcpio` and `update_bootloader` calls
- **ATA fresh-start recovery** — failed migrations can be restarted clean by removing partial systemd state and old backups
- **ATA NTP fallback** — `ata_convert_timesyncd` falls back from `ntp-openrc`/`ntp-runit`/etc. to `chrony-openrc`/`chrony-runit`/etc. if NTP packages are unavailable; service enablement falls back `ntpd` → `ntp` → `chronyd`
- **ATA detection sourcing** — `ata-detect.sh` and `ata-migrate.sh` now source recovery detects and migration common libraries directly, eliminating "command not found" errors

### Changed
- `ata_migrate_main` restructured into discrete stages with resume capability
- `ata_oncalendar_to_cron` patterns quoted to prevent bash glob expansion at parse time
- `ata_convert_timesyncd` uses cascading fallbacks for both package installation and service enablement
- ATA migration returns `0` for expected exits (live ISO, not Arch, user cancelled) to prevent ERR trap false positives
- `tui_migration_menu` ATA entry uses single clean label `"Arch Linux → Artix (EXPERIMENTAL)"` instead of duplicate strings

### Fixed
- Syntax error in `ata_oncalendar_to_cron` caused by unquoted glob patterns in case statement
- `detect_init` now detects systemd via `/usr/lib/systemd/systemd` and `/usr/bin/systemctl` before falling back to Artix inits
- Missing source of `migrations/inits/common.sh` and `migrations/des/common.sh` in ATA migrate entry point
- `cp` backup failure when `/home` directory doesn't exist for a detected user

## v9.2.1.0 (2026-06-24) — ArtixForge

### Added
- **Cinnamon** desktop environment — full integration across installer, migrations, ISO builder, recovery detection, and GUI
- **Budgie** desktop environment — full integration across all modules
- **Moksha** desktop environment — Enlightenment-based, full integration across all modules
- **COSMIC** desktop environment — Rust-based (alpha), full integration with seatd and Wayland support
- COSMIC alpha warning in TUI sanity checks and post-install log
- Moksha community-maintained notice in TUI sanity checks

### Changed
- Supported DE/WM count increased from 13 to 17
- `tui_select_desktop` menu updated with new entries
- `tui_select_display_manager` includes COSMIC in Wayland/seatd group
- `install_desktop` case blocks for all four new DEs with proper package lists, DM pairing, and service enablement
- `basestrap.sh` seat manager block includes COSMIC
- Migration `DE_PACKAGES` and `DE_DISPLAY_MANAGER` arrays updated
- ISO package list generation includes all new DEs
- Recovery `detect_desktop` patterns cover new DEs
- GTK4 GUI desktop combo boxes updated in `base.py`, `migration.py`, and `iso.py`
- README and GUIDE.md desktop table expanded to 17 entries

## v9.2.0.0 (2026-06-24) — I can't believe I'm migrating from arch edition

### Added
- **ATA (Arch to Artix) migration** — experimental full-system conversion from Arch Linux to Artix, preserving user data, credentials, configurations, and installed software
- **ATA system audit** — detects systemd units, timers, homed users, network credentials, PAM modules, pacman hooks, crypttab entries, DKMS modules, flatpaks, snaps, AppImages, Docker containers, and AUR packages
- **ATA package mapping** — dynamic repo comparison between Arch (core/extra/multilib) and Artix (system/world/lib32) with version mismatch warnings and TUI checklist
- **ATA credential security** — network passwords and WiFi PSKs isolated with `chmod 700`, restored to target with proper 600 permissions
- **ATA systemd timer conversion** — OnCalendar → cron, OnBootSec → `@reboot sleep N`, OnUnitActiveSec → background loop scripts
- **ATA PAM conversion** — `pam_systemd.so` → `pam_elogind.so`, `pam_systemd_home.so` removal
- **ATA mkinitcpio conversion** — `systemd`→`udev`, `sd-encrypt`→`encrypt`, `sd-vconsole`→`consolefont`, `sd-lvm2`→`lvm2`, `fsck` insertion
- **ATA pacman hook quarantine** — systemd-dependent hooks moved to `/etc/pacman.d/hooks.bak/`
- **ATA crypttab conversion** — entries converted to kernel command line parameters
- **ATA DNS fix** — `systemd-resolved` stub replaced with real `/etc/resolv.conf`
- **ATA timesyncd replacement** — `ntp` installed and enabled with init-appropriate suffix
- **ATA homed user migration** — LUKS-encrypted systemd-homed images unlocked and migrated to standard `/home`
- **ATA user service conversion** — systemd `--user` services (pipewire, wireplumber, etc.) → XDG autostart `.desktop` files
- **ATA systemd-boot replacement** — GRUB auto-installed to ESP, old boot entries removed
- **ATA AUR batch reinstall** — opt-in reinstall of all AUR packages via paru/yay with per-package failure reporting
- **ATA DKMS rebuild** — `dkms autoinstall` triggered after kernel installation
- **ATA flatpak preservation** — remotes and app list saved for post-migration restoration
- **ATA resume support** — stage-based progress tracking with resume-from-failure or fresh-start options
- **ATA experimental warning** — `tui_yesno` confirmation gate before entering migration
- **ATA GUI integration** — dedicated ATA configuration page in GTK4 frontend with init selection, Arch repos toggle, AUR helper choice, capabilities checklist, and ATA summary page
- `CODE_INDENTS.md` — hack diary covering every deliberate weirdness, workaround, and design quirk across the entire codebase

### Changed
- `tui_migration_menu` — third option "Arch Linux → Artix" with experimental warning gate
- `forge-gui` migration window — new ATA config and summary pages, flow routing for all three migration types
- Non-interactive dispatch — `resume` and `migrate` cases now handle `ata` migration type alongside `init` and `desktop`
- GUI launch detection — checks for `^MODE=` in state file instead of `^DISK=`, enabling migration and ISO modes from GUI
- Runtime self-copy — `cp -a` falls back to `cp -r` when `.git` pack files are read-only
- README migration section updated with ATA capabilities, limitations, and warnings
- GUIDE.md section 19 expanded with full ATA documentation
- Feature table and summaries updated to reflect ATA availability
- SECURITY.md and PRIVACY_POLICY.md updated with ATA credential handling, backup security, and data flow documentation

## v9.1.1.4 (2026-06-23) — ArtixForge

### Fixed
- **Advanced menu skipped** — `Advanced*)` case moved above `*ISO*)` in main menu pattern matching; the string "Advanced – recovery, power user, migration, ISO" was incorrectly matching `*ISO*)` first, bypassing the submenu entirely and launching ISO mode

### Added
- **Seat manager detection** — `detect_seat_manager` now verifies the service is actually enabled for the detected init system, flagging `seat-manager-disabled` in `BOOT_ISSUES` when misconfigured
- **Seat manager repair** — `repair_seat_manager` installs missing `elogind`/`seatd`, enables the service for the correct init, and handles dinit `logind` → `elogind` mapping

### Changed
- `repair_boot` now calls `repair_seat_manager`, so "Fix everything" and "Repair detected issues" both catch and fix desktop session failures automatically

## v9.1.1.3 (2026-06-23) — ArtixForge

### Fixed
- **dinit `elogind` service** — `enable_service` and `enable_service_boot` now map `logind` → `elogind` on dinit systems, preventing missing symlink that caused XFCE and other DEs to crash after login

## v9.1.1.2 (2026-06-23) — ArtixForge

### Fixed
- **BIOS partition error** — removed invalid `bios_grub` flag from MBR partition layout; the flag is GPT-only and `parted` correctly rejected it on `msdos` labels

## v9.1.1.1 (2026-06-23) — ArtixForge

### Fixed
- **Desktop selection crash** — missing closing brace in `tui_select_desktop()` caused the function to never be defined

## v9.1.1.0 (2026-06-23) — ArtixForge

### Fixed
- **Resume after reboot** — storage stage now remounts filesystems when stage was marked complete but `/mnt` is empty, preventing silent failure on all modes after power cycle
- **BIOS + LUKS/LVM boot** — GRUB kernel command line (`cryptdevice=`, `root=/dev/mapper/`, LVM paths) now injected into `/etc/default/grub` before `grub-mkconfig` on BIOS installs, matching the UEFI code path
- **LUKS UUID cross-disk contamination** — `get_luks_raw_uuid()` fallback restricted to partitions on the target disk only, preventing random LUKS partition from being selected
- **Silent VFAT creation failure** — EFI partition now verified with a mount/unmount test after `mkfs.fat`, catching corruption before it cascades into bootloader failure
- **Microcode selection crash** — `grep` replaced with bash builtin pattern match in `tui_select_microcode()`, eliminating possible 127 on dinit live ISOs with broken `grep` symlink
- **Manual partition validation** — missing EFI/root partitions now show descriptive error with `cfdisk`/`fdisk` hint instead of cryptic "does not exist" message

### Changed
- Storage resume path logs "remounting filesystems for resume" for visibility
- Manual partition prompt lists required partition types (EFI System, Linux filesystem)

## v9.1.0.0 (2026-06-22) — ArtixForge

### Added
- **BIOS/Legacy boot support** — MBR partitioning, GRUB `i386-pc` install, conditional ESP and EFI handling across all storage, bootloader, GUI, recovery, and TUI modules ( ͡° ͜ʖ ͡°)
- **ISO and Migration resume support** — interrupted ISO builds and init/desktop migrations can be resumed from the last completed stage, with option to start fresh by cleaning orphaned packages
- **Migration failure recovery** — interrupted migrations offer resume or clean slate option, removing both orphaned init systems or desktop environments with human-readable stage names
- LUKS keyfile toggle (GUI + TUI) — avoids double password prompt at boot, embedded in initramfs via `FILES=(/crypto_keyfile.bin)`
- `--pbkdf pbkdf2` on all LUKS format calls — GRUB compatibility for LUKS2
- Conditional `artix-grub-theme` skip — prevents double insmod bug on encrypted installs
- Parted version check — warns and offers downgrade for BIOS+GRUB compatibility
- Arch repo ISO toggle — GUI checkbox passes `-R arch` to all `buildiso` calls
- GUI BIOS awareness — bootloader dropdown limited to GRUB, UKI hidden, `ARTIX_BOOT_MODE` saved to state
- TUI BIOS awareness — bootloader locked to GRUB, UKI skipped, sanity warnings added for legacy boot
- TUI boot mode notification — informational message displayed when BIOS mode is detected
- GUI logo — header thumbnail and background watermark
- GUI welcome page system info — CPU, RAM, disks detected at startup
- GUI conditional pages system — lambda-based visibility with revealer support
- State persistence for new keys — `LUKS_KEYFILE`, `LUKS_KEYFILE_PATH`, `ISO_ARCH_REPOS`, `ARTIX_BOOT_MODE` saved and restored
- Recovery detection for BIOS mode, keyfile, and bootloader — detection and repair functions BIOS-aware, UKI and EFI checks skipped on legacy systems
- Preflight VFAT kernel module check — ensures EFI partition support before partitioning, falls back to installing `linux` package, gives clear error if ISO kernel lacks VFAT
- `CODE_INDENTS.md` — To be written

### Changed
- `require_efi` replaced with `detect_boot_mode` — BIOS or UEFI auto-detected at startup
- `main_menu()` dynamically shows Resume Migration/ISO options when stage files exist
- `resume_install()` and non-interactive dispatch detect migration and ISO stage files for correct resume
- Storage modules dual-path — `partition.sh`, `filesystem.sh`, `mount.sh` handle BIOS (MBR, no ESP) and UEFI (GPT, ESP)
- Bootloader dual-path — BIOS `i386-pc` and UEFI `x86_64-efi` with auto-detection
- Basestrap package list conditional — `efibootmgr dosfstools` only on UEFI, bootloader packages per selection
- Handoff and chroot validation — BIOS skips UKI and EFI boot entry checks
- Recovery detection — boot mode, bootloader, boot health, and repair all BIOS-aware
- Non-interactive mode — `require_efi` override checks `ARTIX_BOOT_MODE`
- `install` script — `exec` path uses `${BASE_DIR##*/}` for pacman-installed compatibility
- Filesystem TUI menu — ZFS and bcachefs removed
- ISO builder — `build_artix_iso` reads `ISO_ARCH_REPOS` from state, passes `-R arch` to all build phases, supports stage-based resume
- `run_init_migration()` and `run_de_migration()` — stage-based resume with failure recovery, orphan cleanup, and human-readable stage names
- TUI UKI selection — skipped on BIOS systems
- TUI sanity warnings — ZFS and bcachefs warnings removed, BIOS mode warning added
- TUI LUKS selection — keyfile toggle added after passphrase confirmation
- TUI config collection — boot mode notification shown when BIOS detected
- SonicDE — `SigLevel = Never` replaced with proper signing key `72AAA51726BC3C29`, official repo URL `sonicde-artix.github.io`, warnings removed from TUI, Privacy Policy, and Security docs
- Quick Profiles — TestingQP profile ZFS changed to XFS
- README — installation modes table updated for resume support

### Removed
- ZFS filesystem option — kernel 6.19+ incompatibility
- bcachefs filesystem option — Rust rewrite W.I.P.
- Dead ZFS partition layout from `partition.sh`

## v9.0.0.0 (2026-06-21) — ArtixForge

It's finally here. I'm done.

### Added
- GUI installer: full GTK4 + libadwaita graphical interface with 7 installation modes
- GUI: mode selection dialog, persistent config window (13+ pages), progress window with live log and progress bar
- GUI: 5 colour themes (ArtixForge, Artix, Jet Black, Mono, Retro), light/dark backgrounds, logo watermark
- GUI: welcome page with system info, conditional page visibility, extras search tab
- GUI: Power User recipe sections with auto-download, tooltips, conditional hardware pages
- GUI: ISO Builder with Load Profile chooser, Target System Config for offline builds
- GUI: Migration with auto-detection of init and desktop, sub-pages for DM/audio/network/extras
- GUI: password hashing before state save, `Gtk.Revealer` animation framework
- System Migration: init (16 combinations) and desktop (13 DEs/WMs) with auto-detection
- ISO Generation: custom live ISOs with offline bundles, Live Desktop and Installer modes
- Recovery: auto-detection, surgical repair, filesystem repair, rootkit scanning, untrusted recovery
- Power User: source-based package compilation, community recipe repository, `anvil` package manager
- AURIS: Artix User Repository of Init Scripts support
- Quick Install profiles: Desktop, Server, Minimal, Embedded, Gaming, Development, Media, Volk's Personal
- Limine bootloader: BTRFS snapshot booting, Windows chainloading, LUKS/LVM-aware cmdline
- ZFS: wiki-compliant ZFS-on-root with dual-pool setup, native encryption
- CachyOS: all 9 kernel variants with v3/v4 architecture-specific repositories
- SonicDE, MangoWM, TKG, Bazzite, XanMod kernels with AUR/Chaotic-AUR integration
- UKI: Unified Kernel Image with Secure Boot signing
- LVM with LUKS integration, bcachefs with DKMS, f2fs with compression
- Community recipe repository with auto-download, section filtering, and self-healing

### Changed
- GUI: GTK3 → GTK4 + libadwaita (1728 lines removed, 861 added)
- GUI: `Adw.StyleManager` for theming, `Gtk.DropDown`, `Gtk.PasswordEntry`, `Gtk.Application` architecture
- GUI: "Gentoo" → "ArtixForge" theme, `gartix` → `anvil` rename
- Backend: `localectl` removed, X11 keymap via xorg.conf.d, console via vconsole.conf
- Backend: `configure_users` detects pre-hashed passwords for GUI/TUI compatibility
- Backend: `basestrap.sh`, `bootloader.sh`, `detect.sh`, `repair.sh` atomized into sub-modules
- Backend: TKG kernel completely rewritten, no longer depends on interactive scripts
- Filesystems: exFAT removed as root, ZFS temporarily disabled (kernel 6.19+)
- Recovery: kernel detection covers all 9 supported kernels
- Migrations: OpenRC hub model for non-direct conversions, live ISO chroot support
- Documentation: GUIDE.md, SECURITY.md, PRIVACY_POLICY.md, README.md all updated

### Fixed
- GUI: ANSI escape codes stripped, progress window stays visible, password mismatch blocks navigation
- GUI: hidden pages skipped during navigation, disk selection filters loop/optical devices
- GUI: state file cleared on fresh installs, preserved for Resume/Recovery/Migration
- GUI: `install_script` path correct, `sudo` removed from progress commands
- Backend: post-install chroot inherits correct working directory
- Keyboard layout: non-US layouts work without systemd's `localectl`
- TKG: failed patches restore corrupted files, kernel compiles with remaining patches
- Limine: kernel panic on boot, snapshot loop quoting, ESP kernel copy
- CachyOS: Intel 12th gen+ v4→v3 downgrade, architecture repo config
- ZFS: preflight installs correct DKMS for live kernel, GRUB compatibility
- LUKS: mapper name dynamic, crypt_uuid correct for LUKS-only setups
- UKI: generation after ESP detection, Secure Boot signing restored
- bcachefs: mkinitcpio hook appends instead of replacing
- Migrations: custom service detection, orphan removal, init package transformation
- Recovery: plain partition detection, UKI syntax error, pacman batch arithmetic
- ISO: profile.yaml generation, offline kernel builds, workspace path resolution
- Post-install: package list deduplicated, zram-tools package names corrected
- Basestrap: gnupg permissions, /sbin/init symlink, duplicate hook accumulation
- Drivers: VM detection case-insensitive, CachyOS header detection, Nouveau fallback
- Installer: self-update copies to /tmp/artix-run, installer_error shows log tail

## v8.9.4.1 (2026-06-21) — ArtixForge

### Changed
- GUI: user and root passwords now hashed with `openssl passwd -6` before saving to state — plaintext never touches disk
- GUI: progress window now runs backend from correct working directory — `cwd` passed through to `subprocess.Popen`
- Documentation: PRIVACY_POLICY.md updated — GUI network access clarified, password hash storage documented
- Documentation: SECURITY.md updated — GUI password hashing added to best practices
- Documentation: GUIDE.md updated — GUI section expanded with theme support, progress bar, password hashing, Power User recipe fetching, ISO builder file browser, and Migration auto-detection notes
- README.md: GUI dependencies updated to GTK4 + libadwaita, features list corrected, gartix→anvil rename applied

### Fixed
- GUI: `install_script` path uses 4 `dirname` calls — correct path from `forge_ui/artixgui/base.py` to repository root
- GUI: progress bar matches actual backend completion messages — advances at each stage completion
- GUI: `app=self` parameter removed from `mode_select.py` — window constructors no longer receive unexpected keyword argument
- GUI: `app.add_window()` call removed from `run_installer` — progress window registers itself with application
- Backend: `post.sh` `cp -r .` inherits correct working directory — post-install chroot can find ArtixForge scripts
- Backend: `configure_users` detects pre-hashed passwords — compatible with both TUI (plaintext) and GUI (pre-hashed) flows
- Backend: keyboard layout configuration fixed — `localectl` calls removed, console keymap set via `vconsole.conf`, X11 keymap written to `/etc/X11/xorg.conf.d/00-keyboard.conf`

## v8.9.4.0 (2026-06-21) — ArtixForge

### Changed
- GUI: Artix logo added to header bar — 48px branding thumbnail displayed next to title on every page
- GUI: semi-transparent Artix logo watermark restored — 15% opacity logo centered behind all content
- GUI: `_conditional_pages` system added to `BaseWindow` — pages can register visibility conditions via lambdas
- GUI: `add_revealer_page()` method added — wraps content in `Gtk.Revealer` for future animation use
- GUI: `_update_conditional_pages()` re-evaluates all page conditions — called on power user toggle, coreutils change, package selection
- GUI: `_show_current_page()` centralizes page switching — triggers `update_summary()` when reaching last page
- GUI: `Gtk.Stack` transition duration set to 300ms — smoother page slides
- GUI: install button styled with `suggested-action` CSS class — consistent accent color
- GUI: theme accent color codes converted to integers — 34, 117, 196, 255, 11 replace hex strings
- GUI: all dialog dismissals use `.destroy()` — consistent GTK4 resource cleanup

### Fixed
- GUI: `install_script` path corrected in `iso.py`, `migration.py`, `recovery.py` — `..` removed, direct path to repository root
- GUI: `sudo` removed from `iso.py`, `migration.py`, `recovery.py` progress commands — GUI runs as root, no second password prompt
- GUI: `close-request` handler replaces `destroy` for window close — proper GTK4 lifecycle

### Added
- `forge_ui/artixgui/media/` directory — bundled assets directory for logo and future resources

## v8.9.3.0 (2026-06-21) — ArtixForge

### Changed
- GUI: `Gtk.Application` + `GLib.MainLoop` architecture — proper GTK4 application lifecycle replaces manual `Gtk.main()` hacks
- GUI: mode selection window now uses `Gtk.ApplicationWindow` — stays open until user choice, no more instant-close bugs
- GUI: progress window registers with application via `app.add_window()` — application stays alive during installation
- GUI: dialog dismissal uses nested `GLib.MainLoop` — blocks cleanly until user clicks OK, then unwinds all loops
- GUI: `Gtk.Revealer` animation framework prepared — page visibility uses direct `set_visible()` for stability, revealer wrapping deferred to page creation
- GUI: disk selection filters loop (`/dev/loop`) and optical (`/dev/sr`) devices — only real storage devices shown
- GUI: state file cleared on fresh installation modes (Automatic, Manual, Power User, ISO) — preserves state for Resume, Recovery, and Migration
- GUI: theme accent colors applied to entire GUI via `Adw.StyleManager.set_accent_color()` — dropdowns, buttons, and tabs follow selected theme
- GUI: "Gentoo" theme renamed to "ArtixForge" — purple/green palette now the default
- GUI: welcome page displays system information — CPU model, RAM, and available disks detected at startup
- GUI: progress bar added to installation window — fills dynamically as stages complete
- GUI: progress bar matches actual backend completion messages — adapts to whether Power User or BusyBox init stages run
- GUI: ANSI escape sequence stripping hardened — catches gum's bare `[38;5;Nm` patterns without ESC prefix
- GUI: Power User recipe sections trigger package list rebuild — toggling a section immediately refreshes available recipes
- GUI: Power User recipes auto-downloaded from community repository — missing recipe files fetched silently in background
- GUI: Power User package tooltips show source URL and description — user knows where each recipe comes from
- GUI: Power User fallback kernel frame hidden when linux not selected — entire section disappears, not just grayed out
- GUI: hidden pages skipped during navigation — Back/Next jump over invisible pages seamlessly
- GUI: Artix logo overlay support — semi-transparent logo displayed behind all content when `media/artix-logo.png` exists
- `forge_ui/artixgui/media/` directory added — bundled assets ship with the GUI (soon)

### Fixed
- GUI: `Gtk.main()` and `Gtk.main_quit()` fully eradicated — all 8 remaining calls replaced with `GLib.MainLoop`
- GUI: `search-changed` signal corrected to `changed` on search entry — extras search tab no longer crashes
- GUI: `window`/`win` variable name mismatch in `mode_select.py` — mode selection dialog now appears
- GUI: config window no longer closes when progress window opens — `app.hold()` keeps application alive
- GUI: `sudo` removed from progress window command — GUI already runs as root, second sudo prompt killed the window
- GUI: `Gdk` import added to `backends/gui.py` — CSS provider for log view works
- GUI: `ImportError` on `Gtk.main` resolved — Python 3.14 GTK4 bindings compatibility

## v8.9.2.0 (2026-06-21) — ArtixForge

### Changed
- GUI: complete GTK4 + libadwaita rewrite — GTK3 replaced across all 16 frontend files
- GUI: `Gtk.DropDown` replaces `Gtk.ComboBoxText` — native dark/light theme support, no more CSS hacks
- GUI: `Gtk.PasswordEntry` replaces `Gtk.Entry` with visibility toggle — password fields use proper secure widget
- GUI: `Adw.StyleManager` replaces manual CSS providers — system dark/light mode switches automatically, Gentoo/Artix/Jet Black/Mono/Retro themes preserved via accent color
- GUI: all `override_background_color` and `override_color` calls removed — GTK4 deprecation warnings eliminated
- GUI: window sizing simplified — fixed default 680×420, compositor handles centering
- GUI: `theme.py` stripped from 414 lines to 15 — only color code mapping remains for backend ANSI output
- GUI: `setup.py` bumped to v0.4.0, jsonschema removed from hard dependencies
- GUI: LICENSE updated to Forge Attribution License 1.0
- README: updated for GTK4, libadwaita dependency, `--mode config` documented

### Fixed
- GUI: ANSI escape codes finally killed — `isprintable()` filter in progress log view catches all control characters from gum output
- GUI: progress window `_on_destroy` no longer sets `cancelled=True` on successful completion — fixes false "Installation cancelled by user"
- GUI: installation failure dialog now shows last 8 lines of install log — users see what went wrong
- GUI: `Gtk.FileChooserDialog` ported to GTK4 async response pattern — profile file browser works
- GUI: tweak flags dialog uses `Gtk.Dialog` with `transient_for` — proper parenting, no black-on-white rendering bugs

### Removed
- GUI: 1728 lines of GTK3 code deleted — all manual CSS, font overrides, combo box theming, notebook background patches
- `theme.py`: `get_dark_css()`, `get_light_css()`, `get_global_css()`, `_color_to_hex()`, `_lighten_hex()` — all replaced by `Adw.StyleManager`
- Recovery edge cases removed from testing roadmap — will be addressed per user reports

## v8.9.1.0 (2026-06-20) — ArtixForge

### Fixed

- GUI: method name mangling resolved — __init_common_pages renamed to _init_common_pages across CommonPages and AutomaticWindow to prevent AttributeError when inherited by PowerUserWindow
- GUI: stale code execution from /tmp/artix-run copy identified — Python bytecode cache and installer self-copy behavior documented as potential footgun during development
- GUI: tweak flags dialog now inherits parent window background — labels and entries match light/dark theme
- GUI: extras notebook background updates on theme toggle — _apply_theme() re-applies notebook and child page backgrounds when switching between light and dark
- GUI: hardcoded notebook background override removed from create_extras_page — CSS provider handles theming, _apply_theme fixes toggle
- GUI: cancelled installation no longer confuses the TUI fallback — ProgressWindow._cancel() clears DISK= from state.conf so the wrapper doesn't attempt --non-interactive with incomplete state
- GUI: Power User Kernel Hardware page now hidden when linux is not selected in package list
- GUI: Power User New Recipe page now hidden when coreutils is not set to custom
- GUI: Recovery mode now auto-detects installed system on startup — runs reconstruct_state_from_system and displays status before user selects an action
- GUI: Recovery mode dynamically shows repair-method options (filesystem repair method, ClamAV toggle) based on selected action

- GUI: Migration mode now auto-detects current init system and desktop environment — displays detected values and pre-selects combo boxes
- GUI: Desktop migration now includes full sub-prompts — display manager, display stack, audio stack, network stack, and extras checkboxes with parity to TUI
- GUI: ISO Builder now includes Load Profile file chooser with Browse button for selecting saved profile files
- GUI: ISO Builder offline mode now includes Target System Configuration page — writes /tmp/artix-installer/iso-target-state.conf for offline package bundle generation
- GUI: ISO Builder sets ALLOW_OFFLINE, ISO_OUTPUT_DIR, and ISO_EXTRA_PACKAGES in state — offline ISOs build correctly from GUI configuration

### Changed
- GUI: Recovery window restructured — single main page with status display, action combo, and dynamic extra options replacing separate pages
- GUI: Migration window expanded from 3 pages to 6 — adds dedicated pages for DE display/audio config and network/extras config
- GUI: ISO Builder expanded from 7 pages to 9 — adds Load Profile page and Target System Config page for offline builds
- GUI: on_next() navigation logic rewritten for Recovery, Migration, and ISO Builder to handle conditional page flows


## v8.9.0.0 (2026-06-20) — ArtixForge

Many, many things changed. this changelog is incomplete for it's scope.

### Fixed
- GUI: Power User progress window now opens correctly — start_installation() override calls collect_state() before launching the installer, matching the pattern used by Recovery, Migration, and Resume windows
- GUI: ISO Builder now correctly sets ALLOW_OFFLINE in state — offline ISO builds no longer silently fall back to online mode
- GUI: ISO Builder now includes output directory field and sets ISO_OUTPUT_DIR in state — ISO is saved to the user's chosen location
- GUI: password mismatch now blocks navigation — users cannot proceed past the Users page or click Install with mismatched user/root passwords
- GUI: collect_state_common() return value now respected by Automatic, Power User, and Manual windows — silent state collection failures no longer ignored
- GUI: Kernel Hardware page in Power User mode now hidden when linux is not selected in the package list
- GUI: Custom Recipe page in Power User mode now hidden when coreutils is not set to custom
- GUI: __init_common_pages() now called in AutomaticWindow.__init__() — fixes missing extras checkboxes dict in Manual and Power User modes
- GUI: Manual window no longer leaks SWAP_ENABLED, USE_LUKS, LUKS_PASS, USE_LVM into state from previous runs

### Changed
- GUI: password validation extracted to _validate_passwords() method in BaseWindow — reusable across all windows
- GUI: on_next() now calls password validation before leaving the Users page — catches mismatches earlier in the flow
- GUI: Power User package checkboxes now emit toggled signals for conditional page visibility — Kernel Hardware and Custom Recipe pages react in real time
- GUI: ISO Builder build page reorganized with output directory entry alongside offline toggle

### Added
- GUI: conditional page visibility system in PowerUserWindow — _update_conditional_pages() toggles page visibility based on user selections
- GUI: _on_package_toggled() signal handler for package list checkboxes
- GUI: _on_coreutils_changed() signal handler for coreutils combo box

## v8.8.4.8 (2026-06-19) — ArtixForge

### Fixed
- ISO: removed manual service symlink/file creation from live-overlay — artools' `configure_services` handles all init service setup (hopefully lol)

## v8.8.4.7 (2026-06-19) — ArtixForge

### Fixed
- ISO: replaced `-w` flag with `WORKSPACE_DIR` export for all `buildiso` calls — `-w` is "copy pacman.conf", not "workspace directory"

### Confession
- I USED THE WRONG FLAG THIS ENTIRE TIME AND DID NOT CHECK.
- FUCK.

## v8.8.4.6 (2026-06-19) — ArtixForge

### Fixed
- ISO: patched artools `clean_up_chroot` to make `find -delete` non-fatal — fixes build abort when temp files are busy during cleanup

## v8.8.4.5 (2026-06-19) — ArtixForge

### Fixed
- ISO: patched artools `umount_overlayfs` to use lazy unmount with retries — fixes "target is busy" race condition when unmounting livefs overlay

## v8.8.4.4 (2026-06-19) — ArtixForge

### Fixed
- ISO: system `common.yaml` now backed up before override and restored after build — no trace left on the host system
- ISO: profile copy cleaned from `/usr/share/artools/iso-profiles/` after build completes

## v8.8.4.3 (2026-06-19) — ArtixForge

### Added
- AURIS: Artix User Repository of Init Scripts now supported — users can enable community-submitted init scripts during installation

## v8.8.4.2 (2026-06-19) — ArtixForge

### Changed
- ISO: building from a live environment now blocked with a clear message — overlayfs limitations in artools prevent live ISO builds
- ISO: tmpfs mount workaround removed from build pipeline — no longer needed with live ISO block in place

## v8.8.4.1 (2026-06-19) — ArtixForge

### Fixed
- ISO: redirect artools chroot directory via `CHROOTS_DIR` env var — bypasses overlayfs nesting limitation when building ISOs from a live environment without mounting tmpfs on system directories

## v8.8.4.0 (2026-06-19) — ArtixForge

### Added
- ISO: tmpfs workspace mount on live ISO — bypasses overlayfs nesting limitation when building ISOs from a live environment
- ISO: full artools-compatible `profile.yaml` generation with `livefs`, `live-session`, `rootfs` sections, init-specific packages, and service definitions

## v8.8.3.9 (2026-06-19) — ArtixForge

### Fixed
- ISO: generate corrected `common.yaml` in workspace to override broken `xlibre-xf86-*` package names in artools — upstream uses `xf86-` prefix that doesn't match Artix repos
- ISO: profile now copied to `/usr/share/artools/iso-profiles/` for artools compatibility
- ISO: workspace path now resolves to `/root/artools-workspace` on live ISO, `$HOME` elsewhere

## v8.8.3.8 (2026-06-19) — ArtixForge

### Fixed
- ISO: added `use-xlibre` field to generated `profile.yaml` — fixes artools `: command not found` error from empty variable expansion
- ISO: `user-services` now correctly populated based on selected audio stack (pipewire/pulseaudio)

## v8.8.3.7 (2026-06-19) — ArtixForge

### Fixed
- ISO: profile generation now writes full artools-compatible `profile.yaml` with `livefs`, `live-session`, `rootfs` sections, init-specific packages, and service definitions — `buildiso` correctly detects live ISO mode (HOPEFULLY)

## v8.8.3.6 (2026-06-19) — ArtixForge

### Fixed
- ISO: profile generation now writes `profile.yaml` instead of `profile.conf` — what happens when you don't read your sources

## v8.8.3.5 (2026-06-18) — ArtixForge

### Added
- ISO: offline bundles now build non-repo kernels (bazzite, cachyos, xanmod) in chroot and include them — true offline support for exotic kernels
- ISO: `build_nonrepo_for_offline()` — extensible function for building any kernel that needs compilation for offline mode

## v8.8.3.4 (2026-06-18) — ArtixForge

### Fixed
- ISO: target system configuration now correctly saved to separate state file — offline package bundle reflects actual target system choices, not live ISO defaults

## v8.8.3.3 (2026-06-18) — ArtixForge

### Fixed
- ISO: live ISO and offline target system now use completely separate state files — target config no longer pollutes live environment's kernel/DE selection
- ISO: offline package download now uses `--ask=4` to auto-resolve group selections and provider choices — no more interactive prompts blocking the download
- ISO: Quick Profiles removed from ISO configuration — designed for system installation, not live ISO building
- ISO: buildbot signing key now fetched from keyserver before local signing — eliminates spurious key trust warning

## v8.8.3.2 (2026-06-18) — ArtixForge

### Fixed
- ISO: live ISO state and offline target system state now separated — target config no longer overwrites live environment's kernel/DE selection
- ISO: offline package bundle generated from target system config while live ISO uses its own lightweight config
- ISO: live ISO kernel selection locked to standard Artix kernels (linux, zen, lts, hardened) — no AUR/external kernel builds in the live environment

## v8.8.3.1 (2026-06-18) — ArtixForge

### Fixed
- ISO: offline package download now uses live system's pacman database instead of blank db — packages actually download (hopefully)
- ISO: buildbot signing key now fetched from keyserver before local signing — eliminates spurious key trust warning

## v8.8.3.0 (2026-06-18) — ArtixForge

### Changed
- ISO: builder no longer asks for disk, partitions, users, or passwords — live ISO configuration is now lightweight (DE, init, kernel, network, audio, extras only)
- ISO: bootloader, filesystem-specific, and UKI packages removed from live ISO — leaner image, faster builds
- ISO: user can now choose output directory for the final ISO
- ISO: offline mode target system configuration separated from live ISO config — asks for system packages without disk selection

## v8.8.2.7 (2026-06-18) — ArtixForge

### Fixed
- CachyOS: Intel 12th gen+ CPUs (Alder Lake and newer) now correctly downgraded from v4 to v3 — AVX-512 is fused off on these chips despite being reported as supported (Special thanks to https://github.com/HappyAmper for pointing it out)

## v8.8.2.6 (2026-06-18) — ArtixForge

### Fixed
- TKG: `CONFIG_DM_CRYPT` and `CONFIG_DM_INTEGRITY` enabled after `make defconfig` — LUKS-encrypted root now unlocks correctly with TKG-custom kernels
- mkinitcpio: `lvm2`, `encrypt`, `bcachefs`, and `zfs` hooks now check for existing entry before appending — no more duplicate hook accumulation on resume or re-run

## v8.8.2.5 (2026-06-18) — ArtixForge

### Fixed
- TKG: kernel renamed using modification-time detection — newest `vmlinuz*` always becomes `vmlinuz-artixforge-tkg`, eliminating `vmlinuz.old` edge case
- Limine: kernel glob widened from `vmlinuz-*` to `vmlinuz*` with `nullglob` — no longer dies on non-standard kernel names
- mkinitcpio: `lvm2`, `encrypt`, `bcachefs`, and `zfs` hooks now check for existing entry before appending — no more duplicate hook accumulation on resume or re-run

## v8.8.2.4 (2026-06-18) — ArtixForge

### Fixed
- TKG: mkinitcpio preset uses actual kernel path from `make install` — matches `vmlinuz` without version suffix
- TKG: success check matches `vmlinuz*` without requiring version suffix

## v8.8.2.3 (2026-06-18) — ArtixForge

### Fixed
- TKG: mkinitcpio preset now created after kernel build — `mkinitcpio -P` finds the preset and generates initramfs

## v8.8.2.2 (2026-06-18) — ArtixForge

### Fixed
- Bootloader: `generate_root_cmdline()` now includes `rootflags=subvol=@` for btrfs — fixes "init does not exist" on btrfs installs with Limine
- TKG: failed patches now restore ALL files they touched, not just files with `.rej` — fixes `debug.c`/`sched.h` mismatch from partial PRJC patch application

## v8.8.2.1 (2026-06-18) — ArtixForge

### Changed
- TKG: kernel now compiled inside target chroot instead of live ISO (Another oopsie)

### Fixed
- TKG: failed scheduler patches now restore corrupted files and continue build — kernel compiles with remaining patches
- TKG: user warned which patches failed to apply after successful build

## v8.8.2.0 (2026-06-18) — ArtixForge

### Added
- GUI: non-interactive backend now supports Recovery, Migration, ISO, and Power User modes — GUI config flows drive the full pipeline
- GUI: password confirmation enforced — mismatched passwords block navigation with warning dialog

### Changed
- GUI: filesystem list updated — exFAT and ZFS removed to match TUI
- GUI: `save_state()` no longer uses `sudo` — installer already runs as root
- Non-interactive: `tui_password_confirm` reads passwords from state — GUI-saved credentials used correctly
- Non-interactive: `tui_password` handles LUKS prompts from saved state

### Fixed
- Non-interactive: recovery mode reads `RECOVERY_ACTION` from state and executes the correct repair
- Non-interactive: migration mode reads `MIGRATION_SRC`/`MIGRATION_TGT` from state and runs the correct migration
- Non-interactive: ISO mode reads profile/init/kernel from state and builds with `build_artix_iso`
- Power User: interactive `tui_poweruser_config` skipped when `GUI_MODE=yes` — GUI config used instead

## v8.8.1.8 (2026-06-18) — ArtixForge

### Fixed
- Basestrap: `/sbin/init` symlink verified after installation — kernel panic from missing init no longer possible
- Recovery: `detect_boot_health` now checks for `/sbin/init` — missing init symlink detected and repairable
- Recovery: `repair_boot` can recreate `/sbin/init` symlink from detected init system

## v8.8.1.7 (2026-06-18) — ArtixForge

### Fixed
- Basestrap: gnupg permissions corrected on target system — `pacman-key --init` no longer required after installing CachyOS/XanMod kernels (Special thanks to https://github.com/etrigan63 for pointing this out)

## v8.8.1.6 (2026-06-18) — ArtixForge

### Fixed
- Extras: `zram-tools` installs `zramen`/`zramen-${init}`, services use `zramen` and `bluetoothd` — correct Artix package names (Special thanks to https://github.com/etrigan63 for pointing this out)
- Limine: kernel and initramfs copied to ESP — `boot():/` paths now resolve correctly, fixes kernel panic on boot

## v8.8.1.5 (2026-06-18) — ArtixForge

### Fixed
- Migrations: `known_services` exclusion list expanded with `logind`, `lightdm`, and all standard openrc boot services — no more false custom service detection

## v8.8.1.4 (2026-06-18) — ArtixForge

### Fixed
- Migrations: `list_enabled_services()` returns empty string when init not installed — no more ANSI escape codes crashing service enumeration
- Migrations: `_install_target_init_fallback()` removes conflicting `cryptsetup-scripts` before installing openrc
- Installer: `installer_error()` now displays last 10 lines of install log and migration debug log — users see actual errors instead of line numbers

## v8.8.1.3 (2026-06-18) — ArtixForge

### Fixed
- Migrations: `detect_custom_services()` excludes known system services — NetworkManager, agetty, bootmisc, and other standard services no longer misdetected as custom scripts
- Migrations: `migrated=$((migrated + 1))` replaces `((migrated++))` — avoids post-increment `set -e` crash in init service migration loop
- Migrations: service-specific init packages installed before service migration — `NetworkManager-runit`, `dhcpcd-runit`, etc. now present when `enable_service` runs

## v8.8.1.2 (2026-06-18) — ArtixForge

### Fixed
- Migrations: `detect_custom_services()` excludes known system services — NetworkManager no longer misdetected as custom script
- Migrations: `((migrated++))` and `((skipped++))` replaced with `migrated=$((migrated + 1))` — avoids post-increment `set -e` issues in init service migration loop

## v8.8.1.1 (2026-06-17) — ArtixForge

### Added
- Migrations: `_repair_pacman_db()` runs at start of `run_de_migration` — detects and repairs broken package database entries before detection
- Migrations: `_cleanup_target_repo()` removes SonicDE repository after migration — `SigLevel = Never` not left permanent ( ͠° ͟ʖ ͡°)

### Fixed
- Migrations: `ROOT` variable conflict resolved — recovery detection now correctly queries target system packages

## v8.8.1.0 (2026-06-17) — ArtixForge

### Changed
- Migrations: `migrations/inits/common.sh` now supports live ISO via `MIG_ROOT` — all system operations route through chroot
- Migrations: init detection uses recovery's `detect_init` instead of manual selection
- Migrations: `_enable_service()` wrapper shared between DE and init migrations
- Migrations: detection functions in `des/common.sh` replaced with wrappers that call recovery's existing `detect_desktop`, `detect_display_manager`, `detect_xstack`, `detect_audio_stack`, `detect_network_stack` (That moment when you forget your own codebase)

## v8.8.0.10 (2026-06-17) — ArtixForge

### Changed
- Migrations: all detection functions refactored to use associative arrays with loops — adding new DEs/DMs/inits is one line
- Migrations: `_prepare_target_repo()` handles external repository setup (SonicDE, Chaotic-AUR) for migrations
- Migrations: live ISO detection uses `-d` instead of `-f` for `/run/artix/sfs/rootfs` directory check

### Fixed
- Migrations: pacman -Qtdq orphan check now guarded with || true — no longer fatal when no orphans exist
- Migrations: tui_de_migration_menu uses tui_msg_quick instead of tui_msg for current DE detection display

## v8.8.0.9 (2026-06-17) — ArtixForge

### Changed
- Migrations: `migrations/des/common.sh` now detects live ISO and routes all system operations through chroot to `/mnt` — migrations work from both live ISO and installed system
- Migrations: `_chroot()` and `_pacman_Q()` helpers added for transparent root path routing
- Migrations: `_enable_service()` wrapper runs service enablement inside target chroot with correct `INIT` exported
- Migrations: `recovery_mount_all()` offered interactively when target not mounted on live ISO

## v8.8.0.8 (2026-06-17) — ArtixForge

### Fixed
- Migrations: `apply_migration_choices` now exports `INIT` before calling `enable_service` — services enabled for correct init system
- Migrations: `mkinitcpio` now runs inside `artix-chroot /mnt` — no longer rebuilds live ISO kernel (FUCK)
- Recovery: `detect_iso_health` skips when not running from live ISO — no more false `missing-artixforge`
- Recovery: menu loop allows multiple repairs, added "Return to main menu" and "Exit" options

## v8.8.0.7 (2026-06-17) — ArtixForge

### Fixed
- Migrations: `enable_service` calls in `apply_migration_choices` now guarded with `|| log_warn` — no longer fatal when service is missing or something else happens for any reason

## v8.8.0.6 (2026-06-17) — ArtixForge

### Fixed
- Migrations: `run_de_migration` now auto-selects target DE's default display manager when migrating from `none` — e.g. lightdm correctly installed for xfce
- Migrations: `tui_de_migration_menu` no longer warns on missing pair scripts — generic `run_de_migration` handles all combos silently

## v8.8.0.5 (2026-06-17) — ArtixForge

### Fixed
- Drivers: CachyOS kernel header detection simplified — removed nonexistent `linux-cachy-headers` fallback

## v8.8.0.4 (2026-06-17) — ArtixForge

### Fixed
- Drivers: VM detection now case-insensitive, adds `vbox` pattern — VirtualBox no longer misdetected as KVM
- Drivers: `enable_service qemu-guest-agent` guarded with `|| log_warn` — no longer fatal when service is missing

## v8.8.0.3 (2026-06-17) — ArtixForge

### Fixed
- Drivers: CachyOS kernel header detection fixed — `linux-cachy*` pattern now matches all variants

## v8.8.0.2 (2026-06-17) — ArtixForge

### Fixed
- Post-install: removed stale `source ./scripts/post/kernel.sh` — file no longer exists, stage no longer fails

## v8.8.0.1 (2026-06-16) — ArtixForge

### Fixed
- CachyOS: `Architecture = x86_64 x86_64_v4` now set globally under `[options]` instead of per-repo — pacman accepts v4 packages

## v8.8.0.0 (2026-06-16) — ArtixForge

The next few patches will include GUI upgrades.

### Added
- ISO: artix-keyring refreshed before `buildiso` call

### Changed
- System: keyboard layout now applied to X11 sessions via `localectl set-x11-keymap` — non-US layouts work in graphical environments
- Post-install: package list deduplicated with `sort -u` before `pacman -S`
- Installer: self-update copies to `/tmp/artix-run` before replacing files
- Filesystems: exFAT removed as root option — no Unix permissions or symlink support
- Kernel: `find_kernel_image()` and `find_initramfs_image()` match `KERNEL_CHOICE` explicitly
- Bootloader: `generate_root_cmdline()` unified across all five bootloaders
- Bootloader: Secure Boot signing paths use chroot-relative paths
- Audio: `setup_audio()` detects and removes conflicting stacks, skips already-installed packages
- Desktop: SonicDE and MangoWM isolated into dedicated functions with trap cleanup
- Drivers: PCI ID validated as hex, VM detection uses CPUID hypervisor bit, Nouveau fallback cleans DKMS
- Networking: detects conflicting stacks, skips already-installed packages
- Recovery: `detect_init` uses binary detection — no more state/runtime mismatch
- Recovery: kernel detection uses tiered priority
- Recovery: `detect_coreutils` verifies BusyBox symlinks before assuming implementation
- Power User: `validate_system()` uses `sort -V` for kernel module directory ordering
- ZFS: service files support all four init systems, mkinitcpio hook appends instead of replacing
- Migrations: DM/network normalisation uses explicit case mapping, init package transformation fixed
- ISO: `BASE_DIR` and installer functions sourced if missing, chroot detection uses multiple fallbacks
- Partitioning: removed unnecessary `dd` wipe, LVM volume group name configurable

### Fixed
- CachyOS: `Architecture = x86_64_v4` added to v4 repo sections
- Recovery: `pacman_root_has` guarded against empty input
- Recovery: `repair_pacman` batch arithmetic fixed
- Recovery: filesystem repair unmounts BTRFS recursively, verifies FS before remount
- Recovery: `/dev/mapper/control` filtered, already-open mappers skipped
- ZFS: preflight installs `zfs-dkms` from archzfs with repo prefix
- ZFS: removed unbound `zfs_pkg` variable in modprobe check
- TKG: `make modules_install INSTALL_MOD_PATH=/mnt` and `make install INSTALL_PATH=/mnt/boot`
- bcachefs: mkinitcpio hook appends instead of replacing
- Bootloader: `find_kernel_image` matches `KERNEL_CHOICE` instead of alphabetical `head -n1`
- Limine: snapshot loop uses `while read` with proper quoting
- Storage: duplicate block-device validation removed
- Storage: LUKS reopen cleans up stale mappers
- Storage: EFIStub mount detection fixed
- Desktop: dead `elif` in KDE profile logic removed
- Desktop: MangoWM AUR build uses trap for cleanup
- Drivers: PCI ID validated, VM detection improved, Nouveau fallback cleans DKMS
- Networking: service enable failures logged
- Migrations: orphan removal checks list first, extras loop builds clean list
- ISO: offline mode skips target configuration for installer ISOs
- ISO: `cleanup.sh` uses explicit `output_dir` fallback
- Power User: kernel module sort fixed

## v8.7.0.8 (2026-06-16) — ArtixForge

### Fixed
- CachyOS: `Architecture = x86_64_v4` added to v4 repo sections — fixes "package architecture is not valid" on v4-capable CPUs

## v8.7.0.7 (2026-06-15) — ArtixForge

### Fixed
- ISO: artix-keyring refreshed before `buildiso` call — prevents "Signature from Artix Buildbot is invalid" error

## v8.7.0.6 (2026-06-15) — ArtixForge

### Fixed
- CachyOS: v3/v4 mirrorlist now downloaded before repo sections added to `pacman.conf` — fixes broken config when mirrorlist package fails (oops...)

## v8.7.0.5 (2026-06-15) — ArtixForge

### Changed
- Filesystems: ZFS temporarily disabled — ZFS max supported kernel is 6.15 (live ISOs ship 6.19 and above!)
- Filesystems: selecting ZFS now shows an "Unavailable" message and returns to selection

## v8.7.0.4 (2026-06-15) — ArtixForge

### Fixed
- ZFS: preflight now installs `zfs-dkms` from archzfs with repo prefix — live ISO kernel rarely matches prebuilt ABI and may ship outdated ZFS
- ZFS: preflight forces `archzfs/zfs-dkms` to override outdated live ISO packages
- ZFS: removed unbound `zfs_pkg` variable in modprobe check — now reports DKMS status on failure

## v8.7.0.3 (2026-06-15) — ArtixForge

### Fixed
- Recovery: `recovery_mount_all()` now detects plain partitions (ext4/btrfs/xfs/f2fs) — no longer requires LUKS or LVM to auto-mount (I FORGOT)
- Recovery: auto-mount falls back to `lsblk` scan when no LUKS/LVM volumes found
- Recovery: `detect_uki` syntax error fixed — missing `; then` after grep condition causing exit 127
- Recovery: UKI missing file no longer flagged as a boot issue — system boots via bootloader
- TUI: kernel sub-menu case patterns fixed — `"linux-* (standard)"` and `"linux-cachyos-*"` now match menu display
- TUI: `tui_filter()` no longer redirects stdin to `/dev/tty` — `gum filter` correctly receives piped package list (oops)
- Extras: `EXTRAS_SAFETY_FILTER` regex fixed — `*` changed to `.*` to silence grep warnings
- ZFS: preflight now installs ZFS module for live kernel instead of target kernel — fixes install failure when target kernel differs from live ISO
- ZFS: removed spurious die when live and target kernels differ — target gets its own ZFS package during basestrap

## v8.7.0.2 (2026-06-15) — ArtixForge

### Added
- Extras: "Search for packages..." — live fuzzy search over Artix `world` and `galaxy` repositories
- Extras: `tui_search_extras()` using `tui_filter` (wraps `gum filter`) for real-time package filtering
- Extras: `EXTRAS_SAFETY_FILTER` excludes DEs, kernels, bootloaders, init services, and system packages from search results
- TUI: `tui_filter()` wrapper added to `scripts/tui/core.sh`

### Changed
- Post-install: `install_extras()` refactored — `SIMPLE` array loop replaces repetitive `[[ ]]` checks; init-specific packages remain explicit
- Post-install: searched packages install as plain `pacman` packages, curated list unchanged

## v8.7.0.1 (2026-06-14) — ArtixForge

### Changed
- Main menu: Recovery, Power User, Migration, and ISO modes moved under "Advanced" sub-menu
- Each advanced mode now shows a clear warning explaining what it does and its risks before proceeding

## v8.7.0.0 (2026-06-14) — ArtixForge

### Added
- Kernels: sub-menu grouping — standard kernels (linux, zen, lts, hardened) under "linux-*" and CachyOS variants under "linux-cachyos-*"
- CachyOS: full variant support — all 9 CachyOS kernels (cachyos, bore, eevdf, bmq, rt-bore, hardened, lts, server, deckify)
- CachyOS: architecture-specific repository tiers — v3 (AVX2) and v4 (AVX512) optimized repos configured based on CPU detection
- Bazzite: kernel now compiled from AUR during basestrap instead of post-install

### Changed
- `basestrap.sh`: atomized — kernel packages, target repos, custom kernel builds, and ZFS config extracted to `scripts/install/basestraps/`
- `bootloader.sh`: atomized — GRUB, Limine, rEFInd, and EFIStub each in `scripts/install/bootloaders/`
- `detect.sh`: atomized — detection functions grouped into `scripts/recovery/detects/{system,desktop,network_audio,packages,hardware,health}.sh`
- `repair.sh`: atomized — repair functions grouped into `scripts/recovery/repairs/{system,packages,advanced,migration_iso}.sh`
- `kernel.sh`: removed unused `install_kernel_bazzite` (now in `basestraps/kernel_build.sh`)
- `stages/post.sh`: removed dead bazzite build call
- Recovery: `detect_kernel` refactored to single loop over all known kernels
- Recovery: `detect_extras` refactored to single loop with special case for zram-tools
- Recovery: `detect_desktop` refactored to associative array lookup
- TUI: kernel menu uses `-*` suffix notation to indicate sub-menu choices

### Fixed
- Limine: kernel panic on boot — config now creates an entry for every installed kernel with exact filenames and matching initramfs
- Limine: missing kernel path error replaced with clear failure during install if no kernels found

## v8.6.4.7 (2026-06-14) — ArtixForge

### Fixed
- Limine: kernel panic on boot — config now creates an entry for every installed kernel with exact filenames and matching initramfs
- Limine: missing kernel path error replaced with clear failure during install if no kernels found

## v8.6.4.6 (2026-06-13) — ArtixForge

### Added
- SonicDE: user warning before installation — notifies that signature verification is disabled due to upstream key infrastructure issues
- SonicDE: user can cancel and return to desktop selection if they decline unsigned installation

### Fixed
- SonicDE: removed old repository URLs before adding new one to prevent key conflicts
- SonicDE: `SigLevel = Never` at repo level to work around missing upstream signing key (70B4B1EF0FF2A94E)???

## v8.6.4.5 (2026-06-13) — ArtixForge

### Changed
- TKG: completely rewritten build process — no longer depends on TKG's interactive scripts (they suck)
- TKG: clones Artix's current kernel version from kernel.org, applies TKG patches directly
- TKG: uses `make defconfig` for a clean baseline (no LiveISO kernel dependency)
- TKG: GRUB configuration regenerated after kernel install

## v8.6.4.4 (2026-06-13) — ArtixForge

### Added
- Extras: "Wayland Extras" category with swaybg, swaylock, waybar, wofi, fuzzel, foot, hyprpaper
- Wayland compositors now show a recommendation message during extras selection

### Fixed
- MangoWM: complete AUR dependency chain now built in order (wlroots0.19-hidpi-xprop → scenefx0.4 → mangowm-git)
- MangoWM: temporary passwordless sudo configured during AUR builds, cleaned up automatically
- MangoWM: build user added to `seat` group so compositor can launch without root
- MangoWM: Arch repositories now enforced when MangoWM is selected

### Changed
- MangoWM: AUR build now uses `makepkg -si --noconfirm` to automatically resolve all dependencies

## v8.6.4.3 (2026-06-13) — ArtixForge

### Fixed
- MangoWM: pacman keyring initialization now sets `GNUPGHOME` before Chaotic-AUR key import
- MangoWM: AUR build dependencies (`cjson`, `scenefx0.4`, `xorg-xwayland`) installed before compilation
- SonicDE: `sonic-login-manager-${init}` init-specific package restored in desktop installation
- XanMod: pacman keyring initialization now sets `GNUPGHOME` before Chaotic-AUR key import

## v8.6.4.2 (2026-06-12) — ArtixForge

### Changed
- TKG: kernel now compiled automatically during installation instead of requiring manual post-install build
- TKG: uses TKG's own `_tkg_srcprep` + `make` with a non-interactive customization.cfg (BORE scheduler, running-kernel config, GCC)
- TKG: built kernel and modules copied to `/mnt` automatically; target initramfs regenerated

## v8.6.4.1 (2026-06-12) — ArtixForge

### Added
- SonicDE: full desktop environment support — repository setup, package installation, and Sonic Login Manager integration
- SonicDE: migration support — DE_PACKAGES, DE_DISPLAY_MANAGER, and DM_PACKAGES entries for sonicde ↔ any DE
- SonicDE: recovery detection — `detect_desktop()` and `detect_display_manager()` recognize sonicde-meta and sonic-login-manager
- SonicDE: GUI support — desktop combo boxes in `base.py` and `iso.py` include sonicde

## v8.6.4.0 (2026-06-12) — ArtixForge

### Added
- ZFS: full wiki-compliant ZFS-on-root support with dual-pool setup (bpool + rpool)
- ZFS: optional native encryption on root pool (aes-256-gcm) with passphrase confirmation
- ZFS: container and filesystem datasets with data separation (home, root, srv, usr/local, var/log, var/spool, var/tmp)
- ZFS: dedicated boot pool partition (BE00) and root pool partition (BF00) in GPT layout
- ZFS: `archzfs` repository configuration on target system
- ZFS: `zfs-mount` init script for automatic dataset mounting at boot
- ZFS: `zpool.cache` generation for initramfs embedding
- ZFS: GRUB compatibility workarounds (`ZPOOL_VDEV_NAME_PATH`, pool name detection in `10_linux`, `--removable` install)
- ZFS: manual fstab entries for boot pool and EFI partition (replaces fstabgen)
- LUKS: PBKDF2 key derivation added to all `luksFormat` calls for GRUB compatibility
- LUKS/LVM: init-specific service packages (`cryptsetup-${init}`, `lvm2-${init}`) installed on target
- LUKS/LVM: `dmcrypt`, `device-mapper`, and `lvm` services enabled at boot via `enable_service_boot()`
- Services: `enable_service_boot()` function added for boot-runlevel service activation across all four inits
- README: installation instructions for `pacman -S artixforge` package
- README: [galaxy] soonTM badge added
- PKGBUILD: ready for Artix [galaxy] submission? (pending v9 merger)

### Changed
- Migration: `install_target_init` now queries installed init packages via `pacman -Qsq` instead of hardcoded lists
- Migration: `cache_target_init_packages` downloads new init packages before removing old ones (network-safe)
- Migration: `remove_source_init` uses `pacman -Qsq` to find and remove all init-specific packages
- Migration: `cold_reboot()` function for SysRq-based reboot after init swap (prevents broken symlink hangs)
- Partition: ZFS layout now creates 1GB EFI + 4GB boot pool + root pool partitions
- ISO: `build.sh` now uses wiki method for non-repo packages (`buildiso -x` → chroot → `-sc` → `-zc`)
- SECURITY.md: supported versions table updated (v9.x future, v8.6.x best effort)
- OSI.md: corrected license name reference
- GUIDE.md: `gartix` references updated to `anvil`

## v8.6.3.0 (2026-06-12) — ArtixForge

### Added
- Migration: full Arch→Artix migration path following the official Artix wiki — replaces pacman.conf/mirrorlist, installs Artix keyring, removes systemd, reinstalls all packages from Artix repos
- Migration: LVM service enablement for all init systems after migration
- Migration: systemd junk cleanup (accounts, directories)
- Migration: bootloader update (mkinitcpio + GRUB reinstall) after migration
- Migration: pacman cache cleanup and security level toggle for keyring installation

### Changed
- Migration: `run_init_migration` now handles systemd→Artix as a complete system replacement (wiki parity)
- Migration: `install_target_init` now includes elogind and init-system packages for all inits
- Migration: `remove_source_init` replaces manual package removal with batched init-specific cleanup
- Migration: init migration now always updates bootloader and enables LVM services post-migration
- `services.sh`: relaxed sourcing — no longer dies when `/etc/artix-installer.conf` is missing (supports migration/recovery contexts)

## v8.6.2.0 (2026-06-10) — ArtixForge

### Added
- Recovery: migration health detection — detects multiple init systems, init mismatches, orphaned service symlinks
- Recovery: ISO health detection — detects missing pacman, broken package database, missing kernel, incomplete base
- Recovery: migration repair — reinstalls correct init system, cleans up conflicting init directories
- Recovery: ISO repair — reinstalls missing base packages and kernel when salvageable
- Recovery: extended detection prompt — migration and ISO checks are opt-in, keeping standard recovery fast

### Fixed
- Recovery: `esp_disk` and `esp_part` undefined variables in `repair_boot` Limine EFI entry repair
- Recovery: `_kernel_pkg` incorrectly listed `linux-bazzite-bin-headers` as a repo package (AUR, same as TKG)

## v8.6.1.0 (2026-06-10) — ArtixForge

### Fixed
- GUI: `extras_checkboxes` string corruption bug — state collection now reads directly from widget tree
- GUI: `state.conf` not saving — `save_state()` now writes via sudo with temp file shredding
- GUI: installer not launching from GUI — fixed path resolution for `install` script
- GUI: `state_load` never called in non-interactive mode — installer now loads state before pipeline
- GUI: `&&`/`||` logic error in non-interactive auto/manual causing false `power user stage failed` — replaced with `|| true`
- GUI: `GUI_MODE` flag not set — `collect_state_common()` now sets `GUI_MODE="yes"`
- GUI: `MODE` key not set — all modes now set `MODE` in state
- GUI: mode selection dialog added at startup
- GUI: LUKS and BTRFS sub-boxes now properly hidden using `set_no_show_all(True)`
- GUI: `poweruser_box` visibility fixed with `show_all()`/`hide()` toggles
- GUI: `ResumeWindow` missing `start_installation()` override
- GUI: ANSI escape codes stripped from progress log output
- GUI: main config window hidden during installation to prevent accidental closure
- GUI: proper cancel/success/failure dialogs after installation
- GUI: CSS extracted to single `get_global_css()` function in `theme.py` — eliminates 200+ lines of duplication
- ISO: `buildiso` `useradd` error fixed — profile.conf now includes `username` and `password`
- ISO: `blank_db` variable typo fixed (`blankdb` → `blank_db`)
- ISO: `buildiso` flag corrected from `-o` to `-t` for output directory
- ISO: `ISO_DIR` properly defined in `build_artix_iso()` so script works when called directly

### Changed
- GUI: all mode windows now follow same pattern: `collect_state()` → `save_state()` → `./install --non-interactive`
- ISO: `offline.sh` now reads package list from `packages.x86_64` generated by user config instead of hardcoded array
- ISO: `build.sh` adds first-boot setup script for non-repo packages (MangoWM, vxwm, bazzite, tkg)
- ISO: `tui.sh` extra packages checklist fixed — removed broken `"off"` state strings, uses `tr '\n' ' '`
- ISO: offline mode now calls `tui_collect_install_config` to let user configure target system packages for bundling

### Removed
- ISO: hardcoded package list in `offline.sh` — replaced with state-driven `packages.x86_64`
- GUI: custom Bash command construction in `recovery.py`, `iso.py`, `migration.py`

## v8.6.0.0 (2026-06-06) — ArtixForge

### Added
- GUI installer: persistent GTK configuration window (`forge-gui --mode config`) with 12 pages covering all installation options
- GUI installer: theme preview (Gentoo, Artix, Jet Black, Mono, Retro) with live CSS colour updating
- GUI installer: LUKS passphrase entry with confirmation and conditional visibility
- GUI installer: BTRFS layout selector (standard/flat/snapshot) shown only when btrfs filesystem selected
- GUI installer: Power User mode sub-page with coreutils selection, fallback kernel toggle, and package checklist
- GUI installer: Arch repositories and offline mode toggles
- GUI installer: user and root password fields with visibility hiding
- GUI installer: summary page with sanity warnings for dangerous combinations (ZFS, glibc source, EFIStub+LUKS)
- GUI installer: all configuration saved to `/tmp/artix-installer/state.conf` in the same format as the TUI
- GUI integration: automatic detection of `DISPLAY`/`WAYLAND_DISPLAY` and `forge-gui` presence
- GUI integration: user prompt at startup to choose GUI over TUI when graphical session detected
- GUI integration: non-interactive installer mode (`scripts/noninteractive.sh`) overriding all `tui_*` functions when GUI config is saved
- GUI integration: full installation pipeline reuses existing stages without UI prompts
- GUI integration: `forge-gui` added as a git submodule in `forge-gui/`
- `forge-gui` now installs `jsonschema` and `pygobject` as Python dependencies
- `preflight.sh` installs GTK3 and system Python bindings when GUI mode is enabled
- `install` script now supports `--non-interactive` flag (used by GUI after config save)
- GUI installer: categorized extras page with tabs for System Tools, Editors, Browsers, File Managers, Terminals, Shell & Prompt, Monitoring, and Media – includes "Select All" per category
- GUI installer: optional black or white background (user-selectable on Theme page)

### Changed
- `gartix` package manager renamed to `anvil` – binary, internal scripts, and documentation updated accordingly
- `forge-gui` repository stripped of all Textual TUI code – now pure GTK3 GUI only
- `cli.py` extended with `--mode config` to launch persistent configuration window (replaces single-widget mode for install flow)
- `tui_yesno` override in `noninteractive.sh` now checks `SIGN_UKI` state variable to answer Secure Boot prompts correctly
- `state.sh` now includes `GUI_MODE` variable to persist GUI selection across stages
- `install` script now runs non-interactive pipeline directly after GUI config saves, without returning to TUI
- Changelog restructured to separate v8.5 (ISO + migrations) from v8.6 (GUI + integration)

### Fixed
- `bootloader.sh` Secure Boot prompt no longer blocks non-interactive installation – reads `SIGN_UKI` from state instead
- `forge-gui` no longer attempts to run `sudo ./install` on its own – saves config and exits cleanly
- `forge-gui` theme preview now updates correctly when switching theme options

### Documentation
- `README.md` updated to describe GUI installer alongside TUI
- `GUIDE.md` added GUI installation section
- `forge-gui/README.md` rewritten for pure GTK frontend
- `poweruser/README.md` updated: all `gartix` references changed to `anvil`
- `DOCUMENTS/ROADMAP.md` updated: GUI integration moved from think-tank to v8.6

## v8.5.0.0 (2026-06-05) — ArtixForge

### Added
- System Migration: init system conversion between all 16 combinations (openrc, runit, dinit, s6, systemd)
- System Migration: automatic service mapping with hub-chaining through OpenRC for non-direct pairs
- System Migration: custom service detection and backup to `/root/init-backup-*/`
- System Migration: desktop environment migration for all 13 supported DEs/WMs with network stack and extras support
- System Migration: interactive prompts for display manager, display stack, audio stack, and network stack during DE migration
- System Migration: user config backup (~/.config, ~/.local, ~/.cache) during DE migration
- System Migration: init-specific package handling (sddm-dinit, lightdm-openrc, etc.)
- New `migrations/` module structure: `inits/` and `des/` with shared `common.sh` libraries
- System Migration entry in main installer menu
- ISO generation: build custom Artix live ISOs from any Quick Profile or full custom configuration
- ISO generation: Live Desktop mode (full graphical environment) and Installer mode (boots directly into ArtixForge)
- ISO generation: installer auto-launch overlays for OpenRC, dinit, and runit
- ISO generation: offline-capable ISOs with bundled package repository that carries over to installed system
- ISO generation: offline mode auto-detection in `require_internet` when local repo is present
- ISO generation: init-specific live service overlays for OpenRC, dinit, runit
- ISO generation: full ArtixForge installer included on every ISO at `/root/ArtixForge/`
- ISO generation: user-requested extra packages support via `ISO_EXTRA_PACKAGES`
- ISO generation: build logs saved alongside ISO output
- New `iso/` module at repo root: `build.sh`, `common.sh`, `offline.sh`, `cleanup.sh`, `tui.sh`
- "Build ISO" entry in main installer menu

## v8.4.4.1 (2026-06-04) — ArtixForge

### Fixed
- Manual mode: disk selection now runs before partitioning — fixes "No disk selected" crash when choosing Manual installation mode
- Manual mode: user can now specify which partitions to use after manual partitioning — EFI, root, and swap partitions are prompted and stored
- `create_filesystems` and `mount_filesystems` now use manually-specified partitions when available, falling back to automatic numbering

## v8.4.4.0 (2026-06-03) — ArtixForge

### Fixed
- LUKS: `crypt_uuid` validation now verifies the UUID points to an actual `crypto_LUKS` partition — auto-corrects if the wrong UUID was derived, preventing "device not found" at boot

## v8.4.3.10 (2026-06-03) — ArtixForge

### Fixed
- UKI: `mkdir` for output directory now runs inside chroot before `ukify build` — fixes "No such file or directory" when ESP isn't mounted yet
- UKI: `efibootmgr --create` failure downgraded from `die` to `log_warn` — UKI generation completes even when EFI entry creation fails (recovery context)
- Initramfs: `sed` hook injection now anchored to `^HOOKS=` — only modifies the active HOOKS line, not commented examples in `mkinitcpio.conf`
- LUKS: `get_luks_raw_uuid` now walks the full device chain up to the raw partition — correctly resolves LUKS partition UUID for `cryptdevice=` even through LVM layers

## v8.4.3.9 (2026-06-03) — ArtixForge

### Fixed
- Recovery: `detect_luks` now walks the full device mapper chain — correctly detects LUKS even under LVM layers
- Recovery: `repair_uki` checks for UKI directory existence before scanning — fixes crash when `/boot/efi/EFI/Linux` doesn't exist

## v8.4.3.8 (2026-06-03) — ArtixForge

### Fixed
- Recovery: `recovery_mount_all()` now copies `/etc/resolv.conf` into chroot — pacman can resolve mirrors
- Recovery: `repair_pacman` checks chroot functionality before attempting repairs — skips gracefully instead of crashing
- Recovery: `detect_pacman_health` pipeline now tolerates pacman failures with `|| true` — detection completes even if pacman database is broken
- Recovery: `repair_pacman` base reinstall failure downgraded from `die` to `log_warn` — recovery continues with other repairs

## v8.4.3.6 (2026-06-03) — ArtixForge

### Added
- Recovery: `recovery_mount_all()` — auto-detects LUKS containers, prompts for unlock, activates LVM, mounts root/ESP, and bind-mounts virtual filesystems
- Recovery: `detect_boot_health` now checks for missing `cryptdevice=` in bootloader config and missing `encrypt` hook in `mkinitcpio.conf`
- Recovery: `repair_boot` can now regenerate bootloader config with correct `cryptdevice=` and re-add the `encrypt` hook to `mkinitcpio.conf` for all four bootloaders

## v8.4.3.5 (2026-06-03) — ArtixForge

### Fixed
- LUKS: mapper name now dynamic (`cryptlvm` with LVM, `cryptroot` without) – fixes boot when LUKS is used without LVM
- LUKS: `crypt_uuid` correctly derived for LUKS-only setups (previously only worked with LVM)
- GRUB: `cryptdevice=` and correct `root=` now injected into `GRUB_CMDLINE_LINUX` when LUKS is active
- rEFInd: full kernel cmdline with `cryptdevice` and appropriate root written to `refind_linux.conf`
- EFIStub: cmdline rebuilt dynamically for LUKS/LVM combinations
- Limine: cmdline rebuilt dynamically for LUKS/LVM combinations
- UKI: cmdline now built dynamically instead of hardcoded; `cryptdevice=` only appended when LUKS enabled
- Bootloader: `grub-install` and `grub-mkconfig` wrapped with `xtrace_safe` to suppress debug fd leak noise

## v8.4.3.4 (2026-06-03) — ArtixForge

### Fixed
- LUKS+LVM: `encrypt` hook now added to `mkinitcpio.conf` when LUKS is enabled — `cryptsetup` now available in initramfs to unlock LUKS containers at boot
- LUKS+LVM: `crypt_uuid` now resolved from the underlying physical partition instead of the LV — `cryptdevice=` cmdline gets the correct UUID
- LUKS+LVM: EFIStub boot entry now includes `cryptdevice=` and `root=/dev/vg0/root` when LUKS/LVM are active
- Secure Boot: missing signing keys now log a warning instead of `die` — UKI generation completes without signing

## v8.4.3.2 (2026-06-03) — ArtixForge

### Fixed
- UKI: generation block moved after ESP detection — `esp_mount` and `root_uuid` now available when `ukify build` runs
- UKI: output path now uses `${esp_mount#/mnt}` to derive correct chroot path — fixes "No such file or directory" when `ukify` writes inside the chroot
- UKI: signing paths also use `${esp_mount}` — consistent with generated UKI location
- UKI: `mkdir` for output directory now runs inside the chroot via `artix-chroot /mnt mkdir -p`

## v8.4.3.0 (2026-06-03) — ArtixForge

### Changed
- Recovery: kernel detection now covers all nine supported kernels (linux, zen, lts, hardened, libre, cachyos-bore, bazzite, xanmod, tkg) plus custom Power User kernels
- Recovery: bootloader detection expanded to include Limine and rEFInd alongside GRUB and EFIStub
- Recovery: `repair_boot` now reinstalls the correct kernel package for any detected kernel variant
- Recovery: `repair_boot` can now reinstall Limine and rEFInd bootloaders, not just GRUB
- Recovery: install stage detection now reports Limine, rEFInd, and UKI presence
- Recovery: boot health check now detects missing UKI files and reports `no-uki`
- Recovery: `repair_uki` regenerates missing UKIs via `ukify build` when `eukify` is installed

### Fixed
- UKI: `ukify` binary now checked directly via `[[ -x /mnt/usr/bin/ukify ]]` instead of `command -v` in chroot — fixes false negative when `ukify` is installed but not found via `command -v`

## v8.4.2.5 (2026-06-03) — ArtixForge

### Fixed
- Debug mode: `xtrace_safe()` wrapper added to `common.sh` — prevents `BASH_XTRACEFD` from leaking into LVM tools and `basestrap`
- Debug mode: LVM `*create` commands and `basestrap` now wrapped with `xtrace_safe`; `mkfs` and `cryptsetup` left unwrapped for user visibility
- LVM: `pvcreate -ff` now used — suppresses "existing filesystem signature" prompt
- LVM/LUKS: stale device mapper entries and LVM volumes deactivated before disk wipe; mapper existence check added after `luksOpen`
- LVM/LUKS: `wipefs` on root partition skipped when LUKS is active — prevents destroying the LUKS header
- Partitioning: `blockdev --rereadpt` added after `partprobe` — forces kernel to reload partition table
- Limine: `limine.conf` now written to ESP (`${esp_mount}/limine.conf`) — Limine finds its config on the EFI partition
- UKI: replaced broken `uki` mkinitcpio hook with `eukify` (provides `ukify` binary) from Artix system repo — no systemd required
- UKI: removed mkinitcpio preset and hook injection; UKI generated directly via `ukify build` after initramfs creation
- UKI: Secure Boot signing restored with `sbsign` — signed UKI gets separate EFI boot entry
- UKI: all failures now hard `die` — UKI is all-or-nothing when requested

## v8.4.2.4 (2026-06-03) — ArtixForge

### Fixed
- Preflight: mirrorlist backup (`.orig`) now created unconditionally before ranking — retry always has a known-good fallback regardless of user choices
- Preflight: empty `rankmirrors` output now detected and discarded — prevents overwriting mirrorlist with nothing
- Preflight: `pacman -Sy` failure after ranking no longer silently swallowed — logged as warning, retry will attempt with original mirrors

## v8.4.2.3 (2026-06-02) — ArtixForge

### Fixed
- ZFS preflight: plain `linux` live ISO now allowed to install ZFS for `linux-zen` target — kernel ABI is compatible
- ZFS preflight: `mirrorlist_backup` variable now declared at function scope — fixes "unbound variable" crash when mirror ranking is skipped
- ZFS preflight: package install retry no longer uses nested `local` declarations that could trip `set -u`
- LVM: root partition disk-belonging check now skipped when LVM is active — logical volumes don't have a direct disk parent

## v8.4.2.2 (2026-06-02) — ArtixForge

### Changed
- Updated the README.md (Less of a clusterf...)

## v8.4.2.1 (2026-06-02) — ArtixForge

### Fixed
- Bootloader: `findmnt` Btrfs subvolume suffix (`/dev/sda3[/@]`) now stripped before block device checks — fixes "invalid root block device" crash on Btrfs installs
- Bootloader: `set -Eeuo pipefail` restored — was accidentally removed, errors now fail early instead of cascading silently
- Bootloader: rEFInd root device detection now also strips Btrfs subvolume suffix
- Bootloader: removed duplicate UKI existence check that ran before `esp_mount` was set — fixes undefined variable and false negative on UKI file detection
- UKI: `sed` hook injection no longer depends on line-start anchor — works with any `mkinitcpio.conf` formatting
- UKI: missing UKI file after `mkinitcpio -P` now triggers `die` instead of silent warning
- UKI: failed hook injection now triggers `die` — no point continuing if the `uki` hook can't be added to `mkinitcpio.conf`
- Basestrap: `BASH_XTRACEFD` now unset before `basestrap` call — prevents "invalid value for trace file descriptor" errors in post-transaction hooks

## v8.4.2.0 (2026-06-01) — ArtixForge

### Added
- Limine bootloader support — BTRFS snapshot boot entries, Windows chainloading, LUKS/LVM-aware kernel cmdline
- `limine-snapper-sync` automatically installed when BTRFS snapshot layout is selected with Limine

## v8.4.1.1 (2026-06-01) — ArtixForge

### Fixed
- Recovery mode: `detect_pacman_health` now saves the actual broken package list during detection — `repair_pacman` no longer re-detects and comes up empty
- Recovery mode: broken package reinstall uses `pacman --root /mnt` with `--overwrite '*'` in batches of 20 — avoids basestrap dependency failures on large reinstalls
- Recovery mode: broken package reinstall falls back to individual package installs for any batch that fails

## v8.4.1.0 (2026-06-01) — ArtixForge

### Added
- Recovery mode: "Repair filesystem corruption" — safe (`fsck -p`, `xfs_repair -n`, `btrfs check`) and destructive (`fsck -f -y`, `xfs_repair`, `btrfs check --repair`) options for ext4/xfs/btrfs
- Recovery mode: "Untrusted Recovery" — rootkit scan, malware indicator detection (suspicious cron, SUID binaries, SSH keys), optional ClamAV scan; read-only, no modifications

### Fixed
- Recovery mode: `detect_disk` now unwraps LUKS/LVM mappers, walks the device chain to find the physical disk, and falls back to fstab UUID or manual selection — fixes "Invalid disk device" after recovery reset
- Recovery mode: `repair_pacman` now actually reinstalls packages with missing files instead of just warning about them
- Recovery mode: `repair_detected_issues` only runs mkinitcpio and grub-mkconfig when boot or fstab issues were actually fixed — no more mindless initramfs rebuild on every recovery
- Recovery mode: added "Fix everything (nuclear)" option alongside the surgical "Repair detected issues"
- Builder: `BASE_DIR` fallback added so "Update ArtixForge and retry" correctly calls `${BASE_DIR}/install` instead of failing with `./install: command not found`

## v8.4.0.1 (2026-06-01) — ArtixForge

### Fixed
- Generic package install: replaced `cp -a` with `rsync --keep-dirlinks` — prevents symlink collisions on merged-usr systems (`/lib64`, `/sbin`) when installing source-built packages like glibc

## v8.4.0.0 (2026-06-01) — ArtixForge

### Fixed
- Kernel recipe: `VIRTIO_BLK` changed from module to built-in across all config branches — eliminates boot panic when initramfs doesn't load the module before root mount (Volk profile, Power User mode)
- `kconfig.bash`: `VIRTIO_BLK` changed from `--module` to `--enable` in `ensure_boot_essentials()`
- `kconfig.bash`: `DEVTMPFS_MOUNT` added to `ensure_boot_essentials()` — kernel now auto-mounts devtmpfs at boot
- Kernel recipe `localmodconfig` branch now calls `ensure_boot_essentials()` after `make localmodconfig` — live ISO built-in drivers (VIRTIO_BLK, DEVTMPFS, etc.) are no longer silently omitted from the generated config
- Kernel recipe `localmodconfig` branch now applies feature flags (`nvidia-support`, `amd-support`) and resolves dependencies with `yes "" | make oldconfig`
- Kernel recipe: duplicate `scripts/config` calls removed from default config branch
- `bcachefs` added to root filesystem driver case in `localmodconfig` branch
- LUKS+LVM: `luksFormat` now runs before `pvcreate` in `partition.sh` — fixes `pvcreate` failure on missing LUKS mapper
- LUKS (no LVM): `luksFormat` and `luksOpen` added to `filesystem.sh` — plain LUKS installs no longer format the raw partition unencrypted
- LUKS (no LVM): `luksOpen` added to `mount_filesystems()` — root partition correctly mounted from LUKS mapper
- LVM: `filesystem.sh` now creates filesystems on logical volumes instead of overwriting the physical volume
- Volk quick profile: added VM disclaimer — warns users the source-built kernel omits VirtIO drivers and won't boot in virtual machines

### Added
- Recipe self-healing: `heal.bash` auto-detects newer source versions for kernel.org, GitHub releases, and generic directory listings — failed fetches can now self-repair and retry

## v8.3.1.0 (2026-05-30) — ArtixForge

### Fixed
- UKI preset: `ALL_kver` now uses kernel version string instead of file path — mkinitcpio can find modules correctly
- UKI preset: `default_uki` uses generic `artix-linux.efi` instead of hardcoded `linux-custom`
- UKI preset: `uki` hook automatically appended to `mkinitcpio.conf` HOOKS if missing
- UKI EFI boot entry: paths updated from `linux-custom.efi` to `artix-linux.efi`
- EFIStub: kernel and initramfs images detected directly from `/mnt/boot/` instead of reading unset state variables
- CachyOS kernel: mirror scrape failure now falls back to static URLs instead of hard `die`
- Desktop install: `xlibre-input-wacom` added to KDE package array instead of separate install to resolve conflict with `xf86-input-wacom` in same transaction

## v8.3.0.2 (2026-05-30) — ArtixForge

### Fixed
- Power User mode from main menu now correctly sets `POWER_USER=yes` so selecting "Power User" no longer produces a standard install (Whoops...?)
- `verify_installer_layout` updated for new modular directory structure (`scripts/recovery/`, `tui/menus/`, `poweruser/tui/menup/`)
- Custom profile loader now persists all loaded variables to state so now loaded profiles work identically to built-in ones
- Duplicate `KERNEL_CONFIG_DEPTH`, `KEEP_BINARY_KERNEL`, `COREUTILS`, and `KERNEL_IMAGE` lines removed from `handoff.sh` config export
- `gartix` dispatcher and TUI no longer attempt to source nonexistent recovery file, functions are already available

## v8.3.0.0 (2026-05-29) — ArtixForge

### Added
- Three new Quick Install profiles: Gaming, Development, Media
- Custom profile loader — source saved configurations from file
- Quick Profile auto-save to `/etc/artixforge-profile.conf` after installation
- `gartix recovery` command for checking and repairing source-built packages
- `repair_kernel` function in recovery mode — rebuilds custom kernel with latest recipe
- Kernel repair available from build failure menu and `gartix recovery`
- `gartix_recovery.bash` module for post-install package repair

### Changed
- `scripts/tui/menus/` split into 9 focused sub-files
- `poweruser/tui/menu_poweruser.sh` split into 6 sub-files under `menup/`
- `scripts/recovery/` split into `core.sh`, `detect.sh`, `repair.sh`
- `gartix` split into `gartix`, `gartix_common.bash`, `gartix_cli.bash`, `gartix_tui.bash`
- `stage_poweruser` copies all `bin/` files instead of single `gartix` binary
- Kernel config depth defaults to `localmodconfig` in Quick Profiles and "No" path
- Project structure trees updated in README.md and poweruser/README.md

### Fixed
- `stage_validate` poweruser check uses kernel file existence, not `pacman -Q`
- Build timing summary uses `tui_msg_quick` instead of broken `tui_msg`
- Audio install split to avoid KDE `jack2`/`pipewire-jack` conflict
- Kernel recipe VirtIO dependency chain complete (`BLOCK`, `BLK_DEV`, `VIRTIO`, `VIRTIO_PCI`, `VIRTIO_BLK`)

## v8.2.3.4 (2026-05-29) — ArtixForge

### Changed
- Kernel recipe default config method switched to `localmodconfig` — compiles only currently loaded modules, eliminating dependency guessing and `olddefconfig` symbol dropping
- `localmodconfig` added as recommended kernel config depth option in Power User TUI
- `USB_HID` and `VIRTIO_BLK` added as modules to kernel recipe and `kconfig.bash` for initramfs compatibility
- Fallback manual config path uses `yes "" | make oldconfig` to prevent interactive prompts hanging automated builds

### Fixed
- `BLK_DEV` symbol added to kernel recipe dependency chain — `VIRTIO_BLK` was silently dropped without it
- `VIRTIO_PCI` transport added to kernel recipe and `kconfig.bash` `ensure_boot_essentials()`
- Audio package install split — `pipewire-jack` installed separately to avoid KDE `jack2` conflict loop

## v8.2.3.3 (2026-05-28) — ArtixForge

### Fixed
- Power User kernel install bypasses `pacman -U` for `linux-custom`, copying files directly to `/mnt`
- `curl_resume` called with correct argument order in `fetch_sources()`
- SKIP checksum prompt moved outside log redirection — no more invisible prompts stuck in log files
- Broken live-watch `gum pager` removed from build stage; users directed to `tail -f` the log instead
- `POWER_USER` variable added to `state_save()` — Quick Profile Power User state now persists correctly
- `mkinitcpio` added to base package list; no longer missing from minimal installs
- `tui_select_poweruser` checks `POWER_USER` state instead of `MODE` — Quick Profile + Power User works
- Template recipe excluded from `list_recipes()` display
- Gum help text guard added to `tui_poweruser_tweak_profile` to prevent corrupted custom profiles
- `linux.sh` recipe version bumped to 7.0.10 (was 7.0.8 — kernel.org removed the old tarball)
- Recipe auto-fetch runs before Power User config menu — no more empty recipe list on first run
- `tui_poweruser_config` streamlined with Yes/No gate for detailed config vs. auto-detected defaults
- Build timing summary uses `tui_msg_quick` instead of broken `tui_msg` with literal `\n`
- `recoverable_error` function added to `scripts/common.sh` — users can update ArtixForge and retry on critical failures
- `recoverable_error` integrated into `basestrap.sh`, `bootloader.sh`, and `poweruser.sh`
- `stage_poweruser` sources `tui/core.sh` and `scripts/common.sh` for TUI function availability
- Power User kernel recipe install creates `mkinitcpio` preset for `linux-custom`
- `configure_bootloader` validates initramfs by file existence, not `mkinitcpio` exit code — warnings no longer fatal
- ArtixForge self-update available from build failure menu with `exec sudo ./install` restart
- `stage_validate` poweruser check now tests for kernel file existence instead of `pacman -Q` — resume no longer loops on direct-copy installs
- Audio package install uses `--ask=1` to auto-resolve pipewire-jack/jack2 conflicts from KDE dependencies
- Kernel recipe and `kconfig.bash` now enable full VirtIO dependency chain (`VIRTIO`, `VIRTIO_MENU`, `VIRTIO_PCI`, `VIRTIO_BLK`) to prevent `olddefconfig` from silently dropping block driver support

## v8.2.0.0 (2026-05-28) — ArtixForge

### Added
- BTRFS snapshot integration with snapper + GRUB boot menu entries via `grub-btrfs`
- Snapper timeline and cleanup services enabled automatically for BTRFS installs
- `gartix checksum <recipe>` command for generating SHA256 hashes from upstream sources
- SKIP checksum warning in builder with user confirmation prompt
- Categorized extras: System Tools, Editors, Browsers, File Managers, Terminals, Shell & Prompt, Monitoring, Media
- 18 new extra packages: nano, vim, neovim, micro, helix, firefox, chromium, qutebrowser, ranger, lf, nnn, thunar, alacritty, kitty, foot, mpv, feh
- DNS lookup fallback in network connectivity check (dig/nslookup before curl/ping)
- vxwm window manager support (dwm fork with modules, compiled from source)
- Volk's Personal Quick Profile (dinit, KDE minimal, LightDM, source-built kernel)
- LightDM support for KDE Plasma with automatic SDDM replacement
- Recovery repair system: automatic fstab regeneration, pacman lock removal, base package reinstall, kernel reinstall, initramfs rebuild, and GRUB EFI entry repair
- Rootkit scanning via rkhunter in Recovery mode

### Changed
- Replaced `ufw` with `firewalld` across all profiles, extras, and sanity warnings
- ZFS services now use `enable_service` for init-agnostic configuration
- Project renamed to ArtixForge — installer paths, config files, and documentation updated
- Community recipes repository renamed to `ArtixForge-recipes`
- Desktop Quick Install profile now includes firefox, neovim, and alacritty
- Recovery mode now detects LVM, ZFS, UKI, coreutils, Power User state, privilege escalation, install progress, fstab health, boot health, and pacman integrity

### Fixed
- XFS bigtime check in post.sh now runs inside chroot with correct variable escaping
- `enable_service` used consistently for ZFS and snapper across all init systems
- KDE Plasma with LightDM no longer leaves SDDM installed as a conflicting dependency

## v8.1.1.0 (2026-05-27)

### Added
- Community recipe system: `ArtixTUI-recipes` repository with 31 recipes across OFFICIAL/Base, OFFICIAL/Other, and COMMUNITY sections
- `gartix` can fetch individual recipes, sync all enabled sections, and manage section preferences
- `.LIST` index format for recipe discovery (`pkgname|section|description`)
- Power User mode auto-fetches OFFICIAL/Base recipes on first run when the recipes directory is empty
- Recipe section selector in installer TUI (OFFICIAL/Base, OFFICIAL/Other, COMMUNITY/Base, COMMUNITY/Other)
- 20 new OFFICIAL/Other recipes: browsers, media tools, Wayland compositors, development tools, system tools, gaming, libraries, network/security, terminal
- `gartix` section management via CLI (`gartix sections`) and TUI ("Manage recipe sections")
- `gartix` recipe fetch via CLI (`gartix fetch-recipe <name>`) and TUI ("Fetch a recipe from repo")
- `ArtixTUI-recipes` repository with VERSION file and contribution structure

### Changed
- `poweruser/recipes/` now ships only `template.sh` — all other recipes moved to community repo
- `stage_poweruser` auto-downloads OFFICIAL/Base recipes when the local recipe directory is empty
- `gartix sync` now pulls `.LIST` and offers to update all enabled recipes
- `gartix fetch-all` respects enabled section filtering
- `list_recipes()` unchanged — automatically picks up downloaded recipes

### Fixed
- `gartix` theme colours now load from `/etc/gartix-theme.conf` correctly

## v8.0.2.4 (2026-05-26)

### Added
- Colour theme system with five presets: Gentoo (default), Artix, Jet Black, Mono, Retro
- Theme preview with keep/change loop during installation
- Theme persistence: saved to `/etc/gartix-theme.conf` and loaded by `gartix` on startup
- ANSI colour mapping for `log_info` and `log_warn` so log output follows the chosen theme
- `summary.sh` labels now use theme colours
- `gartix` inherits the installer's theme automatically

### Fixed
- Quick install summary now displays proper newlines instead of raw `\n`
- Removed duplicate summary display when using Quick Install profiles
- `check_disk_space` typo in preflight.sh corrected

## v8.0.1.9 (2026-05-26)

### Added
- Resilience helpers: `check_disk_space`, `retry_command`, `clean_pacman_lock`, `curl_resume` added to both `scripts/common.sh` and `poweruser/lib/common.sh`
- Disk space checks at critical stages: preflight (3GB), base (5GB), poweruser (10GB)
- Pacman lock recovery before every `pacman -S` call in basestrap, drivers, and desktop installs
- Retry with exponential backoff for pacman installs in drivers.sh and desktop.sh
- Mid-build resume for Power User recipes via `ARTIX_RESUME_BUILD` flag — preserves work directory on retry
- Resume partial downloads via `curl_resume` in builder.bash `fetch_sources()`
- Enhanced `stage_validate()` in state.sh with real success indicators for base, poweruser, and chroot stages
- VirtIO block driver (`virtio_blk`) added to initramfs MODULES for QEMU/VirtIO VM support
- VFAT/FAT32 kernel module loading: `modprobe fat` first, then `vfat`, with `/proc/filesystems` fallback
- EFI partition check now accepts both `vfat` and `fat32` filesystem labels
- Added a PRIVACY_POLICY.md
- Moved all non-essential documentation for the installer into DOCUMENTS

### Fixed
- Stale UKI state: `state.conf` wiped before fresh auto/manual installs to prevent leaking `GENERATE_UKI=yes` between runs

## v8.0.1.4 (2026-05-24)

### Fixed
- Quick Install profiles now fully define all system variables instead of relying on defaults
- Quick Install profiles now ask for hostname, timezone, locale, keymap, username, and passwords
- Added "Customize" option after Quick Install confirmation to drop into full manual flow
- Desktop profile now uses xlibre (Artix default) instead of X.Org
- UKI preset now dynamically detects installed kernel instead of hardcoding `vmlinuz-linux-custom`
- Quick Install profiles now always run disk selection before proceeding
- Preflight: added `pacman -Sy` before package installation to prevent mirror sync issues
- `state_get`: now returns default value when stored value is empty, not just unset
- `bootloader.sh`: removed duplicate `fi` causing syntax error

## v8.0.1.1 (2026-05-24)

### Fixed
- UKI preset now dynamically detects installed kernel instead of hardcoding `vmlinuz-linux-custom`
- Quick Install profiles now always run disk selection before proceeding

## v8.0.1.0 (2026-05-23)

### Fixed
- UKI reworked as independent toggle alongside any bootloader, not a standalone option
- Removed `uki` from bootloader case in basestrap.sh
- Added `GENERATE_UKI` to state.sh, summary.sh, and handoff.sh
- Removed duplicate v8 variables from handoff.sh config block

## v8.0.0.1 (2026-05-23)

### Fixed
- state.sh: restored missing `stage_validate()` function header lost during v8 merge
- Added missing documentation files: GUIDE.md, CHANGELOG.md, SECURITY.md, OSI.md

## v8.0.0.0 (2026-05-23)

### Added
- UKI (Unified Kernel Image) boot support
- LVM (Logical Volume Management) with LUKS integration
- Swappable coreutils: GNU, BusyBox, uutils, ArtixTUI minimal, Custom
- BusyBox init system (fifth init option, Power User only)
- Quick Install profiles: Desktop, Server, Minimal, Embedded
- Network pre-configuration in require_internet()
- Custom mirror ranking via rankmirrors
- Offline source bootstrap (`gartix fetch-all`)
- UKI Secure Boot signing
- Fallback kernel toggle (keep or skip binary kernel in Power User mode)
- Binary kernel recovery option when source build fails
- Sanity warnings for dangerous feature combinations
- Installation guide (GUIDE.md)

### Changed
- Kernel recipe now starts from allnoconfig, enabling only selected hardware
- Kernel recipe ensures root filesystem driver is built-in
- Kernel recipe adds NVMe and VirtIO block to boot essentials
- gartix upgrade now versions and backs up recipes before pulling
- init system validation in chroot stage tolerates BusyBox
- Preflight installs kernel build tools when Power User mode is active
- Post-build validation checks UKI and LVM configurations
- State persistence includes all v8 variables

### Fixed
- users.sh heredoc quoting for password hashes
- builder.bash copy-to-target race condition with sync+sleep

## v7.2.0.0 (2026-05-15)

### Added
- Power User Mode: source-based package compilation
- gartix package manager (CLI + TUI)
- Hardware auto-detection for kernel configuration
- Feature flags per package
- Compilation profiles with custom flag tweaking
- Build queue with resume and error recovery
- doas as alternative to sudo
- Filesystem best practices (XFS GRUB-safe, F2FS compression, SSD discard)
- Gentoo-wiki-inspired filesystem hardening
- Tabbed TUI (gum-based)
- Recipe system (create, edit, lint, build)
- Post-build system validation
- Live build log viewer
- Binary cache and rebuild detection

## v7.1.5.0 and earlier

- Initial public release
- Basic TUI installer with gum
- Core installation pipeline (partition, format, basestrap, chroot, post)
- Multiple kernel, filesystem, desktop, and bootloader support
- LUKS encryption
- Recovery and resume modes