# Maintainer: Volk <realvolk@github.com>

pkgname=artixforge
pkgver=9.5.1.2
pkgrel=1
pkgdesc="Modular TUI installer framework for Artix Linux"
arch=('x86_64')
url="https://github.com/realvolk/ArtixForge"
license=('custom:CLEAR License v1')
depends=('bash' 'git' 'curl' 'openssl' 'rsync' 'coreutils' 'jq' 'iso-profiles' 'whois')
optdepends=(
    'pacman-contrib: mirror ranking support'
    'artools: ISO build support'
    'gpg: encrypted state presets'
    'eukify: Unified Kernel Image (UKI) generation'
)
makedepends=('git')
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/realvolk/ArtixForge/archive/refs/tags/v${pkgver}.tar.gz")
sha256sums=('SKIP')

package() {
    install -dm755 "${pkgdir}/usr/share/artixforge"
    cp -a "${srcdir}/ArtixForge-${pkgver}"/* "${pkgdir}/usr/share/artixforge/"

    install -dm755 "${pkgdir}/usr/bin"
    ln -sf "/usr/share/artixforge/install" "${pkgdir}/usr/bin/artixforge"

    install -Dm755 "${srcdir}/ArtixForge-${pkgver}/bashisms/bin/tui-x86_64" \
        "${pkgdir}/usr/bin/tui-x86_64"

    install -dm755 "${pkgdir}/usr/share/artixforge/themes"
    cp -a "${srcdir}/ArtixForge-${pkgver}/themes/." "${pkgdir}/usr/share/artixforge/themes/" 2>/dev/null || true

    chmod +x "${pkgdir}/usr/share/artixforge/install"

    install -dm755 "${pkgdir}/usr/share/doc/artixforge"
    cp -a "${srcdir}/ArtixForge-${pkgver}/DOCUMENTS"/* "${pkgdir}/usr/share/doc/artixforge/"

    install -Dm644 "${srcdir}/ArtixForge-${pkgver}/DOCUMENTS/LICENSE" \
        "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}