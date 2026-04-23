#!/bin/bash
set -euo pipefail

APP_NAME="TokenTracker"
BUNDLE_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME}..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf build
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy executable
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Copy Info.plist
cp "${APP_NAME}/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo ""
echo "Build complete: ${BUNDLE_DIR}"
echo ""
echo "To install, run:"
echo "  cp -r ${BUNDLE_DIR} /Applications/"
echo ""
echo "Or run directly:"
echo "  open ${BUNDLE_DIR}"
