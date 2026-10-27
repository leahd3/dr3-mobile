# D3 原生宽屏与 720p 渲染配置

2026-10-18，2026-10-27 扩展为三档。实现是原始游戏的渲染尺寸、显示比例和相机投影配置，不是把 16:9 帧拉伸或裁切。macOS 启动器提供三档，iOS 仍只打包 **1920×720** 一档：

| 模式 | 打包映像 | 客体渲染尺寸 | 窗口宽高比 | MetalFX drawable |
| --- | --- | --- | --- | --- |
| `normal` | 未打补丁的 `rewrite` | 1600×900 | 16:9 | 2560×1440 |
| `wide` | `rewrite-wide`（1568×720 补丁） | 1568×720 | 1568:720 | 2560×1176 |
| `wider` | `rewrite-wider`（1920×720 补丁） | 1920×720 | 8:3 | 2560×960 |

两种 patched performance mode 各自内部使用同一尺寸。相对 16:9，相同垂直视野下 `wide` 的水平可见跨度增加 **22.5%**，`wider` 增加 **50%**。MetalFX 和最终 drawable 分辨率由显示后端单独控制。

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

`tools/mobile_graphics_profile.py` 的 `DEFAULT_WIDTH` 保持 **1920**（iOS 打包与 `verify` 的默认值）；Mac 打包显式传入宽度：

```python
from mobile_graphics_profile import launch_directory, verify
wide_dir = launch_directory(work, unique_destination, 1568, 720)
wider_dir = launch_directory(work, unique_destination, 1920, 720)
report = verify(verified_rewrite_main_bytes, width=1568, height=720)
```

Mac 的 `tools/mac_app.py` 对两个尺寸分别执行 `launch_directory`，各自 `verify` 原始已验证 rewrite bytes，并交叉核对 `graphics.json` 的 `configured_sha256` 与目录中实际 `main.patched.bin` 的哈希，然后复制到 `Contents/Resources/rewrite-wide` 与 `rewrite-wider`。

`launch_directory` 校验 main/SDK 原始 NSO 的完整 Build ID 和 SHA-256、精确配置文件哈希、成功 verification 回执，以及**完整** rewrite 工件集合及每项 SHA-256。先校验所有指令和投影/UI 证据，再创建新目录；拒绝覆盖。输出独立 `main.patched.bin`、其余原 rewrite 工件的链接和 `graphics.json`。原始 rewrite、fixups、客体身份保持不变。

纯配置器的保守数学验证范围为 height=720、width 1280..1920 且按 8 对齐；面积低于原 docked 1600×900。Mac 只打包 1568 与 1920 两档，iOS 签名宽屏固定 **1920×720**，运行时按档位词表拒绝其他配置。像素面积较低不证明所有更宽纹理步长/分配都安全。

iOS 打包器把宽屏复制作为 `mainwide` 的签名节别名，仍使用 main 的 fixups，并继续只打包 **1920×720**。`loader.c` 在 D3 iOS 构建中读取启动前的 `DM_IOS_GRAPHICS_MODE`：

- `normal` / 未设置：原始 `main` 签名节，行为不变。
- `wide`：只有原 main Build ID 前 16 字节与锁定值完全匹配才选择 `__dmmainwidex0` / `__DMmainwideW` / `__dmmainwidex1`，并按 **1920×720** 词表校验（iOS 的单档 `wide` 映射到 `wider` 词表）。
- 未知模式、未知 main build、缺失签名节、签名 text 的尺寸/aspect/投影关键字不匹配：显式失败。

Mac host 不切换签名节，而是直接读启动器选定的映像目录。`loader.c` 在映射 `main.patched.bin` 前读取 `DM_MAC_DISPLAY_MODE`，按 `normal` / `wide` / `wider` 选择词表：1568×720 映像带 1920×720 词（或反向）会立即 die，未知模式同样失败；未设置该变量时不做补丁词表校验。

选择改变的是节名称或目录；`m.name`、模块布局、重定位和游戏身份仍为 main。正常启动后不修改可执行代码。真实完整 NSO 身份由打包阶段的完整哈希校验保证；运行时另核对 fixups 中的原 Build ID 与所选尺寸的签名内容。

1568×720 的渲染面积 1,128,960 px 与 1920×720 的 1,382,400 px 都低于原 docked 1600×900 的 1,440,000 px。MetalFX 按前端给出的 drawable 尺寸输出：`wide` 为 2560×1176（约 1.633×），`wider` 为 2560×960（1.333×），相对正常模式的 2560×1440 输出在窗口/屏幕内按各自比例居中并上下留边。8:3 比 iPhone Air 的 2736:1260 更宽，显示后端只居中不拉伸或裁切。它不会把原 16:9 的水平视野冒充超宽视野。横竖屏/设备几何应在 guest 预加载前确定；运行中切换需要另行生命周期方案。

## 已完成的独立验证

```sh
.venv/bin/python -m unittest discover -s tests -p test_mobile_graphics_profile.py -v
.venv/bin/python tools/mobile_graphics_profile.py --width 1568
.venv/bin/python tools/mobile_graphics_profile.py --width 1920
```

- LLVM 独立解码确认目标寄存器、尺寸、位移和约束谓词；Unicorn 执行真实 initializer、display query、UI 尺寸与投影切片。
- 对 1280、1568、1600、1920 各执行 64 组透视和 64 组正交 normal/wide 对照，确认水平系数降低且垂直完全不变。
- 新增完整纹理查询函数的真实 PC/GOT 执行，每个尺寸配置 28 项：原版 1600×900→1280×720、首版错误的全/半/四分之一尺寸、修复后的双模式，以及无关纹理和宽高不匹配的负对照。它补充了首版验证漏掉的中间 RT 依赖；不代替运行画面回归。
- 修改范围恢复比对、原输入不变、重复配置/越界尺寸/损坏指令/损坏投影证据均拒绝。
- 打包负对照包括编辑点外的 hash 损坏、缺失工件、未知原 NSO，失败时不创建目标目录。
- C fixture 使用与 loader **同一个** `dm_d3_graphics.h`，分别以真实 1568×720 与 1920×720 配置映像验证 normal/SDK 身份、每档词表只接受本档、拒绝另一档、拒绝只改一半宽度的混合映像，以及未知 build/模式与破坏变异；另已通过 ASan/UBSan。
- `loader.c` 通过 iPhoneOS SDK 的独立 syntax-only 编译；不代表签名安装或游戏画面验收。

当前原始 rewrite SHA-256 `248e4b0b98bb6cd57ddf4f714dc9ffcd950a45593c9762dfaf7070f5941d11ba`，对应 1568×720 配置 SHA-256 `16453e873a8c86fef8048690c4584c8328fa293ff6664e1d7031d5d1d52181a5`、1920×720 配置 SHA-256 `4344e89c36aeb39e201544f15b70adea7a677e5987491a2a9db4ee8aab5d6780`。首版失败的配置 SHA 为 `1d7c9b839a87610c38b76cda3bf54732eebf830aff97f4e6acec6c4ab5ca81ba`，仅保留作失败证据。若通用 rewrite 更新，应重新生成并验证，不绕过 guard。
