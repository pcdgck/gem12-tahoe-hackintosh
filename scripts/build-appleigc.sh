#!/bin/bash
# 手动编译 AppleIGC（只有 CLT，没有完整 Xcode）
# 关键点：必须提供 _kmod_info 符号，否则内核拒绝加载
set -u
SDK="$HOME/MacKernelSDK"
SRC="$HOME/AppleIGC-src/AppleIGC"
OUT="/tmp/igcbuild"
rm -rf "$OUT"; mkdir -p "$OUT"

COMMON="-target x86_64-apple-macos10.15 -arch x86_64 \
  -mkernel -nostdinc -nostdlib -fno-builtin -fno-common -fno-exceptions -fno-rtti \
  -I $SDK/Headers -I $SRC -I $SRC/igc \
  -D KERNEL=1 -D __KERNEL__=1 -D APPLE_KEXT=1 -D __PRIVATE_SPI__=1 \
  -O2 -w"

echo "=== [1/5] 编译 AppleIGC.cpp ==="
clang++ $COMMON -std=gnu++17 -fapple-kext -c "$SRC/AppleIGC.cpp" -o "$OUT/AppleIGC.o" 2>&1 | head -30
[ ${PIPESTATUS[0]} -ne 0 ] && { echo "C++ 编译失败"; exit 1; }
echo "  OK"

echo "=== [2/5] 编译 igc/*.c ==="
for n in igc_base igc_i225 igc_mac igc_nvm igc_phy; do
    clang $COMMON -std=gnu11 -c "$SRC/igc/$n.c" -o "$OUT/$n.o" 2>&1 | head -10
    [ ${PIPESTATUS[0]} -ne 0 ] && { echo "  $n 失败"; exit 1; }
    echo "  $n OK"
done

echo "=== [3/5] 编译 kmod_info.c（提供 _kmod_info 符号）==="
clang $COMMON -std=gnu11 -c /tmp/kmod_info.c -o "$OUT/kmod_info.o" 2>&1 | head -20
[ ${PIPESTATUS[0]} -ne 0 ] && { echo "kmod_info 编译失败"; exit 1; }
nm "$OUT/kmod_info.o" | grep -i 'kmod_info' && echo "  符号已生成"

echo "=== [4/5] ld -kext 链接 ==="
ld -kext -arch x86_64 -exported_symbol _kmod_info \
   -o "$OUT/AppleIGC.kextbin" "$OUT"/*.o 2>&1 | head -20
[ ${PIPESTATUS[0]} -ne 0 ] && { echo "链接失败"; exit 1; }
file "$OUT/AppleIGC.kextbin"
echo "  _kmod_info: $(nm -gU "$OUT/AppleIGC.kextbin" 2>/dev/null | grep -c _kmod_info)"

echo "=== [5/5] 组装 kext ==="
K=/tmp/AppleIGC-patched.kext
rm -rf $K; mkdir -p $K/Contents/MacOS
cp "$OUT/AppleIGC.kextbin" $K/Contents/MacOS/AppleIGC
cp /Users/Shared/gpu/backup/AppleIGC-v1.9.kext/Contents/Info.plist $K/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1.9-gem12c' $K/Contents/Info.plist >/dev/null 2>&1
plutil -lint $K/Contents/Info.plist
echo "版本: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $K/Contents/Info.plist)"

echo
echo "=== 符号对比（官方 vs 我们）==="
printf 'exported:  official=%s  ours=%s\n' \
  "$(nm -gU /Users/Shared/gpu/backup/AppleIGC-v1.9.kext/Contents/MacOS/AppleIGC 2>/dev/null | wc -l | tr -d ' ')" \
  "$(nm -gU "$OUT/AppleIGC.kextbin" 2>/dev/null | wc -l | tr -d ' ')"
printf 'undefined: official=%s  ours=%s\n' \
  "$(nm -u /Users/Shared/gpu/backup/AppleIGC-v1.9.kext/Contents/MacOS/AppleIGC 2>/dev/null | wc -l | tr -d ' ')" \
  "$(nm -u "$OUT/AppleIGC.kextbin" 2>/dev/null | wc -l | tr -d ' ')"
