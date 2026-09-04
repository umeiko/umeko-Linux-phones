# umeko-Linux-phones

把旧手机变成 Linux 上位机 —— 自动构建系统。
（Successor of [KlipperPhonesLinux](https://github.com/umeiko/KlipperPhonesLinux)：从"收集刷机包"转向"全自动构建刷机包"。）

**当前状态**：支持红米2 (wt88047) 与 vivo Y23L (pd1419)（msm8916/arm64，一个 extlinux 合并包通吃两机型），以及小米4 (cancro, msm8974/armhf 32 位，独立包)。均为 Ubuntu 24.04 base 最小系统（不含 Klipper），全部由 GitHub Actions 构建。

📖 **文档站**：[umeiko.github.io/umeko-Linux-phones](https://umeiko.github.io/umeko-Linux-phones/) —— 从小白原理到本地构建的完整文档。

## 构建产物

每个构建产出一个 zip 刷机包：

| 文件 | 说明 |
| --- | --- |
| `lk2nd-msm8916.img` | 二级 bootloader（[msm8916-mainline/lk2nd](https://github.com/msm8916-mainline/lk2nd) 官方 release，sha256 校验） |
| `bootfs.img` | ext2 启动分区：`/extlinux/extlinux.conf` + `Image.gz` + `initrd.img` + 全机型 dtb，lk2nd 按机型自动选 dtb |
| `rootfs.img` | Ubuntu 24.04 arm64 最小系统（sparse ext4，刷入 userdata） |
| `flash.sh` / `flash.bat` | fastboot 一键刷入脚本 |
| `BUILD-INFO.txt` | 构建溯源信息 |

## 构建流程（GitHub Actions）

```
build_kernel.sh    交叉编译 msm8916-mainline/linux @ v6.12.1-msm8916（msm8916_defconfig
                   + devices/<codename>/kernel.config 机型配置片段，ccache）
build_rootfs.sh    下载 ubuntu-base 24.04 arm64 tarball（SHA256SUMS 校验），创建固定 UUID 的 ext4 镜像
assemble.sh        mount + qemu-aarch64 chroot：装包/用户/locale/串口 console，装入内核 modules，
                   再套用机型定制：devices/<codename>/rootfs/ overlay 原样拷入根文件系统
                   （systemd 服务、modprobe 配置、辅助脚本），按需下载校验机型预置二进制
                   （如 webssh），最后在 chroot 内执行 devices/<codename>/post-assemble.sh
pack_extlinux.sh   默认路线：mke2fs 出 ext2 的 bootfs.img（extlinux.conf + Image.gz + initrd
                   + 全机型 dtb），img2simg 出 rootfs.img，下载 lk2nd，生成刷机脚本，打 zip
pack.sh            legacy 路线（CI 不再构建）：mkbootimg 出 boot.img 的单机型包
```

所有机型的公共定制（`config/rootfs/`）内置了来自
[umeko-env-init](https://gitee.com/meiziyang2023/umeko-env-init) 的服务：

| 服务 | 作用 |
| --- | --- |
| `umeko-modem-firmware` | 首次开机从手机 modem 分区提取 WiFi/基带固件到 `/lib/firmware`（wcnss 等，不可再分发故不打包进镜像） |
| `usb-gadget` | 开机用 configfs 组装 USB 复合 gadget：acm 串口（ttyGS0）+ NCM 网卡（usb0，手机端 192.168.100.1） |
| `autottyGS0` | ttyGS0 免密自动登录控制台 |
| `autoresize` | 开机自动把根分区文件系统扩满 userdata |
| `auto_rmi4_reload` + `touchscreens-workaround.conf` | 触摸屏驱动 workaround |
| `autowebssh` | webssh 网页 SSH（端口 8888；cancro 暂无 armhf 二进制，WIP 未启用） |
| `autocanup` | 自动拉起 USB CAN（gs_usb，can0 @ 500k） |

- push 到 `main` 或手动触发 → 构建并上传 artifact
- push `v*` tag → 构建并发布 GitHub Release

## 添加新机型

1. 复制 `devices/wt88047.env` 为 `devices/<codename>.env`，改 dtb、mkbootimg 参数、cmdline 等
   （`ARCH` 支持 arm64/armhf；32 位机型还需覆盖 `UBUNTU_BASE_URL` 为 armhf tarball）
2. 如需不同 SoC 内核，添加对应 submodule 到 `kernels/`（如 cancro → `kernels/msm8974`）
3. 机型定制放在 `devices/<codename>/` 目录（全部可选）：
   - `kernel.config` — 内核配置片段，defconfig 之后由 build_kernel.sh 合并
   - `rootfs/` — 机型私有 overlay（机型无关的公共服务在 `config/rootfs/`，所有机型自动套用）
   - `post-assemble.sh` — 根文件系统组装完成后在 chroot 内执行的钩子
     （启用服务、编译安装额外软件等；环境变量带 DEVICE_CODENAME 等机型参数）
4. 同 SoC 同架构的机型加进 `.github/workflows/build.yml` 的 `DEVICE_ENVS_EXTLINUX`，
   出 extlinux 合并包；不同 SoC/架构的机型照 `build-cancro` job 另起独立构建

## 仓库结构

```
├── .github/workflows/build.yml   # CI 流水线（build: msm8916 合并包；build-cancro: armhf 独立包）
├── .github/workflows/pages.yml   # 文档站部署（GitHub Pages）
├── config/base.env               # 全局配置（ubuntu-base 源、预装包、时区、bootfs UUID、buffyboard 开关）
├── config/rootfs/                # 全机型共享 overlay：umeko 服务套件（usb-gadget/autottyGS0/...）
├── devices/wt88047.env           # 机型配置（内核/dtb/mkbootimg 参数/lk2nd/cmdline/webssh 源）
├── devices/wt88047/              # 机型定制：kernel.config、post-assemble.sh
├── devices/vivo-y23l.env         # 第二机型配置（与 wt88047 合并出 extlinux 包）
├── devices/vivo-y23l/            # vivo 机型定制：内核 patch（设备树+面板驱动）、fstab 钩子
├── devices/cancro.env            # 小米4（msm8974/armhf）配置
├── devices/cancro/               # cancro 定制：kernel.config（关 G_SERIAL 等）、post-assemble.sh
├── docker/Dockerfile             # 本地构建环境（与 CI 依赖一致）
├── docs/                         # 文档站源码（mkdocs-material）
├── kernels/msm8916               # submodule：msm8916-mainline/linux @ v6.12.1-msm8916
├── kernels/msm8974               # submodule：bzy-080408/linux-msm8974 @ cancro-klipper
└── scripts/                      # build_kernel / build_rootfs / assemble / pack_extlinux / pack(legacy) / docker_build
```

## 本地构建（可选）

**推荐 Docker 一键构建**（Linux/macOS/Windows 均可，Windows 请在 Git Bash 里跑）：

```bash
git clone --recursive https://github.com/umeiko/umeko-Linux-phones.git
cd umeko-Linux-phones
./scripts/docker_build.sh devices/wt88047.env devices/vivo-y23l.env    # 产物在 ./out/
```

详见[文档站的本地构建篇](https://umeiko.github.io/umeko-Linux-phones/docker/)。

脚本也可在 WSL2 (Ubuntu 24.04) 上直接运行，依赖同 CI：

```bash
sudo apt install gcc-aarch64-linux-gnu bc bison flex libssl-dev libncurses-dev kmod ccache \
    qemu-user-static mkbootimg android-sdk-libsparse-utils e2fsprogs zip curl
git submodule update --init --depth 1
./scripts/build_kernel.sh  devices/wt88047.env devices/vivo-y23l.env
./scripts/build_rootfs.sh  devices/wt88047.env
./scripts/assemble.sh      devices/wt88047.env devices/vivo-y23l.env   # 需要 sudo（mount/chroot）
./scripts/pack_extlinux.sh devices/wt88047.env devices/vivo-y23l.env   # 默认路线
# ./scripts/pack.sh        devices/wt88047.env                         # legacy（mkbootimg）
```

## 刷机（简述）

1. 手机进入 stock fastboot，运行包内 `flash.sh`（或 Windows 下 `flash.bat`；vivo Y23L 流程不同，见[机型页](https://umeiko.github.io/umeko-Linux-phones/devices/vivo-y23l/)）
2. 脚本先刷 lk2nd，重启按住音量减进入 lk2nd 的 fastboot，再刷 bootfs.img 和 rootfs.img
3. 首次启动较慢；登录 `umeko` / `1234`
4. 控制台入口：屏幕、UART（ttyMSM0）、USB 串口 gadget（ttyGS0，插上电脑即出免密控制台）、SSH（先用 nmtui 配 WiFi）、webssh（浏览器访问 `http://<手机IP>:8888`）

## 已知限制 / TODO

- ~~根分区不会自动扩满 userdata~~（已由 autoresize 服务开机自动扩容）
- ~~暂无 USB 网络配置~~（usb-gadget 服务已提供 NCM 网卡：usb0，手机端 192.168.100.1，可 SSH）
- 二期：Klipper 全家桶（klipper/moonraker/fluidd/KlipperScreen）chroot 安装、更多机型
