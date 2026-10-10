#!/usr/bin/env python3
"""Confirm the lifetime finding against admitted unchanged lower products only."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid
import yaml

parser = argparse.ArgumentParser()
parser.add_argument('lane', choices=['native','asan','wasm','embedded'])
args = parser.parse_args()
base = Path(__file__).resolve().parent
root = base.parents[1]
out = base / 'Evidence' / ('contract-' + args.lane)
out.mkdir(exist_ok=False)
scratch = root / '.build/m4-periodic-offset-contract' / args.lane / uuid.uuid4().hex
scratch.mkdir(parents=True)
def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
accepted = base / 'Evidence' / args.lane / 'receipt.json'
r = json.loads(accepted.read_text())
checks = dict(r['inputs'])
checks.update(r['product'])
for n,h in r['logs'].items(): checks[str(accepted.parent / Path(n).name)] = h
checks[str(accepted)] = digest(accepted)
checks[__file__] = digest(__file__)
for n,h in checks.items(): assert digest(n) == h,n
product = Path(next(iter(r['product'])))
build = product.parents[2]
commands = yaml.load((build / 'debug.yaml').read_text(),Loader=yaml.CSafeLoader)['commands']
node = next(v for k,v in commands.items() if k.startswith('C.PeriodicOffsetProof') and k.endswith('.module'))
original = node['args']
source_list = Path(next(x[1:] for x in original if x.startswith('@')))
checks[str(source_list)] = digest(source_list)
sources = []
for line in source_list.read_text().splitlines():
    path = Path(line.strip().strip('"')).resolve()
    assert str(path) in checks,path
    if path.name == 'Proof.swift':
        generated = scratch / 'PeriodicFixture.swift'
        text = path.read_text()
        assert text.count('@main struct PeriodicOffsetProof') == 1
        generated.write_text(text.replace('@main struct PeriodicOffsetProof','struct PeriodicOffsetProof'))
        checks[str(generated)] = digest(generated)
        path = generated
    sources.append(str(path))
fixture = base / 'ContractProof.swift'
checks[str(fixture)] = digest(fixture)
sources.append(str(fixture))
# Preserve target/SDK/Embedded/sanitizer options; remove outputs and old entry naming.
remove_one = {'-module-name','-emit-module-path','-output-file-map','-index-store-path','-module-cache-path'}
remove_flag = {'-emit-dependencies','-emit-module','-incremental','-c','-parseable-output','-serialize-diagnostics','-enable-batch-mode'}
options=[];i=1
while i < len(original):
    x=original[i]
    if x in remove_one: i+=2;continue
    if x == '-Xfrontend' and i+1<len(original) and original[i+1]=='-entry-point-function-name': i+=4;continue
    if x in remove_flag or x.startswith('@'): i+=1;continue
    options.append(x);i+=1
link_node = next(v for k,v in commands.items() if k.startswith('C.PeriodicOffsetProof') and k.endswith('.exe'))
link_args = link_node['args']
for index,option in enumerate(link_args):
    if option == '-Xclang-linker': options.extend([option,link_args[index+1]])
link_list = next(build.rglob('PeriodicOffsetProof.product/Objects.LinkFileList'))
checks[str(link_list)] = digest(link_list)
objects=[]
for line in link_list.read_text().splitlines():
    path=Path(line.strip().strip('"'))
    if 'PeriodicOffsetProof.build' in str(path): continue
    assert str(path) in checks,path
    objects.append(str(path))
output = scratch / ('PeriodicOffsetContractProof.wasm' if args.lane in ['wasm','embedded'] else 'PeriodicOffsetContractProof')
command=[original[0],*options,'-module-name','PeriodicOffsetContractProof','-parse-as-library','-emit-executable',*sources,*objects,'-o',str(output)]
record={'inputs':checks,'runs':[],'scope':'Additional preparation/authority contract fixture; unchanged admitted lower objects, no production rebuild.'}
(out/'inputs.json').write_text(json.dumps(record,indent=2)+'\n')
def run(label,cmd):
    start=time.monotonic()
    with (out/(label+'.log')).open('w') as log:
        result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
    record['runs'].append({'label':label,'command':cmd,'timeoutSeconds':120,'elapsedSeconds':time.monotonic()-start,'exitCode':result.returncode})
    print(args.lane,label,result.returncode,round(record['runs'][-1]['elapsedSeconds'],3),flush=True)
    if result.returncode: raise SystemExit(result.returncode)
run('compile-link',command)
checks[str(output)] = digest(output)
runtime=[str(output)]
if args.lane in ['wasm','embedded']:
    node='/usr/local/bin/node';runner=root/'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'
    checks[node]=digest(node);checks[str(runner)]=digest(runner)
    runtime=[node,str(runner),str(output)]
for n,h in checks.items(): assert digest(n)==h,n
run('proof',runtime)
for n,h in checks.items(): assert digest(n)==h,n
record.update(success=True,product={str(output):digest(output)},logs={p.name:digest(p) for p in out.glob('*.log')})
(out/'receipt.json').write_text(json.dumps(record,indent=2)+'\n')
