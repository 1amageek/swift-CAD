#!/usr/bin/env python3
"""Verify unchanged proof premises in an independent latest-main composition."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('checkout',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[3]
base=Path(__file__).resolve().parent
out=base/'integration';out.mkdir(exist_ok=True)
lanes=['native','wasm','embedded','general-native','general-asan','general-wasm','general-embedded','public-native','public-asan','public-wasm','public-embedded']
bindings={};products={}
for lane in lanes:
    folder=base/lane;r=json.loads((folder/'result.json').read_text())
    if r.get('success') is not True:raise RuntimeError('Unsuccessful lane: '+lane)
    inputs=json.loads((folder/'inputs.json').read_text())
    for path,expected in inputs.items():
        p=args.checkout/path
        if path.endswith('/Package.swift') and r.get('retainedPackagePremise'):
            p=args.checkout/r['retainedPackagePremise']
        actual=hashlib.sha256(p.read_bytes()).hexdigest()
        if actual!=expected:raise RuntimeError('Changed premise: '+lane+':'+path)
    for path,expected in r['artifacts'].items():
        if hashlib.sha256((root/path).read_bytes()).hexdigest()!=expected:
            raise RuntimeError('Changed retained artifact: '+path)
        products[path]=expected
    bindings[lane]=dict(inputCount=len(inputs),inputsSHA256=hashlib.sha256((folder/'inputs.json').read_bytes()).hexdigest(),resultSHA256=hashlib.sha256((folder/'result.json').read_bytes()).hexdigest())
print('PASS all retained source premises and artifact bindings',flush=True)
runs=[]
public=root/'.build/di-m2-production-native/arm64-apple-macosx/debug/IssuedGraphProof'
legacy=public.with_name('NativeExactGeometricProof')
for label,command in [(f'public-{g}',[str(public),str(g)]) for g in [6,7,8,12,14]]+[(g,[str(legacy),g]) for g in ['public-cs-weighted','public-ssi-endpoints']]:
    start=time.monotonic()
    with (out/(label+'.log')).open('w') as log:
        r=subprocess.run(command,cwd=args.checkout,stdout=log,stderr=subprocess.STDOUT,timeout=120)
    run=dict(label=label,command=command,timeoutSeconds=120,elapsedSeconds=round(time.monotonic()-start,3),exitCode=r.returncode)
    runs.append(run);print(json.dumps(run),flush=True)
    if r.returncode:raise RuntimeError('Failed integration: '+label)
record=dict(success=True,checkout=str(args.checkout),composedCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=args.checkout,text=True).strip(),lanes=bindings,artifacts=products,runs=runs)
(out/'result.json').write_text(json.dumps(record,indent=2)+'\n')
