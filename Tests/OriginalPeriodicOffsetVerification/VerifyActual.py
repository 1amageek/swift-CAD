#!/usr/bin/env python3
"""Compose actual Native adapters with admitted current independent source/DI products."""
import argparse,hashlib,json,subprocess,time,uuid,yaml
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument('lane',choices=['native','asan','wasm','embedded'])
parser.add_argument('--output',type=Path)
args=parser.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/('actual-'+args.lane)
out.mkdir(parents=True,exist_ok=False)
scratch=root/'.build/m4-periodic-offset-actual'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
checks={};records=[]
def admit(p,h):
 p=Path(p);assert digest(p)==h,str(p)
 assert str(p) not in checks or checks[str(p)]==h
 checks[str(p)]=h
accepted=base/'Evidence'/args.lane/'receipt.json';r=json.loads(accepted.read_text())
for group in ['inputs','product']:
 for p,h in r[group].items():admit(p,h)
for p,h in r['logs'].items():admit(accepted.parent/Path(p).name,h)
admit(accepted,digest(accepted));admit(__file__,digest(__file__))
product=Path(next(iter(r['product'])));build=product.parents[2]
plan=yaml.load((build/'debug.yaml').read_text(),Loader=yaml.CSafeLoader)['commands']
def options(name):
 original=next(v['args'] for k,v in plan.items() if k.startswith('C.'+name) and k.endswith('.module'))
 remove_one={'-module-name','-emit-module-path','-output-file-map','-index-store-path','-module-cache-path'}
 remove_flag={'-emit-dependencies','-emit-module','-incremental','-c','-parseable-output','-serialize-diagnostics','-enable-batch-mode'}
 result=[];i=1
 while i<len(original):
  x=original[i]
  if x in remove_one:i+=2;continue
  if x=='-Xfrontend' and original[i+1]=='-entry-point-function-name':i+=4;continue
  if x in remove_flag or x.startswith('@'):i+=1;continue
  result.append(x);i+=1
 result[result.index('-package-name')+1]='nativeexactrelationverification'
 if args.lane in ['native','asan']:
  result[result.index('-target')+1]='arm64-apple-macos15.0'
 sources=Path(next(x[1:] for x in original if x.startswith('@')))
 admit(sources,digest(sources))
 return original[0],result,[str(Path(x.strip('"')).resolve()) for x in sources.read_text().splitlines()]
portable=args.lane in ['wasm','embedded']
legacy=root/'Tests/OriginalDomainConsumerVerification/Evidence/M6'/ (args.lane+'/receipt.json' if portable else 'receipt.json')
old=json.loads(legacy.read_text());admit(legacy,digest(legacy))
cache_root=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-'+(args.lane if portable else 'native')+'-production')
cache=cache_root/('wasm32-unknown-wasip1/debug' if portable else 'out/Products/Debug')
# Only the original Native offset numerical/validation path is exercised. Other
# shape/solver branches in cached Geometry are excluded, not current-source proof.
selected=['BSplineSurface3D.swift','BSplineBasis.swift','OffsetSurface3D.swift','Surface3D.swift','SurfaceTaylorJet.swift']
selected_prefixes=['PeriodicBSpline/','OriginalCoefficientAllocation/']
for p,h in old['source_sha256'].items():
 if p.startswith('Sources/CADCore/') or (p.startswith('Sources/CADGeometry/') and
    (p.removeprefix('Sources/CADGeometry/') in selected or p.removeprefix('Sources/CADGeometry/').startswith(tuple(selected_prefixes)))):
  admit(root/p,h)
modules=['CADCore','CADGeometry','HashTreeCollections','InternalCollectionsUtilities'];objects={n:[] for n in modules}
for p,h in old['products'].items():
 path=cache_root/p
 for module in modules:
  if path.suffix=='.o' and (path.parent.name==module+'.build' or path.stem==module):admit(path,h);objects[module].append(path)
  if path.suffix=='.swiftmodule' and (path.stem==module or path.parent.name==module+'.swiftmodule'):admit(path,h)
for n in modules:assert objects[n],n
for p,h in old['runtime_log_sha256'].items():admit(legacy.parent/p,h)
def run(label,command):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:
  result=subprocess.run(list(map(str,command)),cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 records.append(dict(label=label,command=list(map(str,command)),timeoutSeconds=120,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode))
 (out/'runs.json').write_text(json.dumps(records,indent=2)+'\n')
 print(args.lane,label,result.returncode,round(records[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise SystemExit(result.returncode)
swift,source_options,sources=options('SourceIssuer')
cache_modules=cache/'Modules' if portable else cache
source_options=['-I',str(cache_modules),'-I',str(scratch),*source_options]
actual=['BSplineSurface3D+OriginalSourceReading','OriginalBSplineSurfaceSnapshotProvider','OriginalNativeSurfaceFamilySnapshotProvider','OriginalOffsetSnapshot','OriginalOffsetSnapshotProvider']
imports='import L0\nimport SourceIssuer\n'
# These files are compiled inside SourceIssuer itself, so omit a self import.
imports='import L0\nimport struct CADGeometry.BSplineSurface3D\nimport enum CADGeometry.Surface3D\nimport struct CADGeometry.OffsetSurface3D\n'
for name in actual:
 p=root/'Sources/CADGeometry/OriginalSourceIssuance'/(name+'.swift');admit(p,digest(p))
 generated=scratch/(name+'.swift');generated.write_text(imports+p.read_text());admit(generated,digest(generated));sources.append(str(generated))
for p in sources:assert p in checks,p
(out/'inputs-before-compile.json').write_text(json.dumps(checks,indent=2)+'\n')
archive=scratch/'libSourceIssuer.a'
run('compile-source-adapters',[swift,*source_options,'-emit-library','-static','-emit-module','-module-name','SourceIssuer',*sources,'-emit-module-path',scratch/'SourceIssuer.swiftmodule','-o',archive])
admit(archive,digest(archive));admit(scratch/'SourceIssuer.swiftmodule',digest(scratch/'SourceIssuer.swiftmodule'))
archives=[]
for module,inventory in objects.items():
 a=scratch/('libCached'+module+'.a')
 run('archive-'+module,[Path(swift).parent/'llvm-ar' if portable else 'ar','-rcs',a,*inventory]);admit(a,digest(a));archives.append(str(a))
_,proof_options,_=options('PeriodicOffsetProof')
link_node=next(v for k,v in plan.items() if k.startswith('C.PeriodicOffsetProof') and k.endswith('.exe'))
for i,x in enumerate(link_node['args']):
 if x=='-Xclang-linker':proof_options.extend([x,link_node['args'][i+1]])
link_list=next(build.rglob('PeriodicOffsetProof.product/Objects.LinkFileList'));admit(link_list,digest(link_list))
lower=[]
for line in link_list.read_text().splitlines():
 p=Path(line.strip('"'))
 if any(n+'.build' in str(p) for n in ['PeriodicOffsetProof','SourceIssuer']):continue
 assert str(p) in checks,p
 lower.append(str(p))
proof=base/'ActualProof.swift';admit(proof,digest(proof))
artifact=scratch/('ActualPeriodicOffsetProof.wasm' if portable else 'ActualPeriodicOffsetProof')
extra=[]
if portable:extra=['-Xlinker','-z','-Xlinker','stack-size=67108864']
if args.lane=='embedded':
 unicode=Path(old['unicode_data_tables']['path']);admit(unicode,old['unicode_data_tables']['sha256'])
 extra+=['-Xlinker','-lc++','-Xlinker','-lswift_Concurrency',str(unicode)]
run('compile-link',[swift,'-I',str(scratch),'-I',str(cache_modules),*proof_options,'-parse-as-library','-emit-executable','-module-name','ActualPeriodicOffsetProof',proof,archive,*lower,*archives,*extra,'-o',artifact])
admit(artifact,digest(artifact))
for p,h in checks.items():assert digest(p)==h,p
runtime=[str(artifact)]
if portable:
 node=Path('/usr/local/bin/node');runner=root/'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs'
 admit(node,digest(node));admit(runner,digest(runner));runtime=[str(node),str(runner),str(artifact)]
run('proof',runtime)
for p,h in checks.items():assert digest(p)==h,p
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,product={str(artifact):digest(artifact)},runs=records,logs={p.name:digest(p) for p in out.glob('*.log')},scope='Actual Native periodic offset source/provider/DI/numerical point path; fresh source/adapter overlay and admitted lower objects, unchanged cached numerical Core/Geometry children. Cached children are not ASAN instrumented. No broad CAD or L2-L6 rebuild.'),indent=2)+'\n')
print('PASS actual input/product/log premises',len(checks),flush=True)
