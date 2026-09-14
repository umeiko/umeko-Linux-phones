#!/usr/bin/env bash
# Download the Ubuntu base tarball (verified) and create an empty ext4
# rootfs image with a fixed UUID.
# Usage: scripts/build_rootfs.sh devices/wt88047.env
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_device "$@"

mkdir -p "$CACHE_DIR" "$BUILD_DIR"
TARBALL="$CACHE_DIR/$(basename "$UBUNTU_BASE_URL")"

if [[ ! -f "$TARBALL" ]]; then
    log "downloading $UBUNTU_BASE_URL"
    # Download to a temp name first: an interrupted download must not poison
    # the cache (CI caches .cache/ between runs).
    curl -fL --retry 3 -o "$TARBALL.part" "$UBUNTU_BASE_URL"
    mv "$TARBALL.part" "$TARBALL"
else
    log "using cached $(basename "$TARBALL")"
fi

log "verifying tarball against official SHA256SUMS"
curl -fsSL --retry 3 "$UBUNTU_BASE_SHA256SUMS_URL" -o "$CACHE_DIR/SHA256SUMS"
if ! ( cd "$CACHE_DIR" && grep "$(basename "$TARBALL")\$" SHA256SUMS | sed 's/ \*/  /' | sha256sum -c - ); then
    rm -f "$TARBALL"
    die "tarball checksum mismatch — bad cache copy deleted, re-run to re-download"
fi

IMAGE="$BUILD_DIR/rootfs.img"
if [[ ! -f "$IMAGE" ]]; then
    log "creating ${ROOTFS_SIZE_MB} MiB ext4 image (UUID $ROOTFS_UUID)"
    dd if=/dev/zero of="$IMAGE" bs=1M count=0 seek="$ROOTFS_SIZE_MB" status=none
    mkfs.ext4 -q -U "$ROOTFS_UUID" "$IMAGE"
else
    log "reusing existing $IMAGE (delete to rebuild from scratch)"
fi
log "rootfs image ready"
