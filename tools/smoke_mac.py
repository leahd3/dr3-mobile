#!/usr/bin/env python3
"""Run a bounded offscreen diagnostic using a cloned save and verified app."""
import argparse
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import time
from dr3 import WORK, LANG, env, check_modules, profile, sha, save


def save_files(directory):
    return {p.relative_to(directory).as_posix():sha(p) for p in directory.rglob('*') if p.is_file()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-parent',type=Path,default=WORK/'macapp-complete')
    parser.add_argument('--save-source',type=Path,default=WORK/'run/save')
    parser.add_argument('--seconds',type=int,default=100)
    parser.add_argument('--keys',default='8:A,12:A,17:A,22:A,27:A',help='Diagnostic input affects only the offscreen clone')
    parser.add_argument('--opmode',choices=('0','1'),default='1')
    parser.add_argument('--shots',default='1800,3600')
    args=parser.parse_args();check_modules()
    parent=args.app_parent.resolve();receipt=json.loads((parent/'receipt.json').read_text())
    app=Path(receipt['app']);binary=app/'Contents/MacOS/dmhost';resources=app/'Contents/Resources'
    if sha(binary)!=receipt['runtime_sha256']:raise ValueError('App runtime differs from receipt')
    original=args.save_source.resolve();before=save_files(original)
    directory=WORK/'run'/('smoke-'+time.strftime('%Y%m%d-%H%M%S')+'-'+str(time.time_ns()%100000))
    directory.mkdir();shutil.copytree(original,directory/'save');(directory/'temp').mkdir()
    control=directory/'control.txt';control.write_text('1 1\n')
    settings=dict(DM_ROMFS=str(WORK/'game/RomFS'),DM_SAVE=str(directory/'save'),DM_TEMP=str(directory/'temp'),
        DM_AOC_DIR=str(WORK/'aoc'),DM_LANG=LANG,DM_OPMODE=args.opmode,DM_NVN_TBDR='0',DM_PSO_MANIFEST='off',
        DM_NVN_SHMAP=str(resources/'game/shader_map.tsv'),DM_MSL_DIR=str(resources/'shaders'),
        DM_NVN_UNIFORM_FORWARD='1',DM_NVN_UNIFORM_FORWARD_CONTROL=str(control),
        DM_NVN_TSV=str(directory/'performance.tsv'),DM_NVN_TSV_CALLS='0',DM_KEYS=args.keys,
        DM_NVN_SHOT=f'{args.shots}:{directory}/frame-%d.png')
    info=dict(runtime_sha256=receipt['runtime_sha256'],offscreen=True,original_save=str(original),
              scripted_input=args.keys,opmode=args.opmode,uniform_forward=1,attachment_guard=1,seconds=args.seconds)
    start=time.monotonic()
    with (directory/'boot.log').open('w') as log:
        process=subprocess.Popen([str(binary),str(resources/'rewrite'),*profile()['runtime_modules']],env=env()|settings,cwd=directory,stdout=log,stderr=subprocess.STDOUT)
        info['pid']=process.pid;save(directory/'summary.json',info);print(directory,flush=True)
        try:code=process.wait(timeout=args.seconds);info['termination']='self-exit'
        except subprocess.TimeoutExpired:
            info['termination']='harness-deadline';process.terminate()
            try:code=process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();code=process.wait();info['termination']='harness-kill'
    info.update(exit_code=code,wall_seconds=round(time.monotonic()-start,3),original_save_unchanged=before==save_files(original),cloned_save_files=save_files(directory/'save'))
    frames={}
    if (directory/'performance.tsv').exists():
        for line in (directory/'performance.tsv').read_text().splitlines():
            a=line.split('\t')
            if len(a)==3 and a[0].isdigit():
                try:frames.setdefault(int(a[0]),{})[a[1]]=float(a[2])
                except ValueError:pass
    info['max_frame']=max(frames,default=0);latest=max((r.get('@t_s',0) for r in frames.values()),default=0)
    rows=[r for r in frames.values() if r.get('@t_s',0)>=latest-30 and r.get('@draws',0)>=300]
    info['last_30s_gameplay_samples']=len(rows);info['metrics']={}
    for key in ['@frame_ms','@gpu_ms','@passes','@draws','@uf_feedback_splits','@pso_new','@lib_new']:
        values=sorted(r[key] for r in rows if r.get(key,-1)>=0)
        if values:info['metrics'][key]=dict(n=len(values),p50=statistics.median(values),p95=values[int((len(values)-1)*.95)],max=max(values))
    text=(directory/'boot.log').read_text(errors='replace')
    info['crash_lines']=[line for line in text.splitlines() if 'CRASH sig=' in line or 'FATAL' in line]
    info['warnings']=[line for line in text.splitlines() if '【红】' in line]
    info['limitations']=['Offscreen work times are not actual presentation FPS.','A short scene run cannot prove complete game compatibility.']
    save(directory/'summary.json',info);print(json.dumps(info,indent=2,ensure_ascii=False),flush=True)
    if info['crash_lines'] or not info['original_save_unchanged'] or code:raise SystemExit(1)


if __name__=='__main__':main()
