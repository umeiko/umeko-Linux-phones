#!/usr/bin/env bash
# Default packing route: boot via lk2nd + extlinux.conf instead of an
# Android boot.img (no mkbootimg involved; pack.sh is the legacy route).
#
# Usage: PACK_VERSION=v1.0 scripts/pack_extlinux.sh devices/<a>.env [devices/<b>.env ...]
#
# With multiple devices, all their dtbs are shipped under /dtbs/ and the
# extlinux.conf uses "fdtdir /dtbs": lk2nd/lk1st picks the right dtb for the
# device from its own device database at boot. One package serves the set.
#
# Layout produced (pmOS "kernel-extlinux" style):
#   boot     <- lk2nd-msm8916.img   (stock fastboot, once)
#   system   <- bootfs.img          (ext2: /extlinux/extlinux.conf + kernel + dtbs)
#   userdata <- rootfs.img          (sparse ext4, unchanged)
#
# lk2nd scans every partition >= 16MiB (plus boot at +512KiB) for an ext2
# filesystem containing /extlinux/extlinux.conf and boots the default label.
# NOTE: lk2nd's ext2 driver has no extents support, so the boot fs MUST be
# plain ext2 (mke2fs -t ext2), not ext4.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# -ge 1 ]] || die "usage: $0 devices/<codename>.env [more.env ...]"
load_device "$1"
collect_devices "$@"
kernel_arch_vars

KBUILD="$BUILD_DIR/kernel"
KREL="$(cat "$BUILD_DIR/kernelrelease")"
PKG_VERSION="${PACK_VERSION:-$(date +%Y%m%d)}"
DEVS_JOINED="$(IFS=+; echo "${DEVICE_CODES[*]}")"
PKG_NAME="umeko-${DEVS_JOINED}-ubuntu24.04-${PKG_VERSION}-extlinux"
STAGE="$BUILD_DIR/pack-extlinux"
BOOTFS_SIZE_MB=64

[[ -f "$BUILD_DIR/rootfs.img" ]] || die "rootfs.img missing, run assemble.sh first"
command -v mke2fs   >/dev/null || die "mke2fs not installed (e2fsprogs)"
command -v img2simg >/dev/null || die "img2simg not installed (android-sdk-libsparse-utils)"

rm -rf "$STAGE"
mkdir -p "$STAGE/root/extlinux" "$OUT_DIR"

# --- bootfs contents ----------------------------------------------------------
log "staging extlinux boot filesystem (${DEVS_JOINED})"
cp "$KBUILD/$KERNEL_IMAGE_REL" "$STAGE/root/"
INITRD_LINE=""
if [[ -f "$BUILD_DIR/initrd.img" ]]; then
    cp "$BUILD_DIR/initrd.img" "$STAGE/root/initrd.img"
    INITRD_LINE="initrd /initrd.img"
else
    warn "initrd.img missing (assemble.sh too old?) — root=UUID= needs an initramfs!"
fi
for dtb in "${DEVICE_DTBS[@]}"; do
    mkdir -p "$STAGE/root/dtbs/$(dirname "$dtb")"
    cp "$KBUILD/$DTS_DIR_REL/$dtb" "$STAGE/root/dtbs/$dtb"
done

# With a single device, pin the dtb explicitly; with several, let lk2nd pick
# via its device database (fdtdir lookup tries <dir>/qcom/<name>.dtb first,
# which matches our layout).
if [[ ${#DEVICE_DTBS[@]} -eq 1 ]]; then
    FDT_LINE="fdt /dtbs/${DEVICE_DTBS[0]}"
else
    FDT_LINE="fdtdir /dtbs"
fi

cat > "$STAGE/root/extlinux/extlinux.conf" <<EOF
timeout 1
menu title umeko Linux (${DEVS_JOINED})
default umeko

label umeko
    linux /$KERNEL_IMAGE
    $FDT_LINE
    $INITRD_LINE
    append $KERNEL_CMDLINE
EOF

# --- bootfs.img: plain ext2, populated with mke2fs -d --------------------------
log "creating bootfs.img (ext2, ${BOOTFS_SIZE_MB} MiB)"
dd if=/dev/zero of="$STAGE/bootfs.img" bs=1M count="$BOOTFS_SIZE_MB" status=none
mke2fs -q -t ext2 -L umeko-boot -U "$BOOTFS_UUID" -d "$STAGE/root" "$STAGE/bootfs.img"
rm -rf "$STAGE/root"

# --- lk2nd (official prebuilt, checksum-verified) ------------------------------
# NOTE: valid for wt88047 and other non-quirky devices. vivo Y23L (pd1419) is
# a "quirky" vivo CDP device (32-bit stock aboot) and needs lk1st + replaced
# tz/hyp instead — see docs/extlinux.md.
log "downloading lk2nd ${LK2ND_VERSION}"
LK2ND_IMG="$STAGE/lk2nd-${SOC}.img"
curl -fL --retry 3 -o "$LK2ND_IMG" "$LK2ND_URL"
echo "$LK2ND_SHA256  $LK2ND_IMG" | sha256sum -c -

# --- sparse rootfs for fastboot -------------------------------------------------
log "converting rootfs to sparse image"
trim_rootfs_image "$BUILD_DIR/rootfs.img"
img2simg "$BUILD_DIR/rootfs.img" "$STAGE/rootfs.img"

# --- flash scripts ---------------------------------------------------------------
LK2ND_FILE="$(basename "$LK2ND_IMG")"

cat > "$STAGE/flash.sh" <<EOF
#!/usr/bin/env bash
# Flash umeko Linux (${DEVS_JOINED}), extlinux variant.
set -euo pipefail
echo "[1/4] Flashing lk2nd bootloader (stock fastboot)..."
fastboot flash boot $LK2ND_FILE || fastboot flash:raw boot $LK2ND_FILE
echo
echo "lk2nd flashed. Reboot the phone and hold VOLUME-DOWN to enter"
echo "the lk2nd fastboot mode (its own fastboot, not the stock one)."
fastboot reboot || true
read -rp "Press Enter once the phone shows the lk2nd fastboot screen..."
echo "[2/4] Flashing extlinux boot fs to system partition..."
fastboot flash system bootfs.img
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
echo [2/4] Flashing extlinux boot fs to system partition...
fastboot flash system bootfs.img
echo [3/4] Flashing rootfs to userdata (THIS ERASES USER DATA)...
fastboot flash userdata rootfs.img
echo [4/4] Rebooting into Linux...
fastboot reboot
echo Done. First boot takes a while; log in as '$DEFAULT_USER' / '$DEFAULT_PASSWORD'.
pause
EOF

{
    echo "package:  $PKG_NAME  (extlinux boot)"
    for i in "${!DEVICE_DIRS[@]}"; do
        echo "device:   ${DEVICE_NAMES[$i]} ($(basename "${DEVICE_DIRS[$i]}")), dtb ${DEVICE_DTBS[$i]}"
    done
    cat <<EOF
soc:      $SOC
kernel:   $KREL ($KERNEL_SUBMODULE)
cmdline:  $KERNEL_CMDLINE
lk2nd:    $LK2ND_VERSION ($LK2ND_URL)
rootfs:   $(basename "$UBUNTU_BASE_URL"), UUID $ROOTFS_UUID
built:    $(date -u +%Y-%m-%dT%H:%M:%SZ)

Flashing layout (extlinux variant):
  boot     <- $LK2ND_FILE   (once, from the stock bootloader)
  system   <- bootfs.img    (ext2: /extlinux/extlinux.conf + $KERNEL_IMAGE + dtbs)
  userdata <- rootfs.img    (sparse ext4)

Login: $DEFAULT_USER / $DEFAULT_PASSWORD
Consoles: screen (tty0), UART ($SERIAL_CONSOLES), USB gadget serial (ttyGS0), SSH
EOF
} > "$STAGE/BUILD-INFO.txt"

log "packing $PKG_NAME.zip"
( cd "$STAGE" && zip -q -9 -r "$OUT_DIR/$PKG_NAME.zip" . )
ls -lh "$OUT_DIR/$PKG_NAME.zip"
log "done: $OUT_DIR/$PKG_NAME.zip"
