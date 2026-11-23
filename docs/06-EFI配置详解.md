# 06 — EFI 配置详解

`efi/EFI/OC/config.plist` 里每一项为什么这么填。
**按"缺了它会怎样"来组织**，方便排查。

> 所有内容都可用 `plutil -lint config.plist` 校验，
> 或用 `python3 -c "import plistlib;plistlib.load(open('config.plist','rb'))"` 确认能解析。
> 后者能抓到 `plutil` 放过的语义错误。

---

## 一、ACPI（5 个 SSDT）

| 文件 | 启用 | 作用 | 缺了会怎样 |
|---|---|---|---|
| `SSDT-PLUG-ALT.aml` | ✅ | **AMD CPU 拓扑** | 卡在 `CoreAnalyticsHub start completed`，永远起不来 |
| `SSDT-EC.aml` | ✅ | 假 EC 设备 | `AppleACPIEC` 找不到设备，电池/温度相关报错刷屏 |
| `SSDT-USBX.aml` | ✅ | USB 供电参数 | USB 设备供电异常，大功率外设掉线 |
| `SSDT-ALIBFix.aml` | ✅ | ALIB 地址修正 | 内存映射有洞 |
| `SSDT-USB-Reset.aml` | ❌ | USB 复位 | **本机不需要**，启用反而可能掉 USB |

`SSDT-PLUG-ALT` 是 **AMD 平台的硬性要求**，不是可选优化。
它的内容和 Intel 的 `SSDT-PLUG` 完全不同 —— 不生成 `plugin-type`，
而是给每个 CPU 核心补齐 `_PSS`/`_CST` 等 ACPI 对象。

**本机明确不需要的（曾经踩过）**：

```
SSDT-PNLF.aml          内屏背光      ← 迷你主机没有内屏
SSDT-ALS0.aml          环境光传感器
SSDT-XOSI.aml          Windows 兼容层
```

混进去会卡在 `Initializing XNU platform expert`（见 [03-踩坑记录.md](03-踩坑记录.md) 1.3）。

---

## 二、Kexts（14 个）

按加载顺序（`Lilu` 必须最先，依赖它的排后面）：

| # | Kext | 版本 | MinKernel | 作用 |
|---|---|---|---|---|
| 1 | `AppleMCEReporterDisabler` | 1.2 | — | 关掉 MCE 上报，AMD 平台必需 |
| 2 | `Lilu` | 1.7.3 | — | 补丁框架，其它 kext 的前置 |
| 3 | `BlueToolFixup` | 2.7.2 | 21.0.0 | **蓝牙协议栈修复**（patch `BlueTool` / `bluetoothd`） |
| 4 | `IntelBluetoothFirmware` | **2.5.3** | — | AX210 蓝牙固件上传 |
| 5 | `IntelBTPatcher` | **2.5.3** | 21.0.0 | 蓝牙补丁（patch `IOBluetoothFamily`） |
| 6 | `AirportItlwm` | 2.4.0 | — | **Wi-Fi**（Tahoe 专用版本） |
| 7 | `AMFIPass` | 1.4.1 | 20.0.0 | 绕过 AMFI，让未签名 kext 加载 |
| 8 | `PhxBringup` | 1.0.0 | 25.0.0 | **GPU 底层 bring-up**（PSP/MES/GPUVM） |
| 9 | `PhxXhciKick` | 1.0.0 | — | XHCI 控制器唤醒 |
| 10 | `NVMeFix` | 1.1.4 | 18.0.0 | NVMe 电源管理 |
| 11 | `VirtualSMC` | 1.3.9 | — | SMC 模拟 |
| 12 | `USBToolBox` | 1.2.0 | — | USB 端口映射框架 |
| 13 | `UTBDefault` | 1.0 | — | 端口映射数据 |
| 14 | **`AppleIGC`** | **1.8** | 21.0.0 | **板载 I226-V 2.5G 网卡**（原生 dext 协商不出链路，见 [03](03-踩坑记录.md) 3.1） |

**`MinKernel` 的意义**：`21.0.0` = macOS 12，`25.0.0` = macOS 26。
填错会让 kext 在某些系统上完全不加载，而且**日志里不会有任何提示**。

### 两个容易踩的版本坑

**`AppleIGC` 必须用 v1.8，不能用 v1.9。**
v1.9 的 PR #38 让驱动去监听 MSI 中断源，但 `pci_enable_msi_block()`
被 `#if 0` 禁掉了、MSI 从未真正启用 → 中断永不触发 → **RX 完全死掉**
（link 显示 active，`Ipkts` 恒为 0）。详见 [03](03-踩坑记录.md) 3.1。

**`IntelBluetoothFirmware` 必须 ≥ 2.5.2。**
2.5.2 加入 `LE Data Length Change` 注入，清掉 bluetoothd 的
`LE_READY_WAIT_FOR_LENGTH` stall —— 没有它，Tahoe 上 **BLE 设备无法被发现**。

> `AppleIGC` 的 `IOProbeScore = 4000` > 原生 `AppleEthernetE1000` 的 `3000`，
> 所以会自动抢占，**不需要 `e1000=0`**。

> `PhxAccel` **不在这里**。它装在 `/Library/Extensions/`，属于
> **Auxiliary Kernel Collection**，不进 EFI。见 [scripts/README.md](../scripts/README.md) 的 `kinst.sh`。

**曾经放进 EFI 又移除的**：

- `RestrictEvents.kext` — 调用 Lilu `GetVariable` 崩溃
- `SMCBatteryManager` / `SMCLightSensor` / `BrightnessKeys` — 笔记本专用
- `IntelBluetoothInjector.kext` — 有 `USBToolBox` 时不需要，且会和 `BlueToolFixup` 冲突

---

## 三、UEFI Drivers（6 个）

| 文件 | 启用 | 说明 |
|---|---|---|
| `apfs_aligned.efi` | ✅ | **APFS 驱动**（对齐版，兼容性更好） |
| `HfsPlus.efi` | ✅ | HFS+ 读取，用于 U 盘救援 |
| `OpenRuntime.efi` | ✅ | **必需**，OpenCore 的运行时服务 |
| `OpenCanopy.efi` | ✅ | 图形化引导菜单 |
| `ResetNvramEntry.efi` | ✅ | 菜单里的「重置 NVRAM」项 |
| `OpenVariableRuntimeDxe.efi` | ❌ **永久禁用** | **见下** |

### ⚠️ `OpenVariableRuntimeDxe.efi` 必须禁用

这是**本机最危险的驱动**。它模拟 NVRAM，提供的假 `GetVariable`
在 `ExitBootServices` 之后代码页变成 NX（不可执行）：

```
Kernel trap type=14 (page fault)
CR2 == RIP          ← 取指故障
```

连续 4 次 panic 的真凶就是它。**AMD 平台上这是最常见的 panic 原因之一。**

---

## 四、内核补丁（27 个）

`Kernel → Patch` 全部来自 **AMD_Vanilla** 项目，本机只调整了 `MinKernel`/`MaxKernel`
以覆盖 Tahoe（25.x）。

| 类别 | 数量 | 代表补丁 |
|---|---|---|
| CPUID 伪装 | 12 | `_cpuid_set_info`、`_cpuid_set_generic_info`、`_cpuid_set_cache_info` |
| CPU 拓扑 | 4 | `Force cpuid_cores_per_package to constant` |
| 绕过 Intel 检查 | 2 | `Bypass GenuineIntel check panic`、`GenuineIntel to AuthenticAMD` |
| 时间戳 panic | 3 | `Remove non-monotonic time panic`（**Tahoe 必须**） |
| PAT / MTRR | 4 | `_mtrr_update_action | Fix PAT` |
| 其它 | 2 | `_i386_init` 去 rdmsr、`_commpage_populate` |
| **IOPCIFamily** | 2 | `probeBusGated | Disable 10 bit tags` |

### 关键：`Remove non-monotonic time panic`

Tahoe 上这个补丁**必须按版本分段**，否则要么不生效要么打错位置：

| 范围 | 补丁作者 |
|---|---|
| 12.0–26.3 (`21.0.0`–`25.3.99`) | Visual |
| **26.4+ (`25.4.0`–`25.99.99`)** | **laobamac** |

本机跑 26.7.3，**两条都启用**（`21..25.3.99` 和 `25.4.0..25.99.99`），
因为内核版本号和实际系统版本有偏移，宁多勿少。

### `Disable 10 bit tags`

`com.apple.iokit.IOPCIFamily` 的补丁，同样分段：
`21.0.0`–`24.99.99` 和 `25.0.0`–`25.99.99`。
不打这个补丁，PCI 设备枚举会出错。

### 被禁用的 3 个

| # | 补丁 | 原因 |
|---|---|---|
| 19 | `IOPCIIsHotplugPort | Fix PCI bus enumeration on AM5` | 本机不是 AM5 桌面平台 |
| 23 | `algrey | _mtrr_update_action | fix PAT` | 与 24 重复，用 Shaneee 版本 |
| 25 | `Algrey/Zormeister | Fix PAT` | 与 26 重复，用 Shaneee/Zormeister 版本 |

> PAT 补丁**同一范围只能启用一个**。启用两个会导致 `_mtrr_update_action` 被改两次，
> 内存类型错误 → 随机崩溃。

---

## 五、Kernel Quirks

| Quirk | 值 | 为什么 |
|---|---|---|
| `DisableIoMapper` | ✅ | **AMD 平台必需**，否则 IOMMU 相关 panic |
| `DisableIoMapperMapping` | ✅ | 同上 |
| `ProvideCurrentCpuInfo` | ✅ | 提供 CPU 信息，AMD 必需 |
| `CustomSMBIOSGuid` | ✅ | 配合 `PlatformInfo` 覆盖 SMBIOS |
| `DisableLinkeditJettison` | ✅ | Lilu 要求 |
| `LapicKernelPanic` | ✅ | LAPIC 中断不 panic |
| `PanicNoKextDump` | ✅ | panic 时不 dump kext，减少输出 |
| `SetApfsTrimTimeout` | `-1` | 关闭 APFS TRIM 超时（部分 NVMe 需要） |
| `AppleCpuPmCfgLock` | ❌ | AMD 没有这个 MSR |
| `AppleXcpmCfgLock` | ❌ | 同上 |
| `IncreasePciBarSize` | ❌ | 开 4G Decoding 后不需要 |

---

## 六、Booter Quirks

只列**启用的**：

| Quirk | 值 | 作用 |
|---|---|---|
| `AvoidRuntimeDefrag` | ✅ | 必需，避免运行时服务内存碎片 |
| `DevirtualiseMmio` | ✅ | **AMD 必需**，把 MMIO 区域从内存映射里摘出去 |
| `EnableSafeModeSlide` | ✅ | 安全模式也能 slide |
| `FixupAppleEfiImages` | ✅ | OpenCore 1.0+ 新项，修 EFI 镜像 |
| `ProvideCustomSlide` | ✅ | slide 冲突时自己找位置 |
| `ProvideMaxSlide` | `100` | slide 上限 |
| `RebuildAppleMemoryMap` | ✅ | 重建内存映射 |
| `SetupVirtualMap` | ✅ | 建立虚拟映射 |
| `SyncRuntimePermissions` | ✅ | 同步运行时权限 |

`DevirtualiseMmio` 是最关键的一个：不启用的话，macOS 会把固件占用的
MMIO 区域当成可用内存，写到那里直接死机。

---

## 七、DeviceProperties

只给三个 PCI 桥加了 `built-in`：

```
PciRoot(0x0)/Pci(0x1,0x3)/Pci(0x0,0x0)   built-in = 01
PciRoot(0x0)/Pci(0x2,0x1)/Pci(0x0,0x0)   built-in = 01
PciRoot(0x0)/Pci(0x2,0x2)/Pci(0x0,0x0)   built-in = 01
```

`built-in` 让这些桥被识别为内建设备，影响电源管理和设备树排序。

> 显卡**没有**在这里注入任何属性。
> `PhxBringup`/`PhxAccel` 自己管理 GPU 的 PCI 配置，
> 从这里注入反而会干扰它。

---

## 八、NVRAM

### boot-args

```
-v keepsyms=1 revpatch=cpuname,sbvmm ipc_control_port_options=0 \
   -amfipassbeta amfi=0x80 amfi_get_out_of_my_way=0x1 phxdebug=1
```

| 参数 | 作用 |
|---|---|
| `-v` | 啰嗦模式，**调试期必开** |
| `keepsyms=1` | panic 时保留符号名（否则只有地址） |
| `revpatch=cpuname,sbvmm` | RestrictEvents 风格的 CPU 名/虚拟机掩盖（本机由 NVRAM 直接提供，不依赖 kext） |
| `ipc_control_port_options=0` | **Tahoe 必需**，否则部分 IPC 失败 |
| `-amfipassbeta` | AMFIPass beta 模式 |
| `amfi=0x80` | 关闭 AMFI 签名检查 |
| `amfi_get_out_of_my_way=0x1` | 同上，老写法 |
| `phxdebug=1` | **nullarc 调试输出**，排查 GPU 全靠它 |

### 其它 NVRAM 项

```
csr-active-config = 7F080000     # SIP 全关（编译/加载未签名 kext 必需）
run-efi-updater   = "No"         # 阻止固件自动更新
SystemAudioVolume = "F"          # 开机静音（没声卡，避免报错）
bluetoothExternalDongleFailed = 00
bluetoothInternalControllerInfo = 0000000000000000
```

最后两项是**蓝牙必填**：不写这两个空值，`bluetoothd` 会认为
控制器未初始化，`State: Off`。

### `4D1FDA02-...` 那个 GUID

`revcpu=1` + `revcpuname` + `revpatch` 直接写在 NVRAM 里，
效果等同 `RestrictEvents.kext`，但**不加载任何 kext**。
这是本机绕开 `RestrictEvents` 崩溃（见 [03](03-踩坑记录.md) 1.1）的办法。

---

## 九、PlatformInfo

```
SystemProductName = MacBookPro16,1
ProcessorType     = 3841          # 0xF01，四舍五入到最近的 Intel 型号
Automatic         = true
SpoofVendor       = true
ROM               = <全零>         # ← 需自己填真实 MAC
MLB               = GENERATE-WITH-GenSMBIOS
SystemSerialNumber= GENERATE-WITH-GenSMBIOS
SystemUUID        = GENERATE-WITH-GenSMBIOS
```

**为什么是 `MacBookPro16,1`**：

- 需要 `X86PlatformPlugin` 电源管理 → 必须是带 `plugin-type` 的机型
- 需要支持 Metal 3 → 机型不能太老
- 不能是 `iMacPro1,1`（会尝试加载 AMD 独显驱动，冲突）
- `MacBookPro16,1` 是**唯一验证过的**：CPU 电源管理正常，无独显冲突

**`ProcessorType = 3841`**：让「关于本机」显示正确的 CPU 名称，
不设的话会显示 `Unknown`。

---

## 十、Misc

| 项 | 值 | 说明 |
|---|---|---|
| `SecureBootModel` | `Disabled` | 必需，否则未签名 kext 不加载 |
| `DmgLoading` | `Signed` | 只加载签名的 DMG |
| `Vault` | `Optional` | 不用 vault |
| `ScanPolicy` | `0` | 扫描所有设备（否则看不到某些分区） |
| `ExposeSensitiveData` | `7` | 完整暴露（调试用） |
| `BlacklistAppleUpdate` | ✅ | 阻止 Apple 更新覆盖 |
| `PickerMode` | `External` | 用 OpenCanopy 图形菜单 |
| `PickerAttributes` | `17` | 显示辅助项 + 卷标 |
| `Timeout` | `5` | 5 秒后自动启动 |
| `HideAuxiliary` | ❌ | 显示辅助项（调试期需要） |
| `ShowPicker` | ✅ | 显示菜单 |

`ScanPolicy = 0` 在调试期很重要：默认策略会隐藏 Recovery 分区，
出问题时进不去恢复环境。

---

## 十一、校验清单

改完 `config.plist` 后按顺序检查：

```sh
# 1. 语法（XML 层面）
plutil -lint config.plist

# 2. 语义（能否被 plistlib 解析 —— plutil 会放过一些错误）
python3 -c "import plistlib;plistlib.load(open('config.plist','rb'));print('OK')"

# 3. 三码是否已替换
grep -c 'GENERATE-WITH-GenSMBIOS' config.plist    # 应该为 0

# 4. 危险驱动是否禁用
python3 - <<'EOF'
import plistlib
d = plistlib.load(open('config.plist','rb'))
for x in d['UEFI']['Drivers']:
    if 'OpenVariableRuntimeDxe' in x['Path']:
        assert not x['Enabled'], "OpenVariableRuntimeDxe 必须禁用！"
print("safe")
EOF

# 5. SSDT-PLUG-ALT 是否启用
python3 - <<'EOF'
import plistlib
d = plistlib.load(open('config.plist','rb'))
e = [x for x in d['ACPI']['Add'] if 'PLUG-ALT' in x['Path']][0]
assert e['Enabled'], "SSDT-PLUG-ALT 必须启用！"
print("safe")
EOF
```
