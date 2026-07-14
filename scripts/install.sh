#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"
SOURCE="$ROOT/dist/Model Meter.app"
DESTINATION_ROOT="${1:-/Applications}"
DESTINATION="$DESTINATION_ROOT/Model Meter.app"

mkdir -p "$DESTINATION_ROOT"
ditto "$SOURCE" "$DESTINATION"

echo "Installed Model Meter at $DESTINATION"
