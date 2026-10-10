#!/usr/bin/env python3
"""Build current source/DI overlays and exercise real retained/Native lift paths."""
import argparse,hashlib,json,os,subprocess,time,uuid,yaml
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);p.add_argument('--output',type=Path);p.add_argument('--reuse-compile',type=Path);args=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/args.lane;out.mkdir(parents=True,exist_ok=False)
scratch=root/'.build/m4-coons-lift-actual'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
reused=None
if args.reuse_compile:
 reused=json.loads((args.reuse_compile/'runs.json').read_text())[0]
 assert reused['label']=='compile-adapters' and reused['exitCode']==0
 scratch=Path(reused['command'][reused['command'].index('-o')+1]).parent
checks={};replaced={};runs=[]
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def admit(p,h=None):
 p=Path(p).resolve();h=h or digest(p);assert digest(p)==h,str(p)
 assert str(p) not in checks or checks[str(p)]==h
 checks[str(p)]=h;return p
def receipt(path):
 path=admit(path);r=json.loads(path.read_text());assert r['success']
 for group in ['inputs','product']:
  for n,h in r[group].items():
   current=Path(n)
   if digest(current)!=h and any(x in n for x in ['/Sources/CADGeometry/OriginalSourceIssuance/','/Sources/CADGeometry/OriginalDomainIdentity/']) and current.suffix=='.swift':
    local=current.relative_to(root)
    old=subprocess.check_output(['git','show','be4d80ad:'+str(local)],cwd=root)
    assert hashlib.sha256(old).hexdigest()==h,n
    replaced[n]=h
   else:admit(n,h)
 for n,h in r['logs'].items():admit(path.parent/Path(n).name,h)
 return r
def run(label,cmd,seconds=120):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:
  r=subprocess.run(list(map(str,cmd)),cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=seconds)
 runs.append(dict(label=label,command=list(map(str,cmd)),timeoutSeconds=seconds,elapsedSeconds=time.monotonic()-start,exitCode=r.returncode))
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,r.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if r.returncode:raise SystemExit(r.returncode)
 if label=='proof':
  output=(out/(label+'.log')).read_text()
  assert 'FAIL' not in output,'Runtime failure marker is not successful evidence'
  for marker in ['PASS actual retained boundary-correction host','PASS retained atlas Native pcurve','PASS actual original Coons host','PASS actual Coons atlas Native pcurve']:
   assert marker in output,marker
admit(__file__)
prior=receipt(root/'Tests/OriginalPeriodicLiftVerification/Evidence'/args.lane/'receipt.json')
prior_actual=receipt(root/'Tests/OriginalPeriodicLiftVerification/Evidence'/('actual-'+args.lane)/'receipt.json')
product=Path(next(iter(prior['product'])));build=product.parents[2];modules=product.parent/'Modules'
plan_path=admit(build/'debug.yaml');plan=yaml.load(plan_path.read_text(),Loader=yaml.CSafeLoader)['commands']
def options(name):
 original=next(v['args'] for k,v in plan.items() if k.startswith('C.'+name) and k.endswith('.module'))
 swift=Path(original[0]);admit(swift);flags=[];i=1;source_list=None
 skip_value={'-module-name','-emit-module-path','-output-file-map','-index-store-path','-module-cache-path','-emit-objc-header-path'}
 skip={'-emit-dependencies','-emit-module','-incremental','-c','-parseable-output','-serialize-diagnostics','-enable-batch-mode','-emit-objc-header','-DORIGINAL_SOURCE_ISOLATED_VERIFICATION'}
 while i<len(original):
  x=original[i]
  if x.startswith('@'):source_list=admit(x[1:]);i+=1;continue
  if x in skip_value:i+=2;continue
  if x=='-Xfrontend' and original[i+1]=='-entry-point-function-name':i+=4;continue
  if x in skip:i+=1;continue
  if x=='-D' and original[i+1]=='ORIGINAL_SOURCE_ISOLATED_VERIFICATION':i+=2;continue
  flags.append(x);i+=1
 if args.lane in ['native','asan']:flags[flags.index('-target')+1]='arm64-apple-macos15.0'
 flags[flags.index('-package-name')+1]='nativeexactrelationverification'
 return swift,flags,source_list
swift,flags,source_list=options('SourceIssuer');_,proof_flags,_=options('PeriodicLiftProof')
portable=args.lane in ['wasm','embedded']
cache=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-'+(args.lane if portable else 'native')+'-production')
cache_modules=cache/('wasm32-unknown-wasip1/debug/Modules' if portable else 'out/Products/Debug')
sources=[admit(x.strip('"')) for x in source_list.read_text().splitlines()]
for added in ['OriginalPeriodicRetainedSurfaceLiftGraphPreparing','OriginalLiftGraphSourceReading','OriginalRetainedPcurveLiftSourceReading','OriginalRetainedAtlasLiftSourceReading','OriginalFiniteRetainedAtlasLiftGraphPreparing','OriginalNativePcurveRetainedAtlasLiftSourceReading','OriginalFiniteNativePcurveRetainedAtlasLiftGraphPreparing']:
 sources.append(admit(root/'Sources/CADGeometry/OriginalSourceIssuance'/(added+'.swift')))
actual_names=['BSplineSurface3D+OriginalSourceReading','OriginalBSplineSurfaceSnapshotProvider','OriginalNativeSurfaceFamilySnapshotProvider','BSplineCurve2D+OriginalSourceReading','OriginalBSplinePcurveSnapshotProvider','OriginalNativeSurfaceLiftSnapshot','OriginalNativeSurfaceLiftSnapshotProvider','OriginalAffinePcurveSnapshot','OriginalAffinePcurveSnapshotProvider','OriginalAffineSurfaceLiftSnapshot','OriginalAffineSurfaceLiftSnapshotProvider']
header='import L0\nimport L1\nimport struct CADGeometry.BSplineSurface3D\nimport enum CADGeometry.Surface3D\nimport struct CADGeometry.BSplineCurve2D\nimport struct CADGeometry.SurfaceLiftCurve3D\nimport enum CADGeometry.SurfaceParameterCurve\n'
for name in actual_names:
 original=admit(root/'Sources/CADGeometry/OriginalSourceIssuance'/(name+'.swift'))
 generated=scratch/(name+'.swift');generated.write_text(header+original.read_text());sources.append(admit(generated))

(out/'inputs-before-compile.json').write_text(json.dumps(dict(inputs=checks,replacedOldSourceInputs=replaced),indent=2)+'\n')
archives=[]
all_files=[]
for original in sources:
 # Actual adapters were already copied with independent imports; use their originals.
 if original.parent==scratch: original=root/'Sources/CADGeometry/OriginalSourceIssuance'/original.name
 if original.name in [p.name for p in all_files]:continue
 all_files.append(original)
for folder,children,names in os.walk(root/'Tests/OriginalGraphRelationVerification/Sources/DI0',followlinks=True):
 for filename in names:
  if filename.endswith('.swift'):all_files.append(admit(Path(folder)/filename))
for folder,children,names in os.walk(root/'Tests/OriginalGraphRelationVerification/Sources/DI',followlinks=True):
 children[:]=[x for x in children if x!='ExactParameterDomain']
 for filename in names:
  if filename.endswith('.swift'):all_files.append(admit(Path(folder)/filename))
for name in ['OriginalRetainedLiftHostSnapshotting','OriginalRetainedAtlasSurfaceLiftSnapshot','OriginalRetainedAtlasSurfaceLiftSnapshotProvider','OriginalBoundaryCorrectionSnapshot','OriginalBoundaryCorrectionSnapshotProvider','OriginalNativePcurveRetainedAtlasLiftSnapshot','OriginalNativePcurveRetainedAtlasLiftSnapshotProvider','OriginalCoonsAtlasSnapshot','OriginalCoonsAtlasSnapshotProvider']:
 all_files.append(admit(root/'Sources/CADGeometry/OriginalSourceIssuance'/(name+'.swift')))
for name in ['OriginalCoons/OriginalCoonsRationalDifferentialAtlas.swift','OriginalCoons/BoundaryCorrection/OriginalBoundaryCorrectedRationalAtlas.swift','OriginalCoonsIntersectionSources/OriginalCoonsHomogeneousAtlas.swift']:
 all_files.append(admit(root/'Sources/CADGeometry'/name))
assert all(n in {str(x.resolve()) for x in all_files} for n in replaced),'Changed prior source must be freshly compiled'
compiled=[]
for i,original in enumerate(all_files):
 destination=scratch/(str(i)+'-'+original.name)
 text=original.read_text()
 # These imports are assembly headers only. No expression or declaration changes.
 expected='import CADCore\n@testable import CADGeometry\n'+text
 if reused:assert destination.read_text()==expected,str(destination)
 else:destination.write_text(expected)
 compiled.append(admit(destination))
# Actual source/DI types share the admitted numerical lower ABI in this lane.
# No independent L0/L1 declarations are imported or linked.
archive=scratch/'libRetainedHostAdapters.a'
command=list(map(str,[swift,'-I',scratch,'-I',cache_modules,*flags,'-enable-testing','-emit-library','-static','-emit-module','-module-name','RetainedHostAdapters',*compiled,'-emit-module-path',scratch/'RetainedHostAdapters.swiftmodule','-o',archive]))
if reused:
 assert command==reused['command']
 admit(args.reuse_compile/'compile-adapters.log');admit(args.reuse_compile/'runs.json')
 runs.append(dict(reused,label='reused-compile-adapters'))
else:run('compile-adapters',command)
admit(archive);admit(scratch/'RetainedHostAdapters.swiftmodule')
# Bind unchanged numerical producer dependencies to the original actual-source receipt.
derivative_receipt=admit(root/'Tests/OriginalDerivativeSurfaceIntakeVerification/Evidence'/args.lane/'receipt.json')
dr=json.loads(derivative_receipt.read_text());compiled_original={str(x.resolve()) for x in all_files}
excluded={}
for n,h in dr['inputs'].items():
 if n.endswith('/Sources/CADGeometry/RollingBall/RollingBallBlendSurface3D.swift'):
  excluded[n]={'sha256':h,'reason':'Unselected rolling-ball numerical branch; boundary-correction lift never invokes it.'};continue
 if digest(n)!=h and str(Path(n).resolve()) in compiled_original:replaced[n]=h
 else:admit(n,h)
actual_root=Path(next(iter(prior_actual['product']))).parent
archives=[archive]
for name in ['CachedCADCore','CachedCADGeometry','CachedHashTreeCollections','CachedInternalCollectionsUtilities']:archives.append(admit(actual_root/('lib'+name+'.a')))
proof=admit(base/'ActualProof.swift')
old_proof=admit(root/'Tests/OriginalRetainedHostLiftVerification/ActualProof.swift')
regression=scratch/'RetainedHostRegression.swift'
regression.write_text(old_proof.read_text().replace('@main struct ActualRetainedHostLiftProof','struct ActualRetainedHostLiftProof'))
admit(regression)
old_native=admit(root/'Tests/OriginalRetainedNativePcurveLiftVerification/ActualProof.swift')
native_regression=scratch/'NativePcurveRegression.swift'
native_regression.write_text(old_native.read_text().replace('@main struct ActualNativePcurveRetainedHostProof','struct ActualNativePcurveRetainedHostProof'))
admit(native_regression)
coons_affine=admit(base/'AffineProof.swift');extra=[]
if portable:extra+=['-Xlinker','-z','-Xlinker','stack-size=67108864']
if args.lane=='embedded':
 old=json.loads((root/'Tests/OriginalDomainConsumerVerification/Evidence/M6/embedded/receipt.json').read_text())
 extra+=['-Xlinker','-lc++','-Xlinker','-lswift_Concurrency',str(admit(old['unicode_data_tables']['path'],old['unicode_data_tables']['sha256']))]
artifact=scratch/('ActualRetainedHostLiftProof.wasm' if portable else 'ActualRetainedHostLiftProof')
link_node=next(v for k,v in plan.items() if k.startswith('C.PeriodicLiftProof') and k.endswith('.exe'))
for i,x in enumerate(link_node['args']):
 if x=='-Xclang-linker':extra.extend([x,link_node['args'][i+1]])
run('compile-link',[swift,'-I',scratch,'-I',cache_modules,*flags,'-parse-as-library','-emit-executable','-module-name','ActualRetainedHostLiftProof',regression,native_regression,coons_affine,proof,*archives,*extra,'-o',artifact])
admit(artifact)
for n,h in checks.items():assert digest(n)==h,n
runtime=[artifact]
if portable:runtime=[admit('/usr/local/bin/node'),admit(base/'RunWASI.mjs'),artifact]
run('proof',runtime,180)
for log in out.glob('*.log'):
 assert not any(x in log.read_text() for x in ['actor-isolated function','data race detected','null function','function signature mismatch']),str(log)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,replacedOldSourceInputs=replaced,product={str(artifact):digest(artifact)},excludedCachedBranches=excluded,runs=runs,logs={x.name:digest(x) for x in out.glob('*.log')},scope='Fresh original Coons homogeneous producer, sealed source/host, lift and DI on receipt-bound numerical children; actual Coons affine/Native pcurves plus unchanged boundary-correction/Native retained-host regressions. No broad CAD or L2-L6 build. General nonrational/priority images and full M4-M8 remain open.'),indent=2)+'\n')
print('PASS actual source/artifact/runtime premises',len(checks),flush=True)
