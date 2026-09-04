#!/usr/bin/env bash
# Build the kernel (kernel image + device dtb(s) + modules) for one or more
# devices.
# Usage: scripts/build_kernel.sh devices/<a>.env [devices/<b>.env ...]
#
# With multiple devices, every device's kernel.config fragment and
# kernel-patches/ series is applied to the same tree and all their dtbs are
# built — one kernel serves the whole set (used by the combined extlinux
# package). The first env provides the base configuration (defconfig etc.).
# All devices in one invocation must share the same ARCH — 32-bit devices
# (armhf, e.g. cancro) are built as separate packages.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# -ge 1 ]] || die "usage: $0 devices/<codename>.env [more.env ...]"
load_device "$1"
collect_devices "$@"

KSRC="$REPO_ROOT/$KERNEL_SUBMODULE"
KBUILD="$BUILD_DIR/kernel"
[[ -e "$KSRC/.git" ]] || die "kernel submodule missing: $KSRC (run: git submodule update --init)"

kernel_arch_vars
DTS_DIR="$KBUILD/$DTS_DIR_REL"

# Wrap the cross compiler in ccache when available (big win on CI re-runs).
CCACHE=""
command -v ccache >/dev/null && CCACHE="ccache "

export ARCH="$KARCH"
export CROSS_COMPILE="${CCACHE}${CROSS}"
# Keep kernelrelease reproducible when device patches are applied: with
# CONFIG_LOCALVERSION_AUTO off, setlocalversion still appends "+" for a dirty
# tree unless the LOCALVERSION env var is set (even empty). Pin it empty.
export LOCALVERSION=""

# Apply per-device kernel patches (devices/<codename>/kernel-patches/*.patch).
# Idempotent: already-applied patches are skipped. The tree is intentionally
# left dirty — pair with "# CONFIG_LOCALVERSION_AUTO is not set" in a fragment
# to keep the kernelrelease reproducible.
for dir in "${DEVICE_DIRS[@]}"; do
    PDIR="$dir/kernel-patches"
    [[ -d "$PDIR" ]] || continue
    for p in "$PDIR"/*.patch; do
        [[ -e "$p" ]] || continue
        if git -C "$KSRC" apply --check "$p" 2>/dev/null; then
            log "applying kernel patch: $(basename "$p")"
            git -C "$KSRC" apply "$p"
        elif git -C "$KSRC" apply -R --check "$p" 2>/dev/null; then
            log "kernel patch already applied: $(basename "$p")"
        else
            die "kernel patch does not apply: $p"
        fi
    done
done

log "configuring kernel ($KERNEL_DEFCONFIG)"
make -C "$KSRC" O="$KBUILD" "$KERNEL_DEFCONFIG"

# Merge the per-device config fragments (devices/<codename>/kernel.config).
FRAGMENTS=()
for dir in "${DEVICE_DIRS[@]}"; do
    [[ -f "$dir/kernel.config" ]] && FRAGMENTS+=("$dir/kernel.config")
done
if [[ ${#FRAGMENTS[@]} -gt 0 ]]; then
    log "merging kernel config fragments: ${FRAGMENTS[*]}"
    "$KSRC/scripts/kconfig/merge_config.sh" -m -O "$KBUILD" "$KBUILD/.config" "${FRAGMENTS[@]}"
    make -C "$KSRC" O="$KBUILD" olddefconfig
fi

log "compiling $KERNEL_IMAGE + dtbs (${DEVICE_DTBS[*]}) + modules"
make -C "$KSRC" O="$KBUILD" -j"$(nproc)" "$KERNEL_IMAGE" "${DEVICE_DTBS[@]}" modules

log "installing modules to staging dir"
rm -rf "$BUILD_DIR/modinst"
make -C "$KSRC" O="$KBUILD" \
    INSTALL_MOD_PATH="$BUILD_DIR/modinst" INSTALL_MOD_STRIP=1 \
    modules_install

KREL="$(make -s -C "$KSRC" O="$KBUILD" kernelrelease)"
echo "$KREL" > "$BUILD_DIR/kernelrelease"

[[ -f "$KBUILD/arch/$KARCH/boot/$KERNEL_IMAGE" ]] || die "$KERNEL_IMAGE missing"
for dtb in "${DEVICE_DTBS[@]}"; do
    [[ -f "$DTS_DIR/$dtb" ]] || die "dtb missing: $dtb"
done
log "kernel $KREL built OK (dtbs: ${DEVICE_DTBS[*]})"
