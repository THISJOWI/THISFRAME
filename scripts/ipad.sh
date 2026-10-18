#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVICE_KIND="iPad"
exec "$SCRIPT_DIR/apple-app.sh" "${1:-run}" ios "${@:2}"
