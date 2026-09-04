#!/usr/bin/env bash
# Pack the flashing bundle: boot.img (kernel + appended dtb), sparse
# rootfs.img, lk2nd, fastboot flash scripts, build info -> zip.
# Usage: PACK_VERSION=v1.0 scripts/pack.sh devices/wt88047.env
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_device "$@"

KBUILD="$BUILD_DIR/kernel"
KREL="$(cat "$BUILD_DIR/kernelrelease")"
PKG_VERSION="${PACK_VERSION:-$(date +%Y%m%d)}"
PKG_NAME="umeko-${DEVICE_CODENAME}-ubuntu24.04-${PKG_VERSION}"
STAGE="$BUILD_DIR/pack"

# Legacy arm64-only route: Image.gz + single appended dtb. 32-bit devices
# (armhf, e.g. cancro) also need qcdt for the stock boot.img — use the
# extlinux/lk2nd route (pack_extlinux.sh) for those instead.
[[ "${ARCH:-arm64}" == "arm64" ]] || die "pack.sh is arm64-only (legacy); use pack_extlinux.sh for $ARCH"

[[ -f "$BUILD_DIR/rootfs.img" ]] || die "rootfs.img missing, run assemble.sh first"
command -v mkbootimg >/dev/null || die "mkbootimg not installed"
command -v img2simg  >/dev/null || die "img2simg not installed (android-sdk-libsparse-utils)"

# Ubuntu 24.04's mkbootimg package ships /usr/bin/mkbootimg without the gki
# python module it imports at startup (only used by --gki_signing_* options,
# which we never pass). Install a stub so the tool runs.
if ! mkbootimg --help >/dev/null 2>&1; then
    warn "mkbootimg is broken (missing gki module), installing a stub"
    sudo mkdir -p /usr/lib/python3/dist-packages/gki
    printf 'def generate_gki_certificate(*args, **kwargs):\n    raise NotImplementedError("gki signing not available")\n' \
        | sudo tee /usr/lib/python3/dist-packages/gki/generate_gki_certificate.py >/dev/null
    : | sudo tee /usr/lib/python3/dist-packages/gki/__init__.py >/dev/null
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT_DIR"

# --- boot.img: kernel + appended dtb + initramfs (root=UUID= needs it) ------
log "creating boot.img"
cat "$KBUILD/arch/arm64/boot/Image.gz" \
    "$KBUILD/arch/arm64/boot/dts/$KERNEL_DTB" > "$STAGE/kernel-dtb"
RAMDISK_ARGS=()
if [[ -f "$BUILD_DIR/initrd.img" ]]; then
    RAMDISK_ARGS=(--ramdisk "$BUILD_DIR/initrd.img")
else
    warn "initrd.img missing (assemble.sh too old?) — root=UUID= needs an initramfs!"
fi
mkbootimg \
    --kernel "$STAGE/kernel-dtb" \
    "${RAMDISK_ARGS[@]}" \
    --base "$BOOTIMG_BASE" \
    --kernel_offset "$BOOTIMG_KERNEL_OFFSET" \
    --ramdisk_offset "$BOOTIMG_RAMDISK_OFFSET" \
    --second_offset "$BOOTIMG_SECOND_OFFSET" \
    --tags_offset "$BOOTIMG_TAGS_OFFSET" \
    --pagesize "$BOOTIMG_PAGESIZE" \
    --cmdline "$KERNEL_CMDLINE" \
    -o "$STAGE/boot.img"
rm "$STAGE/kernel-dtb"

# --- lk2nd (official prebuilt, checksum-verified) -----------------------------
log "downloading lk2nd ${LK2ND_VERSION}"
LK2ND_IMG="$STAGE/lk2nd-${SOC}.img"
curl -fL --retry 3 -o "$LK2ND_IMG" "$LK2ND_URL"
echo "$LK2ND_SHA256  $LK2ND_IMG" | sha256sum -c -

# --- sparse rootfs for fastboot ------------------------------------------------
log "converting rootfs to sparse image"
trim_rootfs_image "$BUILD_DIR/rootfs.img"
img2simg "$BUILD_DIR/rootfs.img" "$STAGE/rootfs.img"

# --- flash scripts ---------------------------------------------------------------
LK2ND_FILE="$(basename "$LK2ND_IMG")"

cat > "$STAGE/flash.sh" <<EOF
#!/usr/bin/env bash
# Flash umeko Linux ($DEVICE_NAME / $DEVICE_CODENAME) — requires fastboot.
set -euo pipefail
echo "[1/4] Flashing lk2nd bootloader (stock fastboot)..."
fastboot flash boot $LK2ND_FILE || fastboot flash:raw boot $LK2ND_FILE
echo
echo "lk2nd flashed. Reboot the phone and hold VOLUME-DOWN to enter"
echo "the lk2nd fastboot mode (its own fastboot, not the stock one)."
fastboot reboot || true
read -rp "Press Enter once the phone shows the lk2nd fastboot screen..."
echo "[2/4] Flashing boot image (kernel)..."
fastboot flash boot boot.img
echo "[3/4] Flashing rootfs to userdata (THIS ERASES USER DATA)..."
fastboot flash userdata rootfs.img
echo "[4/4] Rebooting into Linux..."
fastboot reboot
echo "Done. First boot takes a while; log in as '$DEFAULT_USER' / '$DEFAULT_PASSWORD'."
EOF
chmod +x "$STAGE/flash.sh"

cat > "$STAGE/flash.bat" <<EOF
@echo off
echo [1/4] Flashing lk2nd bootloader (stock fastboot)...
fastboot flash boot $LK2ND_FILE
if errorlevel 1 fastboot flash:raw boot $LK2ND_FILE
echo.
echo lk2nd flashed. The phone will reboot; hold VOLUME-DOWN to enter
echo the lk2nd fastboot mode (its own fastboot, not the stock one).
fastboot reboot
pause
echo [2/4] Flashing boot image (kernel)...
fastboot flash boot boot.img
echo [3/4] Flashing rootfs to userdata (THIS ERASES USER DATA)...
fastboot flash userdata rootfs.img
echo [4/4] Rebooting into Linux...
fastboot reboot
echo Done. First boot takes a while; log in as '$DEFAULT_USER' / '$DEFAULT_PASSWORD'.
pause
EOF

cat > "$STAGE/BUILD-INFO.txt" <<EOF
package:  $PKG_NAME
device:   $DEVICE_NAME ($DEVICE_CODENAME), SoC $SOC
kernel:   $KREL (msm8916-mainline/linux)
cmdline:  $KERNEL_CMDLINE
lk2nd:    $LK2ND_VERSION ($LK2ND_URL)
rootfs:   $(basename "$UBUNTU_BASE_URL"), UUID $ROOTFS_UUID
built:    $(date -u +%Y-%m-%dT%H:%M:%SZ)

Flashing layout:
  boot     <- $LK2ND_FILE   (once, from the stock bootloader)
  boot     <- boot.img      (from lk2nd fastboot; stored at +512KiB offset)
  userdata <- rootfs.img    (sparse ext4)

Login: $DEFAULT_USER / $DEFAULT_PASSWORD
Consoles: screen (tty0), UART ($SERIAL_CONSOLES), USB gadget serial (ttyGS0), SSH
EOF

log "packing $PKG_NAME.zip"
( cd "$STAGE" && zip -q -9 -r "$OUT_DIR/$PKG_NAME.zip" . )
ls -lh "$OUT_DIR/$PKG_NAME.zip"
log "done: $OUT_DIR/$PKG_NAME.zip"
