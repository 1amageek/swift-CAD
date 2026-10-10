#!/usr/bin/env python3
"""Rebuild only synchronous verification entry points with explicit isolation."""
import argparse, hashlib, json, subprocess, time
from pathlib import Path
import yaml

root=Path(__file__).resolve().parents[3]
base=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('lane')
args=parser.parse_args()
lane=args.lane
public=lane.startswith('public-')
general=lane.startswith('general-')
mode=lane.removeprefix('public-').removeprefix('general-')
module='IssuedGraphProof' if public else 'GeneralGraphProof' if general else 'GraphProof'
cache=root/'.build'/('di-m2-production-native' if lane=='public-native' else 'gp-public-asan-debug' if lane=='public-asan' else 'gp-public-'+mode if public else 'pg-b3-'+mode)
out=base/lane
record=json.loads((out/'result.json').read_text())
plan=yaml.load((cache/'debug.yaml').read_text(),Loader=yaml.CSafeLoader)['commands']
source=root/('Tests/NativeExactRelationVerification/Sources/IssuedGraphProof/IssuedGraphProof.swift' if public else 'Tests/OriginalGraphRelationVerification/Sources/GeneralGraphProof/GeneralGraphProof.swift' if general else 'Tests/OriginalGraphRelationVerification/Sources/Proof/Proof.swift')
inputs=json.loads((out/'inputs.json').read_text())
old=source.read_text().replace('static func main() throws { try run() }\n    nonisolated static func run() throws {','static func main() throws {').encode()
key=str(source.relative_to(root))
if key in inputs and hashlib.sha256(old).hexdigest()!=inputs[key]:
    raise RuntimeError('Entry point premise differs from the isolated modifier repair')
for path,expected in inputs.items():
    if path==key:continue
    p=root/path
    if path.endswith('/Package.swift') and record.get('retainedPackagePremise'):
        p=root/record['retainedPackagePremise']
    if hashlib.sha256(p.read_bytes()).hexdigest()!=expected:
        raise RuntimeError('Changed retained input: '+path)

runs=[]
def execute(label,command,timeout):
    start=time.monotonic()
    with (out/(label+'.log')).open('w') as log:
        try:r=subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        except subprocess.TimeoutExpired:raise RuntimeError('Timed out: '+label)
    entry=dict(label=label,command=command,timeoutSeconds=timeout,elapsedSeconds=round(time.monotonic()-start,3),exitCode=r.returncode)
    runs.append(entry)
    (out/'entrypoint-runs.json').write_text(json.dumps(runs,indent=2)+'\n')
    print(json.dumps(entry),flush=True)
    if r.returncode:raise RuntimeError('Failed: '+label)

commands=[(k,v) for k,v in plan.items() if k.startswith('C.'+module+'-') and k.endswith('.module')]
if len(commands)!=1:raise RuntimeError('Ambiguous compile')
execute('entry-compile',commands[0][1]['args'],240)
for _,v in plan.items():
    if v.get('description')==f'Wrapping AST for {module} for debugging':execute('entry-wrap',v['args'],30)
links=[v for k,v in plan.items() if k.startswith('C.'+module+'-') and k.endswith('.exe')]
if len(links)!=1:raise RuntimeError('Ambiguous link')
link=links[0]
for path in link['inputs']:
    if path.endswith('Objects.LinkFileList'):
        aux=next(v for v in plan.values() if path in v.get('outputs',[]) and v.get('tool')=='write-auxiliary-file')
        objects=[p for p in aux['inputs'] if p!='<link-file-list>']
        if any(not Path(p).is_file() for p in objects):raise RuntimeError('Missing object')
        Path(path).parent.mkdir(parents=True,exist_ok=True)
        Path(path).write_text('\n'.join(json.dumps(p) for p in objects)+'\n')
execute('entry-link',link['args'],120)
portable=mode in ['wasm','embedded']
artifact=cache/('wasm32-unknown-wasip1/debug/'+module+'.wasm' if portable else 'arm64-apple-macosx/debug/'+module)
groups=['general'] if general else [str(i) for i in ([6,8,12,14] if mode=='asan' else [6,7,8,12,14])] if public else ['6','12']
for group in groups:
    command=['/usr/local/bin/node','Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs',str(artifact),group] if portable else [str(artifact)]+([] if general else [group])
    execute('entry-proof-'+group,command,120)
    if 'data race detected' in (out/('entry-proof-'+group+'.log')).read_text():raise RuntimeError('Entry isolation warning')
(out/'entrypoint-prior-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
record['runs'].extend(runs)
record.setdefault('artifacts',{})[str(artifact.relative_to(root))]=hashlib.sha256(artifact.read_bytes()).hexdigest()
inputs[key]=hashlib.sha256(source.read_bytes()).hexdigest()
record['entrypointRepair']='The synchronous main retains required MainActor isolation and delegates to a nonisolated local runner; all retained production inputs match and the rebuilt entry point executes the recorded cases without actor-isolation diagnostics.'
(out/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
(out/'result.json').write_text(json.dumps(record,indent=2)+'\n')
