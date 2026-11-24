#!/bin/bash
# gpuclk: 限制 780M 频率并启用时钟门控。
#
# 来源：MECHREVO WUJIE15XA 项目（8745HS + 780M，同代硬件）的 tools/gpuclk + tools/gpucg
#   https://github.com/QiRanChenk/MECHREVO-WUJIE15XA-8745HS-Hackintosh
#
# 背景：nullarc 让 GGX 时钟固定 2600 MHz（多耗约 25 W），且所有时钟门控都保持复位值。
# 本脚本用 SMU 消息 SetSoftMaxGfxClk(0x1B) 把上限压到 800 MHz，
# 再调 gpucg.sh 打开 MGCG/CGCG/CGLS（约 2 W）。
#
# GEM12 实测：限频前后帧率都是 47 fps（2160×1440），桌面无可见差异。
#
# 跳过条件：/Users/Shared/gpu/gpuclk-off 存在，或 GPU 接管未启用（phxboot-off）。
exec >>/var/log/gpuclk.log 2>&1
echo "== $(date '+%F %T') gpuclk"

G=/Users/Shared/gpu
P=$G/phxctl/phxctl

[ -e "$G/gpuclk-off" ] && { echo "gpuclk-off present, skip"; exit 0; }
[ -e "$G/phxboot-off" ] && { echo "phxboot-off present, GPU not taken over, skip"; exit 0; }

# 等 GPU 合成起来（NMXAccel 出现），最多 5 分钟
for i in $(seq 1 300); do
    ioreg -rc NMXAccel -d0 2>/dev/null | grep -q NMXAccel && break
    sleep 1
done
ioreg -rc NMXAccel -d0 2>/dev/null | grep -q NMXAccel || { echo "no NMXAccel, skip"; exit 0; }

# 稳定后操作，避免和 phxboot 抢寄存器
sleep 15

CAP=${GPUCLK_MHZ:-800}
echo "capping GFX clock to ${CAP} MHz"
$P smu 0x1b "$CAP" | tail -1
$P smu 0x17 0 | tail -1

# 时钟门控
if [ -x /usr/local/libexec/gpucg.sh ] && [ ! -e "$G/gpucg-off" ]; then
    /usr/local/libexec/gpucg.sh all
fi

echo "done $(date '+%T')"
