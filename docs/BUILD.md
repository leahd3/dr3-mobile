# Build locally / 本地构建

Read [GAME_FILES.md](GAME_FILES.md) first. 本教程从你已经合法准备的文件开始，不提供游戏下载或密钥来源。

## Prerequisites / 环境

Apple silicon Mac; macOS 26+; full Xcode with Metal tools (tested Xcode 27); Python 3.12+; LLVM; .NET 10; SPIRV-Cross; XcodeGen for iOS. Install and select your own Xcode/toolchains. LLVM is resolved from `LLVM_BIN`, then `llvm-mc` on `PATH`, and only then from Homebrew's `/opt/homebrew/opt/llvm/bin`. On a nix machine `nix develop` (see `flake.nix`) provides LLVM, .NET 10, SPIRV-Cross and Python 3.12 — it deliberately drops nix's `xcrun`/`clang` wrappers so Xcode's toolchain and the separately installed Metal compiler (`xcodebuild -downloadComponent MetalToolchain`) stay in charge. Prepare substantial free disk space: the tested base/language resource set alone is about 22.75 GB, with additional extraction, shader and build caches.

```sh
git clone https://github.com/enginefuture/dr3-mobile.git
cd dr3-mobile
make setup
make bootstrap
```

Bootstrap clones nxnative at the pinned revision and applies `patches/nxnative.patch`, then copies the local host adapters and verification helpers. It does not fetch game files. Do not remove the pinned-revision or game fingerprint guards.

## Private preparation / 私有游戏准备

Only the configured Switch build **2.7.7.92380**, `01001B300B9BE000`, is accepted. Supply your own base/update and keyset explicitly:

```sh
.venv/bin/python tools/dr3.py prepare --base /path/to/your-base.nsp --update /path/to/your-update.nsp --keys /path/to/your/prod.keys
make rewrite
make verify
make shaders
```

`prepare` checks both Build ID and SHA-256 before using the extraction; it stops on unknown builds. `rewrite` generates private ARM64 images; independent structure and Unicorn checks run in `verify`. Shader extraction/translation/compilation runs locally from your own CPK contents. First compilation is substantial. These checks are not complete gameplay verification.

The current launch profiles expect the user's Simplified Chinese DLC (`01001B300B9BF00B`, filenames `ztCN`). Prepare it before app generation:

```sh
.venv/bin/python tools/chinese.py --keys /path/to/your/prod.keys --nsp /path/to/your-chinese-dlc.nsp
make app
open 'work/macapp/DR3 Mobile.app'
```

Resource and shader fingerprints are checked before packaging/launch. macOS saves are isolated under `work/run/save`. To change an existing save's locale preferences, first quit the game and back it up; the optional `tools/chinese.py --preferences` creates a backup and changes locale fields only. Never edit a running game's save.

## iOS / 真机

```sh
.venv/bin/python tools/build_ios_shaders.py
# Set your own development team and device UDID; no maintainer signing files are supplied.
.venv/bin/python tools/build_ios.py --cpu apple-a17 --sign --team-id YOUR_TEAM_ID --device YOUR_DEVICE_UDID
```

Use `apple-a17` for iPhone 15 Pro/A17 Pro. The default `apple-a18` was used for the newer tested iPhone Air; a deployment target alone is not a hardware-compatibility promise. The final signature **and provisioning profile** must contain Extended Virtual Addressing and Increased Memory Limit. A development certificate alone is insufficient; the profile must also include the device. Enable Developer Mode, unlock and trust the Mac.

Use Xcode's Devices and Simulators to install the generated private `work/build/ios/Build/Products/Release-iphoneos/DR3Mobile.app`, or Apple's `devicectl`. Confirm the exact UDID and wired transport when several devices are connected. Do not uninstall an existing app to update it; back up its committed save first.

The small app leaves game resources outside its bundle. Copy your local `work/game/RomFS` to its `Documents/romfs`, and `work/aoc` to `Documents/aoc`. For example, after installation (replace DEVICE_UDID):

```sh
xcrun devicectl device copy to --device DEVICE_UDID --domain-type appDataContainer --domain-identifier com.enginefuture.dr3-mobile.ios --source "$PWD/work/game/RomFS" --destination Documents/romfs
xcrun devicectl device copy to --device DEVICE_UDID --domain-type appDataContainer --domain-identifier com.enginefuture.dr3-mobile.ios --source "$PWD/work/aoc" --destination Documents/aoc
xcrun devicectl device process launch --device DEVICE_UDID com.enginefuture.dr3-mobile.ios
```

The launcher checks all resource paths, types and lengths against the locally generated manifest. Partial/missing transfers keep Play disabled. `--embed-assets` can instead embed your private resources for personal builds, but neither form is a public distribution package: both contain rewritten game code and shaders. Do not upload the App/IPA.

See [device observations and limitations](IOS_TESTING.md), [wide-screen behavior](MOBILE_WIDESCREEN.md), [MetalFX](METALFX.md) and [local Wi-Fi](LAN_MULTIPLAYER.md). Touch, audio, thermal stability and sustained performance must be tested on each device.

## Checks / 检查

```sh
make test
python3 tools/audit_public.py --all-history
```

`make test` includes native GPU tests and a private-corpus vertex test; it requires the prepared workspace and Metal hardware. CI separately runs source-only synthetic checks without game files. Bonjour discovery testing is explicitly opt-in: `DM_LAN_BONJOUR_TEST=1 .venv/bin/python -m unittest discover -s tests -p test_lan_native.py -v`. It publishes a temporary service on your local network; it does not prove two physical devices can play.
