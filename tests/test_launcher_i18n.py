import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STRINGS = ROOT / 'tools/mac-i18n'
LAUNCHER = ROOT / 'tools/mac_launcher.m'
LANGUAGES = ('en', 'zh-Hans')


def strings_keys(path):
    keys = {}
    for number, line in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
        text = line.strip()
        if not text or text.startswith('/*') or text.startswith('//'):
            continue
        match = re.fullmatch(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text)
        if not match:
            raise AssertionError(f'{path}:{number}: malformed localization entry')
        key, value = match.groups()
        if key in keys:
            raise AssertionError(f'{path}:{number}: duplicate key {key!r}')
        keys[key] = value
    return keys


class LauncherI18N(unittest.TestCase):
    def setUp(self):
        self.strings = {language: strings_keys(STRINGS / f'{language}.lproj' / 'Localizable.strings')
                        for language in LANGUAGES}

    def test_localizations_share_one_key_set(self):
        english, chinese = self.strings['en'], self.strings['zh-Hans']
        self.assertEqual(sorted(english), sorted(chinese))

    def test_localizations_have_values(self):
        for language, entries in self.strings.items():
            for key, value in entries.items():
                self.assertTrue(value.strip(), f'{language}: empty value for {key!r}')

    def test_launcher_keys_exist_and_are_all_used(self):
        source = LAUNCHER.read_text(encoding='utf-8')
        used = set(re.findall(r'NSLocalizedString\(\s*@"((?:[^"\\]|\\.)*)"', source))
        self.assertTrue(used)
        for language, entries in self.strings.items():
            self.assertEqual(used - entries.keys(), set(), f'{language}: missing launcher keys')
            self.assertEqual(entries.keys() - used, set(), f'{language}: unused localization keys')


if __name__ == '__main__':
    unittest.main()
