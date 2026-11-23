# 第三方组件与许可

本仓库**不包含**任何第三方二进制文件（kext / EFI 驱动 / 固件）。
以下列出本项目依赖的组件及其出处，使用者需自行获取并遵守各自许可。

## GPU 驱动

| 组件 | 出处 | 许可 |
|---|---|---|
| nullarc（PhxBringup / PhxAccel） | https://github.com/luuumi-dev/nullarc | 见仓库 LICENSE；部分派生自 NullMoth 驱动，为 PolyForm Noncommercial 1.0.0 |
| k8-accel-vbl-timing-dbuf.patch | https://github.com/izerok/k8-tahoe-hackintosh | MIT（该仓库自有部分） |
| Mesa RADV | https://gitlab.freedesktop.org/mesa/mesa | MIT |
| Vulkan Loader | Khronos Group | Apache-2.0 |

**注意**：nullarc 的部分代码派生自 NullMoth 的 NVIDIA 驱动，
采用 **PolyForm Noncommercial 1.0.0**，**禁止商业使用**。

## 引导与基础 kext

| 组件 | 出处 | 许可 |
|---|---|---|
| OpenCorePkg | https://github.com/acidanthera/OpenCorePkg | BSD-3-Clause |
| Lilu | https://github.com/acidanthera/Lilu | BSD-3-Clause |
| VirtualSMC | https://github.com/acidanthera/VirtualSMC | BSD-3-Clause |
| NVMeFix | https://github.com/acidanthera/NVMeFix | BSD-3-Clause |
| AMFIPass | https://github.com/kaoskinkae/AMFIPass | BSD-3-Clause |
| USBToolBox | https://github.com/USBToolBox/kext | BSD-3-Clause |
| PhxXhciKick | https://github.com/kevin8717/TongFang-7840HS-Hackintosh | 见该仓库 |
| BrcmPatchRAM（BlueToolFixup） | https://github.com/acidanthera/BrcmPatchRAM | BSD-3-Clause |

## 无线

| 组件 | 出处 | 许可 |
|---|---|---|
| AirportItlwm | https://github.com/laobamac/itlwm | GPL-2.0 |
| itlwm（上游） | https://github.com/OpenIntelWireless/itlwm | GPL-2.0 |
| IntelBluetoothFirmware | https://github.com/lshbluesky/IntelBluetoothFirmware | GPL-2.0 |
| IntelBTPatcher | 同上 | GPL-2.0 |

**Intel 蓝牙固件**来自 Linux 开源项目，遵循其原始许可。

## 参考项目

| 项目 | 说明 |
|---|---|
| https://github.com/izerok/k8-tahoe-hackintosh | KTHIN K8（Ryzen 7 H 255 + 780M）完整记录，本项目大量结论来源于此 |
| https://github.com/kevin8717/TongFang-7840HS-Hackintosh | 同方 7840HS EFI，提供了 PhxXhciKick |

## Apple 文件

本仓库不包含任何 Apple 版权文件。
`efi/OC/config.plist.example` 中的 SMBIOS 三码已清空（`GENERATE-WITH-GenSMBIOS`），
使用者需自行生成。

---

各组件版权归各自作者所有。使用前请阅读对应仓库的 LICENSE。