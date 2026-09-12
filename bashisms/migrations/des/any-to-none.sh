#!/usr/bin/env bash
set -Eeuo pipefail
MIGRATIONS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${MIGRATIONS_DIR}/common.sh"
current=$(detect_current_de)
run_de_migration "$current" "none"