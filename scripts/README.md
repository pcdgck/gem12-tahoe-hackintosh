# 脚本说明

从 GEM12 上原样导出的**实际工作版本**。路径按原机部署位置写死，移植时一并修改。

```
/Users/Shared/gpu/            工作目录（phxboot.sh、bringup5.sh、full.sh、kinst.sh、fw/、phxctl/、backup/）
/usr/local/bin/               phxdisplay.sh、vtdec-guard.sh、gpuclk.sh
/usr/local/libexec/           gpucg.sh
/Library/LaunchDaemons/       local.phxboot / local.phxdisplay / local.vtdecguard / local.gpuclk
/Library/GPUBundles/nvmtl/    nvrm610.conf + Mesa RADV 的 dylib
```

---

## 一、开机链路（自动运行）

### `local.phxboot.plist` → `phxboot.sh`

LaunchDaemon，每次开机跑一次。做三件事：

1. 等 `PhxBringup` 起来（轮询 `ioreg` 里的 `"phx-build"`）
2. 放开 GPU：`sysctl -w debug.phxfb_hold=0`
3. 按 M2 状态决定是否 arm 显示（写 `nvram phxfb-boot=1`）

**失败保护**：

| 机制 | 触发条件 | 行为 |
|---|---|---|
| **pending 标记** | `/var/db/phxboot.pending` 存在（上次没跑完） | 建 `phxboot-off`、清 NVRAM、下次不进 M2 |
| **崩溃计数** | WindowServer 90 秒内崩 3 次 | `m2_fail`：关 PhxAMDFB + 重启回固件帧缓冲 |
| **面板时序** | WindowServer 在 arm 之前就打开了面板 | `m2_fail`（该状态**无恢复路径**，只能重启） |
| **长期看门狗** | 5 分钟内 2 个 WindowServer `.ips` | 重启；1 小时内 3 次 → 永久回退 |
| **kill switch** | 文件 `$G/phxboot-off` 存在 | 什么都不做，直接退出 |

`m2_fail` 会 `rm -f $G/phxboot-m2`，所以**连续失败会自我收敛**。

> 彻底关掉 GPU 接管：`sudo touch /Users/Shared/gpu/phxboot-off && sudo reboot`

`DENY` 变量里禁掉了 `mediaanalysisd` / `photoanalysisd` / `Spotlight` ——
它们会加载 MPS/Espresso 卷积核，实测几秒内把 GPU 挂死。

### `local.phxdisplay.plist` → `phxdisplay.sh`

开机设置 `PhxAccel` 的 debug sysctl（**每次重启都会重置**）：

```sh
sysctl -w debug.nvaccel_surface_gpu_on=0   # 消残影
sysctl -w debug.phxfb_dbuf=1               # 双缓冲，防撕裂
sysctl -w debug.phxfb_timing=1             # detailed timing
```

### `nvrm610.conf`

Metal 插件（`NVMTLDriver.bundle`）的运行时开关，放 `/Library/GPUBundles/nvmtl/`：

```ini
NVMTL_WS_WAIT_COMPLETION=1            # 提交后等完成，避免撕裂
NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=1
NVMTL_PIPELINE_THREADS=1              # 单线程，多线程会乱序
```

---

## 二、调试 / 救援工具（手动，需 root）

### `bringup5.sh` — PSP + 固件加载

按 **Linux 驱动的顺序**把 GPU 上电：PSP ring → TOC/TMR → 各引擎固件 `LOAD_IP_FW`
→ RLC autoload → SMU 打开 GFX。

固件来自 `~/gpu/fw/`，对齐 linux-firmware 的 `gc_11_0_1` / `psp_13_0_4`：

| 文件 | 用途 |
|---|---|
| `psp_13_0_4_toc.bin` | PSP 目录表 |
| `gc_11_0_1_{pfp,me,mec}.bin` | 图形前端 / 微引擎 |
| `gc_11_0_1_{mes_2,mes1}.bin` | MES（固件调度器） |
| `gc_11_0_1_imu.bin` | IMU |
| `gc_11_0_1_rlc.bin` | RLC（多 section） |
| `sdma_6_0_1.bin` | SDMA |

> **安全设计**：开头就 `shutdown -r +3` 挂 3 分钟重启看门狗，
> 正常结束会 `killall shutdown`。PSP 卡死时机器会自己重启，不会一直黑屏。

固件从 [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)
的 `amdgpu/` 取，本仓库不含二进制。

### `full.sh` — 完整 bring-up 到 MES

`bringup5.sh` 的上一层：上电 → 开门铃 → 解除 CP halt →
`mesboot gart` → `mesboot mes` → 按环境变量跑指定步骤。带 4 分钟重启看门狗。

### `kinst.sh` — 重建 Auxiliary Kernel Collection

`PhxAccel` 装在 `/Library/Extensions/`，属 **Aux KC**，改完源码必须重建：

```sh
sudo BK=/Users/Shared/gpu/backup ./kinst.sh
```

流程：`kmutil create -n aux` → **校验**（`kmutil inspect` 里必须出现
`com.luuumi.PhxAccel`，缺一个就不发布）→ 备份旧 KC → 覆盖。

> 校验很关键：KC 半成品直接覆盖会导致**开不了机**。脚本宁可失败也不发布。

---

## 三、`vtdec-guard.sh` — 动态壁纸解码看门狗

Tahoe 动态壁纸（170 MB HEVC）在无硬件解码的机器上走纯 CPU 软解，
`VTDecoderXPCService` 会持续占 90%+ CPU。

脚本每 60 s 采一次 CPU，**连续 3 次超过 50%** 才杀掉（避免误杀正常解码），
之后 `WallpaperAgent` 会在下次空闲时重新拉起。

```sh
sudo cp vtdec-guard.sh /usr/local/bin/ && sudo chmod 755 /usr/local/bin/vtdec-guard.sh
sudo cp local.vtdecguard.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/local.vtdecguard.plist
```

日志 `/var/log/vtdec-guard.log`，阈值可用环境变量调：
`VTDEC_THRESH`（默认 50）、`VTDEC_STRIKES`（3）、`VTDEC_INTERVAL`（60）。

实测效果：`WindowServer` 28.8% → 9.8%，load 4.66 → 3.14。
详见 [docs/04](../docs/04-已知问题.md) 2.6。

---

## 四、`memtest.c` — 内存压力测试

诊断内核 panic 时用来**排除内存条故障**。纯 C、无外部依赖。

```sh
clang -O2 -o memtest memtest.c
./memtest 16 3     # 每块 16 GB，跑 3 轮
```

原理：`malloc` + `memset` 触碰所有页 → 四种固定模式填充 →
**逐字节读回比对**，任何一位不一致都计错。

本机实测：4GB×2 + 16GB×3 + 32GB×1，累计约 **350 GB 读写，零位翻转**
→ 排除内存故障，把 panic 嫌疑锁定到 GPU 驱动。

---

## 五、AppleIGC 自编译工具

`build-appleigc.sh` + `kmod_info.c`，用于手工编译 `AppleIGC.kext`。

```sh
git clone https://github.com/SongXiaoXi/AppleIGC.git ~/AppleIGC-src
# 打两个补丁（见 patches/AppleIGC-源码修改.md）
bash build-appleigc.sh
```

必守的两条（都踩过）：

| 规则 | 违反后果 |
|---|---|
| `CFBundleVersion` 必须纯数字点分（`1.9.2`） | 内核**静默拒绝加载** |
| 必须由 `kmod_info.c` 提供 `_kmod_info` | 加载失败，符号表比官方少 1 个 |

**不要**加 `ld ... -exported_symbol _kmod_info`（会把导出符号砍成 1 个）。

完整踩坑见 [patches/AppleIGC-源码修改.md](../patches/AppleIGC-源码修改.md)。

---

## 六、`gpuclk.sh` + `gpucg.sh` — GPU 限频与时钟门控

**来源**：[QiRanChenk/MECHREVO-WUJIE15XA-8745HS-Hackintosh](https://github.com/QiRanChenk/MECHREVO-WUJIE15XA-8745HS-Hackintosh)
（8745HS + 780M，同代硬件）的 `tools/gpuclk` 与 `tools/gpucg`。

**背景**：`nullarc` 让 780M 的 GFX 时钟**固定 2600 MHz**（多耗约 25 W），
并且所有时钟门控都保持复位默认值。

**做法**：

```sh
# 1. SMU SetSoftMaxGfxClk(0x1B) 把上限压到 800 MHz
phxctl smu 0x1b 800
phxctl smu 0x17 0

# 2. 打开 MGCG / CGCG / CGLS（约 2 W）
gpucg.sh all        # status | mgcg | cgcg | all | off
```

**本机实测**（GEM12，2160×1440）：

| 指标 | 限频前 | 限频后 |
|---|---|---|
| 帧率 | 47 fps | **47 fps**（无变化） |
| `WindowServer` CPU | 13.1% | 14.1% |
| 桌面观感 | — | 无可感知差异 |

> SMU 返回 `resp 0x01 (OK) out 0x320`（0x320 = 800）即生效。

**不会解决**的问题（别抱期望）：
`SafeEjectGPUService` 仍会卡死 100% CPU —— 那是 nullarc 的 ioctl 缺陷，与 GPU 负载无关。

**跳过开关**：

| 文件 | 作用 |
|---|---|
| `/Users/Shared/gpu/gpuclk-off` | 整体跳过限频 |
| `/Users/Shared/gpu/gpucg-off` | 只跳过时钟门控 |

频率可用环境变量覆盖：`GPUCLK_MHZ=1600`。

**安装**：

```sh
sudo mkdir -p /usr/local/libexec
sudo cp gpuclk.sh /usr/local/bin/ && sudo chmod 755 /usr/local/bin/gpuclk.sh
sudo cp gpucg.sh  /usr/local/libexec/ && sudo chmod 755 /usr/local/libexec/gpucg.sh
sudo cp local.gpuclk.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/local.gpuclk.plist
sudo launchctl load -w /Library/LaunchDaemons/local.gpuclk.plist
```

日志 `/var/log/gpuclk.log`。
脚本会在 `NMXAccel` 出现后再等 15 秒才动手，避免和 `phxboot` 抢寄存器。

---

## 七、`phxctl/` 与 `mesboot`

nullarc 源码树里编译出来的用户态调试工具（`phxctl` 约 18 KB、`mesboot` 约 59 KB），
通过 `sysctl`/ioctl 直接操作 GPU 寄存器，**本仓库不含二进制**。

```sh
cd nullarc/src/phxctl   && make   # 产出 phxctl
cd nullarc/src/mesboot  && make   # 产出 mesboot
```

装到 `~/gpu/phxctl/`，`bringup5.sh` / `full.sh` 按这个路径调用。

---

## 八、路径约定

所有脚本假设 `$HOME=/Users/Shared`、工作目录 `$G=/Users/Shared/gpu`。
`phxboot.sh` 里显式 `export HOME=/Users/Shared`（LaunchDaemon 默认 `HOME` 是 `/var/root`）。

移植时改这几处：

| 脚本 | 变量 |
|---|---|
| `phxboot.sh` | `G`、`LOG`、`MARK`、`OFF`、`ALLOW`、`DR` |
| `bringup5.sh` / `full.sh` | 把 `~/gpu/...` 改成 `$G` |
| `kinst.sh` | `KC`、`BK` |
