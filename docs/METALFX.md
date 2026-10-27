# MetalFX Spatial：720p 原生宽屏到高分辨率输出

2026-10-18。图形后端已经实现真正的 Apple MetalFX Spatial，使用 `MTLFXSpatialScalerDescriptor` 和 `encodeToCommandBuffer:`。没有用普通双线性缩放替代 MetalFX，也没有帧生成或时域重建。

## 启动与前端接入契约

- 启动前设置 `DM_METALFX=spatial`；`off` 或未设置时继续常规呈现。
- `mtl_set_metalfx(int)` 可切换呈现路径，但不会改变游戏渲染尺寸或相机。
- 游戏/前端负责实际的原生宽屏几何和渲染分辨率。Mac 启动器由 `DM_MAC_DISPLAY_MODE=normal|wide|wider` 选择 1600×900 / 1568×720 / 1920×720；iOS 仍使用 `DM_IOS_GRAPHICS_MODE` 与 `DM_GAME_RES=1920x720` 的单档宽屏。后端不修改游戏 shader、c1、原始链 `87c50a868147`、相机投影或 NVN render target 尺寸。
- 前端负责 `CAMetalLayer.drawableSize`。后端直接使用实际 drawable 尺寸，不硬编码 16:9 或 4K。macOS 的 MetalFX drawable 为 normal 2560×1440、wide 2560×1176、wider 2560×960；2048×940 的宽屏尺寸也已验证。应根据实际屏幕比例计算尺寸。
- macOS/iOS 目标必须链接 `MetalFX.framework`。当前 backend 使用 Metal 4 呈现队列，目标系统仍为 macOS/iOS 26。

**`content=1920x720` 的 MetalFX 日志只证明 upscaler 输入区域是 720 高；它本身不能证明游戏的全部渲染目标已经降到 720p。** 实际分辨率、相机宽屏和性能还需要游戏路径与设备日志共同验收。

## 图形实现

生产代码在 `third_party/nxnative/dm/gfx/nvn/nvn_metalfx_spatial.h` 和 `nvn_mtl.m` 的 `present_metalfx()` / `present_encode_m4()`。

1. 保留 NVN 声明的有效 crop，包括非零起点。先按 1:1 最近点采样提取有效区域并转换到独立 BGRA8Unorm 输入，不改变游戏纹理，也不读取 allocation 中的无效边缘。
2. 输入和输出使用分开的 private 纹理，分别包含 scaler 的 `colorTextureUsage` / `outputTextureUsage`，输入增加 RenderTarget，输出增加 ShaderRead。不能直接假设 CAMetalDrawable 具备 MetalFX 所需使用标志。
3. 使用 Perceptual 色彩模式。`present_raw_src()` 先将 sRGB 纹理变成相同存储的非 sRGB view，避免额外解码；BGRA8Unorm 输入/输出保留游戏 scan-out 的感知编码字节，不重复 gamma 转换。当前明确支持 SDR 2D RGBA/BGRA Unorm 源和 SDR Unorm drawable；其他格式有可见的常规呈现回退。
4. Metal 4 游戏队列 signal 共享事件，经典 MetalFX command buffer wait 后执行 1:1 提取和 Spatial，再 signal 完成事件；Metal 4 呈现队列 wait 后读取真正的放大结果。正常路径没有 CPU GPU 等待或私有 selector。
5. 三个呈现 slot 各有自己的 scaler、输入和输出。原有 present ticket 完成后才能复用对应 slot；尺寸变化也在该安全点重新分配并更新 residency。最终呈现只应用一次原始画面方向翻转。

原生宽屏源与 drawable 比例相符（宽度对齐产生的差异小于 1%）时，输出使用整个 drawable，不留黑边。比例真的不符时，按原比例 fit，不能把拉伸的 16:9 场景叫作原生宽屏。前端必须提供相应的宽屏相机和有效源区域。

设备不支持、输入/输出格式不合或没有上采样时有明确日志，继续正常呈现；不会宣称 MetalFX 已经工作。分配/编码失败会禁用本轮 Spatial，避免每帧重试导致更多压力。异步 GPU 错误会记录并释放事件等待，后续帧回退；该错误路径尚未做故障注入验证。

## 验证

```sh
clang -O1 -Wall -fobjc-arc tests/test_metalfx_spatial.m -framework Foundation -framework Metal -framework MetalFX -o work/test-metalfx-spatial
work/test-metalfx-spatial
```

已在本机 M3 Max 的真实 MetalFX 上通过：

- 1568×720（Mac `wide`）到 2560×1176 与 2048×940 的尺寸检查。
- 三 slot 重复使用和全部输出尺寸变化。
- 非零 crop，排除 allocation 外围的洋红哨兵像素。
- sRGB raw view、RGBA→BGRA 顺序、感知色阶和上下两半不同内容，共 336 个独立颜色通道检查。
- Metal 4 producer 被测试门延迟，classic MetalFX 必须等待，再由 Metal 4 consumer 回读，覆盖跨队列排序。
- 比例不匹配时保留源比例；越界 crop、非上采样和未经 raw view 转换的 sRGB 输入被拒绝。
- 完整 `nvn_mtl.m` 对 macOS 和 iPhoneOS SDK 的语法检查通过。

测试没有打开窗口、启动/重启游戏、安装应用、截图或向正在游玩的 iPhone 注入输入。独立 Mac GPU 测试不能证明 iPhone 已运行、画面观感合格或实战达到 60 FPS。

## 性能与诊断边界

首次创建 scaler、变更尺寸可能有一次性成本；稳定状态复用纹理、scaler 和现有三槽呈现资源。没有额外 CPU readback、全帧 CPU 像素复制或每帧分配输出纹理。

日志中的 `Spatial ... content=... output=... canvas=... perceptual ...` 表示真实 scaler 已创建；`completed=...` 表示其 GPU command 已成功完成。`average-command-GPU-span` 是含输入提取的完整 command GPU 时间，不能当作孤立 MetalFX 算法耗时，也不能代替前台真实上屏间隔。

`DM_NVN_SHOT` / `grab_present` 等原有经典调试截图目前仍走常规诊断呈现路径，不代表用户最终看到的 MetalFX 输出；本轮没有使用这些截图工具做 MetalFX 画质结论。

下一步设备验收应记录真实场景 RT、有效源、drawable/MetalFX 输出尺寸、前台上屏间隔、GPU command span、内存和温度变化。用户目前的 iPhone 会话没有被本次后端工作改变。
