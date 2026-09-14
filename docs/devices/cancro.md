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
| 触摸屏 | 三个批次变体：Synaptics RMI4（I2C 0x70 / 0x71）、Atmel mxt640t —— 每个变体一个 `boots/boot-<变体>.img`，刷机时按屏幕批次选择 |
| 串口 | UART（ttyMSM0，需拆机）、USB gadget 串口（ttyGS0） |

## 支持状态

全部 🧪 —— 构建已验证，**待真机确认**。

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 屏幕 | 🧪 | simplefb；面板/触屏差异靠刷机时选对 boot.img 变体 |
| 触摸屏 | 🧪 | rmi4 / mxt640t 三个 dtb 变体已打包 |
| WiFi | 🧪 | WCN3680，固件由 umeko-modem-firmware 从 modem 分区提取 |
| USB 串口控制台 | 🧪 | configfs gadget（usb-gadget.service）+ ncm-serial，同 msm8916 机型 |
| USB CAN（gs_usb） | 🧪 | 内核已启用（=m，autocanup 拉起） |
| webssh | 🧪 | armhf 二进制从老项目实测包提取（vendored），autowebssh 已启用，端口 8888 |
| 基带 | ❌ | 未做 |

## 构建

- 内核：[bzy-080408/linux-msm8974](https://github.com/bzy-080408/linux-msm8974)
  `cancro-klipper` 分支（msm8974-mainline 的 fork，v6.15.11 + cancro dts +
  `cancro_klipper_defconfig`），submodule pin 在 `cc180c1f`
- defconfig 内建了 `USB_G_SERIAL`，本仓库的设备片段将其关闭
  （[issue #36](https://github.com/umeiko/KlipperPhonesLinux/issues/36) 同款问题），
  gadget 由 configfs 在开机时组装
- 上游曾有事故：`dts/qcom/Makefile` 被误粘了一段 dts 片段导致 make
  missing separator（旧 pin `24b3f611`），上游已在 `cc180c1f` 修复，
  不再需要本地补丁
- **启动路线是 mkbootimg（`pack.sh`），不是 extlinux**：lk2nd 只作为更好用的
  fastboot 刷入 boot 分区，真正的 Android boot.img（zImage+dtb 附加 + initrd）
  从 lk2nd 的 fastboot 再刷入 boot（lk2nd 存在 +512KiB 偏移处并 chainload）。
  这是老项目实测可用的路线；cmdline 里的 workaround 参数
  （`clk_ignore_unused pd_ignore_unused regulator_ignore_unused irqpoll
  msm.vram=192m …`）也从老包 boot.img 中原样继承
- initramfs 用 **gzip**（与老包一致）
- mkbootimg 参数取自历史 pmaports device-xiaomi-cancro 的 deviceinfo
  （base 0x0 / kernel +0x8000 / ramdisk +0x02000000 / tags +0x01e00000 /
  pagesize 2048，无 qcdt）

刷机：stock fastboot 刷 `lk2nd-msm8974.img` → 重启进 lk2nd 的 fastboot →
刷选好的 `boots/boot-<变体>.img` 到 boot + `rootfs.img` 到 userdata。
包内 `flash.sh`/`flash.bat` 会列出变体让你选（和老包一致）。

## 链接

- [msm8974-mainline](https://github.com/msm8974-mainline)（内核上游）
- [lk2nd 设备列表](https://github.com/msm8916-mainline/lk2nd/blob/main/Documentation/devices.md)（msm8974 节含 cancro）
- 机型配置：[`devices/cancro.env` + `devices/cancro/`](https://github.com/umeiko/umeko-Linux-phones/tree/main/devices)
