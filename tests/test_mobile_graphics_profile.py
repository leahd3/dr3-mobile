import importlib
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
m=importlib.import_module('mobile_graphics_profile')


class MobileGraphicsProfile(unittest.TestCase):
    def source(self):
        image=bytearray(0x29c000)
        # Inventoried original renderer initializer and predicate, not searches.
        struct.pack_into('<8I',image,0xe7858,0xd280c808,0xd280a009,0xf2c07088,
            0xf2c05a09,0x5291c72a,0x72a7fc6a,0xb90012ca,0xa90026c8)
        struct.pack_into('<2I',image,0x29b480,0xb00075a8,0xf9423908)
        struct.pack_into('<I',image,0xebb48,0xbd484101)
        for offset,words in m.EVIDENCE.items():struct.pack_into('<'+'I'*len(words),image,offset,*words)
        return image

    def test_changes_are_limited_and_original_is_immutable(self):
        source=self.source();before=bytes(source)
        for width in (1280,1560,1600,1912,1920):
            result=m.configure(source,width,720);restored=bytearray(result)
            for offset,old,_,_ in m.sites(width,720):struct.pack_into('<I',restored,offset,old)
            self.assertEqual(restored,source)
            self.assertEqual(source,before)
            self.assertLessEqual(m.parameters(width)['render_pixels'],1600*900)
            self.assertEqual(struct.unpack_from('<I',result,0x29b480)[0],0xb00075a8 if width==1280 else 0x52800000)

    def test_configuration_and_evidence_guards_are_atomic(self):
        original=self.source()
        offsets=[o for o,*_ in m.SITES]+list(m.EVIDENCE)
        for offset in offsets:
            damaged=bytearray(original);damaged[offset]^=1;before=bytes(damaged)
            with self.assertRaisesRegex(ValueError,'guard failed'):m.configure(damaged)
            self.assertEqual(damaged,before)
        with self.assertRaises(ValueError):m.configure(bytes(64))
        with self.assertRaisesRegex(ValueError,'guard failed'):m.configure(m.configure(original))

    def test_bounds_do_not_allow_unknown_dimensions(self):
        for w,h in ((1272,720),(1928,720),(1569,720),(1920,900),(1920,719),(True,720),(1920,720.0)):
            with self.assertRaises(ValueError):m.parameters(w,h)

    def test_independent_guest_math(self):
        llvm=m.llvm_mc()
        if not llvm.exists():self.skipTest('LLVM unavailable')
        for width in (1280,1600,1920):
            report=m.verify(self.source(),llvm,width,720)
            self.assertTrue(report['passed'])
            self.assertEqual(report['unicorn_perspective_pairs'],64)
            self.assertEqual(report['unicorn_orthographic_pairs'],64)
            self.assertEqual(report['unicorn_whole_texture_query_cases'],28)
            self.assertEqual(report['legacy_handheld_texture_mismatch'][0]['old_reported'],(int(width*0.8),576))

    def fixture(self,path):
        (path/'game/ExeFS').mkdir(parents=True);(path/'rewrite').mkdir()
        modules={}
        for index,name in enumerate(('main','sdk')):
            raw=bytearray(256);raw[:4]=b'NSO0';raw[0x40:0x60]=bytes([index+1])*32
            (path/'game/ExeFS'/name).write_bytes(raw)
            modules[name]=dict(build_id=raw[0x40:0x60].hex(),sha256=hashlib.sha256(raw).hexdigest())
            for suffix in m.SUFFIXES:
                (path/'rewrite'/f'{name}.{suffix}').write_bytes(bytes(self.source()) if name=='main' and suffix=='patched.bin' else b'fixture')
        profile=path/'profile.json';profile.write_text(json.dumps(dict(modules=modules,runtime_modules=['main','sdk'])))
        verification=dict(passed=True,profile_sha256=m.digest(profile),
            artifacts={f.name:m.digest(f) for f in (path/'rewrite').iterdir()})
        (path/'verification.json').write_text(json.dumps(verification))
        return profile,verification

    def test_packaging_identity_and_complete_hash_guards(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp);profile,verification=self.fixture(path);destination=path/'new'
            with mock.patch.object(m,'PROFILE',profile):
                output=m.launch_directory(path,destination)
                self.assertEqual(output,destination)
                self.assertEqual((destination/'sdk.patched.bin').resolve(),(path/'rewrite/sdk.patched.bin').resolve())
                receipt=json.loads((destination/'graphics.json').read_text())
                self.assertEqual(receipt['configured_sha256'],m.digest(destination/'main.patched.bin'))
                with self.assertRaises(FileExistsError):m.launch_directory(path,destination)
                # Corruption outside edited sites must fail cryptographic guard.
                damaged=bytearray((path/'rewrite/main.patched.bin').read_bytes());damaged[0x100]^=1
                (path/'rewrite/main.patched.bin').write_bytes(damaged)
                with self.assertRaisesRegex(ValueError,'unchanged verified'):m.launch_directory(path,path/'corrupt')
                self.assertFalse((path/'corrupt').exists())
                (path/'rewrite/main.patched.bin').write_bytes(self.source())
                verification['artifacts']={};(path/'verification.json').write_text(json.dumps(verification))
                with self.assertRaisesRegex(ValueError,'complete verified'):m.launch_directory(path,path/'missing')
                self.assertFalse((path/'missing').exists())
                # Build-ID failure is checked even before rewrite metadata.
                raw=bytearray((path/'game/ExeFS/main').read_bytes());raw[0x40]^=1
                (path/'game/ExeFS/main').write_bytes(raw)
                with self.assertRaisesRegex(ValueError,'exact inventoried main'):m.launch_directory(path,path/'unknown')
                self.assertFalse((path/'unknown').exists())

    def test_same_signed_loader_header_accepts_only_exact_wide_words(self):
        clang=shutil.which('clang')
        if not clang:self.skipTest('C compiler unavailable')
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp);image=path/'wide.bin';image.write_bytes(m.configure(self.source()))
            binary=path/'guard-test'
            subprocess.run([clang,'-std=c11','-Wall','-Wextra','-Werror',
                str(ROOT/'tests/test_d3_graphics.c'),'-o',str(binary)],check=True,capture_output=True,text=True)
            result=subprocess.run([str(binary),str(image)],check=True,capture_output=True,text=True)
            self.assertIn('PASS:',result.stdout)


if __name__=='__main__':unittest.main()
