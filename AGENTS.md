# AGENTS.md

给 AI 编码助手的项目须知。**开始任何构建相关工作前必须通读本文件**——本仓库的构建流水线在 GitHub Actions 上一路绿灯，但在 Windows + 国内代理网络下本地构建有一整层已知的坑，全部记录在案，不要重新踩一遍。

## 项目是什么

自动构建旧手机的 Ubuntu 24.04 刷机包，用作 Klipper 上位机（Klipper 全家桶是二期，当前只出最小系统）。机型：红米2 wt88047、vivo Y23L（均 msm8916/arm64，合并包）；小米4 cancro（msm8974/armhf 32 位，独立包，CI job `build-cancro`）。

流水线（`scripts/` 下，按序执行）：

1. `build_kernel.sh` — submodule（msm8916 → msm8916-mainline/linux v6.12.1；cancro → bzy-080408/linux-msm8974 的 cancro-klipper 分支）+ `devices/<机型>/kernel-patches/` + `kernel.config` fragment。ARCH 由设备 env 决定（arm64→aarch64 工具链/Image.gz；armhf→arm-linux-gnueabi/zImage），多机型构建必须同架构
2. `build_rootfs.sh` — 下载 ubuntu-base tarball（arm64/armhf 由 `UBUNTU_BASE_URL` 决定，校验 SHA256）+ 固定 UUID 的 ext4 空镜像
3. `assemble.sh` — qemu chroot（arm64→qemu-aarch64-static，armhf→qemu-arm-static）装包/用户/服务 + 内核模块 + initramfs（压缩格式 `INITRD_COMPRESS`，cancro 用 gzip）+ **`config/rootfs/` 共享 overlay**（umeko 服务套件）+ 设备 overlay + post-assemble 钩子。**btrfs-progs 会被 purge（高通平台致命冲突，勿加回）**
4. `pack_extlinux.sh` — **默认路线**：extlinux 合并包（lk2nd 读 bootfs.img 里的 extlinux.conf，fdtdir 支持多机型/多 dtb 变体共包）。`pack.sh`（mkbootimg）是 legacy。

CI 在 `.github/workflows/build.yml`；纯文档 push 不触发构建（changes 门控），tag/手动始终构建。

## 本地构建（Windows）

标准入口：`./scripts/docker_build.sh devices/wt88047.env [devices/vivo-y23l.env ...]`，产物复制到 `UMERO_SHARE_DIR` 指定的共享目录（容器内 `/out-share`）。

### AI 在 Windows 上操作的首选流程

用户明确要求的姿势：**先起特权容器，再在容器内 git clone 仓库并构建**，而不是从 Windows 同步工作区。原因见下节——Windows 的 git checkout 本身就是坏的源头。

```bash
export MSYS2_ARG_CONV_EXCL='*'   # 每次开 Git Bash 会话都要，否则 docker 参数被翻译坏
docker run -d --name umeko-build --privileged \
    --add-host host.docker.internal:host-gateway \
    -e http_proxy=http://host.docker.internal:7890 \
    -e https_proxy=http://host.docker.internal:7890 \
    umeko-build-env sleep infinity
docker exec umeko-build bash -c 'git clone --recursive <repo> /work && cd /work && ./scripts/build_kernel.sh devices/wt88047.env ...'
```

容器保持常驻（ccache、`.cache`、内核 clone 都在容器里，不要随手 `docker rm`）。镜像 `umeko-build-env` 已构建好，**不要删**。

### Windows 特有坑（症状 → 根因）

| 症状 | 根因与对策 |
|---|---|
| docker 参数/路径乱码、容器秒退、`/dev/null` 变 `nul` | Git Bash (MSYS) 路径转换。每条 docker 命令前 `export MSYS2_ARG_CONV_EXCL='*'` |
| 内核编译报头文件缺失、dtc 报错 | Windows 的 git 把 symlink 存成文本文件（`core.symlinks=false`）。在容器内重新 clone 即可；若必须同步工作区，需从 `git ls-tree -r HEAD`（mode 120000）重建 symlink |
| 补丁打不上、脚本语法错 | CRLF 污染（`autocrlf`）。容器内 clone 免疫 |
| `arch/.../aux.h` 永远不存在 | DOS 保留文件名，Windows 上 checkout 不出来，无碍构建，忽略 |
| tar 报 `file changed as we read it` | Defender/索引器在摸文件，或对仓库目录有并发写。直接重跑 |
| 容器内 apt/curl 访问 GitHub 失败 | 容器里 `127.0.0.1` 是容器自己。代理要写成 `host.docker.internal:7890`，且容器启动时加 `--add-host host.docker.internal:host-gateway`，宿主 Clash 需允许局域网连接 |

### 代理进入 chroot 的三个连环坑（已修复，补丁在 assemble.sh 里标了 LOCAL-ONLY）

1. `sudo chroot` 的 `env_reset` 会剥掉 `http_proxy`/`https_proxy` → 用 `apt.conf.d/99umeko-local-proxy` 滴管配置穿透；
2. chroot 里 resolv.conf 是公网 DNS，解析不了 docker 内部名 `host.docker.internal` → 把 host-gateway IP 钉进 chroot 的 `/etc/hosts`（注意 setup 脚本会重写 `/etc/hosts`，要在重写后再补一条）；
3. **必须用 IPv4**：`getent hosts` 优先返回 IPv6，而 apt 用 `AI_ADDRCONFIG` 解析，容器没有全局 IPv6 时会静默丢弃 hosts 里的 IPv6 记录，报 `Could not resolve`——这是最容易误判成 DNS 问题的一个坑。

### chroot apt 换源与 CA 鸡生蛋

代理出口对 `ports.ubuntu.com` 的明文 HTTP 会随机 502（节点抖动）。LOCAL-ONLY 补丁已把 chroot 源换成 `https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports`，但 ubuntu-base 没装 `ca-certificates`，首个 `apt-get update` 会报证书不受信——所以要先从容器把 `/etc/ssl/certs/ca-certificates.crt` 预置进 chroot。这条链已验证可用（438 kB/s）。

## LOCAL-ONLY 纪律（重要）

以下改动**只留本地，绝不提交、绝不推送**：

- `scripts/assemble.sh` 里标 `[LOCAL-ONLY, do not commit]` 的代理穿透 + tuna 换源块
- `scripts/build_rootfs.sh` 的 SHA256SUMS 缓存复用块
- `scripts/docker_build.sh` 的本地适配（代理透传、`Dockerfile.local` 优先、共享区等）
- `docker/Dockerfile.local`（国内源镜像定义，已被 `.git/info/exclude` 屏蔽）

判断标准：与"国内代理网络/Windows 适配"相关的 → 本地；与构建逻辑本身相关的修复（如 `config/base.env` 的 `BUFFYBOARD="${BUFFYBOARD:-0}"`）→ 应入库。提交前先 `git diff` 逐 hunk 核对，别把两类混在一起。

## 其他必知

- **buffyboard**（触屏键盘）：默认关闭（`BUFFYBOARD=0`），`BUFFYBOARD=1` 开启。qemu 下编译 lvgl 要 20-40 分钟，产物缓存进 `.cache` 后可复用。自启 unit 用本仓库的 `config/buffyboard.service`（装到 `/etc/systemd/system/`，优先级高于上游 meson 装的带沙箱限制的版本）。
- `docker_build.sh` 第 5 步会 `rm -rf /out-share/*` 再复制——共享区里的旧产物会被清掉，重要产物提前备份。
- 容器每次构建会 `rm -rf /work` 再同步，容器内的 `/work/.cache` 不持久；宿主机的 `.cache/`（ubuntu-base tarball 等）会同步进容器复用。
- 构建产物 zip 体检清单：`bootfs.img` 必须是**无 extents 的纯 ext2**（`dumpe2fs -h` 看 features）、`rootfs.img` 是 Android sparse 格式（magic `3aff26ed`）、lk2nd img 过 sha256、flash 脚本与 BUILD-INFO.txt 齐全。
- 文档站用 mkdocs（`mkdocs.yml`），文档在 `docs/`，改构建行为时同步更新 `docs/docker.md`。
