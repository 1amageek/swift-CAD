#!/usr/bin/env python3
"""Verify actual derivative Surface3D lift hosts on unchanged numerical products."""
import argparse,hashlib,json,subprocess,time,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);p.add_argument('--output',type=Path);p.add_argument('--reuse-compile',type=Path);args=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/args.lane;out.mkdir(parents=True,exist_ok=False)
checks={}
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def add(p,h=None):
 p=Path(p).resolve();h=h or digest(p);assert digest(p)==h,str(p)
 assert str(p) not in checks or checks[str(p)]==h
 checks[str(p)]=h;return p
prior=add(root/'Tests/OriginalCoonsLiftVerification/Evidence'/args.lane/'receipt.json');r=json.loads(prior.read_text());assert r['success']
add(__file__)
for group in ['inputs','product']:
 for n,h in r[group].items():add(n,h)
for n,h in r['logs'].items():add(prior.parent/Path(n).name,h)
reused=None
if args.reuse_compile:
 reused=next(c for c in json.loads((args.reuse_compile/'runs.json').read_text()) if c['label']=='compile-adapters');assert reused['exitCode']==0
 scratch=Path(reused['command'][reused['command'].index('-o')+1]).parent
 previous=json.loads((args.reuse_compile/'inputs-before-compile.json').read_text())
 for n,h in previous.items():
  if n not in [str(Path(__file__).resolve()),str(base/'Proof.swift')]:add(n,h)
else:
 scratch=root/'.build/m4-derivative-lift-host'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
# The admitted numerical payload differs only by these three additive methods.
# Compile their exact source bodies, using the unchanged original private fields.
model=add(root/'Sources/CADGeometry/OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeSurface3D.swift')
text=model.read_text();start=text.index('    package func hasOriginalDerivativeProjection');end=text.index('    /// Source-law witness;',start)
methods=text[start:end]
cache_receipt=add(root/'Tests/OriginalDomainConsumerVerification/Evidence/M6'/('receipt.json' if args.lane in ['native','asan'] else args.lane+'/receipt.json'))
old=json.loads(cache_receipt.read_text())['source_sha256'][str(model.relative_to(root))]
cache_source=subprocess.check_output(['git','show','d963399f:'+str(model.relative_to(root))],cwd=root)
assert hashlib.sha256(cache_source).hexdigest()==old
assert text[:start]+text[end:]==cache_source.decode(),'Numerical storage/constructor/public body changed'
helpers=scratch/'DerivativePayloadHelpers.swift';helpers.write_text('import CADCore\n@testable import CADGeometry\nextension OriginalPlaneDerivativeSurface3D {\n'+methods+'}\n');add(helpers)
command=next(c['command'] for c in r['runs'] if c['label'].endswith('compile-adapters')).copy()
archive=scratch/'libRetainedHostAdapters.a';command[command.index('-o')+1]=str(archive)
command[command.index('-emit-module-path')+1]=str(scratch/'RetainedHostAdapters.swiftmodule')
command[1:1]=['-I',str(scratch)]
first_source=next(i for i,x in enumerate(command) if x.endswith('.swift'))
helper_archive=scratch/'libDerivativePayloadAccess.a'
helper_command=command[:first_source]+[str(helpers),'-emit-module-path',str(scratch/'DerivativePayloadAccess.swiftmodule'),'-o',str(helper_archive)]
helper_command[helper_command.index('-module-name')+1]='DerivativePayloadAccess'
helper_command[1:1]=['-Xfrontend','-disable-access-control']
for relative in ['OriginalCoons/PlaneDerivatives/OriginalPlaneDerivativeRationalAtlas.swift',
 'OriginalSourceIssuance/OriginalPlaneDerivativeSurfaceSnapshot.swift',
 'OriginalSourceIssuance/OriginalPlaneDerivativeSurfaceSnapshotProvider.swift',
 'OriginalSourceIssuance/OriginalPlaneDerivativeSurfaceSnapshotProvider+LiftHost.swift']:
 source=add(root/'Sources/CADGeometry'/relative);generated=scratch/source.name
 generated.write_text('import CADCore\n@testable import CADGeometry\n@testable import DerivativePayloadAccess\n'+source.read_text());add(generated);command.insert(command.index('-emit-module-path'),str(generated))

link=next(c['command'] for c in r['runs'] if c['label']=='compile-link').copy()
link[1:1]=['-I',str(scratch)]
old_archive=next(x for x in link if x.endswith('/libRetainedHostAdapters.a'));link[link.index(old_archive)]=str(archive);link.insert(link.index('-o'),str(helper_archive))
link.remove(str(root/'Tests/OriginalCoonsLiftVerification/AffineProof.swift'))
link[link.index(str(root/'Tests/OriginalCoonsLiftVerification/ActualProof.swift'))]=str(add(base/'Proof.swift'))
link.insert(link.index('-o'),str(add(base/'Shape.swift')))
artifact=scratch/('DerivativeLiftHostProof.wasm' if args.lane in ['wasm','embedded'] else 'DerivativeLiftHostProof');link[link.index('-o')+1]=str(artifact)
runs=[]
def run(label,cmd):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 runs.append(dict(label=label,command=cmd,timeoutSeconds=120,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode))
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,result.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise SystemExit(result.returncode)
 if label=='proof':
  output=(out/(label+'.log')).read_text();assert 'FAIL' not in output
  for marker in ['PASS derivative actual host/lift/DI','PASS derivative host resources/depth/cancel/lifetime','PASS actual retained boundary-correction host','PASS retained atlas Native pcurve']:assert marker in output,marker
(out/'inputs-before-compile.json').write_text(json.dumps(checks,indent=2)+'\n')
run('compile-payload-helpers',helper_command);add(helper_archive);add(scratch/'DerivativePayloadAccess.swiftmodule')
if reused:
 assert reused['command']==command
 add(args.reuse_compile/'compile-adapters.log');add(args.reuse_compile/'runs.json');add(args.reuse_compile/'inputs-before-compile.json')
 runs.append(dict(reused,label='reused-compile-adapters'))
else:run('compile-adapters',command)
add(archive);add(scratch/'RetainedHostAdapters.swiftmodule')
run('compile-link',link);add(artifact)
runtime=next(c['command'] for c in r['runs'] if c['label']=='proof').copy();runtime[-1]=str(artifact);run('proof',runtime)
for log in out.glob('*.log'):
 assert not any(x in log.read_text() for x in ['warning:','error:','actor-isolated function','data race detected','null function','function signature mismatch']),str(log)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,product={str(artifact):digest(artifact)},runs=runs,logs={p.name:digest(p) for p in out.glob('*.log')},numericalPayload={'sourceSHA256':old,'currentSHA256':digest(model),'difference':'Only three source-identical additive helper methods; storage, initializer and existing public/query bodies are identical. Helpers are compiled against original retained private fields with verification-only access-control disabling.'}),indent=2)+'\n')
