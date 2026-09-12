#!/usr/bin/env bash
set -Eeuo pipefail

DETECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/detects"

source "${DETECT_DIR}/system.sh"
source "${DETECT_DIR}/desktop.sh"
source "${DETECT_DIR}/network_audio.sh"
source "${DETECT_DIR}/packages.sh"
source "${DETECT_DIR}/hardware.sh"
source "${DETECT_DIR}/health.sh"