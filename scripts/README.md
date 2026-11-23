# 脚本说明

这些脚本是两天里反复调试留下的**实际工作版本**，从 GEM12 上原样导出。
路径按原机部署位置写死，移植时请一并修改。

```
/Users/Shared/gpu/            ← 工作目录（bringup5.sh、full.sh、kinst.sh、phxboot.sh、fw/、phxctl/、backup/）
/usr/local/bin/phxdisplay.sh  ← 开机 sysctl
/usr/local/bin/vtdec-guard.sh ← 动态壁纸解码看门狗
/Library/LaunchDaemons/       ← local.phxboot.plist、local.phxdisplay.plist、local.vtdecguard.plist
/Library/GPUBundles/nvmtl/    ← nvrm610.conf + Mesa RADV 的 dylib
```

---

## 一、开机链路（正常启动时自动跑）

### `local.phxboot.plist` → `phxboot.sh`

LaunchDaemon，`RunAtLoad` + `LaunchOnlyOnce`，**每次开机跑一次**。

`phxboot.sh` 做三件事：

1. **等 PhxBringup 起来**（轮询 `ioreg -l | grep '"phx-build"'`，最多 60 s）
2. **放开 GPU**：`sysctl -w debug.phxfb_hold=0`，让 `PhxAMDFB` 交还 GPU，
   GPUWrangler 才会把带加速器的 GPU 发布出去
3. **按 M2 状态决定是否 arm 显示**：写 `nvram phxfb-boot=1` 让下一次开机的
   `PhxAMDFB` 直接接管面板（否则留在固件 framebuffer）

失败保护（都在脚本里，出问题会自动降级而不是死循环）：

| 机制 | 触发条件 | 行为 |
|---|---|---|
| **pending 标记** | `/var/db/phxboot.pending` 存在 = 上次没跑完 | 建 `phxboot-off`、清 NVRAM、下次不进 M2 |
| **崩溃计数** | WindowServer 90 s 内崩 3 次 | `m2_fail`：关 PhxAMDFB + 重启回固件 framebuffer |
| **面板时序** | WindowServer 在 arm 之前就打开了面板 | `m2_fail`（这种状态**没有恢复路径**，只能重启） |
| **长期看门狗** | `watch_hangs`：5 分钟内 2 个 WindowServer `.ips` | 重启；1 小时内 3 次这种重启 → 永久退回固件 framebuffer |
| **kill switch** | 文件 `$G/phxboot-off` 存在 | 什么都不做，直接 `release` 退出 |

`watch_hangs` 是脚本末尾的后台循环（每 15 s 查一次
`/Library/Logs/DiagnosticReports/WindowServer-*.ips`）。
因为 **nullarc 还没有 GPU reset**，一次 GPU 挂死会让 WindowServer 永远等 fence，
watchdogd 杀掉它之后每个新 WindowServer 都同样挂住 —— 只能重启。

`m2_fail` 会 `rm -f $G/phxboot-m2`，所以**连续失败会自我收敛**：
先退回固件 framebuffer（能用但没 GPU 合成），不再反复重启。

> 想彻底关掉 GPU 接管：`sudo touch /Users/Shared/gpu/phxboot-off && sudo reboot`

`DENY` 变量里禁掉了 `mediaanalysisd` / `photoanalysisd` / `Spotlight`：
这几个进程会加载 MPS/Espresso 卷积核，实测**几秒内把 GPU 挂死**（2026-10-21）。
放在 CPU 上只是慢一点，不会崩。

### `local.phxdisplay.plist` → `/usr/local/bin/phxdisplay.sh`

LaunchDaemon，开机后设置 `PhxAccel` 的 debug sysctl（这些 sysctl **每次重启都会重置**）：

```sh
sysctl -w debug.nvaccel_surface_gpu_on=0   # 消残影
sysctl -w debug.phxfb_dbuf=1               # 双缓冲，防撕裂
sysctl -w debug.phxfb_timing=1             # detailed timing
```

脚本会先轮询 60 s 等 `debug.nvaccel_surface_gpu_on` 出现，说明 `PhxAccel` 已加载。

### `nvrm610.conf`

Metal 插件（`NVMTLDriver.bundle`）的运行时开关，放 `/Library/GPUBundles/nvmtl/`：

```ini
NVMTL_WS_WAIT_COMPLETION=1          # WindowServer 提交后等完成，避免撕裂
NVMTL_SCHEDULE_AFTER_SURFACE_WRITES=1
NVMTL_PIPELINE_THREADS=1            # 单线程，多线程会乱序
```

---

## 二、调试/救援工具（手动跑，需要 root）

这几个是**把 GPU 从零点亮**的分层工具。正常开机不需要它们，
只有 `PhxBringup` 没起来、或要验证某一层时才手动执行。

### `bringup5.sh` — PSP + 固件加载

按 **Linux 驱动的顺序**把 GPU 上电：

1. PSP ring 创建、TOC / TMR 载入
2. 每个引擎的固件通过 `LOAD_IP_FW` 逐个加载
3. RLC autoload
4. SMU 消息打开 GFX（`EnableGfxImu(param=1)`）

固件来自 `~/gpu/fw/`，偏移量和大小对齐 linux-firmware 的 `gc_11_0_1` / `psp_13_0_4`：

| 文件 | 用途 |
|---|---|
| `psp_13_0_4_toc.bin` | PSP 目录表 |
| `gc_11_0_1_pfp.bin` / `_me.bin` / `_mec.bin` | 图形前端 / 微引擎 |
| `gc_11_0_1_mes_2.bin` / `mes1.bin` | MES（固件调度器） |
| `gc_11_0_1_imu.bin` | IMU |
| `gc_11_0_1_rlc.bin` | RLC（多个 section） |
| `sdma_6_0_1.bin` | SDMA（两个 section） |

> **安全设计**：脚本开头就 `shutdown -r +3` 挂了个 3 分钟重启看门狗，
> 正常结束会 `killall shutdown` 取消。PSP 卡死时机器会自己重启，
> 不会一直挂在黑屏。

固件从 [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git)
的 `amdgpu/` 目录取（`gc_11_0_1_*`、`psp_13_0_4_*`、`sdma_6_0_1.bin`），
本仓库不含二进制，请自行下载。

### `full.sh` — 完整 bring-up 到 MES

`bringup5.sh` 的上一层：

```sh
bash full.sh <mesboot 步骤名>
```

依次做：上电 → 开门铃（`0xDE0`）→ 解除 CP halt（`0xA802`/`0xA803`）→
`mesboot gart`（GART 表）→ `mesboot mes`（启动 MES）→ 按环境变量跑指定的
`mesboot` 步骤（`MC` / `CS` / `ADOPT` / `GFX` / `AG` 等选项）。

同样带 **4 分钟重启看门狗**，防止 GPU 把总线挂死。

### `kinst.sh` — 重建 Auxiliary Kernel Collection

`PhxAccel` 装在 `/Library/Extensions/`，属于 **Aux KC**（不是 Boot KC）。
改完源码重新编译后必须重建 Aux KC 才生效：

```sh
sudo BK=/Users/Shared/gpu/backup ./kinst.sh
```

流程：

1. `kmutil create -n aux --allow-missing-kdk ...` 重建到 `$KC.phx-new`
2. **校验**：`kmutil inspect -a x86_64 -A $NEW` 里必须出现
   `com.luuumi.PhxAccel`（以及存在的 AppleHDA 各 bundle），缺一个就**不发布**并报错
3. 备份旧 KC 到 `$BK/aux.kc.<时间戳>`，然后才 `mv` 覆盖

> 这一步的校验很关键：KC 半成品直接覆盖会导致**开不了机**。
> 脚本宁可失败也不发布。

---

## 三、`vtdec-guard.sh` — 动态壁纸解码看门狗

**这不是 nullarc 的组件**，是无硬件解码的黑苹果的通用补丁。

Tahoe 的动态壁纸 `Tahoe Day`（170 MB HEVC）在没有硬件解码器的机器上
走纯 CPU 软解，`VTDecoderXPCService` 会持续占 90%+ CPU、4 GB 内存不释放。
详见 [docs/04-已知问题.md](../docs/04-已知问题.md) 2.6。

`vtdec-guard.sh` 每 60 s 采一次 `VTDecoderXPCService` 的 CPU，
**连续 3 次超过 50%** 才杀掉（避免误杀正常解码），
然后 `WallpaperAgent` 会在下次空闲时重新拉起 —— 新进程通常不再进死循环。

```sh
# 安装
sudo cp vtdec-guard.sh /usr/local/bin/
sudo chown root:wheel /usr/local/bin/vtdec-guard.sh
sudo chmod 755 /usr/local/bin/vtdec-guard.sh
sudo cp local.vtdecguard.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/local.vtdecguard.plist
sudo launchctl load -w /Library/LaunchDaemons/local.vtdecguard.plist
```

日志 `/var/log/vtdec-guard.log`，阈值可用环境变量调：

| 变量 | 默认 | 含义 |
|---|---|---|
| `VTDEC_THRESH` | `50` | 触发阈值（%CPU） |
| `VTDEC_STRIKES` | `3` | 连续几次超阈值才动手 |
| `VTDEC_INTERVAL` | `60` | 采样间隔（秒） |

实测效果（杀掉后）：`WindowServer` 28.8% → 9.8%，load 4.66 → 3.14。

**更彻底的办法**（推荐，但需要图形界面）：
系统设置 → 墙纸 → 把**「锁屏」**那一项也改成静态图片。
只改桌面不够 —— `Desktop` 和 `Idle` 是两套独立配置。

---

## 四、`phxctl/` 与 `mesboot`

`phxctl` 和 `mesboot` 是 nullarc 源码树里编译出来的用户态调试工具
（`phxctl` 约 18 KB、`mesboot` 约 59 KB），
通过 `sysctl`/ioctl 直接操作 GPU 寄存器，**本仓库不含二进制**。

从 [luuumi-dev/nullarc](https://github.com/luuumi-dev/nullarc) @ `3497d87` 编译：

```sh
cd nullarc/src/phxctl   && make   # 产出 phxctl
cd nullarc/src/mesboot  && make   # 产出 mesboot
```

装到 `~/gpu/phxctl/`，`bringup5.sh` / `full.sh` 按这个路径调用。

---

## 五、脚本里的路径约定

所有脚本假设 `$HOME=/Users/Shared`、工作目录 `$G=/Users/Shared/gpu`。
`phxboot.sh` 里显式 `export HOME=/Users/Shared`，
因为 LaunchDaemon 的默认 `HOME` 是 `/var/root`。

移植到别的机器时，把这几处一起改：

| 位置 | 变量 |
|---|---|
| `phxboot.sh` | `G`、`LOG`、`MARK`、`OFF`、`ALLOW`、`DR` |
| `bringup5.sh` / `full.sh` | `~/gpu/...`（改用 `$G` 更安全） |
| `kinst.sh` | `KC`、`BK` |
