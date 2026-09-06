#!/bin/bash

set -euo pipefail

SWIFT_FRONTEND="$(xcrun --find swift-frontend)"

if [[ "${1:-}" == "-frontend" ]]; then
    shift
fi

if [[ -n "${PDF_BUILDER_INTERFACE_COMPILER_VERSION:-}" ]]; then
    exec "$SWIFT_FRONTEND" \
        -interface-compiler-version "$PDF_BUILDER_INTERFACE_COMPILER_VERSION" \
        "$@"
fi

exec "$SWIFT_FRONTEND" "$@"
