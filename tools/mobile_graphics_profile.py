"""Exact D3 2.7.7 render/camera configuration; original rewrite is immutable.

The renderer's mode dimensions and display aspect feed the actual camera+0x48.
Perspective uses cot(vertical_fov/2)/aspect; orthographic uses 2/(height*aspect).
The existing UI pixel projection follows the same display dimensions. Disable
the specifically identified authored-16:9 constraint predicate only for wide.
This intentional configuration requires gameplay/menu validation after packaging.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / 'config/diablo3-2.7.7.json'
DEFAULT_WIDTH, DEFAULT_HEIGHT = 1920, 720
SUFFIXES=('patched.bin','fixups.tsv','gates.tsv','sites.tsv','cuts.tsv','obs.tsv','params.tsv')
SITES = (
    (0xe7858, 0xd280c808, 'docked render width'),
    (0xe785c, 0xd280a009, 'handheld render width'),
    (0xe7860, 0xf2c07088, 'docked render height'),
    (0xe7864, 0xf2c05a09, 'handheld render height'),
    (0xe7868, 0x5291c72a, 'display aspect low bits'),
    (0xe786c, 0x72a7fc6a, 'display aspect high bits'),
    (0x29b480, 0xb00075a8, 'authored 16:9 constraint predicate entry'),
    (0x29b484, 0xf9423908, 'authored 16:9 constraint predicate return'),
    (0xebb48, 0xbd484101, 'texture full/half/quarter handheld query scale: equal mode sizes require 1.0'),
)
# Independently inventoried instructions establish what these settings affect.
# They are guards, not replacement words. Never search/replace every 16:9 float.
EVIDENCE = {
    0xebac0: (0xb0008309,0xf944b929,0xb9401028,0x2940292b,0x6b0b011f,0x54000081,
        0xb940142c,0x6b0a019f,0x540000c0,0x6b4b051f,0x54000121,0xb940142c,
        0x6b4a059f,0x540000c1,0x528b1f8a,0x72a0002a,0xb86a6929,0x35000169,
        0x1400000e,0x6b4b091f,0x54000101,0x528b1f8b,0x72a0002b,0xb86b6929,
        0xb940142b,0x6b4a097f,0x7a400920,0x540000a0,0xb9000048,0xb9401428,
        0xb9000068,0xd65f03c0,0x1e230100,0xb0006e28),
    0xebb4c: (0x1e210800,0x1e390008,0xb9000048,0xbd401420,0x7e21d800,
        0x1e210803,0x1e390068,0xb9000068,0xd65f03c0),
    0xe7870: (0xb90012ca, 0xa90026c8),
    0xea11c: (0xb9400129,0xb940014a,0x29022a69,0x29032a69,0x29042a69,
        0xd2800789,0xf2c00409,0xf9001669,0xb9401108,0x2906227f),
    0x2667d0: (0xbd004a60,0xb9003268,0x97fffa26),
    0x29b7d4: (0x1e2e1001,0x1e201820,0x1e293901,0xa901fe7f,0xbd001660,
        0x1e2a1802,0x52b7f008,0xf800c27f,0xf800427f,0xb900367f,0xbd000262),
    0x29b840: (0x1e210801,0x1e201004,0x1e201880,0x1e223863,
        0xbd001400,0x1e211881,0xa901fc1f,0xbd000001),
    0x29a2f4: (0xb942450a,0xb9424909,0x1e230141,0x1e230120,0x5288e90b,
        0x1e2703e2,0x4ea21c43,0xbc2b6901,0x5288e88b,0xbc2b6900,
        0x52889d8b,0xb82b690a,0x52889d0b,0xb82b6909,0x52889e8b,
        0xbc2b6901,0x52889e0b,0xbc2b6900),
    0x29b8c8: (0xbc6b6900,0x1e201002,0x52889e0a,0xbc6a6901,0xf8404128,
        0x1e201840,0x1e301002,0x2941ad2a,0xa941b52c,0x29453d2e,
        0x29472530,0xf8004008,0xd2b7f008,0xf2e7f008,0x2901ac0a,
        0xa901b40c,0x29053c0e,0x29072410,0xf9001808,0xbd000000,
        0x1e211840,0xbd001400),
}
LIMITATIONS = (
    'Intentional graphics configuration, not equivalence to original output.',
    'Actual guest projection expands horizontal view; all cameras, culling and authored UI still need runtime validation.',
    'UI pixel projection follows dimensions; this does not prove every menu anchor or safe area.',
    'Render area stays below original docked area; wider texture strides/allocation still require validation.',
    'Present/upscaling must use this profile geometry; this module does not stretch/crop a 16:9 frame.',
)


def parameters(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT):
    if type(width) is not int or type(height) is not int:
        raise ValueError('Render dimensions must be integers')
    if height != 720 or not 1280 <= width <= 1920 or width % 8:
        raise ValueError('D3 mobile render requires height 720 and 8-aligned width 1280..1920')
    return dict(width=width,height=height,aspect=width/height,
                mode='wide' if width*9>height*16 else 'normal',
                horizontal_expansion=(width/height)/(16/9),
                original_docked_pixels=1600*900,render_pixels=width*height)


def sites(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT):
    p=parameters(width,height)
    aspect=struct.unpack('<I',struct.pack('<f',p['aspect']))[0]
    values=(0xd2800008|(width<<5),0xd2800009|(width<<5),
        0xf2c00008|(height<<5),0xf2c00009|(height<<5),
        0x5280000a|((aspect&65535)<<5),0x72a0000a|((aspect>>16)<<5),
        0x52800000 if p['mode']=='wide' else SITES[6][1],
        0xd65f03c0 if p['mode']=='wide' else SITES[7][1],0x1e2e1001)
    return tuple((o,old,new,purpose) for (o,old,purpose),new in zip(SITES,values))


def validate_evidence(data):
    for offset,words in EVIDENCE.items():
        raw=struct.pack('<'+'I'*len(words),*words)
        if data[offset:offset+len(raw)] != raw:
            raise ValueError(f'D3 camera/UI evidence guard failed at main+{offset:#x}')


def configure(data,width=DEFAULT_WIDTH,height=DEFAULT_HEIGHT):
    selected=sites(width,height)
    for offset,old,_,purpose in selected:
        if offset+4>len(data) or struct.unpack_from('<I',data,offset)[0]!=old:
            raise ValueError(f'D3 graphics guard failed at main+{offset:#x}: {purpose}')
    validate_evidence(data)
    result=bytearray(data)
    for offset,_,new,_ in selected:struct.pack_into('<I',result,offset,new)
    return bytes(result)


def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def launch_directory(work,destination,width=DEFAULT_WIDTH,height=DEFAULT_HEIGHT):
    p=parameters(width,height);work=Path(work);destination=Path(destination)
    profile=json.loads(PROFILE.read_text())
    for name,expected in profile['modules'].items():
        path=work/'game/ExeFS'/name
        with path.open('rb') as stream:header=stream.read(256)
        if header[:4]!=b'NSO0' or header[0x40:0x60].hex()!=expected['build_id'] or digest(path)!=expected['sha256']:
            raise ValueError(f'D3 graphics requires exact inventoried {name} NSO')
    verified=json.loads((work/'verification.json').read_text())
    if not verified.get('passed') or verified.get('profile_sha256')!=digest(PROFILE):
        raise ValueError('D3 graphics requires successful exact-profile rewrite verification')
    expected_artifacts={f'{name}.{suffix}' for name in profile['runtime_modules'] for suffix in SUFFIXES}
    if set(verified.get('artifacts',{}))!=expected_artifacts:
        raise ValueError('D3 graphics requires complete verified rewrite artifacts')
    for name,expected in verified['artifacts'].items():
        if Path(name).name!=name or digest(work/'rewrite'/name)!=expected:
            raise ValueError('D3 graphics requires unchanged verified rewrite artifacts')
    original=(work/'rewrite/main.patched.bin').read_bytes()
    configured=configure(original,width,height)
    # Validate all inputs before creating a new destination; never overwrite.
    destination.mkdir(parents=True,exist_ok=False)
    for path in (work/'rewrite').iterdir():
        if path.is_file() and path.name!='main.patched.bin':(destination/path.name).symlink_to(path.resolve())
    (destination/'main.patched.bin').write_bytes(configured)
    receipt=dict(mode='d3-mobile-graphics',parameters=p,
        modules={name:{key:expected[key] for key in ('build_id','sha256')} for name,expected in profile['modules'].items()},
        verified_rewrite_sha256=hashlib.sha256(original).hexdigest(),
        configured_sha256=hashlib.sha256(configured).hexdigest(),
        sites=[dict(offset=hex(o),original=hex(old),configured=hex(new),purpose=purpose) for o,old,new,purpose in sites(width,height)],
        limitations=list(LIMITATIONS))
    (destination/'graphics.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return destination


def llvm_mc():
    configured=os.environ.get('LLVM_BIN')
    if configured:return Path(configured)/'llvm-mc'
    found=shutil.which('llvm-mc')
    if found:return Path(found)
    return Path('/opt/homebrew/opt/llvm/bin/llvm-mc')


def verify(original,llvm=None,width=DEFAULT_WIDTH,height=DEFAULT_HEIGHT):
    llvm=llvm or llvm_mc()
    from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
    from unicorn.arm64_const import (UC_ARM64_REG_X0,UC_ARM64_REG_X30,UC_ARM64_REG_SP,UC_ARM64_REG_CPACR_EL1,
        UC_ARM64_REG_S0)
    configured=configure(original,width,height)
    selected=sites(width,height)
    code=b''.join(configured[o:o+4] for o,*_ in selected)
    result=subprocess.run([str(llvm),'--disassemble','--triple=aarch64'],
        input=' '.join(f'0x{x:02x}' for x in code),text=True,capture_output=True,check=True)
    decoded=[' '.join(line.split('//')[0].split()) for line in result.stdout.splitlines()
        if line.strip() and not line.lstrip().startswith('.')]
    # Independent decoder must confirm register/width/shift, not just decode success.
    expected=(f'mov x8, #{width}',f'mov x9, #{width}',f'movk x8, #{height}, lsl #32',f'movk x9, #{height}, lsl #32')
    if tuple(decoded[:4])!=expected:raise ValueError(f'LLVM D3 dimensions mismatch: {decoded}')
    if parameters(width,height)['mode']=='wide' and tuple(decoded[6:8])!=('mov w0, #0','ret'):
        raise ValueError('LLVM D3 constraint predicate mismatch')
    if decoded[8]!='fmov s1, #1.00000000':raise ValueError('LLVM D3 texture size conversion mismatch')
    uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(0x10000,0x1000);uc.mem_map(0x20000,0x10000)
    uc.reg_write(UC_ARM64_REG_CPACR_EL1,3<<20);uc.reg_write(UC_ARM64_REG_SP,0x2f000)
    f32=lambda f:struct.unpack('<f',struct.pack('<f',f))[0]
    bits=lambda f:struct.unpack('<I',struct.pack('<f',f))[0]
    def sf(i,value):uc.reg_write(UC_ARM64_REG_S0+i,bits(value))
    def xf(i,value):uc.reg_write(UC_ARM64_REG_X0+i,value)
    def readf(at):return struct.unpack('<f',bytes(uc.mem_read(at,4)))[0]
    def run(raw):
        uc.mem_write(0x10000,raw);uc.ctl_remove_cache(0x10000,0x10000+len(raw))
        uc.emu_start(0x10000,0x10000+len(raw),count=len(raw)//4)
    xf(22,0x20000);run(configured[0xe7858:0xe7878])
    assert struct.unpack('<4I',bytes(uc.mem_read(0x20000,16)))==(width,height,width,height)
    aspect=readf(0x20010);assert aspect==f32(width/height)
    # Actual display-query stores into output+0x10/+0x18/+0x20 and aspect+0x34.
    xf(8,0x20000);xf(9,0x20000);xf(10,0x20004);xf(19,0x21000)
    run(configured[0xea11c:0xea144])
    assert struct.unpack('<6I',bytes(uc.mem_read(0x21010,24)))==(width,height)*3
    assert readf(0x21034)==aspect
    # Actual UI dimension setter and pixel projection, no Python replacement.
    uc.mem_write(0x22244,struct.pack('<2I',width,height));xf(8,0x22000)
    run(configured[0x29a2f4:0x29a33c])
    assert readf(0x264f4)==width and readf(0x264f0)==height
    xf(8,0x22000);xf(11,0x44f4);xf(9,0x28000);xf(0,0x29000)
    uc.mem_write(0x28000,bytes(64));run(configured[0x29b8c8:0x29b920])
    assert readf(0x29000)==f32(2/width) and readf(0x29014)==f32(-2/height)
    rng=random.Random(20261018);perspective=orthographic=0
    for _ in range(64):
        tangent=f32(rng.uniform(0.1,3));near=f32(rng.uniform(0.01,2));far=f32(rng.uniform(20,3000))
        horizontal=[];vertical=[]
        for a in (f32(16/9),aspect):
            sf(0,tangent);sf(8,far);sf(9,near);sf(10,a);xf(19,0x20000)
            run(configured[0x29b7d4:0x29b800])
            horizontal.append(readf(0x20000));vertical.append(readf(0x20014))
            assert horizontal[-1]==f32(f32(1/tangent)/a)
        assert vertical[0]==vertical[1]
        if width>1280:assert horizontal[1]<horizontal[0]
        perspective+=1
        span=f32(rng.uniform(5,200));horizontal=[];vertical=[]
        for a in (f32(16/9),aspect):
            sf(0,span);sf(1,a);sf(2,near);sf(3,far);xf(0,0x20000)
            run(configured[0x29b840:0x29b860])
            horizontal.append(readf(0x20000));vertical.append(readf(0x20014))
            assert horizontal[-1]==f32(2/f32(span*a))
        assert vertical[0]==vertical[1]
        if width>1280:assert horizontal[1]<horizontal[0]
        orthographic+=1
    if width>1280:
        xf(0,0xdeadbeef);run(configured[0x29b480:0x29b484]);assert uc.reg_read(UC_ARM64_REG_X0)==0
    # Execute the WHOLE original texture query, including full/half/quarter and
    # performance-mode branches, at its original PC so ADRP/GOT semantics hold.
    # This catches the real 0.8 conversion missed by projection-only validation.
    uc.mem_map(0xeb000,0x1000);uc.mem_map(0xeb0000,0x1000)
    uc.mem_map(0x114c000,0x1000);uc.mem_map(0x40000,0x20000)
    uc.mem_write(0x114c970,struct.pack('<Q',0x40000))
    uc.mem_write(0xeb0840,struct.pack('<f',0.8))
    def texture_query(image,dw,dh,tw,th,docked):
        raw=bytes(image[0xebac0:0xebb70]);uc.mem_write(0xebac0,raw)
        uc.ctl_remove_cache(0xebac0,0xebb70)
        uc.mem_write(0x40000,struct.pack('<2I',dw,dh))
        uc.mem_write(0x558fc,struct.pack('<I',docked))
        uc.mem_write(0x21010,struct.pack('<2I',tw,th))
        xf(1,0x21000);xf(2,0x22000);xf(3,0x22004);uc.reg_write(UC_ARM64_REG_X30,0x10000)
        uc.emu_start(0xebac0,0x10000,count=100)
        return struct.unpack('<2I',bytes(uc.mem_read(0x22000,8)))
    texture_cases=0
    legacy_mismatch=[]
    for divisor in (1,2,4):
        original_size=(1600//divisor,900//divisor)
        assert texture_query(original,1600,900,*original_size,0)==(1280//divisor,720//divisor)
        texture_cases+=1
        target=(width//divisor,height//divisor)
        legacy=texture_query(original,width,height,*target,0)
        expected_legacy=tuple(int(f32(f32(v)*f32(0.8))) for v in target)
        assert legacy==expected_legacy and legacy!=target
        legacy_mismatch.append(dict(divisor=divisor,actual_texture=target,old_reported=legacy))
        texture_cases+=1
        for docked in (0,1):
            assert texture_query(configured,width,height,*target,docked)==target
            texture_cases+=1
    for target in ((777,333),(width//2,height//2+1),(width,height+1),(64,64)):
        for docked in (0,1):
            assert texture_query(original,width,height,*target,docked)==target
            assert texture_query(configured,width,height,*target,docked)==target
            texture_cases+=2
    return dict(passed=True,parameters=parameters(width,height),llvm_decoded=decoded,
        unicorn_render_initializers=1,unicorn_display_query=1,unicorn_ui_projection=1,
        unicorn_perspective_pairs=perspective,unicorn_orthographic_pairs=orthographic,
        unicorn_whole_texture_query_cases=texture_cases,legacy_handheld_texture_mismatch=legacy_mismatch,
        input_sha256=hashlib.sha256(original).hexdigest(),configured_sha256=hashlib.sha256(configured).hexdigest(),
        limitations=list(LIMITATIONS))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--work',type=Path,default=ROOT/'work')
    p.add_argument('--destination',type=Path)
    p.add_argument('--width',type=int,default=DEFAULT_WIDTH)
    p.add_argument('--height',type=int,default=DEFAULT_HEIGHT)
    a=p.parse_args()
    report=verify((a.work/'rewrite/main.patched.bin').read_bytes(),width=a.width,height=a.height)
    if a.destination:report['directory']=str(launch_directory(a.work,a.destination,a.width,a.height))
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
