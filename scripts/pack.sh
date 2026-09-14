#!/usr/bin/env bash
# Pack the flashing bundle: boot.img (kernel + appended dtb), sparse
# rootfs.img, lk2nd, fastboot flash scripts, build info -> zip.
# Usage: PACK_VERSION=v1.0 scripts/pack.sh devices/<codename>.env
#
# The Android boot.img is flashed from lk2nd's own fastboot: lk2nd stores it
# at +512KiB in the boot partition and chainloads it (lk2nd itself stays).
# Devices shipping several dtb variants (e.g. cancro's three touch panels)
# get one boot-<variant>.img per dtb under boots/ and a chooser flash script.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_device "$1"
collect_devices "$@"
kernel_arch_vars

KBUILD="$BUILD_DIR/kernel"
KREL="$(cat "$BUILD_DIR/kernelrelease")"
PKG_VERSION="${PACK_VERSION:-$(date +%Y%m%d)}"
PKG_NAME="umeko-${DEVICE_CODENAME}-ubuntu24.04-${PKG_VERSION}"
STAGE="$BUILD_DIR/pack"

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
RAMDISK_ARGS=()
if [[ -f "$BUILD_DIR/initrd.img" ]]; then
    RAMDISK_ARGS=(--ramdisk "$BUILD_DIR/initrd.img")
else
    warn "initrd.img missing (assemble.sh too old?) — root=UUID= needs an initramfs!"
fi

# One boot image per dtb. Single-dtb devices get plain boot.img; multi-variant
# devices (cancro touch panels) get boots/boot-<variant>.img each.
BOOT_FILES=()
for dtb in "${DEVICE_DTBS[@]}"; do
    variant="$(basename "$dtb" .dtb)"; variant="${variant#qcom-}"
    if [[ ${#DEVICE_DTBS[@]} -eq 1 ]]; then
        out_img="boot.img"
    else
        out_img="boots/boot-${variant}.img"
        mkdir -p "$STAGE/boots"
    fi
    log "creating $out_img (dtb: $dtb)"
    cat "$KBUILD/$KERNEL_IMAGE_REL" \
        "$KBUILD/$DTS_DIR_REL/$dtb" > "$STAGE/kernel-dtb"
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
        -o "$STAGE/$out_img"
    BOOT_FILES+=("$out_img")
done
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

if [[ ${#BOOT_FILES[@]} -eq 1 ]]; then
    SELECT_SH='IMG="boot.img"'
    SELECT_BAT='@echo off
set IMG=boot.img'
else
    # Numbered chooser over boots/*.img (same UX as the legacy cancro bundle)
    SELECT_SH="$(cat <<'EOS'
mapfile -t IMGS < <(ls boots/*.img)
echo "choose your boot image (touch panel variant):"
for i in "${!IMGS[@]}"; do echo "  $((i+1)). ${IMGS[$i]}"; done
read -rp "number: " choice
IMG="${IMGS[$((choice-1))]:-}"
[[ -n "$IMG" ]] || { echo "invalid choice"; exit 1; }
EOS
)"
    SELECT_BAT='@echo off
setlocal enabledelayedexpansion
set i=0
for %%f in (boots\*.img) do (set /a i+=1 & set "IMG!i!=%%f" & echo   !i!. %%f)
set /p choice=number:
set IMG=
for /f "tokens=1,2 delims==" %%a in ('set IMG%choice% 2^>nul') do set IMG=%%b
if "%IMG%"=="" (echo invalid choice & exit /b 1)'
fi

cat > "$STAGE/flash.sh" <<EOF
#!/usr/bin/env bash
# Flash umeko Linux ($DEVICE_NAME / $DEVICE_CODENAME) — requires fastboot.
set -euo pipefail
$SELECT_SH
echo "[1/4] Flashing lk2nd bootloader (stock fastboot)..."
fastboot flash boot $LK2ND_FILE || fastboot flash:raw boot $LK2ND_FILE
echo
echo "lk2nd flashed. Reboot the phone and hold VOLUME-DOWN to enter"
echo "the lk2nd fastboot mode (its own fastboot, not the stock one)."
fastboot reboot || true
read -rp "Press Enter once the phone shows the lk2nd fastboot screen..."
echo "[2/4] Flashing boot image (\$IMG)..."
fastboot flash boot "\$IMG"
echo "[3/4] Flashing rootfs to userdata (THIS ERASES USER DATA)..."
fastboot flash userdata rootfs.img
echo "[4/4] Rebooting into Linux..."
fastboot reboot
echo "Done. First boot takes a while; log in as '$DEFAULT_USER' / '$DEFAULT_PASSWORD'."
EOF
chmod +x "$STAGE/flash.sh"

cat > "$STAGE/flash.bat" <<EOF
$SELECT_BAT
echo [1/4] Flashing lk2nd bootloader (stock fastboot)...
fastboot flash boot $LK2ND_FILE
if errorlevel 1 fastboot flash:raw boot $LK2ND_FILE
echo.
echo lk2nd flashed. The phone will reboot; hold VOLUME-DOWN to enter
echo the lk2nd fastboot mode (its own fastboot, not the stock one).
fastboot reboot
pause
echo [2/4] Flashing boot image (%IMG%)...
fastboot flash boot %IMG%
echo [3/4] Flashing rootfs to userdata (THIS ERASES USER DATA)...
fastboot flash userdata rootfs.img
echo [4/4] Rebooting into Linux...
fastboot reboot
echo Done. First boot takes a while; log in as '$DEFAULT_USER' / '$DEFAULT_PASSWORD'.
pause
EOF

cat > "$STAGE/BUILD-INFO.txt" <<EOF
package:  $PKG_NAME
device:   $DEVICE_NAME ($DEVICE_CODENAME), SoC $SOC, $ARCH
kernel:   $KREL ($KERNEL_SUBMODULE)
dtb:      ${DEVICE_DTBS[*]}
cmdline:  $KERNEL_CMDLINE
lk2nd:    $LK2ND_VERSION ($LK2ND_URL)
rootfs:   $(basename "$UBUNTU_BASE_URL"), UUID $ROOTFS_UUID
built:    $(date -u +%Y-%m-%dT%H:%M:%SZ)

Flashing layout:
  boot     <- $LK2ND_FILE   (once, from the stock bootloader)
  boot     <- ${BOOT_FILES[*]}   (from lk2nd fastboot; lk2nd stores it at +512KiB)
  userdata <- rootfs.img    (sparse ext4)

Login: $DEFAULT_USER / $DEFAULT_PASSWORD
Consoles: screen (tty0), UART ($SERIAL_CONSOLES), USB gadget serial (ttyGS0), SSH
EOF

log "packing $PKG_NAME.zip"
( cd "$STAGE" && zip -q -9 -r "$OUT_DIR/$PKG_NAME.zip" . )
ls -lh "$OUT_DIR/$PKG_NAME.zip"
log "done: $OUT_DIR/$PKG_NAME.zip"
