#!/usr/bin/env python3
"""Verify original polyline source/domain bodies with unchanged admitted children."""
import argparse, hashlib, json, subprocess, time, uuid
from pathlib import Path

p=argparse.ArgumentParser(); p.add_argument('lane',choices=['native','asan','wasm','embedded'])
p.add_argument('--output',type=Path,required=True); args=p.parse_args()
base=Path(__file__).resolve().parent; root=base.parents[1]; out=args.output.resolve()
out.mkdir(parents=True,exist_ok=False)
scratch=root/'.build/m4-polyline-pcurve'/args.lane/uuid.uuid4().hex; scratch.mkdir(parents=True)
checks={}; runs=[]
def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def add(path,expected=None):
 path=Path(path).resolve(); h=expected or digest(path)
 assert digest(path)==h,str(path)
 assert str(path) not in checks or checks[str(path)]==h,str(path)
 checks[str(path)]=h; return path
def run(label,command):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:
  result=subprocess.run(list(map(str,command)),cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 runs.append(dict(label=label,command=list(map(str,command)),timeoutSeconds=120,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode))
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n')
 print(label,result.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode: raise SystemExit(result.returncode)

prior=add(root/'Tests/OriginalRequestedOrderLiftVerification/Evidence'/(args.lane+'-accepted')/'receipt.json')
r=json.loads(prior.read_text()); assert r['success']
for group in ['inputs','product']:
 for name,h in r[group].items(): add(name,h)
for name,h in r['logs'].items(): add(prior.parent/name,h)
add(__file__)
caller=next(x['command'] for x in r['runs'] if x['label']=='compile-producers')
flags=caller[:caller.index('-emit-library')]
names=['OriginalSourceIssuance/OriginalPolylinePcurveSnapshot','OriginalSourceIssuance/OriginalPolylinePcurveSnapshotProvider']
names += ['OriginalSourceIssuance/'+x for x in ['OriginalRetainedCurveSourceReading','OriginalFiniteRetainedCurveCharts','OriginalFiniteRetainedCurveChartPreparing','DefaultOriginalFiniteRetainedCurveChartPreparer']]
names += ['OriginalDomainIdentity/OriginalDomainCoverage/'+x for x in ['DefaultOriginalRetainedCurveDomainIssuer','OriginalRetainedCurveDomainCover','OriginalRetainedCurveChartOccurrence','OriginalRetainedCurveDomainIssuing']]
files=[]
for name in names:
 original=add(root/'Sources/CADGeometry'/(name+'.swift'))
 generated=scratch/(original.name)
 generated.write_text('import CADCore\n@testable import CADGeometry\n'+original.read_text())
 files.append(add(generated))
archive=scratch/'libPolylinePcurveAdapters.a'
run('compile-source-domain',[*flags,'-emit-library','-static','-emit-module','-module-name','PolylinePcurveAdapters',*files,'-emit-module-path',scratch/'PolylinePcurveAdapters.swiftmodule','-o',archive])
add(archive); add(scratch/'PolylinePcurveAdapters.swiftmodule')
command=next(x['command'] for x in r['runs'] if x['label']=='compile-link')
# Keep the actual unchanged numerical/DI children and target linker options.
proof_flags=flags
extra=[]
for i,arg in enumerate(command):
 if arg=='-Xclang-linker': extra += [arg,command[i+1]]
 if arg=='-Xlinker' and command[i+1] in ['-z','stack-size=67108864','-lc++','-lswift_Concurrency']:
  extra += [arg,command[i+1]]
 if arg.endswith('libswiftUnicodeDataTables.a'): extra.append(arg)
archives=[x for x in command if Path(x).name in ['libCachedCADCore.a','libCachedHashTreeCollections.a','libCachedInternalCollectionsUtilities.a']]
# Original cached CADGeometry has no weakened entries for this additive unit.
cached=next(x for x in r['inputs'] if x.endswith('libCachedCADGeometry.a'))
if cached not in archives: archives.append(cached)
lower=[]
fixture=add(base/'Proof.swift'); artifact=scratch/('PolylinePcurveProof.wasm' if args.lane in ['wasm','embedded'] else 'PolylinePcurveProof')
run('compile-link',[*proof_flags,'-I',scratch,'-parse-as-library','-emit-executable','-module-name','PolylinePcurveProof',fixture,archive,*archives,*lower,*extra,'-o',artifact])
add(artifact)
runtime=next(x['command'] for x in r['runs'] if x['label']=='proof').copy(); runtime[-1]=str(artifact)
for name,h in checks.items(): assert digest(name)==h,name
run('proof',runtime)
for log in out.glob('*.log'):
 assert not any(x in log.read_text() for x in ['warning:','error:','null function','function signature mismatch','data race detected']),str(log)
for name,h in checks.items(): assert digest(name)==h,name
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,product={str(artifact):digest(artifact)},runs=runs,logs={x.name:digest(x) for x in out.glob('*.log')},scope='Fresh additive polyline source/domain bodies; original exact arc-length/retained-chart/numerical children reused after hash admission. No broad CAD or L2-L6 rebuild.'),separators=(',',':'))+'\n')
print('PASS original polyline source/domain',len(checks),flush=True)
