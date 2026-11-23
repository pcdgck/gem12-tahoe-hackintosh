# PhxAccel.kext 源码修改（基于 luuumi-dev/nullarc @ 3497d87 + K8 vbl-timing 补丁）

以下三处修改是让 GEM12（迷你主机，仅外接 HDMI）能用 GPU 合成的关键。

## 1. 主 head 提供 EDID

文件：`src/phxaccel/accel/phxfb.cpp`

原因：CoreDisplay 创建显示设备时必须能读到 EDID，否则 WindowServer 在
`CoreDisplay_CreateDisplayForCGXDisplayDevice` 断言失败。原代码主 head 的
`hasDDCConnect` 返回 false、`getDDCBlock` 返回 unsupported。

修改前：
```cpp
bool hasDDCConnect(IOIndex) override { return false; }
IOReturn getDDCBlock(IOIndex, UInt32, IOSelect, IOOptionBits, UInt8 *, IOByteCount *) override { return kIOReturnUnsupported; }
```

修改后：
```cpp
bool hasDDCConnect(IOIndex idx) override { return idx == 0; }
IOReturn getDDCBlock(IOIndex idx, UInt32 block, IOSelect select, IOOptionBits, UInt8 *data, IOByteCount *length) override {
    if (idx != 0 || block != 0 || !data || !length || select != kIODDCBlockTypeEDID) return kIOReturnBadArgument;
    static const uint8_t kConsoleEdid[128] = {
        0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x1e, 0x6d, 0x55, 0x25, 0x01, 0x01, 0x01, 0x01,
        0x01, 0x20, 0x01, 0x03, 0x80, 0x35, 0x1e, 0x78, 0xea, 0xee, 0x95, 0xa3, 0x54, 0x4c, 0x99, 0x26,
        0x0f, 0x50, 0x54, 0xa5, 0x4b, 0x00, 0x71, 0x4f, 0x81, 0x80, 0x81, 0xc0, 0x01, 0x01, 0x01, 0x01,
        0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02, 0x3a, 0x80, 0x18, 0x71, 0x38, 0x2d, 0x40, 0x58, 0x2c,
        0x45, 0x00, 0x10, 0x09, 0x00, 0x00, 0x00, 0x1e, 0x00, 0x00, 0x00, 0xfd, 0x00, 0x30, 0x4b, 0x1e,
        0x50, 0x0f, 0x00, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0xfc, 0x00, 0x47,
        0x32, 0x35, 0x35, 0x46, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0xff,
        0x00, 0x32, 0x30, 0x32, 0x36, 0x31, 0x31, 0x30, 0x39, 0x30, 0x30, 0x31, 0x0a, 0x20, 0x00, 0x68
    };
    const IOByteCount n = *length < 128 ? *length : 128;
    bcopy(kConsoleEdid, data, n);
    *length = n;
    PFBLOG("EDID: served %u bytes for connection %u", (unsigned)n, (unsigned)idx);
    return kIOReturnSuccess;
}
```

## 2. PWM 不可用时仍创建背光处理器

文件：`src/phxaccel/accel/phxfb.cpp`（`PhxAMDFB::start()`）

原因：CoreDisplay::Display 构造时会调用 InitializeBrightnessControl。外接显示器没有
PWM 背光，原代码直接跳过创建 PhxBacklight，导致 CoreDisplay 拿不到亮度控制对象。

修改前：
```cpp
uint32_t bl = 0;
if (PE_parse_boot_argn("-phxbloff", arg, sizeof arg)) PFBLOG("backlight: -phxbloff, no brightness control");
else if (!backlightRead(&bl)) PFBLOG("backlight: the PWM is not running (no MMIO view, or off), no brightness control");
else if (!(fBacklight = phxBacklightCreate(this))) PFBLOG("backlight: the handler would not attach");
else PFBLOG("backlight: PWM at %u of %u", bl, kBlMax);
```

修改后：
```cpp
uint32_t bl = 0;
if (PE_parse_boot_argn("-phxbloff", arg, sizeof arg)) {
    PFBLOG("backlight: -phxbloff, no brightness control");
} else if (!backlightRead(&bl)) {
    PFBLOG("backlight: the PWM is not running (no MMIO view, or off) -- offering a fixed level anyway");
    fBlSaved = kBlMax;
    if (!(fBacklight = phxBacklightCreate(this))) PFBLOG("backlight: the handler would not attach");
    else PFBLOG("backlight: fixed at %u of %u", fBlSaved, kBlMax);
} else if (!(fBacklight = phxBacklightCreate(this))) {
    PFBLOG("backlight: the handler would not attach");
} else {
    PFBLOG("backlight: PWM at %u of %u", bl, kBlMax);
}
```

## 3. VRAM 池扩容（对齐 phxbringup-ptfix）

文件：`src/phxaccel/accel/phxfb.cpp`

原因：默认 VRAM 池只有 512 MB，与 PhxBringup 报告的 3840 MB 不匹配，
导致截屏/录屏等需要额外 framebuffer 的操作失败。

修改前：
```cpp
static constexpr uint64_t kVaBase = 0x100000000000ull, kVaSize = 1ull << 40, kVramCap = 1024ull << 20;
static constexpr uint64_t kPoolTry[3] = { 512ull << 20, 256ull << 20, 128ull << 20 };
```

修改后：
```cpp
static constexpr uint64_t kVaBase = 0x100000000000ull, kVaSize = 1ull << 40, kVramCap = 3840ull << 20;
static constexpr uint64_t kPoolTry[3] = { 2048ull << 20, 1024ull << 20, 512ull << 20 };
```

## 编译方式

```sh
git clone https://github.com/acidanthera/MacKernelSDK ~/MacKernelSDK
git clone --depth 1 https://github.com/luuumi-dev/nullarc
cd nullarc
git checkout 3497d87
# 应用 K8 的 vbl-timing/dbuf 补丁（见 patches/）
patch -p1 < k8-accel-vbl-timing-dbuf.patch
# 应用上述三处修改
cd src/phxaccel
chmod +x build.sh
./build.sh ~/MacKernelSDK
```