# AppleIGC 源码修改（自编译版）

本仓库附带一个**自行编译**的 `AppleIGC.kext`：

```
版本:  1.9-gem12
来源:  https://github.com/SongXiaoXi/AppleIGC  @ 8802cba
用途:  板载 Intel I226-V（8086:125C）2.5G 网卡
状态:  ⚠️ 当前在 config.plist 里 Enabled = false（会导致内存损坏 panic，见文末）
```

---

## 一、上游的三个版本，各有各的问题

macOS 自带的 `AppleEthernetE1000` 在本机**协商不出 PHY 链路**，
所以只能用社区驱动 `AppleIGC`。但它也有坑：

| 版本 | 结果 |
|---|---|
| **v1.8**（1.8d1） | RX 通，但偶发 `m->m_flags & M_PKTHDR` 内核 panic |
| **v1.9**（1.9d2） | link 正常但 **RX 完全死** —— `Ipkts` 恒为 0 |
| **v1.9-gem12**（本仓库） | 修好了 RX，但出现 `pmap` 内存损坏 panic |

---

## 二、v1.9 的 RX 死：MSI 中断的 bug

### 现象

```sh
ifconfig en0
#   media: autoselect (2500Base-T <full-duplex,flow-control>)
#   status: active                              ← link 是好的

netstat -I en0 -b
#   Ipkts=0  Ibytes=0                           ← 收包永远是 0
#   Opkts=... Obytes=...                        ← 发包正常

sudo tcpdump -i en0 -n
#   0 packets captured                          ← 一个包都收不到

# DHCP 拿不到地址 → 169.254.x.x
```

**只发不收。**

### 根因（upstream issue #40）

`AppleIGC.cpp` 里的 `pci_enable_msi_block()` 被 `#if 0` 整体禁用了：

```c
static int pci_enable_msi_block(IOPCIDevice *dev) {
    int status = -EINVAL, maxvec;
    if (dev->findPCICapability(kIOPCIMSICapability, &pos) == 0)
        return -EINVAL;
    ...
#if 0
    status = pci_msi_check_device(...);      // 禁用
#endif
#if 0
    status = msi_capability_init(dev, nvec); // 真正的 MSI 设置也禁用
#endif
    return status;                           // 永远 -EINVAL
}
```

于是 `IGC_FLAG_HAS_MSI` 永远不会置位，**MSI 在硬件上从未启用**。

但 v1.9 的 PR #38 又让驱动去**监听 MSI 中断源**：

```c
for (int index = 0; ; index++) {
    provider->getInterruptType(index, &interruptType);
    if (interruptType & kIOInterruptTypePCIMessaged) {
        interruptIndex = index;    /* → 1 */
        usingMsi = true;
        break;
    }
}
```

结果：**监听一个永远不会被触发的向量 → `interruptOccurred()` 永不调用 →
RX 队列永不处理**。TX 走同步路径不需要中断，所以不受影响。

> 上游 issue: https://github.com/SongXiaoXi/AppleIGC/issues/40
> issue 作者实测：MSI 源时 `IrqCount = 0`；强制 legacy INTx 后
> `IrqCount = 46528`、`ICR = 0x80000080 (INT_ASSERTED|RXT0)`，DHCP 立刻成功。

---

## 三、本仓库的补丁：强制 legacy INTx

改动位置：`AppleIGC/AppleIGC.cpp` → `AppleIGC::initEventSources()`

**改之前**（找第一个 MSI 源）：

```c
for (int index = 0; ; index++) {
    IOReturn typeResult = provider->getInterruptType(index, &interruptType);
    if (typeResult != kIOReturnSuccess)
        break;
    if (interruptType & kIOInterruptTypePCIMessaged) {
        interruptIndex = index;
        usingMsi = true;
        break;
    }
}
if (interruptIndex != 0)
    pr_debug("Using PCI messaged interrupt source %d (type=0x%x)\n", interruptIndex, interruptType);
else
    pr_debug("No PCI messaged interrupt source found; using source 0 (type=0x%x)\n", interruptType);
```

**改之后**（固定用 source 0 / legacy INTx）：

```c
/* GEM12 patch: force legacy INTx (source 0).
 *
 * pci_enable_msi_block() in AppleIGC.cpp is stubbed out inside #if 0,
 * so IGC_FLAG_HAS_MSI is never set and MSI is never enabled in
 * hardware.  Selecting an MSI source here (PR #38) therefore means the
 * driver listens on a vector that is never asserted: interruptOccurred()
 * never runs and RX is completely dead (link reports active, Ipkts
 * stays 0, DHCP falls back to 169.254.x.x).
 *
 * Upstream issue: https://github.com/SongXiaoXi/AppleIGC/issues/40
 */
provider->getInterruptType(0, &interruptType);
interruptIndex = 0;
usingMsi = false;
pr_debug("GEM12 patch: forcing legacy INTx source 0 (type=0x%x)\n", interruptType);
```

**效果**：RX 恢复正常。

```sh
netstat -I en0 -b
#   Ipkts=7472  Ibytes=4680524      ← RX 活了
#   Opkts=4052  Obytes=872594

ping -c 3 192.168.1.1
#   0.0% packet loss, min/avg/max = 0.396/0.498/0.573 ms

curl --interface 192.168.1.128 https://www.apple.com
#   HTTP 200
```

---

## 四、编译方法（没有完整 Xcode 也能编）

本机只有 **Command Line Tools**（没有 `Xcode.app`），
所以 `xcodebuild` 用不了（会报「requires Xcode」）。
直接调 `clang` 手工编译，项目一共 6 个源文件：

```sh
git clone https://github.com/SongXiaoXi/AppleIGC.git ~/AppleIGC-src
cd ~/AppleIGC-src

# 注意：不要编 igc/igc_main.c —— 它是 Linux 参考实现，
# 需要 linux/module.h，官方 Xcode 项目也没把它加进 Sources。

SDK=~/MacKernelSDK
SRC=~/AppleIGC-src/AppleIGC
OUT=/tmp/igcbuild; mkdir -p $OUT

COMMON="-target x86_64-apple-macos10.15 -arch x86_64 \
  -mkernel -nostdinc -nostdlib -fno-builtin -fno-common -fno-exceptions -fno-rtti \
  -I $SDK/Headers -I $SRC -I $SRC/igc \
  -D KERNEL=1 -D __KERNEL__=1 -D APPLE_KEXT=1 -D __PRIVATE_SPI__=1 \
  -O2 -w"

# 1. C++ 主驱动
clang++ $COMMON -std=gnu++17 -fapple-kext -c $SRC/AppleIGC.cpp -o $OUT/AppleIGC.o

# 2. 五个 C 文件
for f in $SRC/igc/igc_base.c $SRC/igc/igc_i225.c $SRC/igc/igc_mac.c \
         $SRC/igc/igc_nvm.c $SRC/igc/igc_phy.c; do
    clang $COMMON -std=gnu11 -c "$f" -o "$OUT/$(basename "$f" .c).o"
done

# 3. 关键：用 -kext 链接，否则只是 object 不是 kext bundle
ld -kext -arch x86_64 -o $OUT/AppleIGC.kextbin $OUT/*.o

# 4. 组装 kext
mkdir -p AppleIGC.kext/Contents/MacOS
cp $OUT/AppleIGC.kextbin AppleIGC.kext/Contents/MacOS/AppleIGC
cp <v1.9 官方 release 的 Info.plist> AppleIGC.kext/Contents/Info.plist
# 官方 Info.plist 里的 CFBundleIdentifier = com.sxx.AppleIGC、CFBundleVersion = 1.9d2
```

### 两个容易踩的坑

1. **源码里的 `AppleIGC/Info.plist` 是 Xcode 模板**，
   里面是 `${PRODUCT_NAME}`、`${PRODUCT_BUNDLE_IDENTIFIER}` 这类变量，
   没展开就**没有 CFBundleIdentifier**，kext 无法加载。
   → 用官方 release 包里已展开的 `Info.plist`。

2. **必须用 `ld -kext` 链接**。用 `ld -r` 得到的是
   `Mach-O 64-bit object`，不是 `Mach-O 64-bit kext bundle`，OpenCore 不认。

```sh
file AppleIGC.kext/Contents/MacOS/AppleIGC
# 必须是: Mach-O 64-bit kext bundle x86_64
```

---

## 五、⚠️ 为什么当前默认禁用

补丁解决了 RX，但跑了一段时间后出现**内存损坏类 panic**：

```
panic(cpu 13): Possible memory corruption:
pmap_pv_remove(...): null pv_list, priors: 2 @pmap_internal.h:893
Panicked task: pid 571: FamilyControlsAgent
```

崩溃进程是随机的（`FamilyControlsAgent`、`CacheDeleteExtension`），
说明是系统级内存结构被写坏。

**但注意**：这类 `pmap` panic 在装 AppleIGC **之前**就有
（11-23 18:14 已经出现过），所以**不能完全归因于 AppleIGC** ——
更可能是 `nullarc` 的 GPU 接管导致的（见 [docs/07](../docs/07-稳定性与崩溃分析.md)）。

即便如此，在没有更确凿证据前，本仓库的默认配置
**把 AppleIGC 设为 `Enabled = false`**，稳定优先。

### 想自己试

```sh
# 1. 打开 config.plist 里 AppleIGC 那条
#    Kernel → Add → AppleIGC.kext → Enabled = true
# 2. 重启
# 3. 观察 Ipkts 是否增长、是否 panic
```

回滚点备份（本机）：

```
/Users/Shared/gpu/backup/AppleIGC-v1.8.kext     原始 v1.8
/Users/Shared/gpu/backup/AppleIGC-v1.9.kext     原始 v1.9
```

### 更稳妥的替代

**用 Wi-Fi，或者 USB 网卡**（AX88179B，`com.apple.driver.usb.cdc.ncm` 原生驱动）。
I226-V 在 macOS 上目前确实没有可靠的驱动方案，
建议跟进 upstream 的修复合集。
