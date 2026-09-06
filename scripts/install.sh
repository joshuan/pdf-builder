#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$PROJECT_ROOT/dist/PDF Builder.app"
INSTALL_ROOT="${PDF_BUILDER_INSTALL_DIR:-${HOME}/Applications}"
DESTINATION="$INSTALL_ROOT/PDF Builder.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$SOURCE_APP" ]]; then
    "$PROJECT_ROOT/scripts/build-app.sh"
fi

mkdir -p "$INSTALL_ROOT"
ditto "$SOURCE_APP" "$DESTINATION"

if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DESTINATION"
fi

open "$DESTINATION"
echo "Installed: $DESTINATION"
