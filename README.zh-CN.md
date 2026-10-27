# DR3 Mobile

[English](README.md) | 简体中文

面向 Apple silicon macOS 和 iOS 的《暗黑破坏神 III 永恒之战版》原生兼容层研究项目，基于 [nxnative](https://github.com/seedds/nxnative)，复用 d2r-mobile、blade2-mobile 和 Bayonetta 3 Mobile 的方法及部分工具。

> **支持正版，请购买正版游戏，自行准备自己的游戏文件。**
>
> 本仓库仅发布源码、合成测试和教程。**不提供、不托管、不链接、不接受 NSP/XCI/NSZ、密钥、票据、游戏程序、提取资源、原始或翻译后的游戏着色器，以及包含游戏内容的 App/IPA。** 不要上传到 Issue、PR、Release 或 CI 产物。详见[游戏文件政策](docs/GAME_FILES.md)。

本项目独立于暴雪和任天堂，并非官方移植，也未获其背书。游戏内容和商标归权利人所有；源码许可证不包含游戏授权。

## 实测范围

截至 **2026-10-27**，仍是研究预览版，不代表全流程兼容。

| 平台 / 功能 | 已验证范围 |
|---|---|
| Apple silicon Mac | 原生启动、城镇/菜单/背包操作、实体手柄、隔离存档保存与重载 |
| iPhone Air / A19 Pro / iOS 27.2 | 用户确认进入城镇、触摸正常、有声音、宽屏显示修正 |
| iPhone 15 Pro / A17 Pro / iOS 27.2 | 按 A17 编译、开发签名 USB 安装、完整资源检查和启动；游玩与性能待确认 |
| 图形 | 本地提取 1323 个唯一阶段，iOS 含变体共 1993 个库；启动可选 HUD、MetalFX Spatial、正常/宽屏/超宽屏 |
| 离线赛季与挑战秘境 | 主机注入第 37 赛季日历、赛季 XVar 与每周挑战秘境数据，不依赖联网；模式选择已出现挑战秘境一行，但需先通关一个大秘境才解锁，**进入秘境尚未验证** |
| 本地 Wi-Fi | Mac 建房、iPhone 加入同一队伍，用户确认看到双方角色；长时间同步、战斗/掉落/换场景、四人及反向建房待验收 |
| 公网 / Mesh | 仅有接入契约，尚未完成；不提供战网、商店及互联网好友服务 |

macOS 启动器提供三档画面：正常 16:9（1600×900）、宽屏（1568×720）与超宽屏（1920×720），后两者扩大左右视野并保留纵向视野；iOS 仍只有 1920×720 一档宽屏。手机 MetalFX 按画幅输出约 2K。帧率随设备和场景变化，不承诺全程 60 FPS。常量更新转发曾显著改善 Mac 实测帧率，也曾引发灯笼闪烁；附件依赖守卫保留优化，原位置动态画面仍需验收。详见[当前状态](STATUS.md)、[剩余验收](docs/COMPLETION_CHECKLIST.md)与[灯笼记录](docs/LANTERN_STABILITY.md)。

## 自行构建

需要 Apple silicon Mac、macOS 26+、完整 Xcode/Metal 工具链（实测 Xcode 27）、Python 3.12+、LLVM、.NET 10、SPIRV-Cross，以及自己的合法游戏文件。iOS 还需 XcodeGen、开发签名账号和所需内存权限。

```sh
git clone https://github.com/enginefuture/dr3-mobile.git
cd dr3-mobile
make setup
make bootstrap
```

继续阅读[构建教程](docs/BUILD.md)。当前只接受 **2.7.7.92380 / 01001B300B9BE000**，按 Build ID 和 SHA-256 严格校验，不能绕过守卫运行未知版本。

干净克隆不含可运行游戏、着色器缓存或可安装游戏包。工具从固定提交重建被忽略的上游源码，再应用源码补丁。准备并验证自己的文件后：

```sh
make app
open 'work/macapp/DR3 Mobile.app'
```

Mac 本地 App 引用项目内的资源路径，移动项目后需重新打包。**本地 App/IPA 即使未嵌入 RomFS，也已包含游戏程序和着色器，不公开发布。** 原生运行无需 prod.keys 或 Ryujinx 模拟器应用，构建阶段使用其 MIT 着色器翻译代码。

## 操作与联机

启动菜单提供 Metal HUD、MetalFX、正常/宽屏、本地 Wi-Fi 选项。Mac 支持系统 GameController 识别的 USB/蓝牙手柄，默认按 Switch 物理位置映射：右 A、下 B、上 X、左 Y，DualShock 圆圈确认。先聚焦游戏窗口，失焦会清零输入。多个实体手柄合并操作 1P，不代表本地同屏多人。

iOS 提供虚拟摇杆和圆钮，使用附有 MIT 许可证的通用触控素材，不含提取的职业技能图标。键盘 WASD 移动，方向键十字键，J/K/U/I 为 A/B/X/Y，Q/E 为 L/R，Z/C 为 ZL/ZR，回车/Tab 为加减号。

局域网需两端使用同版修复、接入可互访的同一 Wi-Fi，允许 iOS 本地网络访问，保持游戏前台。启动开启本地 Wi-Fi，再在游戏选择与附近玩家本地联机。已实现 Bonjour 发现和原生 UDP/TCP，不等于公网 LAN 或战网。见[局域网说明](docs/LAN_MULTIPLAYER.md)与[未来 Mesh 契约](docs/XMESH_LAN_CONTRACT.md)。

## 参与与许可证

`work/` 与 `platform/ios/Gen/` 为私有忽略目录。不要提交游戏文件、个人存档、签名材料、原始设备日志或生成产物。提交前暂存经过审查的源码，再运行 `python3 tools/audit_public.py --all-history`；CI 重复检查实际 Git 内容。

[MIT 许可证](LICENSE) · [第三方声明](THIRD_PARTY_NOTICES.md) · [上游修改](docs/UPSTREAM_CHANGES.md) · [参与说明](CONTRIBUTING.md)。第三方代码保留原许可证，源码授权不授予游戏内容权利。

**支持正版，不提供 NSP、密钥或含游戏内容的下载。**
