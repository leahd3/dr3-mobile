# iOS 启动界面与触控外观

本次为既有原生界面的延伸：启动器继承 `../bayonetta3-mobile` 的 UIKit 双栏设置布局，触控材质继承 D2R Mobile `9393b00ea9aca52d9254214da93738f26582562f` 的通用外观。本文记录已实现的界面边界，后续修改继续以源码和该引用为准。没有建立新的视觉世界，也没有将本次局部适配写成替代性的 `DESIGN.md` 或 Web 组件 token。

## 启动器

实现位于 `platform/ios/Sources/LauncherViewController.m`。

- 底色为 `systemGroupedBackgroundColor`，主文字为 `labelColor`，辅助文字为 `secondaryLabelColor`，操作强调色为 `systemIndigoColor`；分组、开关、分段选择器与按钮使用 UIKit 原生外观。颜色随系统明暗模式解析，不以截图采样色取代语义色。
- 标题、说明、副注分别使用系统 `LargeTitle`、`Title3`、`Footnote` 文本样式。自建标签允许多行并启用 `adjustsFontForContentSizeCategory`；设置行使用 `UIListContentConfiguration`。文字优先中文，按首选系统语言提供英文回退。
- 横屏两栏位于安全区域内：左右边距各 24 pt，上下各 16 pt，栏间距 24 pt；左栏宽为内容区的 38%。左栏标题与操作为独立滚动视图，右栏为独立滚动的 inset-grouped table。手机首屏以下的局域网项目属于表格滚动内容。
- 左栏常规垂直间距为 16 pt，标题后 8 pt，副标题后 24 pt。开始按钮使用原生 large filled 配置，高度至少 50 pt；画面模式选择器高度至少 44 pt，上下各留 8 pt。开关行高度至少 56 pt，采用原生 accessory switch。44 pt 是此处模式选择器的明确约束，不代表所有游戏触控目标的统一尺寸。
- 正常／宽屏、Metal HUD、MetalFX、本地 Wi-Fi 设置更改即写入 `NSUserDefaults`。宽屏或 LAN 不可用时对应控件不可选；资源不完整时开始按钮禁用并显示原因。开始操作有重复进入保护。

`main.m` 在私有资源检查及玩家选择后才切换至游戏控制器；`front_ios.m` 保留全屏输入覆盖层，正常模式将游戏画面居中适配 16:9，宽屏模式铺满游戏区域。渲染与网络参数的实际效果仍须运行验证。

## Mac 启动设置

Mac 是上述原生设置界面的 AppKit 适配，继续沿用左侧游戏身份与开始操作、右侧设置分组的阅读顺序。实现位于 `tools/mac_launcher.m`，本机打包入口为 `tools/mac_app.py`。这次延伸没有建立新的视觉系统，也没有增加 `DESIGN.md` 或 Web token sidecar。

- 使用真实 `NSWindow`、`NSBox`、`NSSegmentedControl`、原生 checkbox 与圆角开始按钮；窗口、分组表面和控件状态交由 AppKit 绘制。自建文字使用 `labelColor`／`secondaryLabelColor`，不把深色截图中的采样色写成固定色值。
- 标题使用系统字体 28 pt semibold，说明与状态使用系统字体 12 pt；分组标题与控件文字沿用 AppKit 默认排印。窗口初始内容区为 760×470 pt，最小内容区为 700×450 pt；左右边距 28 pt、上边距 28 pt、底部至少 24 pt，左栏宽 240 pt，栏间距 30 pt。左栏间距 16 pt，右侧分组间距 14 pt，分组内部间距 8 pt。最小尺寸和大字号下的实际布局尚未独立截图验收。
- 新的偏好域默认选择正常 16:9，Metal HUD、MetalFX 超分与本地 Wi-Fi 联机默认开启。正常／宽屏和三个开关立即保存至 `NSUserDefaults`；重新打开启动器可重新选择。宽屏选项依赖包内独立的 `rewrite-wide` 映像，打包时检查其配置与独立验证结果；资源缺失时该分段不可选并回到正常模式。
- 玩家选择后点击“开始游戏”（Return 快捷键）才启动游戏。启动器先设置本次画面、HUD、MetalFX 与 LAN 环境，再以 `execv` 执行新的 host 进程；重复开始受保护。源码为启动失败提供原生 `NSAlert` 并恢复开始按钮，但错误状态外观尚未截图验证。
- 正常模式说明为 1280×720、原版 16:9 视野；宽屏说明为 1920×720、扩大左右视野。MetalFX 开关会切换“超分至 2K”或“直接适配窗口”的辅助文字。`third_party/nxnative/dm/host/front_mac.m` 按所选画面比例居中显示，在窗口尺寸或 backing scale 改变时重新计算画面区域，允许留边；MetalFX 的输出目标为正常 2560×1440／宽屏 2560×960。这是源码中的显示契约，完整窗口调整与性能验收另行记录。
- 常规包使用本机原有 `work/run/save`，界面显示“存档：本机游戏进度”。私有 `tools/mac_app.py --test-session <目录>` 将既有独立存档副本路径写入 bundle 的 `DR3TestSessionRoot`，启动器显示“存档：联机测试副本”；测试包的该标记不代表常规包改用了副本。

当前有效截图是 `.impeccable/review/mac-launcher/desktop.png`（1520×1004），来自实际 AppKit 启动器的系统深色外观，可确认两栏、三个设置分组、宽屏选择、开启的图形／LAN 开关与测试存档标记均可读。早期 `initial-layout.png` 是已被替换的压缩布局，不作为当前界面依据。`.impeccable/review/mac-launcher/finish-review.json` 的 `ship` 只覆盖 Mac 启动器 UI；本次另有宽屏选择持久化及 MetalFX 关闭／开启辅助文字的运行检查。浅色外观、其他语言、大字号、辅助功能遍历和错误状态外观仍未验收。

Mac 游戏输入沿用 host 的键盘映射：J 对应 A、K 对应 B、方向键对应十字键；这些绑定与实际游戏行为不属于启动器 UI 验收。LAN 开关与同 Wi-Fi 说明仅表达启动配置，不能证明 Mac／iPhone 已完成双设备联机游戏；该端到端验收仍单独进行。

## 触控外观与输入边界

实现位于 `platform/ios/Sources/DmGamepad.m` 与 `DmTouchControlArt.h`。材质来源、MIT 许可证与文件校验信息保存在 `platform/ios/Sources/ControlArt/`。

- 左右摇杆使用渐隐底盘与黑灰哑光摇杆头；A/B/X/Y 使用薄边圆形嵌槽，白色真实绑定文字位于材质之上。肩键、加减键与布局键保留既有轮廓。这里只复用通用材质，没有接入职业技能图案或动态 D3 技能图标。
- A 在右、B 在下、X 在上、Y 在左；2D／3D 布局、按下所有权、多点触控、滑动切换面键、死区、清零与外接手柄隐藏行为沿用既有输入契约。外观修改不得据此重排绑定或调整命中几何。
- 几何单位 `u = min(视图高度 / 430, 1.3)`；控件依照安全区域、既有半径与额外命中范围布局。视觉尺寸与命中范围不同，现有缩放几何没有统一的 44 pt 最小尺寸约束。
- 单位尺寸或屏幕 scale 改变时生成并替换 10 张小图缓存：嵌槽两态、两个摇杆各自底盘与摇杆头两态。按下切换 `CALayer.contents`，移动更新摇杆头位置；没有逐次触控的全屏重绘。PNG 缺失时有矢量嵌槽降级及日志。
- `work/audit/touch-style/verification.json` 记录 syntax-only 编译通过、输入常量及 28 个输入方法保持不变、physical callback 尾部保持不变。这是静态验证回执，不等于手柄或触摸运行验收。

## 截图证据与验收范围

`.impeccable/review/finish-review.json` 的 `ship` 结论仅覆盖界面完成度与文档修正。以下四张截图已对照上述生产 UI 源码检查：

| 截图 | 可确认的内容 |
| --- | --- |
| `.impeccable/review/phone.png`（2736×1260） | 深色手机横屏；左侧标题和开始操作、右侧原生设置分组；下方设置可滚动 |
| `.impeccable/review/tablet.png`（2420×1668） | 浅色平板横屏；同一双栏结构，完整显示三个设置分组 |
| `.impeccable/review/phone-controls.png`（2736×1260） | 手机 3D 布局；通用摇杆与圆形嵌槽，D3 真实按键文字 |
| `.impeccable/review/tablet-controls.png`（2420×1668） | 平板上的相同材质与按键结构；状态栏来自测试容器 |

这些图片由 `work/ui-preview/Preview.m` 的 UI-only 模拟器容器使用生产 `LauncherViewController.m`、`DmGamepad.m` 与共用绘图代码生成。容器将宽屏、LAN、资源就绪设为可用，并以空函数代替输入后端；灰色背景是测试底色。平板截图包含仅用于展示方向的旋转，不能证明真实设备旋转行为。截图没有启动游戏。

尚未执行的验收包括：辅助功能大字号下的完整布局、VoiceOver 遍历、禁用及持续按下状态的 UIKit 截图、真实多点触摸与外接手柄接入／断开、实际游戏按键响应、真机画面与 MetalFX 性能、双设备局域网游戏。源码中存在对应状态或静态回执，不能替代这些运行结果；当前文档不将这些未验证行为固化为已通过的设计规则。

宽屏映像按 iPhone Air 比例构建；不同宽高比的 iPad 保持该相机画面比例，允许留边，避免把人物拉伸。Air 的比例差小于 1%，填满屏幕。此整合修正不改变启动菜单或触控布局。
