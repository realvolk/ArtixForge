#!/usr/bin/env bash
# migrations/inits/openrc-to-dinit.sh
set -Eeuo pipefail

MIGRATIONS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${MIGRATIONS_DIR}/common.sh"

run_init_migration "openrc" "dinit"