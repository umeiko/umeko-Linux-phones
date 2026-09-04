# vivo Y23L（vivo-y23l）

vivo 2015 年的入门机（PD1419L / PD1419F / PD1419V，同平台还有 Y623 / Y923）。
与红米 2 同为 MSM8916，**OS 侧与红米 2 共享同一个 extlinux 合并包**，
但引导器流程特殊（见下）。

!!! success "已真机验证"
    extlinux 合并包已在真机启动到登录界面（截图见下）。内核设备树和面板驱动
    来自社区 patch（已并入本仓库 `devices/vivo-y23l/kernel-patches/`）。

![vivo Y23L 启动日志](../assets/images/vivo-y23l-boot.jpg)

![vivo Y23L 登录界面](../assets/images/vivo-y23l-login.jpg)

## 硬件参数

| | |
| --- | --- |
| 型号 | vivo Y23L（pd1419） |
| SoC | 高通 MSM8916（4× Cortex-A53） |
| GPU | Adreno 306 |
| 屏幕 | 4.5" 854×480（FWVGA），**两种面板**：nt35510s 或 orise8012a |
| 内存/存储 | 1GB RAM / 16GB eMMC |
| 触摸屏 | Goodix gt928（部分批次 edt-ft5306） |
| 充电 | SMB358 充电管理（I2C） |
| 电池 | 1900mAh |
| 串口 | UART（ttyMSM0） |

## 与红米 2 的关键区别：引导器

Y23L 属于 vivo CDP 家族，是 lk2nd 官方标注的 **quirky 设备**：
原厂系统基于 Android 4.4.4，**aboot 只有 32 位**，无法加载 64 位的 lk2nd。
因此需要用 **lk1st**（一级引导）替换 aboot 分区，并把整套固件换成 64 位版本。

### 完整刷机流程

参考实现：[KlipperPhonesLinux vivo-msm8916 刷机包](https://github.com/umeiko/KlipperPhonesLinux/releases/tag/vivo-qcom410)
（内含一键刷机脚本，以下流程即整理自它）。

**第一步：底包（一次性，"解除 arm64 限制"）**

vivo 专用 fastboot 解锁，然后按序刷入 PD1419 底包固件：

```bash
fastboot bbk unlock_vivo          # 需 vivo 版 fastboot（bbk_unlock_vivo）
fastboot flash partition gpt_both0.bin
fastboot flash hyp       hyp.mbn
fastboot flash rpm       rpm.mbn
fastboot flash sbl1      sbl1.mbn
fastboot flash tz        tz.mbn
fastboot flash recovery  recovery.img
fastboot flash aboot     lk1st-pd1419-<面板>.mbn   # 按屏幕二选一
```

!!! danger "别刷错底包"
    PD1304（Y13L 系列）和 PD1419（Y23L）的 **sbl1 不同**，错刷变砖，需 9008 深刷救回。
    底包文件（gpt/hyp/rpm/sbl1/tz/recovery）是 vivo 专有固件，本仓库不分发；
    可从 vivo 官方 PD1419 线刷包或上面参考刷机包中提取。

**第二步：系统（可反复刷）**

lk1st 住进 aboot 后，boot 分区就空出来了，bootfs 直接刷 boot：

```bash
fastboot flash boot     bootfs.img      # ext2 extlinux 启动分区（sparse）
fastboot flash userdata rootfs.img      # sparse ext4
```

lk1st 按设备数据库选 `msm8916-vivo-pd1419.dtb`，并按探测到的面板改写 dtb 的
panel compatible（match-panel），两种面板驱动都已在合并包内核里。

## 支持状态

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 屏幕 | 🧪 | 两种面板驱动已编译进内核模块；lk1st/lk2nd 的 match-panel 机制按实际面板改写 dtb compatible |
| 触摸屏 | 🧪 | gt928 / edt-ft5306 设备树已配 |
| WiFi | 🧪 | WCN3620，固件提取服务与红米 2 共用 |
| 充电/电量计 | 🧪 | SMB358 + pm8916 BMS，设备树已配 |
| USB 串口控制台 | 🧪 | 与红米 2 相同（configfs gadget + autottyGS0）；dtb 照抄老项目实测可用的 device 版：`dr_mode=otg`，extcon 双槽都给 ID GPIO，`pm8916_usbin` 保持 disabled |
| 基带 | ❌ | 未做 |

✅ = 真机确认可用；🧪 = 构建已验证，待真机确认。

## 构建

Y23L 不单出包，由 extlinux 合并包同时支持（见[机型列表](index.md)）：

```bash
PACK_VERSION=test scripts/pack_extlinux.sh devices/wt88047.env devices/vivo-y23l.env
```

lk2nd/lk1st 开机扫描到 system 分区的 bootfs.img 后，按设备数据库自动挑选
`msm8916-vivo-pd1419.dtb`；面板则由 lk1st 的 match-panel 探测并改写 dtb。

机型定制内容（`devices/vivo-y23l/`）：

- `kernel-patches/`：设备树（msm8916-vivo-cdp.dtsi + pd1419.dts + pd1304.dts）
  和两个面板驱动（修正了上游 patch 中 pd1419 compatible 的笔误；`&usb`
  的 extcon 同时接 `pm8916_usbin`（VBUS 检测）和 `usb_id`（ID GPIO），
  否则 ci_hdrc 拿不到 VBUS、USB device 模式不工作）
- `kernel.config`：`CONFIG_DRM_PANEL_VIVO_NT35510S=m`、
  `CONFIG_DRM_PANEL_VIVO_ORISE8012A=m`
- `post-assemble.sh`：写 fstab 行，把 bootfs（固定 UUID 的 ext2 启动分区）
  开机自动挂载到 `/boot`，方便在系统里直接改 extlinux.conf / 换内核

## 链接

- [lk2nd 设备数据库中的 pd1419](https://github.com/msm8916-mainline/lk2nd/blob/main/lk2nd/device/dts/msm8916/msm8916-vivo-cdp-1.dts)（含 lk1st 构建参数注释）
- [extlinux 启动路线](../extlinux.md)
- 机型配置：[`devices/vivo-y23l.env` + `devices/vivo-y23l/`](https://github.com/umeiko/umeko-Linux-phones/tree/main/devices)
