#!/bin/bash
#
# Build script for Docker Multi-Network Manager plugin
#

set -e

PLUGIN_NAME="docker-networks"
VERSION="${1:-$(date +%Y.%m.%d)}"
BUILD_DIR="build"
ARCHIVE_DIR="archive"

echo "Building ${PLUGIN_NAME} version ${VERSION}..."

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${ARCHIVE_DIR}"

# Copy plugin files to build directory
cp -r src/usr "${BUILD_DIR}/"

# Set executable permissions on scripts
chmod +x "${BUILD_DIR}/usr/local/emhttp/plugins/${PLUGIN_NAME}/scripts/"*.sh

# Create txz archive
cd "${BUILD_DIR}"
tar -cJf "../${ARCHIVE_DIR}/${PLUGIN_NAME}-${VERSION}.txz" usr/
cd ..

# Generate MD5 hash
MD5=$(md5sum "${ARCHIVE_DIR}/${PLUGIN_NAME}-${VERSION}.txz" | cut -d' ' -f1)

echo ""
echo "Build complete!"
echo "Archive: ${ARCHIVE_DIR}/${PLUGIN_NAME}-${VERSION}.txz"
echo "MD5: ${MD5}"
echo ""
echo "Update the .plg file with:"
echo "  version: ${VERSION}"
echo "  md5: ${MD5}"

# Create/update version-specific plg file
sed -e "s/&version;/${VERSION}/g" \
    -e "s/<!ENTITY md5       \"\">/<!ENTITY md5       \"${MD5}\">/g" \
    docker-networks.plg > "${ARCHIVE_DIR}/${PLUGIN_NAME}.plg"

echo ""
echo "Updated plg file: ${ARCHIVE_DIR}/${PLUGIN_NAME}.plg"

# Cleanup
rm -rf "${BUILD_DIR}"

echo ""
echo "Done! Files ready for release in ${ARCHIVE_DIR}/"
