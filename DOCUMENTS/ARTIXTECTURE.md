# ARTIXTECTURE.md — ArtixForge Architecture

This document describes the internal architecture of ArtixForge: how the
state machine works, how the stage pipeline is structured, how the TUI
integrates with gum, how the major subsystems are organized, and how to
add a new configuration option. It is written for contributors who need to
understand the codebase without reverse-engineering it.

---

## 1. Overview

ArtixForge is a **declarative system deployment framework** that materializes
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

---

## 3. State Management (`scripts/state.sh`)

The state file at `/tmp/artix-installer/state.conf` is the **single source
of truth** for the entire deployment. It is a flat key-value file with
single-quoted values. The state file is the interface — no command-line
flags configure behavior; everything is declared in state.

### 3.1 Reading and Writing

- `state_get <key> <default>` reads a key from the state file (with
  fallback to an environment variable, then the default).
- `state_set <key> <value>` writes a key immediately, using `sed -i` for
  in-place replacement or appending a new line.
- `state_save` serializes **every known configuration key** to the state
  file atomically (write to `.tmp`, then `mv`). This ensures that
  interrupted writes do not corrupt the file.

### 3.2 Validation

`lint_state` validates the current state before any pipeline runs. It
checks required keys (DISK, FS_TYPE, BOOTLOADER, KERNEL_CHOICE, INIT),
verifies the target disk exists, validates filesystem/init/bootloader/
privilege escalation/display stack values, and ensures at least one user
or root password is configured.

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

### 3.7 Adding a State Key

To add a new configuration option, you must:

1. Add a `state_get`/`state_set` call in the relevant TUI or subsystem.
2. Add the key to the `state_save` function so it persists across resume.
3. Add the key to `handoff.sh` so it is written to
   `/mnt/etc/artix-installer.conf` on the target system.
4. Add the key to `lint_state` if it has validation requirements.

---

## 4. User Interface Layer (`scripts/tui/`)

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

Quick Profiles are pre-defined configuration presets in `quick_profiles.sh`.
They set multiple state keys at once for common use cases (Base, Plasma,
XFCE, Cinnamon, LXQt, Community GTK, Community Qt, Gaming, Server,
Minimal).

---

## 5. Stage Pipeline (`scripts/stages/`)

The installation pipeline is a linear sequence of stages, each
implemented as a separate script:

| Stage | Script | Responsibility |
|-------|--------|----------------|
| preflight | `preflight.sh` | Dependency checks, network, kernel modules |
| storage | `storage.sh` | Partitioning, filesystem creation, mounting |
| base | `base.sh` | `basestrap` base system, kernel, init |
| poweruser | `poweruser.sh` | Source-based package compilation |
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
Before any stage runs, `lint_state` validates the state file and
`_validate_post_install_script` checks the post-install script path if set.

---

## 6. Subsystem Architecture

### 6.1 Storage (`scripts/storage/`)

- `partition.sh` creates MBR (BIOS) or GPT (UEFI) layouts, with
  optional LVM on LUKS setup.
- `filesystem.sh` formats partitions, handles LUKS encryption, LVM
  logical volumes, and filesystem-specific options (XFS bigtime, F2FS
  compression, BTRFS).
- `mount.sh` mounts the root filesystem, creates BTRFS subvolumes,
  and mounts the EFI partition.

All three use `state_get` for configuration and support both BIOS and
UEFI paths.

### 6.2 Bootloader (`scripts/install/bootloader.sh`)

The main script `configure_bootloader` detects the root device, generates
a kernel command line via `generate_root_cmdline` (handling LUKS, LVM,
BTRFS), runs `mkinitcpio`, and dispatches to a per-bootloader
backend. Backends live in `scripts/install/bootloaders/`:

- `grub.sh` — GRUB for UEFI and BIOS, with LUKS/LVM support.
- `refind.sh` — rEFInd configuration.
- `efistub.sh` — direct kernel boot from UEFI firmware.
- `limine.sh` — Limine bootloader with snapshot entries.
- `uboot.sh` — U-Boot for ARM boards.

### 6.3 Base System (`scripts/install/basestrap.sh`)

This is the largest function in the installer. It selects packages based
on the chosen init, kernel, filesystem, bootloader, desktop, and network
stack. It handles third-party repository setup (CachyOS, Chaotic-AUR,
ARMtix) and kernel-specific build logic (TKG, Bazzite). Kernel detection
is in `scripts/kernels.sh`.

### 6.4 Post-Install (`scripts/post/`)

Each script in `post/` is sourced inside a chroot and configures one
aspect of the installed system:

- `desktop.sh` — installs DE/WM, display manager, display stack.
  Multi-DE install from system and per-user keys.
- `drivers.sh` — GPU drivers, VM guest agents, Nouveau fallback.
- `audio.sh` — PipeWire or PulseAudio setup.
- `networking.sh` — NetworkManager, dhcpcd+iwd, or ConnMan.
- `extras.sh` — additional user-selected packages.
- `users.sh` — user creation, password hashing, sudo/doas setup,
  per-user DE, dotfiles cloning.
- `system.sh` — hostname, locale, keymap, timezone.

### 6.5 Recovery (`scripts/recovery/`)

Recovery has two phases:

- **Detection** (`detects/`): 30+ functions that probe the target system
  and reconstruct a state file (`reconstruct_state_from_system`).
- **Repair** (`repairs/`): functions that fix detected issues (fstab,
  pacman, bootloader, kernel, seat manager, filesystem).

The TUI presents the detected state and offers repair actions. All
detection is read-only until the user confirms a repair.

### 6.6 Migration (`migrations/`)

Three migration types, all state-driven and resumable:

- **Init migration** (`inits/common.sh`): service mapping tables between
  all init pairs, with a hub-chaining model through OpenRC. Explicit
  target selection via `ensure_migration_root`.
- **Desktop migration** (`des/common.sh`): generic scripts that detect
  the current DE, dynamically discover installed packages, and install
  the target DE. Explicit target selection via `ensure_migration_root`.
  Uses `pacman -Rdd` for package removal and user-visible orphan cleanup.
- **ATA migration** (`ata/`): full Arch→Artix conversion with audit,
  selective backup, conversion, package replacement, and service
  migration.

All migrations use stage files (`migration-stage.conf`) for crash-resume.
Migration keys are persisted through `state_save`.

### 6.7 ISO Builder (`iso/`)

A wrapper around `artools` that generates a `profile.yaml` from the state
file, runs `buildiso`, and produces a bootable ISO. Supports offline
mode, non-repo kernel builds, and ARM aarch64 targets.

### 6.8 Power User (`poweruser/`)

A complete source-based package manager implemented in Bash. Key files:

- `lib/recipe.bash` — recipe loading with feature flag metadata parsing.
- `lib/flags.bash` — flag resolution, global defaults, conflict detection.
- `lib/deps.bash` — topological dependency sort with virtual providers.
- `lib/builder.bash` — full build lifecycle with ccache, safety checks,
  sub-packages, file inventory, and atomic staging.
- `lib/kconfig_fragments.bash` — kernel config fragment processor.
- `bin/anvil` — CLI dispatcher for post-install package management.
- `bin/anvil_tui.bash` — gum TUI for interactive package management.

The Power User TUI configuration is in `tui/menu_poweruser.sh`.

---

## 7. Adding a Configuration Option

To add a new user-facing option (e.g., a new kernel variant), touch these
files:

1. **State keys**: add `state_get`/`state_set` calls in the relevant
   subsystem. Add the key to `state_save` in `state.sh`.
2. **TUI menu**: add the prompt in the relevant menu file under
   `scripts/tui/menus/`.
3. **Backend logic**: handle the new key in the appropriate stage script
   or subsystem library.
4. **Handoff**: add the key to the config export in `handoff.sh` so it
   is written to `/mnt/etc/artix-installer.conf`.
5. **Linting**: add validation to `lint_state` in `state.sh` if the key
   has constraints.
6. **Recovery** (if applicable): add detection in `scripts/recovery/detects/`
   and repair in `scripts/recovery/repairs/`.

---

## 8. Resilience Patterns

- **Atomic state writes**: `state_save` writes to `.tmp` then `mv`.
- **State validation**: `lint_state` runs before every pipeline.
- **Stage validation**: `stage_should_skip` re-validates the environment,
  not just the sentinel file.
- **Retry with backoff**: `retry_command` in `common.sh` for network
  operations (3 attempts, 5/10/20s delays).
- **Pacman lock recovery**: `clean_pacman_lock` before every `pacman` call.
- **Disk space checks**: before critical stages (3 GB, 5 GB, 10 GB).
- **Debug mode**: `set -x` to fd 19, separate from TTY.
- **Self-update**: `recoverable_error` offers to update ArtixForge from
  GitHub and restart.
- **Bug report generation**: `_generate_bug_report` collects logs, state,
  stage markers, and system info into a tarball on failure.

---

## 9. Cross-Architecture Support (ARM aarch64)

ARM support is integrated through:

- Cross-compilation profiles in `poweruser/profile/cross-aarch64*.sh`.
- Kernel config fragments in `poweruser/kernel.d/aarch64/`.
- U-Boot bootloader backend in `scripts/install/bootloaders/uboot.sh`.
- ARM kernel detection in `scripts/kernels.sh`.
- ARMtix repository configuration in `scripts/install/basestrap.sh`.
- Architecture and board selectors in `menu_poweruser.sh` and `iso/tui.sh`.

The same state machine and pipeline deploy to aarch64 without modification.

---

## 10. Conclusion

ArtixForge is a unified, state-driven system deployment framework. Every
mode—installer, recovery, migration, ISO builder, poweruser—is an instance
of the same architecture: collect state, run a pipeline, produce a bootable
Artix system. The state file is the interface. The framework is modular at
the directory level, with each subsystem (`scripts/`, `poweruser/`,
`migrations/`, `iso/`) capable of functioning as a standalone project.
gum provides the TUI layer with simple, reliable terminal widgets.

*This document was synthesized from CODE_INDENTS.md, the live codebase,
and the project READMEs. It is updated as the architecture evolves.*