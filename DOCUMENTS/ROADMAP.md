# Roadmap

This roadmap is updated regularly based on:

- User and tester suggestions
- Upcoming features
- Critical bug fixes (security issues are patched immediately and not listed here)
- Ideas that emerge during development

*Version numbers are not strict release targets. Features may ship earlier or later depending on development pace, tester feedback, and available time. This roadmap reflects general direction, not fixed deadlines.*

## v9.?

- Storage: LVM-on-LUKS resume path — mount ordering, custom VG name consistency
- Storage: F2FS/XFS creation logic consolidated into shared helpers
- Storage: dead-code cleanup in XFS mkfs branch
- Installer: "Surprise Me" button with preview
- Installer: split-pane installation dashboard
- Installer: installation profiling report
- Installer: guided partitioning advisor
- Installer: FreeBSD-styled boot menu on installer ISOs (GRUB theme, numbered entries, autoboot countdown)
- Installer: user-editable boot theme for GRUB and Limine
- Power User: `anvil compat` — recipe compatibility matrix
- Power User: build watch — live compilation output

## v10.0 — Magnum Opus (new branch -> merged to main)

- Layout refactor: all subsystems moved under `bashisms/`
  - `bashisms/installer/` (was `scripts/` + `install` pipeline)
  - `bashisms/recovery/` (split out of `scripts/`)
  - `bashisms/migrations/`
  - `bashisms/iso/`
  - `bashisms/poweruser/`
  - `bashisms/state/`, `bashisms/common/`, `bashisms/tui/`
  - `bashisms/packages/` (new subsystem)
- Path references updated across every file; no behavior changes
- `bashisms/BASHISMS.md` documenting each subsystem
- Rename `ArtixForge` → `artix-installer` (repo, package, internal name)
- Merge plan: layout only, verified per subsystem, merged to main when stable
- New `bashisms/packages/` subsystem — single source of truth for package data
- Universal DE/DM/init/network/audio package definitions consumed by installer, migrations, ISO builder, and ATA
- Eliminates parallel package tables (`_desktop_packages_for`, `DE_PACKAGES`, `generate_offline_package_list`, ATA mappings)
- Pre-flight conflict detection (provides/conflicts checked before pacman runs)
- Manifest model: packages declared once, filtered per stage, deduplicated across subsystems
- Overlay-vs-package file conflict handling replaces `--overwrite '*'`
- FILLY build-system split: `libfilly.so` (terminal + headless + widget engine + FIL) separated from `libfilly-gcore.so` (DRM/KMS + X11)
- TUI-only `libfilly.so` has zero desktop-library dependencies; ships on live ISOs
- `libfilly-gcore.so` optional companion package for graphical sessions
- Replace gum with FILLY relay protocol in `bashisms/tui/`
- Port ArtixForge screens as FIL plugins or FILLY plugin `.c` files (based on the old `tui-rewrite` branch's widget set)
- `anvil`'s TUI also migrated to FILLY
- Remote TUI installation over SSH — FILLY's daemon protocol is the transport
- Translations — the `po/filly.pot` gettext scaffolding extends to ArtixForge screens
- Verified on a live ISO before merge
- Boot chain verification (`bashisms/recovery/detects/boot_chain.sh`)
  - Ordered checks: firmware → bootloader → kernel image → initramfs → init binary → essential services → getty/DM
  - Each link reports pass / warn / fail; chain stops at first hard failure
  - Feeds the recovery hub's repair suggestions
- ArtixForge rescue shell — chroot with installer functions sourced against the target's state
- Recovery chroot with state awareness
- Signed preset publishing (`artixforge apply <url>`) — extends encrypted presets with a publish/apply half
- Preset-to-manifest pipeline for reproducible deployment
- Recipe signing — individual maintainer signatures on recipes, verified on fetch
- `anvil fetch-world --hash` — manifest of every source URL and SHA256 for the full world tree
- `linux-libre` recipe (currently only installable via Parabola's `[libre]` repo)
- Fleet deployment (`artixforge deploy profile.conf 10.0.0.25`) — Only if I get paid by someone
- Zero-touch USB install
- Storage: new layout strategies beyond standard LVM-on-LUKS
- FILLY FIL plugin packaging and signing
- System comparison — diff two installed systems' configurations