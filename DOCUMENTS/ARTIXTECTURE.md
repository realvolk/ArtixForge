# ARTIXTECTURE.md — Artix Installer Architecture

This document describes the internal architecture of Artix Installer: how the
state machine works, how the stage pipeline is structured, how the TUI
integrates with gum, how the major subsystems are organized, and how to
add a new configuration option. It is written for contributors who need to
understand the codebase without reverse-engineering it.

---

## 1. Overview

Artix Installer is a **declarative system deployment framework** that materializes
a complete Artix Linux installation from a central state file. All user
choices are collected through a TUI, stored as key-value pairs
in `/tmp/artix-installer/state.conf`, and consumed by a linear pipeline of
stage scripts. Subsystems for recovery, system migration, ISO generation,
and source-based package management (Power User) read from the same state
file, making the installer, the recovery tool, the migration engine, and
the package builder all instances of the same underlying framework.

The framework is written entirely in **Bash** (≈12,000 lines). The user
interface is provided by **gum**, a terminal UI toolkit that handles
rendering, input, and interactive widgets.

All framework code lives under `bashisms/`. The repository root contains
only the entry point (`install`), packaging (`PKGBUILD`), version metadata
(`VERSION`), documentation (`DOCUMENTS/`), and the `bashisms/` tree itself.

### 1.1 Directory Layout

| Directory | Purpose |
|-----------|---------|
| `bashisms/state/` | State registry, file management, validation, inheritance, encryption |
| `bashisms/common/` | Logging, retry helpers, kernel detection, YAML parser |
| `bashisms/packages/` | Package data (`catalog/`), query functions (`resolve.sh`), install helpers (`install.sh`) |
| `bashisms/tui/` | gum wrappers, menus, summary rendering |
| `bashisms/installer/` | Install pipeline: stages, storage, install modules, post-install |
| `bashisms/recovery/` | Detection and repair subsystems |
| `bashisms/migrations/` | Init, desktop, and ATA migrations |
| `bashisms/iso/` | ISO builder wrapping `artools` |
| `bashisms/poweruser/` | Source-based package manager (`anvil`) |

---

## 2. Entry Point (`install`)

The script `install` in the repository root is the entry point for all
modes. Its responsibilities are:

- **Self-copy to `/tmp/artix-run`**: ensures a writable working directory
  even on read-only media (ISO loopback, NFS).
- **Self-update check**: compares `VERSION` against the upstream GitHub
  release and offers to update.
- **gum bootstrap**: checks for `gum` binary, installs if missing.
- **Mode dispatch**: presents a main menu (`Installation`, `Resume`,
  `Advanced`) and routes to the appropriate pipeline function. The
  Advanced menu (Recovery, Power User, Migration, ISO) requires the root
  password via `_verify_root_password`.
- **Bug report generator**: `_generate_bug_report` collects logs, state,
  stage markers, and system info into a tarball on failure.
- **Post-install script validation**: `_validate_post_install_script`
  checks path exists and is readable before pipeline.
- **Layout verification**: `verify_installer_layout` checks that every
  required `bashisms/` subdirectory exists before sourcing anything.
  Failure triggers `self_update_installer` to repair the tree.

The source block sources subsystems in dependency order: `common` → `state`
→ other `common` → catalog → resolve → install helpers → everything else.
Subdirectories are sourced via `source_tree`, which finds every `*.sh` at
`-maxdepth 1` and sources it in sorted order. Catalog files have no
dependencies on each other, so alphabetical order is fine.

---

## 3. State Management (`bashisms/state/state.sh`)

The state file at `/tmp/artix-installer/state.conf` is the **single source
of truth** for the entire deployment. It is a flat key-value file with
`%q`-encoded values. The state file is the interface — no command-line
flags configure behavior; everything is declared in state.

### 3.1 Reading and Writing

- `state_get <key> <default>` reads a key from the state file. The file
  stores values with `printf '%q'` encoding, so a value containing single
  quotes, backslashes, or spaces round-trips correctly. `state_get`
  decodes with `eval "printf '%s' ${raw}"` — the `%q` inverse.
- `state_set <key> <value>` writes a key immediately via a temp-file
  rewrite (not `sed -i`), using `printf '%q'` for the value.
- `state_save` iterates the state registry (§3.8) and serializes every
  registered key to the state file atomically (write to `.tmp`, then `mv`).
  Per-user keys (`USER_<n>_*`) are written by a hand-written loop after
  the registry loop, driven by `USER_COUNT`.

### 3.2 Validation

`lint_state` runs before any pipeline. It checks a small set of required
keys (DISK, FS_TYPE, BOOTLOADER, KERNEL_CHOICE, INIT), iterates
`STATE_VALIDATORS` for enum checks (FS_TYPE, INIT, BOOTLOADER,
PRIV_ESCALATION, X_STACK, USE_LUKS, USE_LVM, GENERATE_UKI,
ENABLE_ARCH_REPOS, ARTIX_BOOT_MODE, SWAP_ENABLED, MICROCODE_OVERRIDE,
AUDIO_STACK, NETWORK_STACK, DISPLAY_MANAGER), and runs three special-case
checks that don't fit the validator pattern: target disk is a block
device, and when `USER_COUNT=0` a root password must be set.

Adding an enum validator is one entry in `STATE_VALIDATORS` in
`bashisms/state/state.sh`. No other file changes.

### 3.3 Inheritance

A preset file can declare `BASE_STATE='/path/to/base.conf'`. When loaded
via `state_load_preset`, the base is loaded first and the preset's keys
are applied on top. Relative paths resolve against the preset's directory.
Empty values in the override mean "use base". There is exactly one level
of inheritance — no recursion.

### 3.4 Templating

State values can reference other keys: `HOSTNAME='${USER_1_NAME}-machine'`.
`state_resolve_templates` resolves `${KEY}` references after preset load
using bash indirect expansion. No eval, no shell injection. Unknown
references are left literal. Maximum 10 iterations guards against cycles.

### 3.5 Encryption

Presets can be encrypted with GPG symmetric encryption (AES256). The
encrypted format is a magic header (`ARTIXFORGE_ENCRYPTED=1`) followed by
base64-encoded GPG binary. `state_encrypt_preset` and
`state_decrypt_preset` handle encryption and decryption. Passphrases pass
via fd 3, never on the command line. The live state file remains plaintext
on tmpfs — encryption is for persistent presets only.

### 3.6 Stage Tracking

Each stage of the pipeline is tracked by a sentinel file in
`/tmp/artix-installer/stages/<name>.done`. The function `stage_should_skip`
checks both the sentinel and the actual state of the environment (via
`stage_validate`). If a stage is marked complete but the environment is
invalid (e.g., `/mnt` is empty after a reboot), the stage is reset and
re-run. This enables crash-resume.

The `payload` stage uses a **target-side marker** in addition to the local
sentinel: `/mnt/.artixforge-payload-<profile>`. `stage_validate payload`
checks the marker, not the sentinel, so the stage is only considered valid
if its overlay was actually applied to the target.

### 3.7 Adding a State Key

Adding a new configuration option is a registry edit plus the code that
sets it. Concretely:

1. **Registry entry** in `bashisms/state/state.sh`:
   - Add the key to `STATE_KEYS` (the ordered master list).
   - Add its default to `STATE_DEFAULTS`.
   - If it has an enum constraint, add a regex to `STATE_VALIDATORS`.
2. **Cross the chroot boundary** if the key is read by anything under
   `bashisms/installer/post/`: add it to `STATE_KEYS_CHROOT`. That one
   array feeds both `handoff.sh`'s write of
   `/mnt/etc/artix-installer.conf` and `stage_post`'s heredoc exports.
3. **Persist in the quick-install profile** if the key belongs there: add
   it to `STATE_KEYS_PROFILE`.
4. **Set it** wherever the TUI prompt or subsystem sets it, via
   `state_set`.

That's the whole list. Per-user keys are handled by
`STATE_USER_FIELDS` + `STATE_USER_DEFAULTS` (arrays of field names and
defaults); adding a per-user field is one entry in each.

### 3.8 The State Registry

The registry is a set of arrays in `bashisms/state/state.sh` that own the
key list:

| Array | Shape | Consumers |
|-------|-------|-----------|
| `STATE_KEYS` | ordered list of static key names | `state_save` |
| `STATE_DEFAULTS` | assoc: key → default value | `state_save`, `handoff.sh`, `stage_post.sh` |
| `STATE_VALIDATORS` | assoc: key → POSIX regex | `lint_state` |
| `STATE_KEYS_CHROOT` | ordered list, subset | `handoff.sh`, `stage_post.sh` |
| `STATE_KEYS_PROFILE` | ordered list, subset | `handoff.sh` |
| `STATE_USER_FIELDS` | ordered list of suffixes (`NAME`, `PASS`, …) | `state_save`, `handoff.sh` |
| `STATE_USER_DEFAULTS` | assoc: suffix → default | `state_save` |

Before the registry, adding a key required editing four to six places
(`state_save`'s printf block, `handoff.sh`'s config export, the
`stage_post` heredoc, `lint_state`, and any preset-aware code). Missing
one silently dropped the key on the next save — this happened with
`QUICK_PROFILE` and `PROFILE_PACKAGES` in v9.4.0.6. The registry makes
that class of bug structurally impossible: `state_save` iterates
`STATE_KEYS`, so a key that is registered is persisted, and a key that is
not registered does not exist.

The three view arrays (`STATE_KEYS_CHROOT`, `STATE_KEYS_PROFILE`,
`STATE_USER_FIELDS`) are the only place a key's "which consumers see it"
decision lives. There is no separate handoff config export to keep in
sync.

---

## 4. User Interface Layer (`bashisms/tui/`)

All user interaction goes through gum, a terminal UI toolkit. The Bash
side calls gum commands directly through wrapper functions.

### 4.1 Core Transport (`core.sh`)

`tui_msg`, `tui_yesno`, `tui_input`, `tui_password`, `tui_menu`,
`tui_checklist`, `tui_filter`, and `tui_msg_quick` are thin wrappers that
format output and call gum commands. Each wrapper handles `/dev/tty`
redirection for reliable terminal access.

### 4.2 Menu System (`menus/`)

Configuration is collected through sequential menus. Each menu file
(`main.sh`, `desktop.sh`, `user.sh`, etc.) contains functions that prompt
for specific configuration categories, read user input via TUI wrappers,
and write to the state file.

The `tui_collect_install_config` function in `main.sh` orchestrates the
full flow: theme, disk, quick profile (optional), init, filesystem,
bootloader, UKI, kernel, power user, microcode, desktop, display manager,
display stack, network, audio, shell, privilege escalation, extras, LUKS,
AURIS, Arch repos, offline mode, hostname, timezone, locale, keyboard
layout, users, and sanity warnings.

### 4.3 Quick Profiles

Quick Profiles come in two forms. When the `iso-profiles` package is
installed and `/usr/share/artools/iso-profiles/{common,base}` exist,
`quick_profiles.sh` offers upstream Artix profiles via `iso_profiles_list`
and loads their package sets into `PROFILE_PACKAGES` via
`quick_profile_load`. The hardcoded presets remain as a fallback when
upstream profiles are unavailable, and both paths share a common finalize
step (hostname, timezone, locale, keyboard, users, summary, customize).

---

## 5. Stage Pipeline (`bashisms/installer/stages/`)

The installation pipeline is a linear sequence of stages, each
implemented as a separate script:

| Stage | Script | Responsibility |
|-------|--------|----------------|
| preflight | `preflight.sh` | Dependency checks, network, kernel modules |
| storage | `storage.sh` | Partitioning, filesystem creation, mounting |
| base | `base.sh` | `basestrap` base system, kernel, init |
| poweruser | `poweruser.sh` | Source-based package compilation |
| payload | `payload.sh` | Applies `root-overlay` trees from upstream iso-profiles for the selected Quick Profile |
| chroot | `chroot.sh` | System configuration, users, bootloader |
| init | `init.sh` | BusyBox init setup (if applicable) |
| post | `post.sh` | Desktop, drivers, audio, extras |
| finalize | `finalize.sh` | Validation, report, post-install script, unmount |

Each stage script follows the same pattern:

1. Call `stage_should_skip <name>`; return 0 if already completed.
2. Perform the stage's work.
3. Call `stage_mark_done <name>`.
4. Return 0.

Stages are called sequentially by `run_install_pipeline` in `install`.
The Power User stage is only executed if `POWER_USER=yes` in the state.
The payload stage is only executed if `QUICK_PROFILE` is set; it
self-skips cleanly when no profile is selected or when `iso-profiles` is
unavailable. Before any stage runs, `lint_state` validates the state file
and `_validate_post_install_script` checks the post-install script path if
set.

---

## 6. Subsystem Architecture

### 6.1 Storage (`bashisms/installer/storage/`)

- `partition.sh` creates MBR (BIOS) or GPT (UEFI) layouts, with
  optional LVM on LUKS setup.
- `filesystem.sh` formats partitions, handles LUKS encryption, LVM
  logical volumes, and filesystem-specific options (XFS bigtime, F2FS
  compression, BTRFS).
- `mount.sh` mounts the root filesystem, creates BTRFS subvolumes,
  and mounts the EFI partition.

All three use `state_get` for configuration and support both BIOS and
UEFI paths.

### 6.2 Bootloader (`bashisms/installer/install/bootloader.sh`)

The main script `configure_bootloader` detects the root device, generates
a kernel command line via `generate_root_cmdline` (handling LUKS, LVM,
BTRFS), runs `mkinitcpio`, and dispatches to a per-bootloader
backend. Backends live in `bashisms/installer/install/bootloaders/`:

- `grub.sh` — GRUB for UEFI and BIOS, with LUKS/LVM support.
- `refind.sh` — rEFInd configuration.
- `efistub.sh` — direct kernel boot from UEFI firmware.
- `limine.sh` — Limine bootloader with snapshot entries.
- `uboot.sh` — U-Boot for ARM boards.

### 6.3 Base System (`bashisms/installer/install/basestrap.sh`)

This is the largest function in the installer. It selects packages based
on the chosen init, kernel, filesystem, bootloader, desktop, and network
stack — all via `resolve_*` calls into `bashisms/packages/`. It handles
third-party repository setup (CachyOS, Chaotic-AUR, ARMtix) and
kernel-specific build logic (TKG, Bazzite). Kernel detection is in
`bashisms/common/kernels.sh`.

### 6.4 Post-Install (`bashisms/installer/post/`)

Each script in `post/` is sourced inside a chroot and configures one
aspect of the installed system:

- `desktop.sh` — installs DE/WM, display manager, display stack via
  `resolve_de_packages`. Multi-DE install from system and per-user keys.
  Appends `PROFILE_PACKAGES` from the selected Quick Profile before dedup
  and install.
- `drivers.sh` — GPU drivers, VM guest agents, Nouveau fallback. Uses
  `resolve_gpu_packages`, `resolve_vm_packages`, `resolve_kernel_headers`,
  `resolve_xstack_packages`, and `resolve_de_display_server`.
- `audio.sh` — PipeWire or PulseAudio setup via
  `resolve_audio_packages` / `resolve_audio_service_packages`. Conflict
  list comes from `AUDIO_CONFLICTS`.
- `networking.sh` — NetworkManager, dhcpcd+iwd, or ConnMan via
  `resolve_network_packages` / `resolve_network_services`. Conflict
  detection is catalog-driven.
- `extras.sh` — additional user-selected packages.
- `users.sh` — user creation, password hashing, sudo/doas setup,
  per-user DE, dotfiles cloning.
- `system.sh` — hostname, locale, keymap, timezone.

The chroot heredoc exports every key in `STATE_KEYS_CHROOT`; the post
modules read those from the environment, not from the state file.

### 6.5 Recovery (`bashisms/recovery/`)

Recovery has two phases:

- **Detection** (`detects/`): 30+ functions that probe the target system
  and reconstruct a state file (`reconstruct_state_from_system`).
- **Repair** (`repairs/`): functions that fix detected issues (fstab,
  pacman, bootloader, kernel, seat manager, filesystem).

The TUI presents the detected state and offers repair actions. All
detection is read-only until the user confirms a repair. Recovery keys
(`FSTAB_ISSUES`, `BOOT_ISSUES`, `PACMAN_ISSUES`, `MIGRATION_ISSUES`,
`ISO_ISSUES`, `BROKEN_PACKAGES`, `SEAT_MANAGER`, `SEAT_MANAGER_DISABLED`,
`HAS_CHAOTIC`, `RECOVERY_STATUS`) are in the state registry, so detection
results persist across `state_save`.

### 6.6 Migration (`bashisms/migrations/`)

Three migration types, all state-driven and resumable:

- **Init migration** (`inits/common.sh`): service mapping tables live in
  `bashisms/packages/catalog/services.sh`; the migration file reads them
  via `resolve_service_map`. Hub-chaining through OpenRC. Explicit target
  selection via `ensure_migration_root`, guarded against double-source so
  a single migration run does not re-prompt.
- **Desktop migration** (`des/common.sh`): generic logic that detects the
  current DE via `resolve_detect_current_de`, dynamically discovers
  installed packages via `resolve_de_installed_packages`, and installs the
  target DE via `resolve_de_packages`. Uses `pacman -Rdd` for package
  removal and user-visible orphan cleanup. Source guard added.
- **ATA migration** (`ata/`): full Arch→Artix conversion with audit,
  selective backup, conversion, package replacement, and service
  migration. `ATA_SKIP_UNITS` and `ATA_ARCH_DE_PACKAGES` are catalog data;
  `resolve_systemd_unit_package` handles the live package lookup for each
  systemd unit. GNOME detection warns the user and sets `WM_DE=none` —
  GNOME is unsupported on Artix since September 2025.

All migrations use stage files (`migration-stage.conf`) for crash-resume.
Migration keys are persisted through `state_save`.

### 6.7 ISO Builder (`bashisms/iso/`)

A wrapper around `artools` that **extends an upstream `iso-profiles` base
profile** with Artix Installer-specific additions:

- `profile-artixforge.yaml` — live session user, services, and per-init
  packages layered on top of the upstream profile.
- `live-overlay/` — installer-ISO auto-boot hooks for openrc/dinit/runit/s6
  (written only in installer-ISO mode; upstream `live-overlay/` content is
  preserved otherwise).
- `airootfs/root/ArtixForge/` — the installer tree, baked into the ISO.
- `packages-offline.x86_64` — package list used by `build_offline_repo`
  for offline bundle downloads.

The extended profile lives in the artools workspace and is **not** written
back to `/usr/share/artools/iso-profiles/` — that would shadow upstream
profile directories and risk cross-contamination between the ISO build
path and the install-time payload path. Supports offline mode, non-repo
kernel builds, and ARM aarch64 targets. Kernel menus read
`ISO_KERNEL_CHOICES`; extras menu reads `ISO_EXTRA_PACKAGES_CHOICES`;
offline package list comes from `generate_offline_package_list`, which is
now a resolver consumer.

### 6.8 Power User (`bashisms/poweruser/`)

A complete source-based package manager implemented in Bash. Key files:

- `lib/recipe.bash` — recipe loading with feature flag metadata parsing.
- `lib/flags.bash` — flag resolution, global defaults, conflict detection.
- `lib/deps.bash` — topological dependency sort with virtual providers.
- `lib/builder.bash` — full build lifecycle with ccache, safety checks,
  sub-packages, file inventory, and atomic staging.
- `lib/kconfig_fragments.bash` — kernel config fragment processor.
- `bin/anvil` — CLI dispatcher for post-install package management.
- `bin/anvil_tui.bash` — gum TUI for interactive package management.

The Power User TUI configuration is in `bashisms/tui/menus/poweruser.sh`.

### 6.9 iso-profiles Integration (`bashisms/common/yaml.sh`, `bashisms/installer/iso-profiles.sh`, `bashisms/installer/stages/payload.sh`)

Artix Installer consumes the upstream `iso-profiles` package at
`/usr/share/artools/iso-profiles/` for two purposes:

- **Quick Profiles** — `bashisms/common/yaml.sh` provides a line-oriented
  parser for the Artix profile YAML format (top-level keys, nested keys at
  2/4/6-space indents, dash-lists, inline scalars, comments, quotes, and
  `---`; fails silently on unrecognized constructs).
  `bashisms/installer/iso-profiles.sh` uses it to discover profiles
  (`iso_profiles_list`), fetch the upstream `wip` tarball on demand
  (`iso_profiles_ensure`), check staleness against upstream
  (`iso_profiles_validate`, soft-fail), and union the selected profile's
  package sets into `PROFILE_PACKAGES` (`quick_profile_load`).
- **Payload overlays** — `bashisms/installer/stages/payload.sh` applies
  `root-overlay` trees from `common`, `common/community`, the profile's
  GTK or Qt family overlay, and the selected profile itself to the target
  between the `poweruser` and `chroot` stages. Overlays are copied with
  `cp -rL` (symlinks dereferenced). Only `root-overlay` trees are applied
  to the installed system; `live-overlay` belongs to the ISO build path
  (§6.7).

The same source of truth feeds the ISO builder, which extends upstream
base profiles rather than generating its own.

### 6.10 Package Catalog (`bashisms/packages/`)

The package subsystem is the single source of truth for every package
list in the project. Before it existed, "what does XFCE need" was
answered in four or more places (`_desktop_packages_for`, DE migration
arrays, ATA detection tables, ISO offline list) and they had drifted.

Three layers, sourced in order by `install`:

- **`catalog/*.sh`** — pure data, no functions, no state reads. One file
  per domain: `ata.sh`, `audio.sh`, `base.sh`, `bootloader.sh`, `de.sh`,
  `extras.sh`, `filesystem.sh`, `gpu.sh`, `init.sh`, `iso.sh`,
  `kernel.sh`, `network.sh`, `services.sh`, `xstack.sh`. Each declares
  associative or indexed arrays consumed by the resolver layer.
- **`resolve.sh`** — pure query functions. Every function takes arguments
  (no `state_get` inside), prints newline-separated output, and is
  consumed by callers via `mapfile -t`. Examples: `resolve_de_packages
  <de> <init> <kde_profile>`, `resolve_audio_service_packages <stack>
  <init>`, `resolve_systemd_unit_package <unit> <init>`,
  `resolve_service_map <src> <tgt> <service>`.
- **`install.sh`** — `pkg_install` (dedupes, calls `retry_command`),
  `pkg_install_from`, `pkg_remove`, `pkg_exists`, `pkg_verify_list`,
  `pkg_query_installed`.

**Adding a DE, kernel, network stack, audio stack, filesystem, or
bootloader is one catalog entry plus the TUI prompt.** Every consumer
picks it up automatically. The `DE_SEAT_PACKAGE`, `DE_DISPLAY_MANAGER`,
`DE_DISPLAY_SERVER`, `DE_TOOLKIT`, `DE_PRETTY_NAME`, `DE_TO_PROFILE`,
`DE_DETECT_PATTERN`, `DE_DETECT_ORDER`, `DE_INSTALL_LIST`,
`DE_MIGRATION_TARGETS`, and `DE_MIGRATION_SOURCES` arrays in `catalog/de.sh`
together define a DE completely; adding one means editing each of those
(in most cases one line apiece).

GNOME is deliberately absent. Artix dropped GNOME support in September
2025 because `gnome-session` 49 removed the non-systemd fallback code
that elogind patches had been relying on. The stale `world` packages can
be installed but GNOME will not launch on Artix's inits. ATA detects
GNOME on the source Arch system and warns the user before migration, but
the fresh-install path does not offer it.

---

## 7. Adding a Configuration Option

To add a new user-facing option (e.g., a new kernel variant), touch these
files:

1. **Registry** in `bashisms/state/state.sh`: add the key to `STATE_KEYS`,
   its default to `STATE_DEFAULTS`, and any validator to
   `STATE_VALIDATORS`. If it crosses the chroot boundary, add it to
   `STATE_KEYS_CHROOT`; if it belongs in the quick-install profile, add it
   to `STATE_KEYS_PROFILE`. Per-user fields go in `STATE_USER_FIELDS` and
   `STATE_USER_DEFAULTS`.
2. **TUI menu**: add the prompt in the relevant menu file under
   `bashisms/tui/menus/`.
3. **Catalog** (if it selects packages): add the entry to the relevant
   `bashisms/packages/catalog/*.sh` file. Add a resolver if the consumer
   needs a new query shape.
4. **Backend logic**: handle the new key in the appropriate stage script
   or subsystem library, calling the resolver from the catalog.

Steps 4 through 7 of the previous version of this document — handoff
config export, chroot heredoc export, `lint_state` hand-edits, and
`state_save` printf lines — are gone. The registry covers all of them.

Recovery detection for a new key (if applicable) is still a separate
edit: `bashisms/recovery/detects/` for the detection function, and
`bashisms/recovery/repairs/` for the repair function.

---

## 8. Resilience Patterns

- **Atomic state writes**: `state_save` writes to `.tmp` then `mv`.
- **State validation**: `lint_state` runs before every pipeline.
- **Stage validation**: `stage_should_skip` re-validates the environment,
  not just the sentinel file.
- **Retry with backoff**: `retry_command` in `bashisms/common/common.sh`
  for network operations (3 attempts, 5/10/20s delays, deterministic-error
  short-circuit, output captured to `/tmp/artix-installer/logs/retry.log`).
- **Pacman lock recovery**: `clean_pacman_lock` before every `pacman` call.
- **Disk space checks**: before critical stages (3 GB, 5 GB, 10 GB).
- **Debug mode**: `set -x` to fd 19, log at
  `/tmp/artix-installer/logs/artix-debug.log`, separate from TTY.
- **Self-update**: `recoverable_error` offers to update Artix Installer
  from GitHub and restart. Falls back to `log_error` when no TTY is
  available (chroot context).
- **Bug report generation**: `_generate_bug_report` collects logs, state,
  stage markers, and system info into a tarball on failure.
- **ISO build script restoration**: `bashisms/iso/build.sh` mutates
  `/usr/bin/buildiso` and `/usr/share/artools/lib/iso/mount.sh` at build
  time and restores them via an `EXIT` trap, so a hard failure mid-build
  cannot leave mutated binaries in place.

---

## 9. Cross-Architecture Support (ARM aarch64)

ARM support is integrated through:

- Cross-compilation profiles in `bashisms/poweruser/profile/cross-aarch64*.sh`.
- Kernel config fragments in `bashisms/poweruser/kernel.d/aarch64/`.
- U-Boot bootloader backend in
  `bashisms/installer/install/bootloaders/uboot.sh`.
- ARM kernel detection in `bashisms/common/kernels.sh`.
- ARMtix repository configuration in
  `bashisms/installer/install/basestrap.sh`.
- Architecture and board selectors in `menu_poweruser.sh` and
  `bashisms/iso/tui.sh`.

The same state machine and pipeline deploy to aarch64 without modification.

---

## 10. Conclusion

Artix Installer is a unified, state-driven system deployment framework.
Every mode—installer, recovery, migration, ISO builder, poweruser—is an
instance of the same architecture: collect state, run a pipeline, produce
a bootable Artix system. The state file is the interface, and its shape
is defined by a single registry. Package data lives in a single catalog,
consumed through pure query functions. The framework is modular at the
subsystem level, with each directory under `bashisms/` capable of
functioning as a standalone project. gum provides the TUI layer with
simple, reliable terminal widgets.

*This document was synthesized from CODE_INDENTS.md, the live codebase,
and the project READMEs. It is updated as the architecture evolves.*