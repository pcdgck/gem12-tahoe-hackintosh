#!/bin/bash
# Display knobs that only exist while PhxAccel is loaded (debug.* sysctls reset at every boot).
# K8's known-good combination: surface_gpu_on=0 (no residual image), dbuf=1 (double-buffered scan-out, no tearing).
for i in $(seq 1 60); do
    sysctl -n debug.nvaccel_surface_gpu_on >/dev/null 2>&1 && break
    sleep 1
done
sysctl -w debug.nvaccel_surface_gpu_on=0 >/dev/null 2>&1
sysctl -w debug.phxfb_dbuf=1 >/dev/null 2>&1
sysctl -w debug.phxfb_timing=1 >/dev/null 2>&1
