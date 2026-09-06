#!/bin/sh
# Installs the latest PDF Builder release into /Applications when possible,
# falling back to the current user's Applications folder.
#
#   curl -fsSL https://raw.githubusercontent.com/joshuan/pdf-builder/main/install.sh | sh
#
# Pin a version with PDF_BUILDER_VERSION=v1.2.3.
set -eu

REPOSITORY="joshuan/pdf-builder"
VERSION="${PDF_BUILDER_VERSION:-latest}"
ARCHIVE_NAME="PDFBuilder.zip"
APP_NAME="PDF Builder.app"

if [ "$(uname -s)" != "Darwin" ]; then
	echo "PDF Builder runs on macOS only." >&2
	exit 1
fi

if [ "$VERSION" = "latest" ]; then
	url="https://github.com/$REPOSITORY/releases/latest/download/$ARCHIVE_NAME"
else
	url="https://github.com/$REPOSITORY/releases/download/$VERSION/$ARCHIVE_NAME"
fi

destination="/Applications"
if [ ! -w "$destination" ]; then
	destination="$HOME/Applications"
	mkdir -p "$destination"
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

echo "Downloading $url"
curl -fsSL "$url" -o "$staging/$ARCHIVE_NAME"
ditto -x -k "$staging/$ARCHIVE_NAME" "$staging"

app="$staging/$APP_NAME"
if [ ! -d "$app" ]; then
	echo "The archive did not contain $APP_NAME." >&2
	exit 1
fi

codesign --verify --deep --strict "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true

if [ -d "$destination/$APP_NAME" ]; then
	echo "Replacing $destination/$APP_NAME"
	rm -rf "$destination/$APP_NAME"
fi
ditto "$app" "$destination/$APP_NAME"

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$lsregister" ]; then
	"$lsregister" -f "$destination/$APP_NAME" || true
fi

echo "Installed $destination/$APP_NAME"
echo "Open it with: open -a \"$destination/$APP_NAME\""
