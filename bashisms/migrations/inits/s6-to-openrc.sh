#!/usr/bin/env bash
set -Eeuo pipefail
MIGRATIONS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${MIGRATIONS_DIR}/common.sh"
run_init_migration "s6" "openrc"