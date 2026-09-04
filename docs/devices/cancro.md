# 小米 4（cancro）

小米 2014 年发布的旗舰（Mi 4 / Mi 3 联通电信版共用代号 cancro），
MSM8974PRO（骁龙 801）。本项目第一款 **32 位（armhf）** 机型，
独立出包，不进 msm8916 的 extlinux 合并包。

## 硬件参数

| | |
| --- | --- |
| 型号 | 小米 4 / 小米 3（W/C 版），代号 cancro |
| SoC | 高通 MSM8974PRO（4× Krait 400 @ 2.45GHz，32 位） |
| 屏幕 | 5.0" 1920×1080 IPS |
| 内存/存储 | 2~3GB RAM / 16~64GB eMMC |
| 触摸屏 | 三个批次变体：Synaptics RMI4（I2C 0x70 / 0x71）、Atmel mxt640t —— 包内带全部三个 dtb，lk2nd 按 fdtdir 匹配 |
| 串口 | UART（ttyMSM0，需拆机）、USB gadget 串口（ttyGS0） |

## 支持状态

全部 🧪 —— 构建已验证，**待真机确认**（包括 lk2nd-msm8974 的 extlinux
引导路径，msm8916 上已验证的用法在 8974 上首次使用）。

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 屏幕 | 🧪 | simplefb；面板识别靠 lk2nd 选 dtb 变体 |
| 触摸屏 | 🧪 | 三个 dtb 变体已打包 |
| WiFi | 🧪 | WCN3680，固件由 umeko-modem-firmware 从 modem 分区提取 |
| USB 串口控制台 | 🧪 | configfs gadget（usb-gadget.service）+ autottyGS0，同 msm8916 机型 |
| USB CAN（gs_usb） | 🧪 | 内核片段已启用（=m，autocanup 拉起） |
| webssh | ⏳ | **WIP**：暂无 armhf 的 webssh 预构建二进制，未启用（找到后补 WEBSSH_URL + enable autowebssh） |
| 基带 | ❌ | 未做 |

## 构建

- 内核：[bzy-080408/linux-msm8974](https://github.com/bzy-080408/linux-msm8974)
  `cancro-klipper` 分支（msm8974-mainline 的 fork，v6.15.11 + cancro dts +
  `cancro_klipper_defconfig`），submodule pin 在 `24b3f611`
- defconfig 内建了 `USB_G_SERIAL`，本仓库的设备片段将其关闭
  （[issue #36](https://github.com/umeiko/KlipperPhonesLinux/issues/36) 同款问题），
  gadget 由 configfs 在开机时组装
- initramfs 用 **gzip**（该内核 RD_ZSTD 支持未验证，RD_GZIP 确认开启）
- mkbootimg 参数（legacy `pack.sh` 用）取自历史 pmaports
  device-xiaomi-cancro 的 deviceinfo（该设备包已从 pmaports 移除）；
  注意 stock 打包需要 qcdt（`bootimg_qcdt=true`），extlinux/lk2nd 路线不需要

刷机步骤与其它机型相同，见[刷机与日常使用](../flashing.md)（lk2nd 刷 boot、
bootfs 刷 system、rootfs 刷 userdata）。

## 链接

- [msm8974-mainline](https://github.com/msm8974-mainline)（内核上游）
- [lk2nd 设备列表](https://github.com/msm8916-mainline/lk2nd/blob/main/Documentation/devices.md)（msm8974 节含 cancro）
- 机型配置：[`devices/cancro.env` + `devices/cancro/`](https://github.com/umeiko/umeko-Linux-phones/tree/main/devices)
