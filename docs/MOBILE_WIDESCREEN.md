# D3 原生宽屏与 720p 渲染配置

2026-10-18。实现是原始游戏的渲染尺寸、显示比例和相机投影配置，不是把 16:9 帧拉伸或裁切。当前固定 iPhone 宽屏配置为 **1920×720，aspect=8/3≈2.66667**；两种 performance mode 使用同一尺寸。相对 16:9，相同垂直视野下的水平可见跨度增加 **50%**。MetalFX 和最终 drawable 分辨率由显示后端单独控制。

首轮实机宽屏出现嵌套矩形、清屏底色和右/下黑区，**未通过运行验收**。随后独立 Mac 宽屏在关闭 MetalFX 时也复现，说明故障先于最终上屏。已定位并修复漏掉的 handheld 纹理尺寸查询转换，见下节；修复版本仍需实际画面回归，不能把先前投影数学通过当作整条渲染链通过。本轮没有操作正在运行的设备、存档或窗口。

## 精确构建与静态数据流

只支持 `config/diablo3-2.7.7.json` 锁定的 D3 `2.7.7.92380`：

- main Build ID：`2607a74f5df7754cc0357b5df7e496931355d8ca000000000000000000000000`
- main NSO SHA-256：`7f3910c7a15d4bc053cdc8204f1abcac526c57f205c584d1d97779a1a10a98c3`
- SDK Build ID：`3ae34e689d7a35f13cbf42bfd672af8b5eb64a9d000000000000000000000000`
- SDK NSO SHA-256：`21e08d575abd8cb08ba1ab3be3fa92c02a1384428f161e8e88eb578e897f2c0b`

本地原始 NSO 解码映像经动态重定位、AArch64 指令及调用关系追踪，得到以下链路；私有汇编证据保存在 `work/audit/widescreen/`。

| 原始 main 地址 | 已确认作用 |
| --- | --- |
| `0xe7858..0xe7874` | 初始化 renderer 全局 `main+0x179bc58`：docked 1600×900、handheld 1280×720、显示 aspect=16/9 |
| `0xea0e0` | 按 performance mode 选择尺寸，复制到 display info 的多组 width/height，aspect 在 `+0x34` |
| `0x29a7f0` | 读取引擎 display info `+0x258` 的 aspect |
| `0x266740` / `0x2667d0` | 从 display aspect 设置相机 `+0x48`，然后更新投影 |
| `0x29b7e8` | 透视投影水平系数为 `cot(verticalFov/2)/aspect`；垂直系数保持同一 cot 值 |
| `0x29b840..0x29b85c` | 正交投影水平系数 `2/(height*aspect)`，垂直为 `2/height` |
| `0x29a2f4` / `0x29b15c` | display width/height 进入 UI 逻辑尺寸 `+0x44f4/+0x44f0` |
| `0x29b8b0` | UI 像素投影使用 `2/width`、`-2/height`，没有沿用固定 16:9 投影矩阵 |
| `0x29b480` | flag bit 5 且显示比例偏离 16:9 时启用原版比例约束；其相机/UI 消费者会回退 16:9 |
| `0xebac0` / `0xebb48` | 对匹配 docked 全/半/四分之一的纹理，在 handheld 下返回尺寸×0.8；同尺寸双模式配置必须同步改为×1.0 |

宽屏配置仅修改 9 个已锁定指令：双模式 width/height、float aspect 的两条装载、约束谓词入口的 `return false`，以及**该纹理查询函数**的 0.8 装载改为 1.0。没有修改全局 0.8 常量、全局替换 16:9、FOV 值、深度参数、原版 UI 常量或未知辅助相机。

## 首轮运行失败与修复依据

原本 docked 1600×900 与 handheld 1280×720 的尺寸关系是 4/5；游戏不只在显示初始化中保存两个尺寸，还在 `0xebac0` 的纹理查询中隐含这项关系。查询识别 docked 全尺寸、半尺寸、四分之一尺寸纹理；当前 performance mode 为 handheld 时用固定 0.8 返回有效尺寸。首版 profile 把两模式改成同样 1568×720，却漏掉了这条转换，导致真实 RT 与查询结果不同：

| 真实纹理 | 首版错误查询 | 修复后查询 |
| --- | --- | --- |
| 1568×720 | 1254×576 | 1568×720 |
| 784×360 | 627×288 | 784×360 |
| 392×180 | 313×144 | 392×180 |

查询结果在 `0x29c30c` 之后用于 render-target viewport，在 `0x1229d0` / `0x123070` 之后用于 UV 归一化，所以错误不只影响交换链裁切，会污染中间合成。实机图中的约 80% 清屏矩形/重复场景与这项数据流相符；Mac 的 FX-off 复现进一步排除了“仅 MetalFX 拉伸错误”的解释。

另已追到 `0xe6dd0..0xe6e90` 的实际 NVN 纹理 alias 分配：它直接从 renderer 全局 `+8/+0xc` 读取 handheld 尺寸，半/四分之一再右移；该分配路径没有另一个隐含 0.8。因此首版实际分配已经是新尺寸，查询函数却仍报告旧比例，形成具体的不一致。相关证据在 `texture-allocation.asm`；没有因此随意改写分配预算或所有缩放常量。

修复只在已验证的同尺寸双模式配置图像中，把 `0xebb48: LDR s1,[...,0.8]` 改为 `FMOV s1,1.0`。普通原始游戏映像和所有其他引用同一 0.8 常量的逻辑保持原状。签名宽屏运行时 guard 同时新增该 word，拒绝误装首版 wide。

原始 `work/rewrite/main.params.tsv` 没有 resolution/aspect 参数位，因此旧宿主里的 `DM_GAME_RES` 不能单独驱动本作宽屏。

## 构建与加载接口

`tools/mobile_graphics_profile.py`：

```python
from mobile_graphics_profile import launch_directory, verify
wide_dir = launch_directory(work, unique_destination, 1920, 720)
report = verify(original_verified_main_bytes, width=1920, height=720)
```

`launch_directory` 校验 main/SDK 原始 NSO 的完整 Build ID 和 SHA-256、精确配置文件哈希、成功 verification 回执，以及**完整** rewrite 工件集合及每项 SHA-256。先校验所有指令和投影/UI 证据，再创建新目录；拒绝覆盖。输出独立 `main.patched.bin`、其余原 rewrite 工件的链接和 `graphics.json`。原始 rewrite、fixups、客体身份保持不变。

纯配置器的保守数学验证范围为 height=720、width 1280..1920 且按 8 对齐；面积低于原 docked 1600×900。但 iOS 当前签名宽屏选项固定 **1920×720**，运行时 guard 拒绝其他配置。像素面积较低不证明所有更宽纹理步长/分配都安全。

iOS 打包器把宽屏复制作为 `mainwide` 的签名节别名，仍使用 main 的 fixups。`loader.c` 只在 D3 iOS 构建中读取启动前的 `DM_IOS_GRAPHICS_MODE`：

- `normal` / 未设置：原始 `main` 签名节，行为不变。
- `wide`：只有原 main Build ID 前 16 字节与锁定值完全匹配才选择 `__dmmainwidex0` / `__DMmainwideW` / `__dmmainwidex1`。
- 未知模式、未知 main build、缺失签名节、宽屏 text 的尺寸/aspect/投影关键字不匹配：显式失败。

选择改变的是节名称；`m.name`、模块布局、重定位和游戏身份仍为 main。正常启动后不修改可执行代码。真实完整 NSO 身份由打包阶段的完整哈希校验保证；运行时另核对 fixups 中的原 Build ID 与宽屏签名内容。

1920×720 的渲染面积 1,382,400 px 仍低于原 docked 1600×900 的 1,440,000 px；MetalFX 以 1.333× 倍放大到 2560×960，相对正常模式的 2560×1440 输出，在窗口/屏幕内按 8:3 居中并上下留边。8:3 比 iPhone Air 的 2736:1260 更宽，显示后端只居中不拉伸或裁切。它不会把原 16:9 的水平视野冒充超宽视野。横竖屏/设备几何应在 guest 预加载前确定；运行中切换需要另行生命周期方案。

## 已完成的独立验证

```sh
.venv/bin/python -m unittest discover -s tests -p test_mobile_graphics_profile.py -v
.venv/bin/python tools/mobile_graphics_profile.py --width 1920
```

- LLVM 独立解码确认目标寄存器、尺寸、位移和约束谓词；Unicorn 执行真实 initializer、display query、UI 尺寸与投影切片。
- 对 1280、1600、1920 各执行 64 组透视和 64 组正交 normal/wide 对照，确认水平系数降低且垂直完全不变。
- 新增完整纹理查询函数的真实 PC/GOT 执行，每个尺寸配置 28 项：原版 1600×900→1280×720、首版错误的全/半/四分之一尺寸、修复后的双模式，以及无关纹理和宽高不匹配的负对照。它补充了首版验证漏掉的中间 RT 依赖；不代替运行画面回归。
- 修改范围恢复比对、原输入不变、重复配置/越界尺寸/损坏指令/损坏投影证据均拒绝。
- 打包负对照包括编辑点外的 hash 损坏、缺失工件、未知原 NSO，失败时不创建目标目录。
- C fixture 使用与 iOS loader **同一个** `dm_d3_graphics.h`，验证 normal/SDK 身份、未知 build/模式拒绝、真实配置映像关键字与破坏变异；另已通过 ASan/UBSan。
- `loader.c` 通过 iPhoneOS SDK 的独立 syntax-only 编译；不代表签名安装或游戏画面验收。

当前原始 rewrite SHA-256 `05e9888c3a766d966ceb4c6e3c67de200027673a9310f840b6a0f6e850458e4d`，对应修复后的 1920×720 配置 SHA-256 `df6148a9175765db0c5864d0b73aafef03258e247af00ac74849b765743dbda7`。首版失败的配置 SHA 为 `1d7c9b839a87610c38b76cda3bf54732eebf830aff97f4e6acec6c4ab5ca81ba`，仅保留作失败证据。若通用 rewrite 更新，应重新生成并验证，不绕过 guard。
