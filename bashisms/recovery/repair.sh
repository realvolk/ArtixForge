#!/usr/bin/env bash
set -Eeuo pipefail

REPAIR_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/repairs"

source "${REPAIR_DIR}/system.sh"
source "${REPAIR_DIR}/packages.sh"
source "${REPAIR_DIR}/advanced.sh"
source "${REPAIR_DIR}/migration_iso.sh"