# 刷机与日常使用

## 刷机

!!! warning "会清空手机数据"
    rootfs 刷入的是 userdata 分区，**手机里的数据会被全部清除**。刷机前请备份。

1. 解压刷机包 zip，电脑上装好 fastboot（Windows 可用 [platform-tools](https://developer.android.com/tools/releases/platform-tools)）
2. 手机关机，按住 **音量下 + 电源** 进原厂 fastboot（米兔修车画面）
3. 运行包内脚本：Linux/macOS 用 `bash flash.sh`，Windows 双击 `flash.bat`
4. 脚本分两个阶段，中间需要人工配合一次：
   - **阶段一**（原厂 fastboot）：刷入 `lk2nd-msm8916.img`，然后手机重启——**重启时按住音量下**，进入 lk2nd 自己的 fastboot 界面（屏幕上会有 lk2nd 字样和菜单），按回车继续
   - **阶段二**（lk2nd fastboot）：刷入 `bootfs.img`（ext2 启动分区，进 system 分区）和 `rootfs.img`（系统，sparse 格式，刷入 userdata，耐心等）
5. 刷完自动重启进 Ubuntu。首次启动较慢（要生成 SSH host key 等），等一两分钟

!!! note "vivo Y23L 不一样"
    Y23L 需要先刷 lk1st 底包，且 bootfs 刷 boot 分区而非 system。完整流程见
    [vivo Y23L 机型页](devices/vivo-y23l.md)。

!!! note "legacy mkbootimg 包"
    旧版单机型包（`boot.img` + `rootfs.img`，mkbootimg 打包）已不再由 CI 构建，
    刷法类似：阶段二刷 `boot.img`（boot 分区）和 `rootfs.img`（userdata）。

## 首次登录

- 用户名 `umeko`，密码 `1234`
- **最快的方式**：USB 线把手机插上电脑，设备管理器/设备列表里会多出一个串口（ttyGS0 / COMx），用任意串口工具（115200 8N1）或直接 `screen`/`PuTTY` 打开——**免密直接进入 shell**（autottyGS0 服务）。同时还会多出一张 USB 网卡（NCM）：手机侧是 `192.168.100.1`，电脑侧拿到同网段地址后可以直接 `ssh umeko@192.168.100.1`
- 屏幕上也直接有登录提示；有 TTL 线的话 UART 是 ttyMSM0

## 配网

系统里装的是 NetworkManager，配 WiFi 用文本界面：

```bash
nmtui
```

选 *Edit a connection* → *Add* → *Wi-Fi*，填 SSID 和密码，保存后 *Activate a connection* 启用。连上后：

```bash
ip addr show wlan0        # 看 IP
ssh umeko@<手机IP>        # 之后就可以 SSH 了
```

浏览器访问 `http://<手机IP>:8888` 可以用 webssh（网页里的 SSH 终端）。

!!! note "WiFi 起不来？"
    检查固件提取服务：`systemctl status umeko-modem-firmware`，以及
    `ls /lib/firmware/wcnss.mdt` 是否存在。该服务把固件从手机 modem 分区提取到
    `/lib/firmware`，正常刷机流程下首次开机会自动完成。

## 内置服务一览

| 服务 | 默认 | 作用 |
| --- | --- | --- |
| `umeko-modem-firmware` | 启用 | 从 modem 分区提取 WiFi/基带固件到 /lib/firmware（一次性） |
| `autottyGS0` | 启用 | USB 串口免密控制台 |
| `autoresize` | 启用 | 开机自动把根文件系统扩满 userdata 分区（oneshot） |
| `auto_rmi4_reload` | 启用 | 触摸屏驱动重载 workaround |
| `autowebssh` | 启用 | webssh，端口 8888 |
| `autocanup` | 启用 | 检测并拉起 USB CAN 适配器（can0，500k，队列 1024） |
| `serial-getty@ttyMSM0` | 启用 | UART 登录控制台 |
| `ssh` | 启用 | OpenSSH server |

看日志用 `journalctl -u <服务名>`，停用用 `sudo systemctl disable <服务名>`。

## 常见问题

**rootfs 会不会占满？** 镜像本身 2GB，刷入后 `autoresize` 服务会自动扩满整个 userdata（红米2 一般是 8G/16G）。手动确认：`df -h /`。

**屏幕显示方向不对？** 内核 cmdline 里可以加 `video=DSI-1:panel_orientation=...` 之类的参数，改 `devices/wt88047.env` 的 `KERNEL_CMDLINE` 重新构建即可。

**想装 Klipper？** 二期计划会把 klipper/moonraker/fluidd 做进构建。当前先手动：参考 [KlipperPhonesLinux 文档](https://github.com/umeiko/KlipperPhonesLinux)，系统里已经有 CAN 支持和串口。

**刷回 Android？** 用小米官方线刷包（miflash）刷回原厂分区即可，lk2nd 会被覆盖掉。

## 救砖

lk2nd 不动原厂 bootloader，所以最差情况也能进原厂 fastboot（音量下 + 电源）重刷。万一 lk2nd 刷坏：原厂 fastboot 里 `fastboot flash boot <原厂boot.img>` 即可恢复。
