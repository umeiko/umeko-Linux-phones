# umeko-Linux-phones 本地构建环境
#
# 与 .github/workflows/build.yml 中 CI runner 的依赖保持一致。
# chroot/mount 需要特权容器运行：
#   docker run --privileged ...
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 包说明：
#   gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi
#       —— 交叉编译内核（arm64: msm8916；armhf: msm8974/cancro）
#   build-essential bc bison flex libssl-dev libncurses-dev dwarves
#       —— 内核构建脚本与宿主机工具
#   kmod ccache             —— depmod 生成 modules.dep；ccache 加速重复编译
#   qemu-user-static        —— 在 x86_64 上 chroot 进 arm64/armhf rootfs 执行 apt/systemctl
#   mkbootimg               —— 打 Android boot.img（pack.sh 会自愈 Ubuntu 包缺 gki 模块的问题）
#   android-sdk-libsparse-utils —— img2simg 转 sparse 镜像给 fastboot
#   e2fsprogs               —— mkfs.ext4/resize2fs
#   zip curl ca-certificates git sudo python3 —— 打包、下载校验、submodule、脚本环境
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi build-essential bc bison flex libssl-dev \
        libncurses-dev kmod ccache dwarves \
        qemu-user-static mkbootimg android-sdk-libsparse-utils e2fsprogs \
        zip curl ca-certificates git sudo python3 \
    && rm -rf /var/lib/apt/lists/*

# 构建在容器本地 ext4 文件系统的 /work 下进行（不要直接在 Windows/macOS
# 的 bind mount 上编译内核，9p/virtiofs 会慢一个数量级）。
WORKDIR /work
