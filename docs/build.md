# 构建系统详解

## 流水线总览

四个脚本按顺序组成完整流水线（CI 和本地都是同一套）：

```
build_kernel.sh     交叉编译内核：Image.gz + 机型 dtb + 内核 modules
build_rootfs.sh     下载 ubuntu-base tarball（sha256 校验）+ 创建固定 UUID 的空 ext4 镜像
assemble.sh         挂载镜像 + qemu-aarch64 chroot：装包、建用户、locale、串口 console、
                    装内核 modules、生成 initramfs、套用机型定制（overlay / 预置二进制 /
                    post-assemble 钩子），可选编译安装 buffyboard（见下文）
pack_extlinux.sh    默认打包路线：mke2fs 出纯 ext2 的 bootfs.img（extlinux.conf +
                    Image.gz + initrd.img + 全机型 dtb）、img2simg 出 sparse rootfs.img、
                    下载 lk2nd、生成 flash.sh/flash.bat 和 BUILD-INFO.txt，打 zip
pack.sh             legacy 路线（CI 不再自动构建）：mkbootimg 出 boot.img 的单机型包
```

所有脚本接受同一个参数：机型配置文件，如 `./scripts/build_kernel.sh devices/wt88047.env`。
`build_kernel.sh` / `assemble.sh` / `pack_extlinux.sh` 还接受**多个机型配置**：
每个机型的定制（patch、config 片段、overlay、钩子）都会叠加进同一份产物——
这是 extlinux 合并包（一个包支持多台机器）的基础，第一个 env 提供共享基准配置
（cmdline、rootfs UUID、主机名等）。

## 配置分层

```
config/base.env            # 全局：ubuntu-base 源、预装包清单、时区、locale
devices/wt88047.env        # 机型：内核 submodule/dtb、mkbootimg 布局参数、rootfs UUID、
                           #       cmdline、lk2nd 版本+sha256、主机名、默认用户、串口、webssh 源
devices/wt88047/           # 机型定制目录（全部可选，见下）
```

### 机型定制目录 `devices/<codename>/`

| 文件/目录 | 何时被使用 | 作用 |
| --- | --- | --- |
| `kernel.config` | build_kernel.sh | 内核配置片段，defconfig 之后用内核自带的 `scripts/kconfig/merge_config.sh` 合并，再 `olddefconfig` |
| `kernel-patches/` | build_kernel.sh | 内核补丁（`*.patch`，按文件名排序用 `git apply` 打进内核树，幂等；已应用的会跳过）。注意：打补丁会弄脏内核工作树，配合片段里 `# CONFIG_LOCALVERSION_AUTO is not set`（脚本同时导出空 `LOCALVERSION`）保证 kernelrelease 可复现 |
| `rootfs/` | assemble.sh | 机型私有 overlay，原样拷入根文件系统。所有机型共享的 overlay 在 `config/rootfs/`（umeko 服务套件：usb-gadget、autottyGS0、autoresize 等），先拷贝、可被机型 overlay 覆盖 |
| `post-assemble.sh` | assemble.sh | 根文件系统组装完成后在 chroot 里执行的钩子：`systemctl enable …`、编译安装额外软件等。环境变量带 `DEVICE_CODENAME` `DEVICE_NAME` `SOC` `DEFAULT_USER` `BOOTFS_UUID` |

`KERNEL_DTB` 支持空格分隔多个 dtb（如 cancro 的三个触屏变体），多于一个时
extlinux.conf 自动走 `fdtdir /dtbs` 由 lk2nd 匹配。

跨架构说明：`ARCH`（arm64/armhf）决定交叉工具链、chroot 用的 qemu 二进制、
内核镜像（Image.gz / zImage）和 ubuntu-base tarball（设备 env 里覆盖
`UBUNTU_BASE_URL` 选 armhf；initrd 压缩格式用 `INITRD_COMPRESS` 覆盖）。
不同架构的机型不能进同一次多机型构建，各自出独立包（见 CI 的 build-cancro job）。

wt88047 的内核片段（`devices/wt88047/kernel.config`）在 msm8916_defconfig 基础上打开了：USB configfs gadget（`USB_CONFIGFS` + SERIAL + NCM，由 `usb-gadget.service` 开机组装出 ttyGS0 串口 + usb0 网卡，见下文"已知边界"）、CAN + gs_usb（USB CAN 适配器）、RNDIS host、FRAMEBUFFER_CONSOLE（屏幕控制台）。这些参考自 KlipperPhonesLinux 广受好评的红米2 刷机包所用的内核配置。

## CI 流水线（.github/workflows/build.yml）

- **触发**：push 到 `main` 且改动涉及代码（`scripts/` `devices/` `config/` `kernels/` 等，由前置 `changes` job 用 `git diff` 门控——纯文档变更不构建）或手动触发 → 构建并上传 artifact（保留 14 天）；push `v*` tag → 始终构建并发布 GitHub Release（tag 不受路径过滤影响）
- **环境**：`ubuntu-24.04` runner，依赖安装清单与 [Dockerfile](docker.md) 一致
- **产物**：两个 job 两个包——`build` 出 msm8916 extlinux 合并包（`DEVICE_ENVS_EXTLINUX`：红米2 + vivo Y23L），`build-cancro` 出 cancro 独立包（armhf，内核源/工具链/底包均不同）；mkbootimg 单机型包（`pack.sh`）已转 legacy，CI 不再构建，需要时本地跑
- **buffyboard**：CI 上 `BUFFYBOARD=0`，只构建 base 包（qemu 下编译 buffyboard 太慢），开关见下文
- **缓存**：
  - ccache（key `kernel-wt88047`）——第二次起内核编译从 ~8 分钟降到 1~2 分钟
  - ubuntu-base tarball（`.cache/` 目录）
- **并发控制**：同一 ref 的重复 push 会取消正在进行的旧构建

## buffyboard 屏幕键盘（可选）

[buffyboard](https://gitlab.postmarketos.org/postmarketOS/buffybox) 是 pmOS 项目的
触摸屏控制台键盘，直接在 framebuffer/DRM 上画键盘，不依赖显示服务器——适合
手机当上位机、没接键盘时直接在屏幕上操作终端。

默认关闭（CI 也是 `BUFFYBOARD=0`），本地构建打开：

```bash
# 临时开一次
BUFFYBOARD=1 ./scripts/assemble.sh devices/wt88047.env devices/vivo-y23l.env
# 或者改 config/base.env 里的 BUFFYBOARD="1"
```

- 打开后在 chroot 里从源码编译（qemu 下约 10 分钟），产物是
  `usr/local/bin/buffyboard` + 配置文件 + systemd unit（默认 enabled，开机自启）
- **本地缓存**：第一次编译完成后产物打成
  `.cache/buffyboard-<tag>-arm64.tar.gz`，之后构建直接解包安装，几秒完成；
  删掉该文件（或改 `BUFFYBOARD_TAG`）才会重新编译
- 版本钉在 `config/base.env` 的 `BUFFYBOARD_TAG`（当前 3.5.1），保证可复现

## 可复现性设计

- 内核 submodule 钉死在固定 commit（`git submodule` 天然带 SHA）
- lk2nd / ubuntu-base / webssh 二进制全部带 sha256 校验
- rootfs ext4 使用固定 UUID（`93afcbbe-…`），cmdline 里 `root=UUID=` 因此可复现
- 每次构建生成 `BUILD-INFO.txt` 记录所有来源和版本

## 添加新机型

1. 复制 `devices/wt88047.env` 为 `devices/<codename>.env`，改 dtb、mkbootimg 参数、cmdline、rootfs UUID 等
2. 如需不同 SoC 的内核，`git submodule add` 到 `kernels/`
3. 按需创建 `devices/<codename>/`（kernel.config / kernel-patches/ / rootfs overlay / post-assemble.sh）
4. 在 `.github/workflows/build.yml` 把 `DEVICE_ENV` 改成 matrix 以并行构建多机型；
   同 SoC 的机型也可以加进 `DEVICE_ENVS_EXTLINUX` 出一个 extlinux 合并包（见 [extlinux 路线](extlinux.md)）

## boot.img 打包参数（mkbootimg）来源

`devices/wt88047.env` 里的 `BOOTIMG_*` 参数不是拍脑袋定的，来源是 **postmarketOS 的 pmaports 仓库**：

`device/community/device-xiaomi-wt88047/deviceinfo`（[gitlab.com/postmarketOS/pmaports](https://gitlab.com/postmarketOS/pmaports/-/blob/master/device/community/device-xiaomi-wt88047/deviceinfo)）中的 `deviceinfo_flash_offset_*` 系列：

| 本仓库参数 | pmaports deviceinfo | 值 |
| --- | --- | --- |
| `BOOTIMG_BASE` | `deviceinfo_flash_offset_base` | `0x80000000` |
| `BOOTIMG_KERNEL_OFFSET` | `deviceinfo_flash_offset_kernel` | `0x00080000` |
| `BOOTIMG_RAMDISK_OFFSET` | `deviceinfo_flash_offset_ramdisk` | `0x02000000` |
| `BOOTIMG_SECOND_OFFSET` | `deviceinfo_flash_offset_second` | `0x00f00000` |
| `BOOTIMG_TAGS_OFFSET` | `deviceinfo_flash_offset_tags` | `0x01e00000` |
| `BOOTIMG_PAGESIZE` | `deviceinfo_flash_pagesize` | `2048` |
| dtb 追加在 kernel 后（`cat Image.gz dtb`） | `deviceinfo_append_dtb="true"` | — |

这套布局是 **lk2nd 引导约定的事实标准**（lk2nd 解析 boot.img 头并按这些偏移加载）。注意老项目 KlipperPhonesLinux 的 `mkboot.sh` 用的是 stock-aboot 风格偏移（kernel `0x8000` / ramdisk `0x01000000` / tags `0x100`），与本仓库不同——两套经 lk2nd 引导都能工作，新项目统一采用 pmOS 约定。

`KERNEL_CMDLINE` 里的 `root=UUID=93afcbbe-…` 来自 `build_rootfs.sh` 里 `mkfs.ext4 -U` 写入的固定 UUID（沿用老项目 base rootfs 的 UUID），不是从任何设备里读出来的。

**添加新机型时**：优先抄对应 pmaports `deviceinfo` 的 `deviceinfo_flash_offset_*`；pmaports 没有的机型，用 `unpackbootimg` 或 `pmbootstrap bootimg_analyze` 分析原厂 boot.img 提取参数。

## 已知边界

- 内核版本号在本地 Windows 工作区直接构建时可能带 `-dirty` 后缀（Windows 文件系统丢 exec 位/符号链接导致内核 git 树变"脏"）。用[容器内构建](docker.md)则无此问题；CI 上始终干净
- Ubuntu 24.04 的 `mkbootimg` 包漏装了 `gki` python 模块（上游打包 bug，只在用 GKI 签名参数时才真正需要它）。`pack.sh` 检测到会自动在宿主机装一个 stub 模块，无需人工干预
- **USB gadget 走 configfs，不再内建 g_serial**（修复 [#36](https://github.com/umeiko/KlipperPhonesLinux/issues/36)）：内建的 `CONFIG_USB_G_SERIAL=y` 开机即独占 USB 控制器（UDC），OTG ID 脚触发的角色切换无法进行。现在 gadget 由 `usb-gadget.service` 开机通过 configfs 按需组装（acm 串口 ttyGS0 + NCM 网卡 usb0，脚本在 `config/rootfs/usr/local/lib/umeko/usb_gadget_setup.sh`），UDC 在 gadget 创建时才绑定，给 OTG 角色切换留出了空间。插电脑同时得到串口控制台和 USB 网卡（手机端 `192.168.100.1`，可直接 SSH）
- **btrfs-progs 已强制移除**：ubuntu-base 自带的 btrfs-progs 与高通 SoC 平台存在致命冲突（其 udev 规则/用户态会在启动时卡死），assemble.sh 在 chroot 里 `apt-get purge -y btrfs-progs`，不要在 `ROOTFS_PACKAGES` 里再加回来
