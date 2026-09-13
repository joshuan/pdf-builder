#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_NAME="PDF to JPG.workflow"
SOURCE="$PROJECT_ROOT/dist/$WORKFLOW_NAME"
SERVICES_DIR="${PDF_TO_JPG_SERVICES_DIR:-$HOME/Library/Services}"
DESTINATION="$SERVICES_DIR/$WORKFLOW_NAME"

if [[ ! -f "$SOURCE/Contents/document.wflow" ]]; then
    echo "Build the workflow first: make pdf-to-jpg" >&2
    exit 1
fi
mkdir -p "$SERVICES_DIR"
STAGING="$(mktemp -d "$SERVICES_DIR/.pdf-to-jpg-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$SOURCE" "$STAGING/$WORKFLOW_NAME"

# Keep a previous local version recoverable when reinstalling.
if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
    BACKUP="$SERVICES_DIR/.pdf-to-jpg-backup-$(uuidgen)"
    mv "$DESTINATION" "$BACKUP"
    if ! mv "$STAGING/$WORKFLOW_NAME" "$DESTINATION"; then
        mv "$BACKUP" "$DESTINATION"
        exit 1
    fi
    echo "Previous version: $BACKUP"
else
    mv "$STAGING/$WORKFLOW_NAME" "$DESTINATION"
fi

if [[ "$SERVICES_DIR" == "$HOME/Library/Services" ]]; then
    /System/Library/CoreServices/pbs -update
fi
echo "Installed: $DESTINATION"
