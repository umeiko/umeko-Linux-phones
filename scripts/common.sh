#!/usr/bin/env bash
# Common helpers shared by all build scripts.
# Scripts run on a Linux host (GitHub Actions ubuntu-24.04 runner, or WSL2).
set -euo pipefail

log()  { printf '\033[1;32m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"
BUILD_DIR="$REPO_ROOT/build"
OUT_DIR="$REPO_ROOT/out"
MNT_DIR="$BUILD_DIR/mnt"

# Load devices/<codename>.env (argument) plus config/base.env.
load_device() {
    local env_file="${1:?usage: $0 devices/<codename>.env}"
    [[ -f "$env_file" ]] || die "device config not found: $env_file"
    env_file="$(realpath "$env_file")"
    # shellcheck disable=SC1090
    source "$env_file"
    # shellcheck disable=SC1091
    source "$REPO_ROOT/config/base.env"
    # Per-device customization directory (kernel fragment, rootfs overlay,
    # post-assemble hook). All entries are optional.
    DEVICE_DIR="$REPO_ROOT/devices/$DEVICE_CODENAME"
    log "device: $DEVICE_NAME ($DEVICE_CODENAME, SoC $SOC)"
}

# Collect per-device info for a multi-device invocation. Fills two indexed
# arrays: DEVICE_DIRS (devices/<codename>/ per env) and DEVICE_DTBS (the
# KERNEL_DTB of each env — a space-separated list is split into separate
# entries, e.g. cancro ships three touchscreen-variant dtbs). The first env is
# the "base" one already loaded by load_device; its other values (cmdline,
# UUID, hostname, ...) are used for the shared artifacts.
collect_devices() {
    DEVICE_DIRS=()
    DEVICE_DTBS=()
    DEVICE_NAMES=()
    DEVICE_CODES=()
    local env code dtbs dtb dname
    for env in "$@"; do
        [[ -f "$env" ]] || die "device config not found: $env"
        code="$(basename "$env" .env)"
        [[ -d "$REPO_ROOT/devices/$code" ]] || die "device dir missing: devices/$code"
        dtbs="$(bash -c 'source "$1" >/dev/null 2>&1; echo "${KERNEL_DTB:-}"' _ "$(realpath "$env")")"
        [[ -n "$dtbs" ]] || die "KERNEL_DTB missing in $env"
        dname="$(bash -c 'source "$1" >/dev/null 2>&1; echo "${DEVICE_NAME:-}"' _ "$(realpath "$env")")"
        DEVICE_DIRS+=("$REPO_ROOT/devices/$code")
        for dtb in $dtbs; do
            DEVICE_DTBS+=("$dtb")
        done
        DEVICE_NAMES+=("${dname:-$code}")
        DEVICE_CODES+=("$code")
    done
}

# Derive kernel-tree variables from the device ARCH (arm64 | armhf).
# Sets: KARCH (kernel tree arch), CROSS (toolchain prefix, overridable via
# CROSS_COMPILE_PREFIX in a device env), KERNEL_IMAGE (Image.gz on arm64,
# zImage on 32-bit ARM unless overridden), KERNEL_IMAGE_REL / DTS_DIR_REL
# (paths relative to the kernel build dir).
kernel_arch_vars() {
    case "${ARCH:?ARCH missing in device env}" in
        arm64) KARCH=arm64; DEFAULT_CROSS=aarch64-linux-gnu- ;;
        armhf) KARCH=arm;   DEFAULT_CROSS=arm-linux-gnueabi- ;;
        *)     die "unsupported ARCH: $ARCH (expected arm64 or armhf)" ;;
    esac
    CROSS="${CROSS_COMPILE_PREFIX:-$DEFAULT_CROSS}"
    KERNEL_IMAGE="${KERNEL_IMAGE:-Image.gz}"
    [[ "$KARCH" == "arm" && "$KERNEL_IMAGE" == "Image.gz" ]] && KERNEL_IMAGE="zImage"
    KERNEL_IMAGE_REL="arch/$KARCH/boot/$KERNEL_IMAGE"
    DTS_DIR_REL="arch/$KARCH/boot/dts"
}

# Trim free space in the rootfs image (punch holes via loop discard) so the
# sparse image produced by img2simg does not carry stale blocks from files
# deleted during assemble (e.g. purged build dependencies).
trim_rootfs_image() {
    local img="$1" mnt
    mnt="$(mktemp -d)"
    sudo mount -o loop "$img" "$mnt"
    sudo fstrim "$mnt"
    sudo umount "$mnt"
    rmdir "$mnt"
}
