#!/usr/bin/env bash
# Template (placeholder)

pkgname=your-package
pkgver=1.0
pkgrel=1
desc="Short description"
url="https://example.com"

sources=(
  "https://example.com/${pkgname}-${pkgver}.tar.gz|SKIP|${pkgname}-${pkgver}.tar.gz"
)

depends=()
makedepends=(base-devel)

feature_flags=()

prepare() {
  cd "${BUILD_DIR}"
  tar xf "${SOURCES_DIR}/${pkgname}-${pkgver}.tar.gz"
  mv "${pkgname}-${pkgver}" src
}

configure() {
  cd "${BUILD_DIR}/src"
  ./configure --prefix=/usr
}

build() {
  cd "${BUILD_DIR}/src"
  make -j"${ARTIX_MAKEFLAGS}"
}

check() {
  cd "${BUILD_DIR}/src"
  make check || true
}

package() {
  cd "${BUILD_DIR}/src"
  make DESTDIR="${PKG_DESTDIR}" install
}