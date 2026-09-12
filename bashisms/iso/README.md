# ISO Generation

Build custom Artix live ISOs from upstream `iso-profiles` profiles.

## Usage

From the ArtixForge installer main menu, select **Build ISO**, then configure
the ISO. Choose an upstream base profile, customize the live session, and
optionally bundle all packages for offline installation.

## How it works

`iso/` extends upstream profiles rather than generating its own. The selected
base profile is copied from `/usr/share/artools/iso-profiles/<base>/` into the
artools workspace and ArtixForge-specific additions are layered on top:

- `profile-artixforge.yaml` — live session user, services, and per-init packages
- `live-overlay/` — installer-ISO auto-boot hooks (openrc/dinit/runit/s6)
- `airootfs/root/ArtixForge/` — the installer tree, baked into the ISO
- `packages-offline.x86_64` — package list for offline bundle downloads

`buildiso` is then invoked against the extended profile. Upstream
`common/common.yaml` is used as-is.

## Structure

| File | Purpose |
|------|---------|
| `common.sh` | Upstream profile extension and offline package list generation |
| `build.sh` | Build orchestration – wraps `buildiso`, handles chroot builds, output copy |
| `offline.sh` | Offline repository creation for disconnected installs |
| `cleanup.sh` | Workspace cleanup after build |
| `tui.sh` | TUI wizard for ISO configuration |

## Requirements

- `artools` and `iso-profiles` packages (installed automatically if missing)
- `loop` kernel module loaded
- Sufficient disk space for package downloads and ISO creation