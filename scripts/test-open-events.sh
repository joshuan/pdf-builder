#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_ROOT/scripts/swift-env.sh"
CHECK_DIR="$(mktemp -d "$PROJECT_ROOT/.build/open-events-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT

# Compile the real application delegate and model without launching the UI,
# requesting notification permissions, or touching the user's source files.
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    -emit-library -emit-module -module-name PDFBuilderCore \
    "$PROJECT_ROOT"/Sources/PDFBuilderCore/*.swift \
    -emit-module-path "$CHECK_DIR/PDFBuilderCore.swiftmodule" \
    -o "$CHECK_DIR/libPDFBuilderCore.dylib"

swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -parse-as-library \
    -I "$CHECK_DIR" -L "$CHECK_DIR" -lPDFBuilderCore \
    -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    "$PROJECT_ROOT/Sources/PDFBuilder/AppDelegate.swift" \
    "$PROJECT_ROOT/Sources/PDFBuilder/BuilderModel.swift" \
    "$PROJECT_ROOT/Sources/PDFBuilder/PageQuickLookController.swift" \
    "$PROJECT_ROOT/Sources/PDFBuilder/UpdateController.swift" \
    "$PROJECT_ROOT/Sources/PDFBuilder/UpdateNotifier.swift" \
    "$PROJECT_ROOT/Tests/PDFBuilderOpenChecks/main.swift" \
    -o "$CHECK_DIR/PDFBuilderOpenChecks"

"$CHECK_DIR/PDFBuilderOpenChecks"
