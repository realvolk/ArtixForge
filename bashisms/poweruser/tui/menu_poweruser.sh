#!/usr/bin/env bash
set -Eeuo pipefail

MENUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/menup"

source "${MENUP_DIR}/profile.sh"
source "${MENUP_DIR}/packages.sh"
source "${MENUP_DIR}/kernel_config.sh"
source "${MENUP_DIR}/recipes.sh"
source "${MENUP_DIR}/summary.sh"
source "${MENUP_DIR}/config.sh"