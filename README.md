# DR3 Mobile

English | [简体中文](README.zh-CN.md)

An experimental native compatibility layer for running your own Nintendo Switch copy of **Diablo III: Eternal Collection** on Apple silicon macOS and iOS. Built on [nxnative](https://github.com/seedds/nxnative), with tools and input work derived from [d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile), [blade2-mobile](https://github.com/ha7rock/blade2-mobile) and [Bayonetta 3 Mobile](https://github.com/enginefuture/bayonetta3-mobile).

> **Support the original game. Buy a legitimate copy. Bring your own game files.**
>
> Source code, synthetic tests and tutorials only. **No NSP/XCI/NSZ, keys, tickets, game executables/assets/shaders, or game-containing App/IPA downloads are provided, hosted, linked or accepted.** Do not upload these to Issues, PRs, Releases or Actions artifacts. Read the [game files policy](docs/GAME_FILES.md).

Independent community research; not an official port and not affiliated with or endorsed by Blizzard Entertainment or Nintendo. The source license does not license the game or its trademarks.

## Observed status

As of **2026-10-27**. Research preview, not complete-game compatibility.

| Area | Verified scope |
|---|---|
| macOS / Apple silicon | Native startup, town/menu/inventory interaction, controller input and isolated save/reload checks |
| iPhone Air / A19 Pro / iOS 27.2 | User-confirmed town entry, working touch input, audible sound and corrected wide-screen output |
| iPhone 15 Pro / A17 Pro / iOS 27.2 | Device-specific build, development-signed USB install, complete resource checks and app launch; gameplay/performance not yet verified |
| Graphics | 1,323 unique original stages compiled locally; 1,993 iPhoneOS libraries including fetch/layout variants; MetalFX Spatial and Normal/Wide/Wider launch options |
| Offline seasons and challenge rifts | Season 37 calendar, season XVars and the weekly challenge-rift payload are injected from the host with no online state; the Challenge Rifts row appears in Mode Select. Entry is still locked until a Greater Rift is cleared, so rift entry is **not** verified |
| Local Wi-Fi | Mac host → iPhone client joined the same party; user confirmed both characters visible. Long sessions, combat/drop/scene synchronization, four players and reverse hosting remain unverified |
| Public Internet / Mesh | Design contract only; no released Mesh integration or Battle.net services |

The macOS launcher offers three display modes — Normal 16:9 (1600×900), Wide (1568×720) and Wider (1920×720) — plus Metal HUD, MetalFX Spatial and local Wi-Fi options. Both patched modes expand the horizontal view while keeping the vertical field of view; iOS keeps its single wide mode at 1920×720. Mobile MetalFX targets approximately 2K while preserving aspect. macOS and iOS use separate shader builds. Frame rate varies with device and scene; this is not a guarantee of sustained 60 FPS.

Constant-update forwarding substantially improved the observed Mac scene performance, but the original lantern flicker reproduced when forwarding was enabled. Attachment-dependency guards retain the optimization; the original location still needs dynamic visual acceptance. Full chapters, sustained thermal behavior, every rendering path and extended multiplayer stability are pending. See [status](STATUS.md), [acceptance checklist](docs/COMPLETION_CHECKLIST.md), [rendering notes](docs/LANTERN_STABILITY.md) and [LAN scope](docs/LAN_MULTIPLAYER.md).

## Build locally

Requires an Apple silicon Mac, macOS 26+, full Xcode with Metal tools (development used Xcode 27), Python 3.12+, LLVM, .NET 10, SPIRV-Cross, and your own legally prepared game files. iOS builds additionally need XcodeGen and an appropriate development-signing account/profile with both required memory entitlements.

```sh
git clone https://github.com/enginefuture/dr3-mobile.git
cd dr3-mobile
make setup
make bootstrap
```

Follow the [build tutorial / 构建教程](docs/BUILD.md) to prepare your own files, verify the exact build, translate shaders locally and build the host. Only **2.7.7.92380**, Program ID `01001B300B9BE000`, is accepted by the locked Build ID/SHA-256 profile. Unknown builds stop rather than bypassing the guard.

A fresh clone contains **no runnable game, generated shader cache or installable game package**. The ignored upstream checkout is recreated from its pinned commit and the reviewed source patch. After completing local preparation:

```sh
make app
open 'work/macapp/DR3 Mobile.app'
```

The generated Mac app refers to your local resource paths; regenerate it after moving the project. Local App/IPA outputs contain private game programs/shaders even when resources are external: **do not publish them**. Runtime execution does not require prod.keys or the Ryujinx emulator application. The MIT Ryujinx shader translator is used offline during the local build.

## Input and local multiplayer

GameController supports system-recognized USB/Bluetooth Extended Gamepads. Default face mapping follows Switch physical positions: right=A, bottom=B, top=X, left=Y (DualShock circle confirms). Focus the Mac game window to enable input; focus loss clears it. iOS supplies virtual sticks and circular buttons with MIT generic control artwork; no extracted skill icons are included.

Keyboard: WASD left stick; arrows D-pad; J/K/U/I = A/B/X/Y; Q/E = L/R; Z/C = ZL/ZR; Return/Tab = Plus/Minus. Multiple local controllers currently feed the same player input, not couch co-op.

For LAN, use matching updated builds, the same Wi-Fi with client-to-client access, local network permission on iOS, and keep both games in the foreground. Enable local Wi-Fi in the launcher, then select the game's nearby/local communication mode. Bonjour discovery and native UDP/TCP carry the local room. Battle.net, store, Internet friends and invite services are not supplied. [LAN details](docs/LAN_MULTIPLAYER.md) · [future Mesh contract](docs/XMESH_LAN_CONTRACT.md).

## Source, checks and license

- `tools/`, `native/`, `platform/ios/`: build helpers and platform shells.
- `config/`: exact-version fingerprints and interface metadata, no game modules.
- `patches/`, `third_party/`: pinned upstream source changes, small verification/parser sources and license notices.
- `tests/`: synthetic regressions; some native tests require the reconstructed upstream, Apple frameworks or private local corpus.
- `work/` and `platform/ios/Gen/`: ignored private inputs, keys, saves, generated code/shaders, packages and device evidence.

```sh
# After bootstrap; native tests need Apple frameworks/Metal.
make test
# Stage reviewed source only, then audit actual indexed and historical blobs.
python3 tools/audit_public.py --all-history
```

See [CONTRIBUTING.md](CONTRIBUTING.md), [third-party notices](THIRD_PARTY_NOTICES.md), [upstream changes](docs/UPSTREAM_CHANGES.md) and [metadata inventory](docs/DERIVED.md). Compatibility-layer source is [MIT licensed](LICENSE); third-party licenses remain intact.

**Support legitimate purchases. No NSP. No keys. No game-content downloads.**
