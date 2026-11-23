#!/bin/bash
# vtdec-guard: VTDecoderXPCService 的兜底看门狗。
#
# 背景：没有硬件 HEVC 解码器的黑苹果上，Tahoe 的动态壁纸（Tahoe Day.mov，170 MB HEVC）
# 会让 VideoToolbox 回落到纯 CPU 软解，VTDecoderXPCService 从开机起持续占 90%+ CPU、
# 4 GB 内存，而且不会自己停 —— 桌面换成静态图也没用，因为服务的是 Idle(锁屏) 壁纸。
# 详见 docs/04-已知问题.md 2.6。
#
# 做法：每 60 s 看一眼 VTDecoderXPCService 的 CPU。连续 3 次都超过阈值
# （默认 50%）才动手杀掉，避免误杀"短暂解码一下"的正常情况。
# 杀掉之后 WallpaperAgent 会在下次空闲时重新拉起，新进程通常不会再进死循环。
#
# 安装：
#   sudo cp vtdec-guard.sh /usr/local/bin/vtdec-guard.sh
#   sudo chown root:wheel /usr/local/bin/vtdec-guard.sh
#   sudo chmod 755 /usr/local/bin/vtdec-guard.sh
#   sudo cp local.vtdecguard.plist /Library/LaunchDaemons/
#   sudo chown root:wheel /Library/LaunchDaemons/local.vtdecguard.plist
#   sudo launchctl load -w /Library/LaunchDaemons/local.vtdecguard.plist
#
# 日志：/var/log/vtdec-guard.log

set -u
LOG=/var/log/vtdec-guard.log
THRESH=${VTDEC_THRESH:-50}   # 触发阈值（%CPU）
STRIKES=${VTDEC_STRIKES:-3}  # 连续几次超阈值才动手
INTERVAL=${VTDEC_INTERVAL:-60}

exec >>"$LOG" 2>&1

log() { echo "$(date '+%F %T') $*"; }

log "== vtdec-guard start (threshold=${THRESH}% strikes=${STRIKES} interval=${INTERVAL}s)"

# 一次采样：VTDecoderXPCService 的 %CPU（没有该进程则输出空）
sample_cpu() {
    ps -Ao pcpu=,comm= 2>/dev/null \
        | awk '/VTDecoderXPCService/ {printf "%.0f\n", $1; exit}'
}

strikes=0
while sleep "$INTERVAL"; do
    cpu=$(sample_cpu)
    if [ -z "$cpu" ]; then
        # 进程不存在：没有解码在做，正常
        strikes=0
        continue
    fi
    if [ "$cpu" -ge "$THRESH" ]; then
        strikes=$((strikes + 1))
        log "VTDecoderXPCService at ${cpu}% (strike ${strikes}/${STRIKES})"
        if [ "$strikes" -ge "$STRIKES" ]; then
            log "killing WallpaperAerialsExtension + VTDecoderXPCService (${cpu}% sustained)"
            killall WallpaperAerialsExtension 2>/dev/null
            killall VTDecoderXPCService 2>/dev/null
            strikes=0
            sleep 5
            newcpu=$(sample_cpu)
            log "after kill: VTDecoderXPCService ${newcpu:-gone}%"
        fi
    else
        [ "$strikes" -gt 0 ] && log "back to ${cpu}%, reset"
        strikes=0
    fi
done
