# 第三方组件与许可

本仓库**包含**完整的 `efi/EFI/` 目录，其中含有第三方编译产物
（kext 二进制、EFI 驱动、AML 文件）。这些组件的版权归各自作者所有，
以各自的许可证分发。**使用前请阅读对应仓库的 LICENSE。**

`efi/EFI/OC/config.plist` 中的 SMBIOS 三码（序列号 / MLB / UUID / ROM）
已替换为占位符，**需自行生成**，详见 README「使用前必须做的事」。

---

## 一、本仓库实际分发的二进制

以下文件**直接存在于** `efi/EFI/` 中：

| 文件 | 大小 | 来源 | 许可 |
|---|---|---|---|
| `BOOT/BOOTx64.efi` | 52 KB | OpenCorePkg | BSD-3-Clause |
| `OC/OpenCore.efi` | 872 KB | OpenCorePkg | BSD-3-Clause |
| `OC/Drivers/OpenRuntime.efi` | 36 KB | OpenCorePkg | BSD-3-Clause |
| `OC/Drivers/OpenCanopy.efi` | 151 KB | OpenCorePkg | BSD-3-Clause |
| `OC/Drivers/ResetNvramEntry.efi` | 57 KB | OpenCorePkg | BSD-3-Clause |
| `OC/Drivers/HfsPlus.efi` | 37 KB | Apple 开源 HFS+ 驱动 | APSL-2.0 |
| `OC/Drivers/apfs_aligned.efi` | 718 KB | Acidanthera 社区分支 | 见上游 |
| `OC/Drivers/OpenVariableRuntimeDxe.efi` | 69 KB | OpenCorePkg | BSD-3-Clause |
| `OC/Kexts/Lilu.kext` | 543 KB | acidanthera/Lilu | BSD-3-Clause |
| `OC/Kexts/VirtualSMC.kext` | 245 KB | acidanthera/VirtualSMC | BSD-3-Clause |
| `OC/Kexts/NVMeFix.kext` | 51 KB | acidanthera/NVMeFix | BSD-3-Clause |
| `OC/Kexts/AMFIPass.kext` | 832 KB | kaoskinkae/AMFIPass | BSD-3-Clause |
| `OC/Kexts/USBToolBox.kext` | 39 KB | USBToolBox/kext | BSD-3-Clause |
| `OC/Kexts/UTBDefault.kext` | 8 KB | USBToolBox | BSD-3-Clause |
| `OC/Kexts/AppleMCEReporterDisabler.kext` | 2 KB | 社区 | 见上游 |
| `OC/Kexts/PhxXhciKick.kext` | 48 KB | kevin8717/TongFang-7840HS-Hackintosh | 见上游 |
| `OC/Kexts/BlueToolFixup.kext` | 41 KB | acidanthera/BrcmPatchRAM | BSD-3-Clause |
| `OC/Kexts/IntelBluetoothFirmware.kext` | **11.2 MB** | lshbluesky/IntelBluetoothFirmware | GPL-2.0 |
| `OC/Kexts/IntelBTPatcher.kext` | 40 KB | 同上 | GPL-2.0 |
| `OC/Kexts/AirportItlwm.kext` | **15.2 MB** | laobamac/itlwm | GPL-2.0 |
| `OC/Kexts/AppleIGC.kext` | 94 KB | SongXiaoXi/AppleIGC @ `8802cba` | GPL-2.0 |
| `OC/Kexts/PhxBringup.kext` | 78 KB | **本项目自编译** | 见下方 nullarc 段落 |
| `OC/ACPI/*.aml` (5 个) | 共 1.8 KB | 本项目编写 / 社区 SSDT | MIT（本项目部分） |

> **`PhxBringup.kext` 是从 [luuumi-dev/nullarc](https://github.com/luuumi-dev/nullarc) @ `3497d87`
> 加上 `patches/PhxBringup-源码修改.md` 的改动自行编译的。**
> 源码修改说明在本仓库，二进制随之分发，但**原始代码的许可仍归上游**。

### ⚠️ 三个体积较大 / 重要的 GPL 组件

`AirportItlwm.kext`（15.2 MB）、`IntelBluetoothFirmware.kext`（11.2 MB）
和 `AppleIGC.kext`（94 KB）均以 **GPL-2.0** 分发。
GPL-2.0 要求分发二进制时提供对应源码。源码地址：

- https://github.com/laobamac/itlwm（Tahoe 分支）
- https://github.com/lshbluesky/IntelBluetoothFirmware
- https://github.com/SongXiaoXi/AppleIGC
  （本仓库附带的是**自行编译**的 `1.9-gem12`，打了强制 legacy INTx 的补丁，
  见 [patches/AppleIGC-源码修改.md](patches/AppleIGC-源码修改.md)）

**如果你要再分发本仓库，请保留这些来源链接，或改为让使用者自行下载这些 kext。**

### 固件文件

`IntelBluetoothFirmware.kext` 内含从 Linux 开源项目提取的 Intel 蓝牙固件
（`ibt-*.sfi` 等），遵循其原始许可（Intel 的 redistributable 条款 +
Linux firmware 的 `LICENCE.fw`）。

---

## 二、不在仓库中、但本方案依赖的组件

| 组件 | 出处 | 许可 | 为什么不在仓库 |
|---|---|---|---|
| **nullarc**（PhxAccel） | https://github.com/luuumi-dev/nullarc | 部分派生自 NullMoth，**PolyForm Noncommercial 1.0.0，禁止商业使用** | 装在 `/Library/Extensions/`，属 Aux KC，非 EFI 组件 |
| Mesa RADV | https://gitlab.freedesktop.org/mesa/mesa | MIT | 在 `/Library/GPUBundles/nvmtl/`，约 21 MB |
| Vulkan Loader | Khronos Group | Apache-2.0 | 同上 |
| `k8-accel-vbl-timing-dbuf.patch` | https://github.com/izerok/k8-tahoe-hackintosh | MIT（该仓库自有部分） | 是补丁文件，需自行获取 |
| AMD_Vanilla 内核补丁 | https://github.com/AMD-OSX/AMD_Vanilla | MIT | 已作为配置项写在 config.plist 里，非独立文件 |

**`PhxAccel.kext` 不在本仓库**，因为它不属于 EFI：
它安装到 `/Library/Extensions/` 并打包进 Auxiliary Kernel Collection。
请从 upstream 获取源码、应用 `patches/PhxAccel-源码修改.md` 的三处改动后自行编译。

---

## 三、许可兼容性提示

- **BSD-3-Clause / MIT / APSL-2.0**：可自由再分发，保留版权声明即可。
- **GPL-2.0**（AirportItlwm / IntelBluetoothFirmware）：
  再分发需附源码或书面 offer。本仓库按「提供源码链接」方式处理。
- **PolyForm Noncommercial 1.0.0**（nullarc 部分）：
  **禁止任何商业用途**。本仓库不含其二进制，但 `patches/` 里的修改说明
  与该代码衍生相关，请勿用于商业产品。

---

## 四、Apple 文件

本仓库**不包含**任何 Apple 版权文件（无 macOS 安装镜像、无系统 kext、
无 Apple 私有框架副本）。

`efi/EFI/OC/Drivers/HfsPlus.efi` 源自 Apple 开源的 HFS+ 驱动，
按 APSL-2.0 分发。

---

## 五、参考项目

| 项目 | 说明 |
|---|---|
| https://github.com/izerok/k8-tahoe-hackintosh | KTHIN K8（Ryzen 7 H 255 + 780M）完整记录，本项目大量结论来源于此 |
| https://github.com/kevin8717/TongFang-7840HS-Hackintosh | 同方 7840HS EFI，提供了 PhxXhciKick |
| https://github.com/luuumi-dev/nullarc | Rx 7000/8000 系列（RDNA3）macOS 驱动 |

---

各组件版权归各自作者所有。本仓库自有文字、脚本与配置以 MIT 发布。
