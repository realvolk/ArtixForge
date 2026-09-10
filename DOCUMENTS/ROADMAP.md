# Roadmap

This roadmap is updated regularly based on:

- User and tester suggestions
- Upcoming features
- Critical bug fixes (security issues are patched immediately and not listed here)
- Ideas that emerge during development

*Version numbers are not strict release targets. Features may ship earlier or later depending on development pace, tester feedback, and available time. This roadmap reflects general direction, not fixed deadlines.*

## v9.?

- Migration engine: all 16 init pairs tested
- Migration engine: systemd→Artix full migration tested
- Migration engine: custom service detection and backup audited
- Installer: "Surprise Me" button with preview
- Installer: split-pane installation dashboard
- Installer: installation profiling report
- Installer: guided partitioning advisor
- Power User: `anvil compat` — recipe compatibility matrix
- Power User: build watch — live compilation output
- Power User: FILLY TUI upgrades for all new `anvil` subcommands
- Power User: signed recipe repository (poweruser keypair)
- ARM: additional ARM board profiles
- ARM: ISO builder final polish
- ARM: embedded SD card deployment target

# The think-tank

Ideas under consideration, construction or already being worked on with no real time frame or version numbering.

## Community & Ecosystem

- Translations (German, French, Russian, Chinese, Japanese, Portuguese, Spanish)
- Fleet deployment (`artixforge deploy profile.conf 10.0.0.25`) — Only if I get paid by someone
- Remote TUI installation over SSH
- Declarative system convergence
- Time-travel recovery
- One-click system replication
- Kernel bisect for Power User
- Recovery chroot with state awareness
- State file as bootable artifact
- Zero-touch USB install
- ARM and RISC-V(?) architecture support
- Extras category grouping
- Community recipe promotion workflow (COMMUNITY → OFFICIAL)