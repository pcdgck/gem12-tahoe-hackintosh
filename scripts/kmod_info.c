/* GEM12: 手动提供 kext 必需的 kmod_info 符号。
 *
 * 用 `ld -kext` 手工链接（没有完整 Xcode）时，链接器不会自动生成
 * `_kmod_info`，导致内核拒绝加载（kextlibs 会显示缺少该符号）。
 *
 * KMOD_EXPLICIT_DECL 展开成一个 kmod_info_t 结构体，符号名固定为 `kmod_info`。
 * start/stop 传 0 —— IOKit kext 走 OSKext/IOKit 的加载路径，不用 kmod 风格的入口。
 */
#include <mach/kmod.h>

KMOD_EXPLICIT_DECL(com.sxx.AppleIGC, "1.9-gem12b", 0, 0);
