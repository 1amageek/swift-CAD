#!/usr/bin/env python3
"""Complete only unfinished nodes of the recorded production Embedded build plan."""
import sys
from pathlib import Path
import json,hashlib,shutil,yaml
sys.argv=['public.py','embedded']
__file__=str(Path(__file__).with_name('public.py').resolve())
source=Path(__file__).read_text()
exec(source[:source.index("execute('toolchain'")])
shutil.copytree(out,out.parent/'diagnostic-embedded-repeated-build',dirs_exist_ok=True)
records=[r for r in json.loads((out/'result.json').read_text())['runs'] if r['exitCode']==0]
completed=json.loads((out/'completed-compile-nodes.json').read_text()) if (out/'completed-compile-nodes.json').exists() else []
records.extend(completed)
plan=yaml.load((cache/'debug.yaml').read_text(),Loader=yaml.CSafeLoader)['commands']

def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

premises=json.loads((out.parent/'public-native/inputs.json').read_text())
# All actual production and fixture source premises remain unchanged.
for path,expected in premises.items():
    if path == 'Tests/NativeExactRelationVerification/Sources/IssuedGraphProof/IssuedGraphProof.swift': continue
    if digest(root/path)!=expected:raise RuntimeError('Changed production source: '+path)
(out/'prebuilt-sources.json').write_text(json.dumps(premises,indent=2)+'\n')
retained={}
for module in ['CADCore','CADGeometry','InternalCollectionsUtilities','HashTreeCollections']:
    directory=cache/'wasm32-unknown-wasip1/debug'
    paths=list((directory/(module+'.build')).glob('*.o'))+[directory/'Modules'/(module+'.swiftmodule')]
    if not paths or any(not p.is_file() for p in paths):raise RuntimeError('Missing completed module: '+module)
    for p in paths:retained[str(p.relative_to(root))]=digest(p)
(out/'prebuilt-products.json').write_text(json.dumps(retained,indent=2)+'\n')
selected={}
for module in ['IssuedGraphFixtures','IssuedGraphProof']:
    key=f'C.{module}-wasm32-unknown-wasip1-debug.module'
    command=plan[key];selected[key]=command
    for input in command['inputs']:
        if input.startswith(str(root)) and not Path(input).exists():raise RuntimeError('Missing compile input: '+input)
    reuse=any(r['label']=='compile-'+module and r['command']==command['args'] for r in completed)
    if not reuse:execute('compile-'+module,command['args'],360)
    matches=[(k,v) for k,v in plan.items() if v.get('description')==f'Wrapping AST for {module} for debugging']
    if len(matches)!=1:raise RuntimeError('Ambiguous module wrap')
    key,command=matches[0];selected[key]=command
    reuse=any(r['label']=='wrap-'+module and r['command']==command['args'] for r in completed)
    if not reuse:execute('wrap-'+module,command['args'],30)
key='C.IssuedGraphProof-wasm32-unknown-wasip1-debug.exe';command=plan[key];selected[key]=command
for input in command['inputs']:
    if input.endswith('Objects.LinkFileList'):
        auxiliary=next(v for v in plan.values() if input in v.get('outputs',[]) and v.get('tool')=='write-auxiliary-file')
        # The first llbuild input is a virtual format node, not an object path.
        objects=[p for p in auxiliary['inputs'] if p != '<link-file-list>']
        missing=[p for p in objects if not Path(p).is_file()]
        if missing:raise RuntimeError('Missing original link objects: '+repr(missing[:3]))
        Path(input).parent.mkdir(parents=True,exist_ok=True)
        Path(input).write_text('\n'.join(json.dumps(p) for p in objects)+'\n')
        shutil.copyfile(input,out/'retained-Objects.LinkFileList')
(out/'retained-build-nodes.json').write_text(json.dumps(selected,indent=2)+'\n')
runtime=json.loads((out/'retained-runtime-nodes.json').read_text()) if (out/'retained-runtime-nodes.json').exists() else None
artifact=cache/'wasm32-unknown-wasip1/debug/IssuedGraphProof.wasm'
if runtime is None or digest(artifact)!=runtime['artifactSHA256']:
    execute('link',command['args'],120)
    runtime=None
else:
    records.extend(runtime['runs'])
artifact=cache/'wasm32-unknown-wasip1/debug/IssuedGraphProof.wasm'
for group in range(6,15):
    if runtime and any(r['label']==f'proof-{group}' for r in runtime['runs']):continue
    execute(f'proof-{group}',[node,'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs',str(artifact),str(group)],120)
exec(source[source.index('inputs = {}'):])
r=json.loads((out/'result.json').read_text())
r['resumeDriverSHA256']=digest(Path(__file__).with_name('resume_embedded.py'))
r['note']='Completed unchanged full production CADCore/CADGeometry modules and objects are reused; only the remaining original SwiftPM build-plan nodes are executed directly. Exact commands, objects, source premises and link list are retained.'
(out/'result.json').write_text(json.dumps(r,indent=2)+'\n')
