#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Jungo.app}"

"$ROOT_DIR/Scripts/build-app.sh" "$APP_PATH"
open "$APP_PATH"
