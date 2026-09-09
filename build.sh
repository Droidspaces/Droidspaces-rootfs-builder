#!/bin/bash
# Droidspaces RootFS build engine. Builds one template for one architecture.
#
#   ./build.sh -a <arch> -i <Name> [-v <version>]
#   ./build.sh -a aarch64 -i Ubuntu-24.04-Minimal -v v20260101-000000
#
# <arch> is a key in archs.json and a folder under templates/.
# <Name> is templates/<arch>/<Name>.Dockerfile.
# Output: <Name>-Droidspaces-rootfs-<arch>-<YYYYMMDD>-<version>.tar.xz
set -euo pipefail
cd "$(dirname "$0")"

VERSION="dev"
while getopts "a:i:v:" opt; do
  case $opt in
    a) ARCH="$OPTARG" ;;
    i) NAME="${OPTARG%.Dockerfile}" ;;
    v) VERSION="$OPTARG" ;;
    *) echo "Usage: $0 -a <arch> -i <Name> [-v <version>]" >&2; exit 1 ;;
  esac
done
[ -n "${ARCH:-}" ] && [ -n "${NAME:-}" ] || { echo "Usage: $0 -a <arch> -i <Name> [-v <version>]" >&2; exit 1; }

DOCKERFILE="templates/$ARCH/$NAME.Dockerfile"
[ -f "$DOCKERFILE" ] || { echo "Error: $DOCKERFILE not found" >&2; exit 1; }

PLATFORM=$(jq -er --arg a "$ARCH" '.[$a].platform' archs.json) \
  || { echo "Error: arch '$ARCH' not in archs.json" >&2; exit 1; }

FINAL_NAME="${NAME}-Droidspaces-rootfs-${ARCH}-$(date +%Y%m%d)-${VERSION}.tar.xz"
TEMP_TAR="custom-${ARCH}-${NAME}-rootfs.tar"

echo "========================================================="
echo " Template : $DOCKERFILE"
echo " Platform : $PLATFORM"
echo " Version  : $VERSION"
echo "========================================================="

# Register QEMU handlers only when the host cannot run the target natively.
if ! docker run --rm --platform "$PLATFORM" alpine:3.23 true >/dev/null 2>&1; then
  echo "Host cannot run $PLATFORM natively; installing binfmt/QEMU..."
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
fi

if ! docker buildx inspect droidspaces-builder >/dev/null 2>&1; then
  docker buildx create --name droidspaces-builder --driver docker-container --use
else
  docker buildx use droidspaces-builder
fi
docker buildx inspect --bootstrap >/dev/null

docker buildx build \
  --platform "$PLATFORM" \
  --target export \
  --output "type=tar,dest=$TEMP_TAR" \
  -f "$DOCKERFILE" \
  .

echo "Compressing (xz -T0 -9)..."
xz -T0 -9 -f "$TEMP_TAR"
mv "${TEMP_TAR}.xz" "$FINAL_NAME"

echo "========================================================="
echo " Done: $FINAL_NAME"
echo "========================================================="
