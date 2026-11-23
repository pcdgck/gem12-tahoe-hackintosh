# PhxBringup.kext 源码修改（phxbringup-ptfix）

文件：`src/phxbringup/PhxBringup.cpp`

原因：每进程 GPU 页表上限 2 GiB + 显存池偏小，导致窗口捕获/截屏/锁屏崩溃。
这是 K8 项目（izerok/k8-tahoe-hackintosh）文档里描述的 `phxbringup-ptfix`。

## 修改内容

修改前：
```cpp
static constexpr uint64_t kHiTotal = 1536ull << 20;   // VRAM 池 1.5 GiB
static constexpr uint64_t kGttCap = 512ull << 20;     // GTT 512 MiB
static constexpr uint64_t kGttMaxBo = 256ull << 20;   // 单个 BO 256 MiB
// 第 187 行
static constexpr uint32_t kPtChunkBytes = 64u << 10, kPtChunkPages = kPtChunkBytes / 4096, kPtChunks = 64;
```

修改后：
```cpp
static constexpr uint64_t kHiTotal = 3840ull << 20;   // VRAM 池 3.75 GiB
static constexpr uint64_t kGttCap = 2048ull << 20;    // GTT 2 GiB
static constexpr uint64_t kGttMaxBo = 1024ull << 20;  // 单个 BO 1 GiB
static constexpr uint32_t kPtChunkBytes = 64u << 10, kPtChunkPages = kPtChunkBytes / 4096, kPtChunks = 256;
```

页表块数 64 → 256（64 KiB × 256 = 16 MiB 页表空间，可映射约 8 GiB）。

## 编译

```sh
cd src/phxbringup
chmod +x build.sh
./build.sh ~/MacKernelSDK
```