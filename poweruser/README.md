# Power User Mode

<p align="center">
  <img src="https://img.shields.io/badge/Power_User-v2.0.0.0-blue?style=flat-square" alt="Power User Version">
  <img src="https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash" alt="Bash">
  <img src="https://img.shields.io/badge/Build_Engine-makepkg-FFB6C1?style=flat-square" alt="makepkg">
  <img src="https://img.shields.io/badge/TUI-gum-FFB6C1?style=flat-square" alt="gum">
</p>

Power User Mode is ArtixForge's source-based package compilation subsystem.

It provides source-based package management and fine-grained build control
for Artix Linux — build kernels, drivers, init systems, coreutils, and
userspace packages from source with custom compilation flags and feature
toggles. Inspired by Gentoo's Portage and CRUX's pkgmk, implemented entirely
in Bash.

---

## How It Works

During installation, select **Power User** from the main menu.

After the base system is installed, you'll configure:

1. Compilation profile — safe, performance, hardened, or custom flags
2. Package selection — choose which packages to build from source
3. Feature flags — toggle per-package options (e.g. NVIDIA/AMD support)
4. Kernel configuration:

   * `localmodconfig` — compile only currently loaded modules (recommended)
   * Hardware auto-detection
   * Manual checklist configuration
   * Kernel config fragments (`/etc/anvil/kernel.d/`)
   * `make menuconfig`
5. Coreutils selection:

   * GNU coreutils
   * BusyBox
   * uutils (Rust)
   * ArtixForge minimal coreutils
   * Custom recipe
6. Init configuration:

   * OpenRC
   * runit
   * dinit
   * s6
   * BusyBox init

The build engine then:

* Resolves dependencies with topological sort
* Applies conditional dependencies from feature flags
* Detects and reports flag conflicts before compilation
* Fetches and verifies sources
* Compiles packages with profile-driven compiler flags
* Supports ccache for faster rebuilds
* Runs safety checks (PIE, RELRO, stack protector) when enforced
* Supports sub-packages with separate packaging functions
* Creates binary artifacts and installs to the target system
* Tracks file inventory for verification and uninstall
* Records build resource statistics (wall time, CPU time, peak memory)

---

## After Installation

The `anvil` tool is installed to `/usr/local/bin/anvil`.

Use it to manage recipes, source-built packages, kernel configuration,
recovery operations, the world file, and community repositories.

---

## Commands

### Package Management

```bash
anvil list                 # List installed source packages
anvil list-recipes         # List available recipes
anvil info <pkg>           # Show build details
anvil files <pkg>          # List files owned by a package
anvil verify <pkg>         # Verify installed files exist
anvil remove <pkg>         # Uninstall a source-built package
anvil rebuild <pkg>        # Rebuild a specific package
anvil rebuild --isolated <pkg>  # Rebuild in a clean chroot
anvil rebuild --target aarch64 <pkg>  # Cross-compile for another architecture
```

### Build Lifecycle

```bash
anvil world status         # Show world file and package versions
anvil world add <pkg>      # Add a package to the world file
anvil world remove <pkg>   # Remove a package from the world file
anvil world build          # Build all packages in the world file
anvil world build --jobs N # Build with N parallel jobs
anvil world build --stage /nextroot  # Build into a staging directory
anvil world activate       # Atomically cut over to the staged system
anvil bootstrap [dir]      # Build a full system from world into a directory
anvil estimate             # Estimate build time from historical stats
```

### Feature Flags

```bash
anvil flag <pkg>                 # List flags for a package
anvil flag <pkg> <flag>          # Toggle a flag on or off
anvil flag <pkg> <flag> on       # Enable a flag
anvil flag <pkg> <flag> off      # Disable a flag
anvil flag info <pkg> <flag>     # Show flag description and effects
```

Flags are stored in `/etc/anvil/package.use/<pkgname>`. Global defaults
are set in the active profile via `GLOBAL_FEATURES`. Flags can pull in
conditional dependencies and conflict with other flags, enforced at
build time.

### Recipe Management

```bash
anvil new <name>           # Create a new recipe from template
anvil edit <name>          # Edit recipe
anvil lint <name>          # Validate recipe
anvil checksum <recipe>    # Download sources and print SHA256 checksums
anvil log <pkg>            # Show recipe commit history
anvil diff <pkg>           # Show last recipe change
anvil rollback-recipe <pkg> <commit>  # Revert recipe to a previous commit
anvil trial <url>          # Generate a draft recipe from a source tarball
anvil shell <pkg>          # Interactive build debugging shell
```

Recipes are tracked in a local git repository with automatic commits on
edit, fetch, sync, and upgrade operations.

### Community Repository

```bash
anvil sync                 # Update .LIST and recipes from community repo
anvil sections             # Manage enabled recipe sections
anvil fetch-recipe <name>  # Download a single recipe from the community repo
anvil fetch-all            # Download all recipe sources for offline builds
anvil fetch-world          # Download sources for the full dependency tree
anvil upgrade              # Backup recipes, update repository, report changes
```

### Kernel

```bash
anvil config               # Edit running kernel config
anvil menuconfig           # Launch make menuconfig
anvil fetch-source <pkg>   # Prepare package sources for manual build
```

Kernel configuration fragments can be placed in `/etc/anvil/kernel.d/`
and are applied automatically during kernel builds. ARM-specific
fragments for aarch64 boards are bundled in `poweruser/kernel.d/aarch64/`.

### Maintenance

```bash
anvil cache-clean          # Remove obsolete cached packages
anvil gc                   # Garbage collect unreachable artifacts
anvil audit [pkg]          # Security audit of built binaries (PIE/RELRO/SP)
anvil recovery             # Check and repair source-built packages
anvil recovery <pkg>       # Rebuild a specific package for recovery
anvil --tui                # Launch interactive TUI
```

Theme selection is inherited from installation and stored in
`/etc/anvil-theme.conf` (legacy: `/etc/gartix-theme.conf` also supported).
It is loaded automatically on startup.

---

## Recipes

Recipes are Bash-based build definitions stored in the ArtixForge-recipes
repository.

The local `poweruser/recipes/` directory ships only `template.sh`. All
other recipes are fetched during installation or via `anvil fetch-recipe`.

Each recipe defines:

* Sources
* Dependencies (with conditional dependencies from feature flags)
* Feature flags (with descriptions, conflicts, and dependency metadata)
* Build phases (prepare, configure, build, check, package)
* Optional sub-packages
* Optional ccache support (`use_ccache=true`)
* Optional snippet inheritance (`inherit base-binary`)
* Optional virtual package provides (`provides=(virtual/libc)`)

Recipes can be patched locally by placing `.patch` files in
`/etc/anvil/patches/<pkgname>/`. Patches are applied after the prepare
phase and their hashes are included in the build cache key.

New recipes can be created with:

```bash
anvil new <name>
```

Or generated automatically from a source tarball:

```bash
anvil trial <url>
```

---

## Recipe Sections

Recipes are grouped into sections:

* OFFICIAL/Base — core maintained recipes
* OFFICIAL/Other — extended tested recipes
* COMMUNITY/Base — community submissions under review
* COMMUNITY/Other — experimental community recipes

Manage enabled sections with:

```bash
anvil sections
```

Only enabled sections are used by fetch, sync, and source operations.

---

## Profiles

Compilation profiles are stored in:

```text
poweruser/profile/
```

Built-in profiles:

| Profile | CFLAGS | Features |
|---------|--------|----------|
| default | `-O2 -march=x86-64 -mtune=generic` | none |
| safe | `-O2 -fstack-protector-strong` | stack-protector |
| performance | `-O3 -march=native -flto=auto` | lto |
| hardened | `-O2 -fstack-protector-strong -fPIE` | pie relro stack-protector |

Profiles can also set `GLOBAL_FEATURES` which apply to all packages unless
overridden, and `ANVIL_SAFETY_MODE=strict` to abort builds that produce
binaries missing required security features.

Profiles are customized during installation and persisted automatically.
Cross-compilation profiles are available for ARM aarch64:

```text
poweruser/profile/cross-aarch64.sh
poweruser/profile/cross-aarch64-rpi4.sh
```

---

## Cross-Compilation

ARM aarch64 targets are supported through cross-compilation profiles and
U-Boot bootloader integration.

```bash
anvil rebuild --target aarch64 <pkg>
```

Cross-compilation profiles set `CROSS_COMPILE`, `ARCH`, and `TARGET_ARCH`
for ARM builds. Board-specific profiles define kernel defconfig, device
tree, and U-Boot target.

Board support includes:

* Raspberry Pi 4
* Raspberry Pi 3B+
* Odroid N2
* Pinephone
* Firefly RK3399
* Orange Pi PC2
* QEMU VM

SD card deployment is available via `deploy_sd_card` in `builder.bash`.

---

## Build Cache

Built artifacts are stored in:

```text
poweruser/build/artifacts/
```

or

```text
/var/cache/artix-poweruser/artifacts/
```

Package database location:

```text
poweruser/db/local.db
```

or

```text
/usr/share/artix-poweruser/db/local.db
```

depending on installation mode.

Tracked metadata includes:

* Installed packages with file inventory
* Build flags and resolved dependency hashes
* Feature flag state and applied patches
* Package versions and build timestamps
* Build resource statistics (wall time, CPU time, peak memory)

---

## Offline Builds

```bash
anvil fetch-all
```

Downloads all required source archives for enabled recipes.

```bash
anvil fetch-world
```

Resolves the full dependency tree from the world file and downloads
all sources. The system can then be built fully offline.

---

## Staged Builds and Atomic Activation

```bash
anvil world build --stage /nextroot
```

Builds every package in the world file into a parallel root directory.

```bash
anvil world activate
```

On BTRFS, snapshots the current root and swaps in the new one. On other
filesystems, uses `kexec` to load the new kernel and jump into the staged
system without a full reboot. The previous system state is preserved for
rollback.

---

## Requirements

* Artix Linux environment
* Internet connection for source downloads
* ~5 GB temporary disk space for kernel builds
* `gum` for TUI (installed automatically if missing)
* `bc` for build time calculations
* `ccache` optional for faster rebuilds
* Build system supports retries, resume on interruption, and lock recovery