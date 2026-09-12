#!/usr/bin/env bash
set -Eeuo pipefail

tui_poweruser_recipe_sections() {
    local sections
    sections=$(tui_checklist "Recipe Sources" "Which recipe sections to include?" \
        "OFFICIAL/Base (recommended)" \
        "OFFICIAL/Other (extended, tested)" \
        "COMMUNITY/Base (pending review)" \
        "COMMUNITY/Other (experimental)") || true

    if [[ -n "${sections}" ]]; then
        state_set RECIPE_SECTIONS "${sections//$'\n'/ }"
    else
        state_set RECIPE_SECTIONS "OFFICIAL/Base"
    fi
}

tui_poweruser_create_recipe() {
    if ! tui_yesno "Create Recipe" "Would you like to create a new recipe?"; then
        return 0
    fi

    local name version url desc dependencies
    name=$(tui_input "Recipe Name" "Package name:") || return 1
    version=$(tui_input "Version" "e.g. 1.0:") || return 1
    url=$(tui_input "Source URL" "Tarball URL:") || return 1
    desc=$(tui_input "Description" "Short description:") || true
    dependencies=$(tui_input "Dependencies" "Space-separated list:") || true

    local recipe_file="${POWERUSER_DIR}/recipes/${name}.sh"
    cat > "${recipe_file}" <<EOF
#!/usr/bin/env bash
pkgname=${name}
pkgver=${version}
pkgrel=1
desc="${desc}"
url="${url}"

sources=(
  "${url}|SKIP|${name}-\${pkgver}.tar.gz"
)

depends=(${dependencies})
makedepends=(base-devel)

prepare() {
  cd "\${BUILD_DIR}"
  tar xf "\${SOURCES_DIR}/${name}-\${pkgver}.tar.gz"
  mv "${name}-\${pkgver}" src
}

configure() {
  cd "\${BUILD_DIR}/src"
  ./configure --prefix=/usr
}

build() {
  cd "\${BUILD_DIR}/src"
  make -j\${ARTIX_MAKEFLAGS}
}

package() {
  cd "\${BUILD_DIR}/src"
  make DESTDIR="\${PKG_DESTDIR}" install
}
EOF
    tui_msg "Recipe Created" "Saved to ${recipe_file}."
}