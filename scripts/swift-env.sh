#!/bin/bash

# Beta Command Line Tools can occasionally pair a compiler and SDK whose patch
# versions differ. The frontend override lets compatible textual modules load.
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    PDF_BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    PDF_BUILDER_ROOT="$PWD"
fi

if [[ -n "${PDF_BUILDER_SDK:-}" ]]; then
    export SDKROOT="$PDF_BUILDER_SDK"
else
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PDF_BUILDER_ROOT/.build/ModuleCache}"

SWIFT_INTERFACE_FILE="$(find "$SDKROOT/usr/lib/swift/Swift.swiftmodule" -name '*apple-macos.swiftinterface' -print -quit 2>/dev/null || true)"
if [[ -n "$SWIFT_INTERFACE_FILE" ]]; then
    SDK_SWIFT_VERSION="$(sed -nE 's|.*Apple Swift version ([^ ]+).*|\1|p' "$SWIFT_INTERFACE_FILE" | head -n 1)"
    COMPILER_SWIFT_VERSION="$(swiftc --version | sed -nE 's|.*Apple Swift version ([^ ]+).*|\1|p' | head -n 1)"
    if [[ -n "$SDK_SWIFT_VERSION" && "$SDK_SWIFT_VERSION" != "$COMPILER_SWIFT_VERSION" ]]; then
        export PDF_BUILDER_INTERFACE_COMPILER_VERSION="$SDK_SWIFT_VERSION"
        export SWIFT_DRIVER_SWIFT_FRONTEND_EXEC="$PDF_BUILDER_ROOT/scripts/swift-frontend-wrapper.sh"
    fi
fi
