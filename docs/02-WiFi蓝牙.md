# 02 — Intel AX210 Wi-Fi 与蓝牙

GEM12 的无线网卡是 **Intel AX210**（PCI `8086:2723`，蓝牙 USB `8087:0029`）。

macOS 原生不支持 Intel 网卡，需要第三方驱动。

---

## 最终配置

### EFI/Kexts 里需要四个 kext

| Kext | 版本 | MinKernel | 作用 |
|---|---|---|---|
| `AirportItlwm.kext` | 2.4.0（Tahoe 版） | — | Wi-Fi |
| `IntelBluetoothFirmware.kext` | 2.5.1 | — | 上传蓝牙固件 |
| `IntelBTPatcher.kext` | 2.5.1 | 21.0.0 | 蓝牙补丁（Monterey+） |
| `BlueToolFixup.kext` | 2.7.2 | 21.0.0 | 修 transport 误判 + BlueTool 超时 |

**顺序很重要**（`Kernel/Add` 数组）：

```
Lilu.kext
BlueToolFixup.kext
IntelBluetoothFirmware.kext
IntelBTPatcher.kext
AirportItlwm.kext
```

`BlueToolFixup` 必须在 `IntelBluetoothFirmware` 之前。

**不要加 `IntelBluetoothInjector.kext`** —— Monterey 之后由 `IntelBTPatcher` 取代，
两者同时存在会冲突。

---

## Wi-Fi

### 结果

```
en3:
  Card Type: Wi-Fi  (0x8086, 0x84)
  Firmware Version: itlwm: 2.4.0_7204c69 fw: 68.01d30b0c.0
  MAC Address: 6e:61:c4:d4:9c:67
  Locale: FCC
  Country Code: US
```

**不需要 OCLP root patch**，直接用原生 Wi-Fi 接口。
这是 [laobamac 的 fork](https://github.com/laobamac/itlwm) 的特性。

### 支持范围

| 项目 | 状态 |
|---|---|
| WPA2-Personal | ✅ |
| WPA2/WPA3 transition（含可选 PMF） | ✅ |
| WPA3-only | ❌ |
| 强制 PMF | ❌ |
| AWDL / AirDrop | ❌ |
| MLO | ❌ |
| Wi-Fi 6 (802.11ax / HE) | ⚠️ 默认关闭 |

**开启 Wi-Fi 6**：加 boot-arg `itlwm_he=1`。

### 下载

```
https://github.com/laobamac/itlwm/releases
→ AirportItlwm-Tahoe-v2.4.0-RELEASE-alpha-*.zip
```

**注意必须选 `Tahoe` 版本**，Sequoia/Ventura 版不通用。

---

## 蓝牙

### 遇到的三个问题

#### 问题 1：设备枚举了但 `State: Off`

初始状态：

```
Bluetooth:
  Address: NULL
  State: Off
  Chipset: BCM_4350C2     ← Apple 的占位符，说明没识别到真实芯片
  Firmware Version: v0 c0
  Transport: UART          ← 错误！AX210 是 USB
```

但 USB 树上设备确实存在：

```
Bluetooth USB Host Controller@60500000
  idVendor  = 32903 = 0x8087   ← Intel
  idProduct = 41    = 0x0029   ← AX210 蓝牙
  IntelBluetoothFirmware 已挂载
  BlueTool 已连接
```

#### 问题 2：`BlueTool timed out running boot script`

```
bluetoothd: BlueTool timed out running boot script!
bluetoothd: Sending FWError to CoreAnalytics Type: ChipBootNonFatalFailure, ErrorCode: 0
```

#### 问题 3：transport 类型误判

```
bluetoothd: BT_HCI_TRANSPORT not set - Attempting to read from plist.
bluetoothd: FindTransportType -- UART Transport
bluetoothd: HCI Transport is set to H4BC
```

**AX210 是 USB 传输，被误判成 UART（串口），导致 BlueTool 脚本走错路径并超时。**

### 修复：加 `BlueToolFixup.kext` 2.7.2

这个 kext 正是为了修这两个问题。

```sh
# 从 BrcmPatchRAM release 里取
https://github.com/acidanthera/BrcmPatchRAM/releases
→ BrcmPatchRAM-2.7.2-RELEASE.zip
→ 里面只需要 BlueToolFixup.kext
```

### 修复后

```
Bluetooth:
  Address: EC:4C:8C:F2:F1:AB    ← 真实 MAC
  State: On
  Chipset: THIRD_PARTY_DONGLE
  Firmware Version: v8641 c8641  ← 固件已上传
  Transport: USB                 ← 正确了
  Supported services: 0x392039 < HFP AVRCP A2DP HID Braille LEA AACP GATT SerialPort >
```

日志：

```
bluetoothd: HCI Transport is set to USB
```

### 可用功能

✅ **能用：**
- 蓝牙键鼠
- 蓝牙耳机/音箱（A2DP）
- 蓝牙文件传输
- 大部分 BLE 设备

❌ **不能用（Intel 网卡固有限制，与驱动无关）：**
- Handoff / 接力
- AirDrop
- iPhone 自动配对（连续性功能）

`THIRD_PARTY_DONGLE` 这个标识本身就说明系统把它当作第三方蓝牙，
Apple 的连续性功能只对原生芯片开放。

---

## 排错命令

### Wi-Fi

```sh
# 接口状态
system_profiler SPAirPortDataType

# kext 是否加载
kmutil showloaded | grep -i itlwm

# 扫描网络
/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s
```

### 蓝牙

```sh
# 状态
system_profiler SPBluetoothDataType

# kext 是否加载
kmutil showloaded | grep -iE "bluetooth|bluetool"

# USB 树上的蓝牙设备（应看到 8087:0029）
ioreg -l -w0 -rc IOUSBHostDevice | grep -A5 "Bluetooth USB Host"

# 蓝牙守护进程日志
log show --predicate 'process == "bluetoothd"' --last 5m | grep -iE "error|fail|transport"
```

---

## 已知坑

1. **蓝牙枚举很慢**：日志里 `busy 0 (7260 ms)`，约 7 秒。
   这不影响功能，但会让开机后蓝牙比 Wi-Fi 晚可用。

2. **`IntelBluetoothInjector` 不要加**：Monterey+ 与 `IntelBTPatcher` 冲突。

3. **`AirportItlwm` 版本必须匹配系统大版本**：Tahoe 版不能用在 Sequoia 上。

4. **USB 端口映射**：蓝牙在内部 USB 2.0 端口上，
   `UTBDefault.kext`（通用映射）足够，不需要定制 `UTBMap`。
   但如果以后换成定制映射，记得把蓝牙那个端口标为 `internal`（255）。
