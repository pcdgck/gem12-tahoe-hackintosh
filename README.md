# GEM12 (Ryzen 7 8845HS / Radeon 780M) — macOS Tahoe 26 黑苹果

> **天钡 GEM12 迷你主机**上安装并跑通 macOS Tahoe 的完整记录：
> OpenCore 引导、nullarc 780M 显卡接管、GPU 桌面合成、Intel AX210 Wi-Fi/蓝牙，
> 以及踩过的每一个坑和对应的修复方法。

![platform](https://img.shields.io/badge/CPU-Ryzen%207%208845HS-ED1C24)
![gpu](https://img.shields.io/badge/GPU-Radeon%20780M-ED1C24)
![os](https://img.shields.io/badge/macOS-26.7.3-000000)
![oc](https://img.shields.io/badge/OpenCore-1.0.x-4B8BBE)

**[⬇️ 下载完整 EFI（29.7 MB zip）](https://github.com/pcdgck/gem12-tahoe-hackintosh/releases/download/efi-v1.0/EFI-GEM12-Tahoe.zip)**
· [仓库内 `efi/EFI/`](efi/EFI) · [EFI 结构说明](efi/EFI目录结构.md)

---

## 先说结论

**这台机器能跑 macOS Tahoe 桌面，但必须在「流畅」和「可用」之间二选一。**

- **流畅档**（GPU 接管）：Metal 3、拖动 57 fps —— 但 **Safari 等大批系统进程会被 SIGKILL**，
  每次关机还会留 `pmap` panic 记录
- **稳定档**（默认）：固件帧缓冲，界面卡顿 —— 但系统干净，应用正常

根因是依赖的 GPU 驱动 `nullarc` 还是 alpha 阶段，**会改写内存页**：
写脏的页落在 `dyld_shared_cache` 里，Tahoe 的代码签名校验就会杀掉相关进程。
详见 [docs/07-稳定性与崩溃分析.md](docs/07-稳定性与崩溃分析.md)。

| 子系统 | 状态 | 说明 |
|---|---|---|
| 引导 | ✅ | OpenCore，内置盘独立启动 |
| **GPU 硬件** | ✅ | Radeon 780M，8 GB VRAM，Metal 3，2160×1440 |
| **GPU 接管 / 桌面合成** | ⚠️ | 开启后流畅但**有严重副作用**，默认关闭<br>见 [docs/07](docs/07-稳定性与崩溃分析.md) |
| **系统稳定性** | ⚠️ | **16 次内核 panic** + **Safari 等进程批量 SIGKILL**<br>均发生在启用 GPU 接管期间 |
| **Wi-Fi** | ✅ | Intel AX210，`AirportItlwm` 2.4.0 —— **当前主用网络** |
| **蓝牙** | ⚠️ | 驱动/固件/扫描全部正常，但**射频信号极弱**（RSSI -90~-106），搜不到设备 —— 天线问题，见 [docs/04](docs/04-已知问题.md) 2.7 |
| USB | ✅ | XHC0，6 设备正常 |
| **板载有线网卡** | ❌ | Intel I226-V ×2，**四个驱动方案全部失败**<br>见 [docs/03](docs/03-踩坑记录.md) 3.1 与 [patches/AppleIGC](patches/AppleIGC-源码修改.md) |
| USB 网卡 | ✅ | AX88179B（`com.apple.driver.usb.cdc.ncm` 原生驱动），**推荐的有线方案** |
| 存储 | ✅ | NVMe + APFS |
| CPU 电源管理 | ✅ | X86PlatformPlugin |
| **音频** | ❌ | AMD ACP（`1022:15e3`）无 macOS 驱动 |
| **截屏 / 录屏** | ❌ | nullarc 读回路径未实现 |
| **AirDrop / Handoff** | ❌ | Intel 网卡无 AWDL |
| **USB-C 视频输出** | ❌ | USB4 router 无 macOS 驱动 |
| **硬件视频解码** | ❌ | 无 VCN 驱动，HEVC/H.264 全靠 CPU |
| 睡眠 / 唤醒 | ⚠️ | 未充分验证 |

> **性能提示**：如果空闲时 CPU 占用很高，先查 `VTDecoderXPCService` ——
> 系统动态壁纸在无硬件解码的机器上会持续软解 90%+ CPU。
> 见 [docs/04](docs/04-已知问题.md) 2.6，`scripts/vtdec-guard.sh` 是现成的看门狗。
>
> **档位提示**：`ioreg -rc IOFramebuffer -d1 | grep '^+-o'`，
> 显示 `PhxAMDFB` 是流畅档，显示 `.Display_boot` 是稳定档。

---

## 硬件

| 部件 | 规格 |
|---|---|
| 机器 | 天钡 GEM12 迷你主机 |
| CPU | AMD Ryzen 7 8845HS（8C/16T，Zen 4，Hawk Point） |
| 核显 | AMD Radeon 780M（PCI `1002:1900`，RDNA3，12 CU） |
| 内存 | 48 GB DDR5-5600 |
| 存储 | aigo NVMe SSD P7000Z 2TB（整盘安装 macOS） |
| 无线 | Intel AX210（`8086:2723`，Wi-Fi 6E + BT 5.3） |
| 有线 | 板载 **Intel I226-V ×2**（2.5G，`8086:125C`）—— **macOS 下无可用驱动**<br>推荐 **USB AX88179B**（`com.apple.driver.usb.cdc.ncm` 原生驱动）或 Wi-Fi |
| 显示 | **仅外接 HDMI**，2160×1440@60（固件 GOP 点亮的单一模式） |
| 系统 | macOS Tahoe **26.7.3**（build `25G342`） |
| SMBIOS | `MacBookPro16,1` |

**关键：GEM12 没有内建屏，只能外接 HDMI。这一点是后面所有麻烦的根源。**

---

## 核心难点：迷你主机的外接显示

nullarc 的 `PhxAMDFB`（帧缓冲驱动）原本**只支持内建 eDP 面板**。
上游 `KNOWN_ISSUES.md` 的原文：

> **Причина**: `PhxAMDFB` настроен только на встроенную eDP-панель.
> Дополнительные DCN-пайплайны и PHY не сконфигурированы.
> **Статус**: В работе.
>
> （原因：PhxAMDFB 只配置了内建 eDP 面板。额外的 DCN 流水线和 PHY 未配置。状态：进行中。）

GEM12 一个 eDP 都没有，所以直接使用官方 release 会得到：

```
WindowServer crash:
  CoreDisplay_CreateDisplayForCGXDisplayDevice
  UpdateCGXDisplayDevice
  AddCGXDisplayDeviceToDeviceList
  CGXDisplayDriverInitialize
  WS::Displays::CoreDisplayManager::initialize()
  → SIGABRT
```

**本文档记录的就是如何让这条路走通。**

---

## 修复路线（7 个关键点）

完整排查过程见 [docs/01-GPU接管.md](docs/01-GPU接管.md)，这里是速查表：

| # | 关键点 | 缺了会怎样 |
|---|---|---|
| 1 | **代码基线**：`nullarc @ 3497d87` + K8 的 `vbl-timing-dbuf.patch` | 用官方 release 直接 WindowServer 崩溃 |
| 2 | **PhxBringup ptfix**：`kHiTotal` 3840M / `kGttCap` 2048M / `kPtChunks` 256 | VRAM 池只有 512 MB |
| 3 | **BIOS** `UMA Frame Buffer Size = 8G` | 申请 2 GB 物理连续内存失败，降级到 512 MB |
| 4 | **PhxAccel VRAM 池对齐**：`{ 2048, 1024, 512 }` MB，`kVramCap 3840` | 与第 2 步的 `kHiTotal` 不匹配 |
| 5 | **主 head 提供 EDID** ★ | `CoreDisplay_CreateDisplayForCGXDisplayDevice` 断言 → SIGABRT |
| 6 | **PWM 不可用时仍创建 `PhxBacklight`** ★ | CoreDisplay 拿不到亮度控制对象 |
| 7 | **`PhxGPU` 目录 `chmod -R 755`** ★ | WindowServer（uid 88）加载不了 Metal 插件 → 显示器 offline |

> 第 5~7 项是本项目对 nullarc 的**源码修改**，
> 详见 [patches/PhxAccel-源码修改.md](patches/PhxAccel-源码修改.md)。

---

## 运行时配置

### boot-args

```
-v keepsyms=1 revpatch=cpuname,sbvmm ipc_control_port_options=0
-amfipassbeta amfi=0x80 amfi_get_out_of_my_way=0x1 phxdebug=1
```

### csr-active-config

```
7F080000  (SIP 关闭)
```

### nvrm610.conf（`/Library/GPUBundles/nvmtl/`）

```
NVMTL_WS_WAIT_COMPLETION=1
NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=1
NVMTL_PIPELINE_THREADS=1
```

### 开机自动设置（`/usr/local/bin/phxdisplay.sh` + LaunchDaemon）

```sh
sysctl -w debug.nvaccel_surface_gpu_on=0   # 消除残影
sysctl -w debug.phxfb_dbuf=1               # 双缓冲防撕裂
sysctl -w debug.phxfb_timing=1             # detailed timing
```

---

## 目录结构

```
.
├── README.md                        本页
├── docs/
│   ├── 01-GPU接管.md                780M 驱动接管的完整过程
│   ├── 02-WiFi蓝牙.md               Intel AX210 配置
│   ├── 03-踩坑记录.md               所有失败尝试与原因分析
│   ├── 04-已知问题.md               仍然存在的问题
│   ├── 05-恢复手册.md               出问题怎么救
│   ├── 06-EFI配置详解.md            config.plist 逐项说明
│   └── 07-稳定性与崩溃分析.md ★     12 个 panic 的分类、内存排除、nullarc 嫌疑
├── efi/
│   ├── EFI/                         ★ 完整可刷写的 EFI 分区内容（34 MB）
│   │   ├── BOOT/BOOTx64.efi
│   │   ├── OC/
│   │   │   ├── OpenCore.efi
│   │   │   ├── config.plist         三码已替换为占位符
│   │   │   ├── ACPI/                5 个 SSDT
│   │   │   ├── Drivers/             6 个 .efi
│   │   │   ├── Kexts/               14 个 kext（含自编译 AppleIGC，默认禁用）
│   │   │   └── Resources/           OpenCanopy 字体与图标
│   │   └── NullMoth/LogoutHook/     上游附带，本机不用（见说明）
│   └── EFI目录结构.md               结构详解、为什么禁用某些组件
├── patches/
│   ├── PhxAccel-源码修改.md         EDID + 背光 + VRAM 池
│   ├── PhxBringup-源码修改.md       ptfix
│   └── AppleIGC-源码修改.md         强制 legacy INTx 补丁 + 无 Xcode 编译方法
├── scripts/                         实际部署的工作脚本（见 scripts/README.md）
│   ├── README.md                    每个脚本干什么、失败保护怎么工作
│   ├── phxboot.sh                   开机 GPU bring-up + M2 状态机
│   ├── local.phxboot.plist          对应 LaunchDaemon
│   ├── phxdisplay.sh                开机 sysctl（残影/撕裂/timing）
│   ├── local.phxdisplay.plist       对应 LaunchDaemon
│   ├── nvrm610.conf                 Metal 插件配置
│   ├── bringup5.sh                  PSP + 全部引擎固件加载
│   ├── full.sh                      完整 bring-up 到 MES
│   ├── kinst.sh                     重建 Aux KC（带校验）
│   ├── vtdec-guard.sh               动态壁纸解码看门狗（防 90% CPU）
│   ├── local.vtdecguard.plist       对应 LaunchDaemon
│   └── memtest.c                    内存压力测试（排除内存故障用）
└── evidence/                        系统信息
```

**`efi/EFI/` 是完整可用的 EFI**，直接拷贝到 ESP 分区即可引导
（只需先填自己的 SMBIOS 三码）。

各第三方组件的版权与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) ——
其中 `AirportItlwm.kext` 和 `IntelBluetoothFirmware.kext` 是 **GPL-2.0**，
再分发请保留源码链接。

---

## 使用前必须做的事

### 1. 填 SMBIOS 三码 ★

`efi/EFI/OC/config.plist` 里的三码**已替换成占位符**（不能直接用于登录 iCloud）：

```
SystemSerialNumber = GENERATE-WITH-GenSMBIOS
MLB                = GENERATE-WITH-GenSMBIOS
SystemUUID         = GENERATE-WITH-GenSMBIOS
ROM                = 00:00:00:00:00:00
```

用 [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 生成与 `MacBookPro16,1` 匹配的三码，
`ROM` 填真实网卡 MAC（十六进制）。

**不填会怎样**：能开机、能进桌面、GPU/Wi-Fi 都正常，
但 App Store / iMessage / FaceTime 会报「无法验证设备」。

### 2. PhxAccel 需要自己编译

`efi/EFI/OC/Kexts/PhxBringup.kext` **本仓库已提供**（按 `patches/PhxBringup-源码修改.md` 编译好的）。

但 `PhxAccel.kext` **不在仓库里** —— 它装在 `/Library/Extensions/`，
属于 Auxiliary Kernel Collection，不是 EFI 组件。需要自行编译：

```sh
git clone https://github.com/acidanthera/MacKernelSDK ~/MacKernelSDK
git clone https://github.com/luuumi-dev/nullarc
cd nullarc && git checkout 3497d87
patch -p1 < k8-accel-vbl-timing-dbuf.patch    # 从 izerok/k8-tahoe-hackintosh 获取
# 按 patches/PhxAccel-源码修改.md 改三处（EDID / 背光 / VRAM 池）
cd src/phxaccel && ./build.sh ~/MacKernelSDK
# 装到 /Library/Extensions/ 后用 scripts/kinst.sh 重建 Aux KC
```

**没有 PhxAccel 也能开机**（GPU 退回固件 framebuffer），
只是没有 Metal、没有 GPU 合成、窗口拖动会很卡。

### 3. BIOS 设置

- UMA Frame Buffer Size = **8G**
- 开机前确认显示器输入源 = **HDMI**（无 EDID 会退回 4K framebuffer 导致黑屏）

### 4. 刷写 EFI

```sh
# 1. 先备份现有 EFI（强烈建议）
sudo diskutil mount disk0s1
sudo cp -R /Volumes/EFI/EFI ~/EFI.backup.$(date +%Y%m%d)

# 2. 把本仓库的 EFI 覆盖上去
sudo rm -rf /Volumes/EFI/EFI
sudo cp -R /path/to/gem12-tahoe-hackintosh/efi/EFI /Volumes/EFI/

# 3. 校验（这一步别省）
plutil -lint /Volumes/EFI/EFI/OC/config.plist
grep -A3 'OpenVariableRuntimeDxe' /Volumes/EFI/EFI/OC/config.plist | grep -q '<false/>' \
  && echo "危险驱动已禁用 OK"

# 4. 卸载并重启
sudo diskutil unmount /Volumes/EFI
sudo reboot
```

**刷完第一次开机的预期**：

| 现象 | 是否正常 |
|---|---|
| 出现 OpenCore 图形菜单 | ✅ |
| 开机能进桌面，但显示 2160×1440 无 HiDPI | ✅ |
| 有 Metal 3、GPU 合成（需先装 PhxAccel） | ✅ |
| iMessage 提示无法验证设备 | 正常，三码没填 |
| 桌面拖动很卡 | 正常，PhxAccel 没装 |
| **黑屏 / 卡在苹果 logo** | ❌ 见 [docs/05-恢复手册.md](docs/05-恢复手册.md) |

---

## 组件来源

| 组件 | 出处 | 版本 |
|---|---|---|
| OpenCore | [Acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) | 1.0.x |
| Lilu / VirtualSMC / NVMeFix | Acidanthera | 1.7.3 / 1.3.9 / 1.1.4 |
| AMFIPass | [kaoskinkae/AMFIPass](https://github.com/kaoskinkae/AMFIPass) | 1.4.1 |
| **PhxBringup / PhxAccel** | [luuumi-dev/nullarc](https://github.com/luuumi-dev/nullarc) @ `3497d87` | 自编译 |
| **vbl-timing/dbuf 补丁** | [izerok/k8-tahoe-hackintosh](https://github.com/izerok/k8-tahoe-hackintosh) | `k8-accel-vbl-timing-dbuf.patch` |
| PhxXhciKick | [kevin8717/TongFang-7840HS-Hackintosh](https://github.com/kevin8717/TongFang-7840HS-Hackintosh) | 1.0.0 |
| USBToolBox / UTBDefault | [USBToolBox](https://github.com/USBToolBox/kext) | 1.2.0 |
| **AirportItlwm** | [laobamac/itlwm](https://github.com/laobamac/itlwm) | 2.4.0（Tahoe） |
| **AppleIGC** | [SongXiaoXi/AppleIGC](https://github.com/SongXiaoXi/AppleIGC) @ `8802cba` | **1.9-gem12（自编译，默认禁用）**<br>强制 legacy INTx，见 [patches/AppleIGC](patches/AppleIGC-源码修改.md) |
| **IntelBluetoothFirmware** | [lshbluesky/IntelBluetoothFirmware](https://github.com/lshbluesky/IntelBluetoothFirmware) | **2.5.3**（2.5.2 起含 Tahoe BLE 修复） |
| **BlueToolFixup** | [Acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) | 2.7.2 |
| IntelBTPatcher | lshbluesky fork | **2.5.3** |

**特别感谢 [izerok/k8-tahoe-hackintosh](https://github.com/izerok/k8-tahoe-hackintosh)**
——同一代硬件（KTHIN K8，Ryzen 7 H 255 + 780M）的完整记录，
本文档的很多结论直接来自它。

---

## 免责声明

- 本项目仅供学习研究。修改 SMBIOS 可能违反 Apple 软件许可协议。
- 刷写 EFI 有变砖风险，请先备份原 EFI 并准备 U 盘救援。
- nullarc 是 alpha 阶段的内核驱动，可能导致内核 panic、数据损坏。
- 本仓库不含任何 Apple 版权文件。
- 各第三方组件版权归原作者，许可证以各自仓库为准。

---

## 许可

本仓库自有文字与配置以 MIT 发布。
