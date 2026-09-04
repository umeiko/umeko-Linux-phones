# umeko-Linux-phones

把旧手机变成 Linux 上位机 —— **全自动构建刷机包**。

本项目是 [KlipperPhonesLinux](https://github.com/umeiko/KlipperPhonesLinux) 的续作：从"收集别人做好的刷机包"转向"从源码全自动构建刷机包"。目前支持 **红米2（wt88047）**、**vivo Y23L（pd1419）** 两款 MSM8916 机型（arm64）和 **小米4（cancro，MSM8974PRO，32 位 armhf，独立包）**（见[机型列表](devices/index.md)），系统底包为 **Ubuntu 24.04 最小系统**。

全部构建由 GitHub Actions 完成，也可以用 Docker 在本机一键构建（见[本地 Docker 构建](docker.md)）。

## 构建产物是什么

每次构建产出一个 zip 刷机包（extlinux 合并包，一个包支持全部机型），里面 6 个文件：

| 文件 | 是什么 |
| --- | --- |
| `lk2nd-msm8916.img` | 二级 bootloader（[msm8916-mainline/lk2nd](https://github.com/msm8916-mainline/lk2nd) 官方 release，sha256 校验）。刷进 boot 分区，负责识别机型、选对 dtb、提供 fastboot |
| `bootfs.img` | ext2 启动分区（红米2 刷 system 分区，Y23L 刷 boot 分区）：`/extlinux/extlinux.conf` + 内核 `Image.gz` + `initrd.img` + 全部机型的 dtb，lk2nd 按机型自动挑选（见 [extlinux 路线](extlinux.md)） |
| `rootfs.img` | Ubuntu 24.04 arm64 最小系统（sparse ext4 格式，刷入 userdata 分区），已内置全部预装软件和自启服务 |
| `flash.sh` / `flash.bat` | fastboot 一键刷入脚本（Linux/macOS 用 .sh，Windows 用 .bat） |
| `BUILD-INFO.txt` | 构建溯源信息：内核版本、cmdline、lk2nd 版本、rootfs 来源、构建时间 |

这些文件全部由 CI 从公开源码/官方源实时构建，不存在"不明来源的二进制"（唯一的例外是 webssh 预编译二进制，构建时从[指定 commit](https://gitee.com/meiziyang2023/umeko-env-init) 下载并做 sha256 校验）。

## 怎么获取和刷入

1. **下载**：到 [Actions 页面](https://github.com/umeiko/umeko-Linux-phones/actions)找最新一次成功的构建，下载 `wt88047-package` artifact；或下载 [Release](https://github.com/umeiko/umeko-Linux-phones/releases)（打 tag 的正式版）。
2. **刷入**：解压 zip，手机进 fastboot，运行 `flash.sh`（或 Windows 下 `flash.bat`），按提示操作即可。详见[刷机与日常使用](flashing.md)。
3. **登录**：用户名 `umeko`，密码 `1234`。

## 控制台入口（刷完怎么操作它）

| 入口 | 说明 |
| --- | --- |
| 屏幕 | 直接显示启动日志和登录提示（tty0） |
| USB 串口 | **插上电脑就出一个免密串口控制台**（ttyGS0，configfs gadget 由 usb-gadget.service 开机组装），同时还有一个 USB 网卡（usb0，手机端 `192.168.100.1`，可直接 SSH） |
| UART | ttyMSM0，115200（需要拆机接 TTL 串口线） |
| SSH | 先用上面的任意控制台 `nmtui` 配好 WiFi |
| webssh | 配好网络后浏览器访问 `http://<手机IP>:8888` |

## 内置服务

构建时已集成来自 [umeko-env-init](https://gitee.com/meiziyang2023/umeko-env-init) 的初始化服务（针对 Klipper 上位机场景）：

| 服务 | 作用 |
| --- | --- |
| `umeko-modem-firmware` | 首次开机从手机自己的 modem 分区提取 WiFi/基带固件（高通专有固件不能打进发布物，设备上自提取） |
| `autottyGS0` | USB 串口免密自动登录控制台 |
| `autoresize` | 开机自动把根分区扩满整个 userdata |
| `auto_rmi4_reload` | 触摸屏驱动 workaround（配合 `touchscreens-workaround.conf`） |
| `autowebssh` | webssh 网页 SSH（端口 8888） |
| `autocanup` | 自动拉起 USB CAN 适配器（gs_usb，can0 @ 500k，接 3D 打印机工具板用） |

## 下一步读什么

- 想知道**为什么旧手机能跑主线 Linux**：读[原理篇](principle.md)
- 想知道**构建系统怎么工作**、怎么加新机型：读[构建系统详解](build.md)
- 想**在自己电脑上构建**（不用 GitHub Actions）：读[本地 Docker 构建](docker.md)
