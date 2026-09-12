#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_ROOT/scripts/swift-env.sh"

swift run \
    --package-path "$PROJECT_ROOT" \
    --disable-sandbox \
    --cache-path "$PROJECT_ROOT/.build/swiftpm-cache" \
    PDFBuilderCoreChecks

"$PROJECT_ROOT/scripts/test-open-events.sh"
