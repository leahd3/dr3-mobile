#!/usr/bin/env python3
"""Build a local macOS app around the verified native runtime and shader cache."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time
from dr3 import ROOT, WORK, UPSTREAM, TITLE, PROFILE, sha, check_modules, fingerprints, native_fingerprints, check_shaders, save
from app_icons import mac_icns
from mobile_graphics_profile import launch_directory, verify

LANGUAGES = ('en', 'zh-Hans')


def strings_keys(path):
    keys = {}
    for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        text = line.strip()
        if not text or text.startswith('/*') or text.startswith('//'):
            continue
        match = re.fullmatch(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text)
        if not match:
            raise ValueError(f'{path}:{number}: malformed localization entry')
        key, value = match.groups()
        if not value:
            raise ValueError(f'{path}:{number}: empty value for {key!r}')
        keys[key] = value
    return keys


def check_localizations():
    files = {}
    for language in LANGUAGES:
        path = ROOT / 'tools/mac-i18n' / f'{language}.lproj' / 'Localizable.strings'
        if not path.is_file():
            raise ValueError(f'Missing localization file: {path}')
        files[language] = strings_keys(path)
    if files['en'].keys() != files['zh-Hans'].keys():
        missing = sorted(files['en'].keys() - files['zh-Hans'].keys())
        extra = sorted(files['zh-Hans'].keys() - files['en'].keys())
        raise ValueError(f'Localization key sets differ; absent from zh-Hans: {missing}; absent from en: {extra}')
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-parent', type=Path, default=WORK / 'macapp')
    parser.add_argument('--test-session', type=Path, help='Use an existing independent save copy for LAN validation')
    args = parser.parse_args()
    if args.test_session:
        args.test_session=args.test_session.resolve(strict=True)
        if not (args.test_session/'save/account.dat').is_file():raise ValueError('Test session requires an existing save copy')
    localizations = check_localizations()
    check_modules()
    verification = json.loads((WORK / 'verification.json').read_text())
    if not verification['passed'] or verification['artifacts'] != fingerprints() or verification['profile_sha256'] != sha(PROFILE):
        raise ValueError('Rewrite verification is stale')
    shaders = check_shaders()
    host = UPSTREAM / 'dm/host/dmhost'
    built = json.loads((WORK / 'host-build.json').read_text())
    if (built['binary_sha256'] != sha(host)
            or built['patch_sha256'] != sha(ROOT / 'patches/nxnative.patch')
            or built.get('gamepad_sha256') != sha(ROOT / 'native/gamepad_mac.m')
            or built.get('native_files') != native_fingerprints()
            or built['profile_sha256'] != sha(ROOT / 'config' / TITLE / 'game.tsv')):
        raise ValueError('Host build receipt is stale')
    parent = args.output_parent.resolve()
    parent.mkdir(parents=True, exist_ok=True)
    stage = parent / 'DR3 Mobile.partial.app'
    final = parent / 'DR3 Mobile.app'
    if stage.exists():
        shutil.rmtree(stage)
    mac = stage / 'Contents/MacOS'
    resources = stage / 'Contents/Resources'
    mac.mkdir(parents=True)
    resources.mkdir()
    for language in localizations:
        shutil.copytree(ROOT / 'tools/mac-i18n' / f'{language}.lproj', resources / f'{language}.lproj')
    mac_icns(WORK/'game/icon.jpg',resources/'AppIcon.icns',WORK/'build/app-icons')
    shutil.copy2(host, mac / 'dmhost')
    shutil.copytree(WORK / 'rewrite', resources / 'rewrite', ignore=shutil.ignore_patterns('*.log', '*.orig.bin'))
    wide=launch_directory(WORK,WORK/'mac-profiles'/str(time.time_ns()))
    proof=verify((WORK/'rewrite/main.patched.bin').read_bytes())
    graphics=json.loads((wide/'graphics.json').read_text())
    if not proof['passed'] or proof['configured_sha256']!=graphics['configured_sha256']:
        raise ValueError('Mac wide image failed independent verification')
    shutil.copytree(wide,resources/'rewrite-wide',ignore=shutil.ignore_patterns('*.log','*.orig.bin'))
    shutil.copytree(UPSTREAM / 'dm/games' / TITLE, resources / 'game')
    shutil.copytree(shaders, resources / 'shaders' / shaders.name,
                    ignore=shutil.ignore_patterns('*.metal', '*.air', '*.spv'))
    info = {'CFBundleName': 'DR3 Mobile', 'CFBundleDisplayName': 'DR3 Mobile',
            'CFBundleIdentifier': 'com.enginefuture.dr3-mobile', 'CFBundleExecutable': 'DR3Mobile',
            'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'zh-Hans'],
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1.0', 'CFBundleIconFile': 'AppIcon.icns',
            'CFBundleVersion': '3', 'NSLocalNetworkUsageDescription': '用于发现并加入同一 Wi-Fi 内的暗黑破坏神 III 游戏。',
            'NSBonjourServices': ['_dr3lan._udp'], 'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True}
    (stage / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    if args.test_session:
        info['DR3TestSessionRoot']=str(args.test_session)
        (stage/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['clang', '-O2', '-mmacosx-version-min=26.0', '-DDR3_WORK=' + json.dumps(str(WORK)),
                    '-fobjc-arc', str(ROOT / 'tools/mac_launcher.m'), '-framework', 'Cocoa', '-o', str(mac / 'DR3Mobile')], check=True)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(stage)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
    if final.exists():
        shutil.rmtree(final)
    stage.rename(final)
    save(parent / 'receipt.json', {'app': str(final), 'runtime_sha256': sha(final / 'Contents/MacOS/dmhost'),
                                 'launcher_sha256': sha(final / 'Contents/MacOS/DR3Mobile'),
                                 'launcher_source_sha256': sha(ROOT / 'tools/mac_launcher.m'),
                                 'icon_source_sha256': sha(WORK/'game/icon.jpg'),
                                 'icon_icns_sha256': sha(final/'Contents/Resources/AppIcon.icns'),
                                 'game_assets': str(WORK / 'game/RomFS'), 'shader_chain': shaders.name,
                                 'graphics': graphics, 'startup_menu': True, 'test_save_root':str(args.test_session) if args.test_session else None,
                                 'local_only': True, 'keys_required_at_runtime': False})
    print(final)


if __name__ == '__main__':
    main()
