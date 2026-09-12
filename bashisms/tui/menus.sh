#!/usr/bin/env bash
set -Eeuo pipefail

MENUS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/menus"

source "${MENUS_DIR}/main.sh"
source "${MENUS_DIR}/desktop.sh"
source "${MENUS_DIR}/user.sh"
source "${MENUS_DIR}/network_audio.sh"
source "${MENUS_DIR}/extras.sh"
source "${MENUS_DIR}/advanced.sh"
source "${MENUS_DIR}/quick_profiles.sh"
source "${MENUS_DIR}/sanity.sh"
source "${MENUS_DIR}/poweruser.sh"