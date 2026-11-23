# EFI 分区结构

从 GEM12 实际 EFI 分区导出（2026-11-24），**完整内容在 `efi/EFI/` 目录下，可直接刷写**。
唯一被改动的是 `OC/config.plist` 里的 SMBIOS 三码（已替换为占位符）。

总体积 **33.9 MB**，共 110 个文件。

```
EFI/
├── BOOT/
│   └── BOOTx64.efi                     52 KB    ← OpenCore 引导入口
├── NullMoth/
│   └── LogoutHook/                     ← 上游 nullarc 附带，本机不用（见下）
│       ├── Launchd.command            23 KB    模拟 NVRAM 的保存钩子
│       ├── Launchd.command.plist
│       ├── README.md
│       └── nvramdump                  35 KB
└── OC/
    ├── OpenCore.efi                  872 KB
    ├── config.plist                   47 KB    ← 本仓库给的是脱敏版
    ├── ACPI/
    │   ├── SSDT-ALIBFix.aml            52 B    ✅ 启用
    │   ├── SSDT-EC.aml                125 B    ✅ 启用
    │   ├── SSDT-PLUG-ALT.aml        1,096 B    ✅ 启用（AMD 必需）
    │   ├── SSDT-USB-Reset.aml         435 B    ❌ 禁用
    │   └── SSDT-USBX.aml              166 B    ✅ 启用
    ├── Drivers/
    │   ├── apfs_aligned.efi         718 KB    ✅
    │   ├── HfsPlus.efi               37 KB    ✅
    │   ├── OpenCanopy.efi           151 KB    ✅
    │   ├── OpenRuntime.efi           36 KB    ✅
    │   ├── ResetNvramEntry.efi       57 KB    ✅
    │   └── OpenVariableRuntimeDxe.efi 69 KB   ❌ 永久禁用（见下）
    ├── Kexts/
    │   ├── AMFIPass.kext                         1.4.1
    │   ├── AirportItlwm.kext                     2.4.0
    │   ├── AppleIGC.kext                         1.8      ← I226-V 2.5G 网卡
    │   ├── AppleMCEReporterDisabler.kext          1.2
    │   ├── BlueToolFixup.kext                    2.7.2
    │   ├── IntelBTPatcher.kext                   2.5.3
    │   ├── IntelBluetoothFirmware.kext           2.5.3
    │   ├── Lilu.kext                             1.7.3
    │   ├── NVMeFix.kext                          1.1.4
    │   ├── PhxBringup.kext                       1.0.0（自编译）
    │   ├── PhxXhciKick.kext                      1.0.0
    │   ├── USBToolBox.kext                       1.2.0
    │   ├── UTBDefault.kext                       1.0
    │   └── VirtualSMC.kext                       1.3.9
    ├── Resources/                     ← OpenCanopy 图形菜单资源（字体 + 图标 + 标签）
    │   ├── Font/                      Font_1x/2x.bin/png, Terminus.hex
    │   ├── Image/Acidanthera/GoldenGate/   26 个 .icns
    │   └── Label/                     17 组 .lbl/.l2x
    └── [根目录还有 opencore-*.txt 启动日志，可删]
```

---

## 一、`NullMoth/LogoutHook` 是什么，为什么不装

这是 [acidanthera/NVMeFix](https://github.com/acidanthera) 生态里
**NVRAM 模拟**的标准工具（`org.acidanthera.nvramhook`），
作用是在关机/注销时把 NVRAM 内容存到 ESP 分区的 `nvram.plist`，
下次启动由 OpenCore 读回来 —— 用来在没有原生 NVRAM 的主板上"假装"有 NVRAM。

**本机不需要它**，因为这个平台有原生 NVRAM：

```sh
# 没有 nvram.plist / NVRAM 目录 = 没有模拟 NVRAM
ls /Volumes/EFI/nvram.plist          # 不存在
ls /Volumes/EFI/NVRAM/               # 不存在

# 但 NVRAM 里的值是真的
nvram -p | grep phxfb
#   phxfb-boot  1
#   IONVRAM-FORCESYNCNOW-PROPERTY  phxfb
```

**这也是 `OpenVariableRuntimeDxe.efi` 必须禁用的原因**：
既然原生 NVRAM 能用，就不需要模拟 NVRAM 驱动；
而它一旦加载，会在 `ExitBootServices` 之后留下 NX 代码页 → `Kernel trap 14` panic。
详见 [docs/03-踩坑记录.md](../docs/03-踩坑记录.md) 1.1。

> 那个 `EFI/NullMoth/` 目录是拷贝上游 EFI 时一起带进来的，**没有安装**：
> ```sh
> defaults read com.apple.loginwindow LogoutHook   # → 未设置
> ```
> 保留它无害（OpenCore 不会加载 `EFI/NullMoth/`），但可以删掉减少混淆。

---

## 二、`phxfb-boot` 与 NVRAM 落盘的坑

`phxboot.sh` 里有一行看着奇怪：

```sh
nv_commit() { nvram IONVRAM-FORCESYNCNOW-PROPERTY=phxfb >/dev/null 2>&1; }
```

**为什么需要它**：macOS 默认只在**正常关机**时把 NVRAM 改动刷进 SPI Flash。
如果断电/电池耗尽/强制重启，刚写的 `phxfb-boot` 就丢了。

本机踩过这个坑（2026-10-22）：当晚电池耗尽，第二天开机 `PhxAMDFB` 没被 arm，
WindowServer 落在固件 framebuffer 上，界面完全没法用。

`IONVRAM-FORCESYNCNOW-PROPERTY` 是 OpenCore 提供的私有变量，
写它等于命令 NVRAM 立刻落盘，不等关机。

---

## 三、SSDT 为什么是这几个

**AMD 平台的最小必要集**：

| SSDT | 必需性 |
|---|---|
| `SSDT-PLUG-ALT` | **硬性要求**，提供 AMD CPU 拓扑（`_PSS`/`_CST`） |
| `SSDT-EC` | 必需，假 EC 设备 |
| `SSDT-USBX` | 必需，USB 供电参数 |
| `SSDT-ALIBFix` | 本机需要，修内存映射 |
| `SSDT-USB-Reset` | **不需要**，启用反而可能掉 USB |

**绝对不能加的**（笔记本专用，加了会卡 `Initializing XNU platform expert`）：

```
SSDT-PNLF    内屏背光
SSDT-ALS0    环境光传感器
SSDT-XOSI    Windows 兼容层
```

---

## 四、Resources 目录能不能删

`OC/Resources/` 约 3.5 MB，全是 OpenCanopy 的字体和图标。

- 用图形菜单（`Misc.Boot.PickerMode = External`）→ **必需**
- 用文字菜单（改成 `Builtin`）→ 可删

本机用图形菜单，所以保留。

---

## 五、恢复 EFI 的最小步骤

```sh
# 1. 挂载 ESP
sudo diskutil mount disk0s1        # 盘号用 diskutil list 确认

# 2. 确认结构
ls /Volumes/EFI/EFI/BOOT/BOOTx64.efi
ls /Volumes/EFI/EFI/OC/OpenCore.efi
ls /Volumes/EFI/EFI/OC/config.plist

# 3. 校验 config.plist（最容易出错的一步）
plutil -lint /Volumes/EFI/EFI/OC/config.plist

# 4. 确认危险驱动禁用
grep -A2 'OpenVariableRuntimeDxe' /Volumes/EFI/EFI/OC/config.plist | grep -E 'Enabled' 
#   应该是 <false/>

# 5. 卸载
sudo diskutil unmount /Volumes/EFI
```

**完整恢复流程见 [docs/05-恢复手册.md](../docs/05-恢复手册.md)。**
