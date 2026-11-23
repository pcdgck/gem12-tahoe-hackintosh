# 01 — 780M GPU 接管全过程

本文记录从「WindowServer 崩溃」到「GPU 桌面合成正常工作」的完整排查路径。

---

## 起点：官方的 release 直接失败

用 `luuumi-dev/nullarc` 的 `v0.4.0-alpha` release 包，
按 `install.sh --windowserver` 安装后，每次启动都得到：

```
WindowServer crash (SIGABRT):
  0 libsystem_kernel.dylib   __pthread_kill
  1 libsystem_pthread.dylib  pthread_kill
  2 libsystem_c.dylib        abort
  3 libsystem_c.dylib        __assert_rtn
  4 CoreDisplay              CoreDisplay_CreateDisplayForCGXDisplayDevice +289801
  5 CoreDisplay              UpdateCGXDisplayDevice +876293
  6 CoreDisplay              AddCGXDisplayDeviceToDeviceList +876889
  7 CoreDisplay              CGXDisplayDriverInitialize +883910
  8 SkyLight                 WS::Displays::CoreDisplayManager::initialize() +43
  9 SkyLight                 WSInitialize +3956
 10 WindowServer             +1745
```

`phxboot` 的保护机制会在崩 3 次后自动回滚：

```
M2 failed (WindowServer crashed or hung 3 times on the 780M): PhxAMDFB off, rebooting
```

**这不是配置问题，是 CoreDisplay 拿不到有效显示设备。**

---

## 逐步定位

### 第一层：`phxboot-m2` 与 NVRAM arming

`PhxAMDFB` 的 `start()` 有 arming 检查：

```cpp
if (!takeBootArming()) { PFBLOG("NVRAM phxfb-boot not set: leaving the firmware framebuffer"); return false; }
```

日志证据：

```
PhxFB: NVRAM phxfb-boot not set: leaving the firmware framebuffer this boot
```

**修复**：创建 `/Users/Shared/gpu/phxboot-m2` 并设 `nvram phxfb-boot=1`。

**效果**：日志变成 `PhxAMDFB on the panel: 1`，但 WindowServer 依然崩。

---

### 第二层：VRAM 池太小

日志：

```
PhxFB: VRAM pool: 512 MB at phys 0x1e860000
PhxFB: VRAM: 12533760 bytes at phys 0x1e860000 from the pool (12533760 out)
```

`12533760 = 2160 × 1440 × 4`，刚好一帧。

**排查**：`PhxBringup` 报告 3840 MB（改过 ptfix 后），
但 `PhxAccel` 的 `kPoolTry` 还是 `{512, 256, 128}` MB —— 两边不匹配。

**修复**：`kPoolTry = {2048, 1024, 512}`、`kVramCap = 3840`。

**效果**：

```
PhxFB: VRAM pool: 2048 MB at phys 0x100000000
```

但 WindowServer 依然崩。

---

### 第三层：`MM commit NOT MAPPED`

日志：

```
NVVidMemory::allocPhysical: SCANOUT phys 0xc60000000 (12533760 bytes) -- already backed, nothing allocated
MM commit: NOT MAPPED -- hVirt 0x1 kapiMem 0x0 len 12533760
NVVidMemory::deallocPhysical: SCANOUT -- not ours to free, only forgetting it
```

**分析**：scanout 内存走 `fScanout` 分支，只设物理地址、不创建 RM handle，
所以 `commitIntoGPUPageTable` 里 `kapiMem = 0` 直接返回 false。

**关键观察**：偶尔第一次会 fallback 成功——

```
NVVidMemory::allocPhysical: 12533760 bytes of REAL VRAM -- phys 0x1d860000 [BAR1]
MM commit: MAPPED gpuVA 0x100000000000 len 12533760 <- hMem 0x2  *** the GPU can reach these bytes ***
```

**修复**：让 scanout 分支也给出一个非空 `fRmHandle`（`nvGpuVaMap` 本来就只发记账句柄、
不做真实映射），并在 `deallocPhysical` 里清掉它避免复用过期值。

**效果**：每轮都 `MAPPED`，但 WindowServer 依然崩。

---

### 第四层：timing 不是问题

一度怀疑 `getTimingInfoForDisplayMode` 返回无效导致 CoreDisplay 断言。
加日志确认：

```
PhxFB: timing: head 0 asked for mode 1 (w 2160 h 1440 ht 2320 vt 1481 60000 mHz)
```

参数完全正确、确实被调用。**排除 timing。**

---

### 第五层：EDID 缺失 ★

从 dyld 共享缓存里提取 CoreDisplay 的符号，找到：

```
CoreDisplay::Display::InitializeBrightnessControl
CoreDisplay::Display::Display(CGXDisplayDevice *)
Unknown CGXDisplayDevice: 0x%08x
```

回到 `PhxFB`，发现主 head 根本不提供 EDID：

```cpp
bool hasDDCConnect(IOIndex) override { return false; }
IOReturn getDDCBlock(...) override { return kIOReturnUnsupported; }
```

**修复**：主 head 返回一份 128 字节 1920×1080@60 EDID。

---

### 第六层：背光处理器缺失 ★

`CoreDisplay::Display` 构造时调用 `InitializeBrightnessControl`。
而 `PhxAMDFB::start()` 里：

```cpp
else if (!backlightRead(&bl)) PFBLOG("backlight: the PWM is not running ... no brightness control");
```

外接显示器没有 PWM 背光，所以 `fBacklight` 始终为 NULL。

**修复**：即使 `backlightRead` 失败也创建 `PhxBacklight`（亮度固定 `kBlMax`）。

**效果**（重大进展）：

```
PhxFB: backlight: the PWM is not running (no MMIO view, or off) -- offering a fixed level anyway
PhxFB: backlight: fixed at 1024 of 1024
PhxFB: backlight: brightness parameter on AppleBacklightDisplay, 1024 of 1024
childPublished: AppleBacklightDisplay(0x10000054d) published
```

**`AppleBacklightDisplay` 成功发布了！** 但 WindowServer 还是崩。

---

### 第七层：Metal 插件权限 ★★

这是最后一块拼图。WindowServer 日志：

```
WindowServer: [ERROR] Cannot find executable for CFBundle
  </System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU/NVMTLDriver.bundle> (not loaded)

WindowServer: (CoreDisplay) [ERROR] - Setting offline display 0x00000000 main
  in AddCGXDisplayDeviceToDeviceList
  0 CoreDisplay::AddMainOfflineBreadcrumb
  1 AddCGXDisplayDeviceToDeviceList +209
  2 CGXDisplayDriverInitialize +1710
```

**排查**：`NVMTLDriver.bundle` 的可执行文件确实存在（1.57 MB），
`Info.plist` 的 `CFBundleExecutable` 也对。

**但是权限**：

```
drwx------  NVMTLDriver.bundle/Contents
-rwx------  NVMTLDriver.bundle/Contents/MacOS/NVMTLDriver
```

`700` / `600` —— **只有 root 能读**。而 WindowServer 以 userID 88 运行。

**修复**：

```sh
sudo chmod -R 755 /System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU
```

**效果**：显示器从 offline 变 online，GPU 合成开始工作：

```
AMD Radeon 780M
  VRAM (Total): 8 GB
  Metal Support: Metal 3
  Displays:
    Display:
      Resolution: 2160 x 1440
      Online: Yes
      Connection Type: Internal

debug.nvaccel_iop_ok: 3 秒内增长 12 → GPU 正在合成
WindowServer CPU: 空闲 0.2%
```

---

## 最终 `phxboot` 成功日志

```
== 2026-11-24 00:02:08 phxboot
PhxAMDFB on the panel: 1
compute: scratch0=0xdeadbeef (want deadbeef) testbuf=0xfeedf00d (want feedf00d) hqd_active=1 rptr=8
adopt queue -> kr 0x0
gfx: scratch1=0xdeadbeef (want deadbeef) testbuf=0x6f7a6f7a (want 6f7a6f7a) rptr=0 rptr_wb=968 grbm=0xa800302c cp_stat=0x00000000
adopt gfx queue -> kr 0x0
claim -> kr 0x0
armed and released at 00:02:17; agdc 1
WindowServer pid 194, frames on the panel 3337
PhxAMDFB armed for the next boot
done 00:24:37
```

`PhxAMDFB armed for the next boot` 表示 arming 已持久化，下次启动自动生效。

---

## 帧率与 CPU

| 场景 | 帧率 | WindowServer CPU |
|---|---|---|
| 空闲（无画面变化） | 0 fps | **0.2%** |
| 打开窗口 | ~38 fps | 4-9% |
| 拖动窗口 | 57 fps | 127%（见下） |

**关于 127% CPU**：这是 nullarc 架构的固有代价
（CA 图层准备 + Metal 绘制 + `NVMTL_WS_WAIT_COMPLETION` 的忙等）。
K8 同代硬件空闲也有 ~33%。

### ⚠️ 先排除一个假象：动态壁纸

看到"什么都没开却 90%+ CPU"时，**第一件事不是怀疑显卡，而是查 `VTDecoderXPCService`**：

```sh
top -l 2 -n 10 -o cpu -stats pid,command,cpu,mem | tail -12
```

如果看到：

```
705   VTDecoderXPCServ 93.2  4.1 GB
```

那是 Tahoe 的动态壁纸 `Tahoe Day`（170 MB HEVC）在**纯 CPU 软解** ——
因为 780M 没有 macOS 下的 VCN 硬件解码器。

实测杀掉它之后：

| 指标 | 杀之前 | 杀之后 |
|---|---|---|
| `VTDecoderXPCService` | 93.2% / 4.1 GB | 退出 |
| `WindowServer` | 28.8% | **9.8%** |
| load average | 4.66 | **3.14** |

```sh
sudo killall WallpaperAerialsExtension
```

**这不属于 nullarc 的问题**，是任何无硬件解码的黑苹果都会遇到的。
详见 [04-已知问题.md](04-已知问题.md) 2.6。

### 真正的 nullarc 开销

**缓解手段**：

```sh
defaults write com.apple.universalaccess reduceTransparency -bool true
defaults write com.apple.universalaccess reduceMotion -bool true
```

去掉毛玻璃后帧率从 2 fps 提到 57 fps（因为消除了 `CA::OGL::BlurState` 的递归渲染）。
代价是界面失去毛玻璃效果。

---

## 关键 sysctl 一览

| sysctl | 值 | 作用 |
|---|---|---|
| `debug.phxfb_dbuf` | 1 | 双缓冲扫描输出（防撕裂） |
| `debug.phxfb_dbuf_state` | 1 | 1=已激活 |
| `debug.phxfb_timing` | 1 | 发布 detailed timing（CoreVideo 拿到真实刷新率） |
| `debug.nvaccel_surface_gpu_on` | 0 | 消除残影 |
| `debug.nvaccel_iop_sse` | 1 | SSE 流式拷贝（1.0ms/帧 vs 2.1ms） |
| `debug.nvaccel_iop_vsync` | 1 | 拷贝在下一个 VBL 完成 |
| `debug.nvaccel_iop_ok` | 递增 | GPU 合成帧计数 |

**这些 `debug.*` 每次重启重置，靠 `local.phxdisplay` LaunchDaemon 开机重设。**
