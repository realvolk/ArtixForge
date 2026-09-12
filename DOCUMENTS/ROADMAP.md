# Roadmap

This roadmap is updated regularly based on:

- User and tester suggestions
- Upcoming features
- Critical bug fixes (security issues are patched immediately and not listed here)
- Ideas that emerge during development

*Version numbers are not strict release targets. Features may ship earlier or later depending on development pace, tester feedback, and available time. This roadmap reflects general direction, not fixed deadlines.*

## v9.?

- Installer: "Surprise Me" button with preview
- Installer: split-pane installation dashboard
- Installer: installation profiling report
- Installer: guided partitioning advisor
- Installer: FreeBSD-styled boot menu on installer ISOs (GRUB theme, numbered entries, autoboot countdown)
- Installer: user-editable boot theme for GRUB and Limine
- Installer: TUI menu for `X_STACK=wayland` (valid value, not currently selectable)
- Power User: `anvil compat` — recipe compatibility matrix
- Power User: build watch — live compilation output
- Catalog: pre-flight conflict detection (provides/conflicts checked before pacman runs)
- Catalog: overlay-vs-package file conflict handling replaces `--overwrite '*'`

## v10.0 — Magnum Opus (branch merged to main)

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
- FILLY FIL plugin packaging and signing
- System comparison — diff two installed systems' configurations