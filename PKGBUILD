# Maintainer: Volk <realvolk@github.com>

pkgname=artixforge
pkgver=9.5.1.0
pkgrel=1
pkgdesc="Modular TUI installer framework for Artix Linux"
arch=('any')
url="https://github.com/realvolk/ArtixForge"
license=('custom:IRX License 1.0')
depends=('bash' 'gum' 'git' 'curl' 'openssl' 'rsync' 'coreutils' 'jq' 'iso-profiles' 'whois')
optdepends=(
    'pacman-contrib: mirror ranking support'
    'artools: ISO build support'
    'gpg: encrypted state presets'
    'eukify: Unified Kernel Image (UKI) generation'
)
makedepends=('git')
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/realvolk/ArtixForge/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('87c2e5e0fa940e0946902bcdd0487c30d717494d3291d1d35e4d6a64c6279a32')

package() {
    install -dm755 "${pkgdir}/usr/share/artixforge"
    cp -a "${srcdir}/ArtixForge-${pkgver}"/* "${pkgdir}/usr/share/artixforge/"

    install -dm755 "${pkgdir}/usr/bin"
    ln -sf "/usr/share/artixforge/install" "${pkgdir}/usr/bin/artixforge"
    chmod +x "${pkgdir}/usr/share/artixforge/install"

    install -dm755 "${pkgdir}/usr/share/doc/artixforge"
    cp -a "${srcdir}/ArtixForge-${pkgver}/DOCUMENTS"/* "${pkgdir}/usr/share/doc/artixforge/"

    install -Dm644 "${srcdir}/ArtixForge-${pkgver}/DOCUMENTS/LICENSE" \
        "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}