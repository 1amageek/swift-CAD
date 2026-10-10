#!/usr/bin/env python3
"""Verify retained host-specific inherited depth without rebuilding source modules."""
import argparse,hashlib,json,subprocess,time,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);args=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=base/'Evidence'/('caller-'+args.lane);out.mkdir(exist_ok=False)
prior=base/'Evidence'/('actual-'+args.lane)/'receipt.json';r=json.loads(prior.read_text());assert r['success']
checks={}
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def add(p,h=None):
 p=Path(p).resolve();h=h or digest(p);assert digest(p)==h,str(p);checks[str(p)]=h;return p
add(prior);add(__file__)
for group in ['inputs','product']:
 for n,h in r[group].items():add(n,h)
for n,h in r['logs'].items():add(prior.parent/n,h)
scratch=root/'.build/m4-retained-native-pcurve-caller'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
original=add(base/'ActualProof.swift')
command=next(x['command'] for x in r['runs'] if x['label']=='compile-link').copy()
command[command.index(str(original))]=str(add(base/'CallerProof.swift'))
adapter_command=next(x['command'] for x in r['runs'] if x['label'].endswith('compile-adapters'))
flags=adapter_command[:max(i for i,x in enumerate(adapter_command) if x=='-enable-testing')]
names=['OriginalRollingBallCurveSnapshot','OriginalRollingBallCurveSnapshotProvider','OriginalRollingBallCurveGraphEvidence','OriginalRollingBallCurveGraphCoverage','DefaultOriginalRollingBallCurveGraphPreparer','BSplineCurve3D+OriginalSourceReading','OriginalBSplineCurveSnapshotProvider','OriginalNativeCurveFamilySnapshotProvider']
header='import CADCore\n@testable import func CADGeometry.exactScalarPayloadBytes\n@testable import RetainedHostAdapters\nimport enum CADGeometry.Curve3D\nimport struct CADGeometry.BSplineCurve3D\nimport struct CADGeometry.BSplineSurface3D\nimport struct CADGeometry.BSplineCurve2D\nimport struct CADGeometry.OriginalExactScalarDomain\nimport protocol CADGeometry.ExactScalarAdmission\nimport enum CADGeometry.ExactScalarFailure\n'
files=[]
for name in names:
 source=add(root/'Sources/CADGeometry/OriginalSourceIssuance'/(name+'.swift'))
 generated=scratch/(name+'.swift');generated.write_text(header+source.read_text());files.append(add(generated))
archive=scratch/'libCallerAdapters.a'
compile_command=[*flags,'-I',str(scratch),'-enable-testing','-emit-library','-static','-emit-module','-module-name','CallerAdapters',*map(str,files),'-emit-module-path',str(scratch/'CallerAdapters.swiftmodule'),'-o',str(archive)]
command[command.index('-parse-as-library'):command.index('-parse-as-library')]=['-I',str(scratch)]
command.insert(command.index('-o'),str(archive))
artifact=scratch/('RetainedLiftCallerProof.wasm' if args.lane in ['wasm','embedded'] else 'RetainedLiftCallerProof');command[command.index('-o')+1]=str(artifact)
runs=[]
def run(label,cmd):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 runs.append(dict(label=label,command=cmd,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode,timeoutSeconds=120))
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,result.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise SystemExit(result.returncode)
run('compile-caller',compile_command);add(archive);add(scratch/'CallerAdapters.swiftmodule')
run('compile-link',command);add(artifact)
runtime=next(x['command'] for x in r['runs'] if x['label']=='proof').copy();runtime[-1]=str(artifact)
run('proof',runtime)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,product={str(artifact):digest(artifact)},runs=runs,logs={x.name:digest(x) for x in out.glob('*.log')}),indent=2)+'\n')
