# AppleIGC 源码修改（自编译版）

本仓库附带一个**自行编译**的 `AppleIGC.kext`：

```
版本:  1.9.2（CFBundleVersion 必须是纯数字）
来源:  https://github.com/SongXiaoXi/AppleIGC  @ 8802cba
用途:  板载 Intel I226-V（8086:125C）2.5G 网卡
状态:  ⚠️ config.plist 里 Enabled = false，默认禁用
```

---

## 一、上游版本的两个问题

macOS 自带的 `AppleEthernetE1000` 在本机**协商不出 PHY 链路**，
所以只能用社区驱动 `AppleIGC`，但它也有坑：

| 版本 | 结果 |
|---|---|
| **v1.8** | RX 通，但偶发 `m->m_flags & M_PKTHDR` 内核 panic |
| **v1.9** | link 正常但 **RX 完全死** —— `Ipkts` 恒为 0 |
| **v1.9.2（本仓库）** | 修好了 RX，但加载被系统拒绝 |

### v1.9 的 RX 死

现象是**只发不收**：

```sh
ifconfig en0    # media: 2500Base-T, status: active   ← link 正常
netstat -I en0  # Ipkts=0, Ibytes=0                  ← 收包永远 0
sudo tcpdump -i en0 -n                               # 0 packets captured
# DHCP 拿不到 → 169.254.x.x
```

**根因**（upstream [issue #40](https://github.com/SongXiaoXi/AppleIGC/issues/40)）：

`pci_enable_msi_block()` 被 `#if 0` 整体禁用，永远返回错误，
所以 `IGC_FLAG_HAS_MSI` 永不置位 —— **MSI 在硬件上从未启用**。

但 v1.9 的 PR #38 又让驱动去**监听 MSI 中断源**。
结果：监听一个永不触发的向量 → 中断处理永不执行 → RX 队列永不处理。
TX 走同步路径不需要中断，所以「只发不收」。

---

## 二、本仓库的两个补丁

### 补丁 1：强制 legacy INTx（修 RX 死）

位置：`AppleIGC.cpp` → `AppleIGC::initEventSources()`

```c
/* GEM12 patch: force legacy INTx (source 0).
 *
 * pci_enable_msi_block() is stubbed out inside #if 0, so IGC_FLAG_HAS_MSI
 * is never set and MSI is never enabled in hardware.  Selecting an MSI
 * source here (PR #38) therefore means the driver listens on a vector that
 * is never asserted: interruptOccurred() never runs and RX is completely
 * dead.  Upstream issue: https://github.com/SongXiaoXi/AppleIGC/issues/40
 */
provider->getInterruptType(0, &interruptType);
interruptIndex = 0;
usingMsi = false;
```

替换掉原来的「遍历找第一个 MSI 源」的循环。

**效果**：RX 恢复正常。

```sh
netstat -I en0 -b
#   Ipkts=7472  Ibytes=4680524      ← RX 活了
ping -c 3 192.168.1.1
#   0.0% packet loss, 0.396/0.498/0.573 ms
curl --interface 192.168.1.128 https://www.apple.com   # HTTP 200
```

### 补丁 2：RX 按完整帧分配（修 mbuf 链）

位置：`igc_clean_rx_irq()`

```c
/* GEM12 patch: allocate a full frame, not just the header.
 *
 * Upstream Linux allocates IGC_RX_HDR_LEN (256 bytes) here and attaches the
 * payload as page frags, so the skb only holds the header.
 *
 * The macOS port has no frag mechanism: igc_add_rx_frag() calls
 * mbuf_copyback() to copy the WHOLE frame into this mbuf.  With a 256-byte
 * allocation a 1500-byte frame gets split into a chain of 6-7 mbufs,
 * which is fragile (and slow).
 */
skb = netdev_alloc_skb_ip_align(rx_ring->netdev, IGC_RXBUFFER_2048);
```

> 用 `IGC_RXBUFFER_2048` 而不是 `IGC_MAX_FRAME_BUILD_SKB` ——
> 后者依赖 Linux 宏 `SKB_WITH_OVERHEAD`，macOS 分支没定义，会编译失败。

---

## 三、手工编译（没有完整 Xcode 也能编）

本机只有 **Command Line Tools**，`xcodebuild` 会报 "requires Xcode"。
直接用 `clang` 手工编译（项目一共 6 个源文件）：

```sh
git clone https://github.com/SongXiaoXi/AppleIGC.git ~/AppleIGC-src
cd ~/AppleIGC-src
# 打上上面两个补丁

# 快捷方式：用本仓库的脚本
bash scripts/build-appleigc.sh
```

脚本要点（细节见 `scripts/build-appleigc.sh`）：

| 步骤 | 关键 |
|---|---|
| 编译 | 6 个文件：`AppleIGC.cpp` + `igc_{base,i225,mac,nvm,phy}.c`<br>**不要编 `igc_main.c`**（Linux 参考实现，官方项目也没编） |
| 提供 `kmod_info` | 必须有 `scripts/kmod_info.c`，见下面第 4 个坑 |
| 链接 | `ld -kext -arch x86_64` —— **必须是 `-kext`**，`ld -r` 得到的是 object 不是 kext bundle |
| 校验 | `file .../AppleIGC` 应为 `Mach-O 64-bit kext bundle x86_64` |

---

## 四、四个坑（都踩过）★

### 坑 1：`Info.plist` 是未展开的模板

源码里的 `AppleIGC/Info.plist` 是 Xcode 模板，含 `${PRODUCT_NAME}` 这类变量，
没展开就**没有 `CFBundleIdentifier`**。
→ 用官方 release 包里已展开的 `Info.plist`。

### 坑 2：必须 `ld -kext` 而不是 `ld -r`

后者产出 `Mach-O 64-bit object`，OpenCore 不认。

### 坑 3：`CFBundleVersion` 必须纯数字点分 ★

```
1.9-gem12c   ❌  ← 本项目踩过
1.9.2        ✅
```

报错只有一行，**极易漏掉**：

```
Kext com.sxx.AppleIGC error - CFBundleVersion bad value '1.9-gem12c'.
```

**这条错误是静默的**：OpenCore 不提示，系统照常启动，
只是 kext 没被加载。本项目因此白折腾两轮，误以为「驱动加载后卡死」。

### 坑 4：手工编译必须自己提供 `_kmod_info` ★

`ld -kext` 不会自动生成 `_kmod_info`，内核用它登记 kext。缺了就加载失败。

判断方法（对比官方 release）：

```sh
nm -gU 官方/Contents/MacOS/AppleIGC | wc -l    # 143
nm -gU 我们/Contents/MacOS/AppleIGC | wc -l    # 142  ← 差的正是 _kmod_info
```

修法：`scripts/kmod_info.c`

```c
#include <mach/kmod.h>
KMOD_EXPLICIT_DECL(com.sxx.AppleIGC, "1.9.2", 0, 0);
```

> ⚠️ **不要加 `ld ... -exported_symbol _kmod_info`**。
> 那个参数会把导出符号表砍成只有 1 个（143 → 1），类的元数据符号全被隐藏。

---

## 五、最终结论：不可用

四个坑填完后，kext 终于能被识别，但加载被系统拒绝：

```
Extension with identifiers com.sxx.AppleIGC not approved to load.
  Please approve using System Settings.
```

### 最重要的教训

**改完 `config.plist` 的 `Enabled = true` 不等于 kext 生效了。**
由于坑 3 和坑 4，本项目自编译的三个版本**从来没有一个真正加载过**。

也就是说：那些被归因于「AppleIGC 导致 `pmap` 内存损坏」的 panic，
跟 AppleIGC **毫无关系** —— 它当时根本没在跑。
真正的元凶是 `nullarc` 的 GPU 接管（见 [docs/07](../docs/07-稳定性与崩溃分析.md)）。

**每次都确认它真的加载了**：

```sh
kmutil showloaded | grep -i igc
ioreg -rc AppleIGC -d1
```

### 下次可以继续的方向

1. 把 `CFBundleVersion` 改对、确认 kext 真的加载，再重新验证 RX
   —— 本项目的两个补丁逻辑理论上是对的，但从没在"真正加载"的前提下验证过
2. 确认 `IOProbeScore` 是否真的抢占了原生 dext（4000 > 3000）：
   ```sh
   ioreg -rc IOUserNetworkEthernet -d1 | grep IOModel   # 还挂着原生吗
   ```
3. 跟进 upstream 的 issue #40

### 当前生产方案

**Wi-Fi**，或 **USB 网卡 AX88179B**（`com.apple.driver.usb.cdc.ncm` 原生驱动，免驱即插即用）。
