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

**这台机器现在可以正常跑 macOS 桌面，GPU 合成、Metal 3、Wi-Fi、蓝牙都能用。**

但必须说清楚：这是**实验性**配置，依赖一个 alpha 阶段的 GPU 驱动（nullarc），
并且在迷你主机（无内建屏、纯外接 HDMI）这个上游**明确标注未支持**的场景下，
需要三处源码修改才能工作。

| 子系统 | 状态 | 说明 |
|---|---|---|
| 引导 | ✅ | OpenCore，内置盘独立启动 |
| **GPU / 显示** | ✅ | Radeon 780M，**8 GB VRAM，Metal 3**，2160×1440 |
| **桌面合成** | ✅ | WindowServer 在 GPU 上，空闲 CPU 0.2% |
| 帧同步 | ✅ | vbl-timing，60 Hz |
| 残影 | ✅ | dbuf 双缓冲 |
| **Wi-Fi** | ✅ | Intel AX210，`AirportItlwm` 2.4.0 |
| **蓝牙** | ⚠️ | Intel AX210，驱动/固件/扫描全部正常，但**射频信号极弱**（RSSI -90~-106），搜不到设备 —— 见 [docs/04](docs/04-已知问题.md) 2.7 |
| USB | ✅ | XHC0，6 设备正常 |
| **有线网卡** | ✅ | **板载 Intel I226-V ×2，2.5G**（`AppleIGC` v1.8，见 [docs/03](docs/03-踩坑记录.md) 3.1） |
| USB 网卡 | ✅ | AX88179B，装机时用（Recovery 里需要它，见 [docs/03](docs/03-踩坑记录.md) 3.2） |
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
> 见 [docs/04-已知问题.md](docs/04-已知问题.md) 2.6，`scripts/vtdec-guard.sh` 是现成的看门狗。

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
| 有线 | 板载 **Intel I226-V ×2**（2.5G，`8086:125C`）<br>驱动用 `AppleIGC` v1.8（原生 dext 在本机协商不出链路，见 [docs/03](docs/03-踩坑记录.md) 3.1）<br>+ USB AX88179B（装机时用） |
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

按依赖顺序，每一环都不可或缺：

### 1. 用对代码基线

```
luuumi-dev/nullarc @ 3497d87  +  izerok 的 k8-accel-vbl-timing-dbuf.patch
```

**不要**用官方 `v0.4.0-alpha` release，也**不要**用 `hdmi-fb2` 分支：

- 官方 release（`phx-build 34`）不含 vbl-timing / dbuf / `PhxHDMIHead`
- `hdmi-fb2` 分支走的是另一套（head 1 + `phxfb1_config`）方案，未验证
- K8 补丁必须打在 `3497d87` 上才能干净应用（其它版本冲突严重）

详见 [docs/01-GPU接管.md](docs/01-GPU接管.md)。

### 2. PhxBringup 页表与显存池扩容（ptfix）

```cpp
kHiTotal  : 1536 MiB → 3840 MiB
kGttCap   :  512 MiB → 2048 MiB
kGttMaxBo :  256 MiB → 1024 MiB
kPtChunks :   64     →  256        // 每进程 GPU 页表 ≈8 GiB
```

见 [patches/PhxBringup-源码修改.md](patches/PhxBringup-源码修改.md)。

### 3. BIOS 调大 UMA Frame Buffer 到 8 GB

`Advanced → AMD CBS → NBIO Common Options → GFX Configuration → UMA Frame Buffer Size = 8G`

**没有这一步，`PhxAccel` 申请 2 GB 物理连续内存会失败，降级到 512 MB。**

### 4. PhxAccel VRAM 池对齐

```cpp
kPoolTry : { 512, 256, 128 } MB → { 2048, 1024, 512 } MB
kVramCap : 1024 MB → 3840 MB
```

**必须和第 2 步的 `kHiTotal` 匹配，否则两边不一致。**

### 5. 主 head 提供 EDID ★

`CoreDisplay` 创建显示设备时必须能读到 EDID。原代码主 head：

```cpp
bool hasDDCConnect(IOIndex) override { return false; }
IOReturn getDDCBlock(...) override { return kIOReturnUnsupported; }
```

改为返回一份 128 字节的 1920×1080@60 EDID。

### 6. PWM 不可用时仍创建背光处理器 ★

`CoreDisplay::Display` 构造时会调用 `InitializeBrightnessControl`。
外接显示器没有 PWM 背光，原代码直接跳过创建 `PhxBacklight`，
导致 CoreDisplay 拿不到亮度控制对象。

改为：即使 PWM 读不到，也创建 handler（亮度固定 `kBlMax`）。

### 7. PhxGPU 目录权限 755 ★

**这是最后一块拼图，也是最容易被忽略的。**

nullarc 的安装脚本把 `PhxGPU/` 下的文件设成了 `700`/`600`（仅 root 可读）。
但 WindowServer 以 userID 88 运行，无法加载 Metal 插件：

```
WindowServer: [ERROR] Cannot find executable for CFBundle
  .../PhxGPU/NVMTLDriver.bundle (not loaded)
WindowServer: [ERROR] Setting offline display 0x00000000 main
```

修正：

```sh
sudo chmod -R 755 /System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU
```

**改完这一条，显示器从 offline 变 online，GPU 合成立刻工作。**

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
│   └── 06-EFI配置详解.md            config.plist 逐项说明
├── efi/
│   ├── EFI/                         ★ 完整可刷写的 EFI 分区内容（33 MB）
│   │   ├── BOOT/BOOTx64.efi
│   │   ├── OC/
│   │   │   ├── OpenCore.efi
│   │   │   ├── config.plist         三码已替换为占位符
│   │   │   ├── ACPI/                5 个 SSDT
│   │   │   ├── Drivers/             6 个 .efi
│   │   │   ├── Kexts/               13 个 kext
│   │   │   └── Resources/           OpenCanopy 字体与图标
│   │   └── NullMoth/LogoutHook/     上游附带，本机不用（见说明）
│   └── EFI目录结构.md               结构详解、为什么禁用某些组件
├── patches/
│   ├── PhxAccel-源码修改.md         EDID + 背光 + VRAM 池
│   └── PhxBringup-源码修改.md       ptfix
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
│   └── local.vtdecguard.plist       对应 LaunchDaemon
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
| **AppleIGC** | [SongXiaoXi/AppleIGC](https://github.com/SongXiaoXi/AppleIGC) | **v1.8**（v1.9 有 MSI bug，见 [docs/03](docs/03-踩坑记录.md) 3.1） |
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
