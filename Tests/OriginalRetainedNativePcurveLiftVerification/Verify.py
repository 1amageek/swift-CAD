#!/usr/bin/env python3
"""Build current source/DI overlays and exercise real retained/Native lift paths."""
import argparse,hashlib,json,os,subprocess,time,uuid,yaml
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);p.add_argument('--output',type=Path);args=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/args.lane;out.mkdir(parents=True,exist_ok=False)
scratch=root/'.build/m4-retained-native-pcurve-regression'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
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
   if digest(current)!=h and '/Sources/CADGeometry/OriginalSourceIssuance/' in n and current.suffix=='.swift':
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
assert all(n in checks for n in replaced),'Changed prior source must be freshly compiled'
(out/'inputs-before-compile.json').write_text(json.dumps(dict(inputs=checks,replacedOldSourceInputs=replaced),indent=2)+'\n')
archives=[]
for name,definition,files in [('SourceIssuer','ORIGINAL_SOURCE_ISOLATED_VERIFICATION',sources),('DI0','EXACT_DOMAIN_ISOLATED_VERIFICATION',None),('DI','ORIGINAL_DOMAIN_ISOLATED_VERIFICATION',None)]:
 if files is None:
  files=[]
  for folder,children,names in os.walk(root/'Tests/OriginalGraphRelationVerification/Sources'/name,followlinks=True):
   if name=='DI':children[:]=[x for x in children if x!='ExactParameterDomain']
   for filename in names:
    if filename.endswith('.swift'):files.append(admit(Path(folder)/filename))
 archive=scratch/('lib'+name+'.a')
 run('compile-'+name,[swift,'-I',scratch,'-I',cache_modules,'-I',modules,*flags,'-D',definition,'-emit-library','-static','-emit-module','-module-name',name,*sorted(files),'-emit-module-path',scratch/(name+'.swiftmodule'),'-o',archive])
 archives.append(admit(archive));admit(scratch/(name+'.swiftmodule'))
actual_root=Path(next(iter(prior_actual['product']))).parent
for name in ['CachedCADCore','CachedCADGeometry','CachedHashTreeCollections','CachedInternalCollectionsUtilities']:archives.append(admit(actual_root/('lib'+name+'.a')))
link_list=admit(next(build.rglob('PeriodicLiftProof.product/Objects.LinkFileList')));lower=[]
for line in link_list.read_text().splitlines():
 path=Path(line.strip('"'))
 if any(x+'.build' in str(path) for x in ['SourceIssuer','PeriodicLiftProof']):continue
 assert str(path) in checks;lower.append(path)
fixtures=[]
for directory,name,generated_name in [('OriginalPeriodicLiftVerification','Checks.swift','SourceChecks.swift'),('OriginalPeriodicLiftVerification','Proof.swift','SourceProof.swift'),('OriginalPeriodicLiftVerification','ActualProof.swift','ActualSourceProof.swift'),('OriginalPeriodicLiftDomainVerification','Checks.swift','DomainChecks.swift'),('OriginalPeriodicLiftDomainVerification','Proof.swift','DomainProof.swift'),('OriginalPeriodicLiftDomainVerification','ActualProof.swift','ActualDomainProof.swift')]:
 original=admit(root/'Tests'/directory/name);generated=scratch/generated_name
 text=original.read_text().replace('@main struct','struct')
 if generated_name=='SourceChecks.swift':text=text.replace('func position<S: OriginalSurfaceLiftSourceReading>', 'func position<S: OriginalLiftSourceReading>')
 generated.write_text(text);fixtures.append(admit(generated))
old_retained=admit(root/'Tests/OriginalPeriodicRetainedLiftVerification/RetainedLiftProof.swift')
generated=scratch/'RetainedLiftRegression.swift';generated.write_text(old_retained.read_text().replace('@main struct','struct'));fixtures.append(admit(generated))
fixtures += [admit(root/'Tests/OriginalDomainIdentityVerification/Sources/Fixtures/NativeSource.swift'),admit(root/'Tests/OriginalRetainedHostLiftVerification/Proof.swift')]
link_node=next(v for k,v in plan.items() if k.startswith('C.PeriodicLiftProof') and k.endswith('.exe'))
for i,x in enumerate(link_node['args']):
 if x=='-Xclang-linker':proof_flags.extend([x,link_node['args'][i+1]])
extra=[]
if portable:extra+=['-Xlinker','-z','-Xlinker','stack-size=67108864']
if args.lane=='embedded':
 old=json.loads((root/'Tests/OriginalDomainConsumerVerification/Evidence/M6/embedded/receipt.json').read_text())
 extra+=['-Xlinker','-lc++','-Xlinker','-lswift_Concurrency',str(admit(old['unicode_data_tables']['path'],old['unicode_data_tables']['sha256']))]
artifact=scratch/('RetainedHostLiftProof.wasm' if portable else 'RetainedHostLiftProof')
run('compile-link',[swift,'-I',scratch,'-I',cache_modules,'-I',modules,*proof_flags,'-parse-as-library','-emit-executable','-module-name','RetainedHostLiftProof',*fixtures,*archives,*lower,*extra,'-o',artifact])
admit(artifact)
for n,h in checks.items():assert digest(n)==h,n
runtime=[artifact]
if portable:runtime=[admit('/usr/local/bin/node'),admit(root/'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'),artifact]
run('proof',runtime,180)
for log in out.glob('*.log'):
 assert not any(x in log.read_text() for x in ['actor-isolated function','data race detected','null function','function signature mismatch']),str(log)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,replacedOldSourceInputs=replaced,product={str(artifact):digest(artifact)},runs=runs,logs={x.name:digest(x) for x in out.glob('*.log')},scope='Fresh current source/adapters, DI0/DI and actual retained/Native lift fixtures; unchanged L0/L1 and numerical children admitted before/after. No CAD or L2-L6 build.'),indent=2)+'\n')
print('PASS current source/artifact/runtime premises',len(checks),flush=True)
