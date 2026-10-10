#!/usr/bin/env python3
"""Compile the changed DI boundary against receipt-admitted immutable source products."""
import argparse,hashlib,json,os,subprocess,time,uuid,yaml
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);p.add_argument('--actual',action='store_true');p.add_argument('--output',type=Path);args=p.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/(('actual-' if args.actual else '')+args.lane)
out.mkdir(parents=True,exist_ok=False)
scratch=root/'.build/m4-periodic-lift-domain'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
checks={};runs=[]
def admit(path,expected=None):
 path=Path(path).resolve();expected=expected or digest(path)
 assert digest(path)==expected,str(path)
 assert str(path) not in checks or checks[str(path)]==expected
 checks[str(path)]=expected
 return path
def receipt(path):
 path=admit(path);r=json.loads(path.read_text());assert r['success']
 for group in ['inputs','product']:
  for name,h in r[group].items():admit(name,h)
 for name,h in r['logs'].items():admit(path.parent/Path(name).name,h)
 return r
def run(label,command,seconds=120):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:
  result=subprocess.run(list(map(str,command)),cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=seconds)
 runs.append(dict(label=label,command=list(map(str,command)),timeoutSeconds=seconds,elapsedSeconds=time.monotonic()-start,exitCode=result.returncode))
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,result.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 if result.returncode:raise SystemExit(result.returncode)
admit(__file__)
source_base=root/'Tests/OriginalPeriodicLiftVerification'
source_receipt=receipt(source_base/'Evidence'/args.lane/'receipt.json')
source_product=Path(next(iter(source_receipt['product'])));build=source_product.parents[2]
plan=yaml.load((build/'debug.yaml').read_text(),Loader=yaml.CSafeLoader)['commands'];admit(build/'debug.yaml')
modules=source_product.parent/'Modules'
def options(name):
 original=next(v['args'] for k,v in plan.items() if k.startswith('C.'+name) and k.endswith('.module'))
 compiler=Path(original[0]);admit(compiler);flags=[];i=1
 remove_one={'-module-name','-emit-module-path','-output-file-map','-index-store-path','-module-cache-path','-emit-objc-header-path'}
 remove_flag={'-emit-dependencies','-emit-module','-incremental','-c','-parseable-output','-serialize-diagnostics','-enable-batch-mode','-emit-objc-header'}
 while i<len(original):
  x=original[i]
  if x in remove_one:i+=2;continue
  if x=='-Xfrontend' and original[i+1]=='-entry-point-function-name':i+=4;continue
  if x in remove_flag or x=='-DORIGINAL_SOURCE_ISOLATED_VERIFICATION' or x.startswith('@'):i+=1;continue
  if x=='-D' and original[i+1]=='ORIGINAL_SOURCE_ISOLATED_VERIFICATION':i+=2;continue
  flags.append(x);i+=1
 return compiler,flags
swift,flags=options('SourceIssuer');_,proof_flags=options('PeriodicLiftProof')
link_list=admit(next(build.rglob('PeriodicLiftProof.product/Objects.LinkFileList')))
lower=[]
for line in link_list.read_text().splitlines():
 path=Path(line.strip('"'))
 if 'PeriodicLiftProof.build' in str(path):continue
 assert str(path) in checks,str(path);lower.append(path)
archives=[];extra=[];portable=args.lane in ['wasm','embedded']
if args.actual:
 independent=receipt(base/'Evidence'/args.lane/'receipt.json')
 library_root=Path(next(iter(independent['product']))).parent
 for name in ['DI0','DI']:archives.append(admit(library_root/('lib'+name+'.a')))
 actual=receipt(source_base/'Evidence'/('actual-'+args.lane)/'receipt.json')
 actual_root=Path(next(iter(actual['product']))).parent
 lower=[x for x in lower if 'SourceIssuer.build' not in str(x)]
 for name in ['SourceIssuer','CachedCADCore','CachedCADGeometry','CachedHashTreeCollections','CachedInternalCollectionsUtilities']:
  archives.append(admit(actual_root/('lib'+name+'.a')))
 source_modules=actual_root
 native_cache=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-native-production/out/Products/Debug')
 cache_modules=Path('/private/tmp/cad-di-m6-consumers-20261009/.build/m6-'+args.lane+'-production/wasm32-unknown-wasip1/debug/Modules') if portable else native_cache
 for value in [flags,proof_flags]:
  if not portable:value[value.index('-target')+1]='arm64-apple-macos15.0'
 if args.lane=='embedded':
  old=json.loads((root/'Tests/OriginalDomainConsumerVerification/Evidence/M6/embedded/receipt.json').read_text())
  extra+=['-Xlinker','-lc++','-Xlinker','-lswift_Concurrency',str(admit(old['unicode_data_tables']['path'],old['unicode_data_tables']['sha256']))]
else:
 library_root=scratch;source_modules=modules;cache_modules=modules
 for name,definition in [('DI0','EXACT_DOMAIN_ISOLATED_VERIFICATION'),('DI','ORIGINAL_DOMAIN_ISOLATED_VERIFICATION')]:
  files=[];directory=root/'Tests/OriginalGraphRelationVerification/Sources'/name
  for folder,children,names in os.walk(directory,followlinks=True):
   if name=='DI':children[:]=[x for x in children if x!='ExactParameterDomain']
   for filename in names:
    path=Path(folder)/filename
    if path.suffix=='.swift':files.append(admit(path))
  assert files
  archive=scratch/('lib'+name+'.a')
  run('compile-'+name,[swift,'-I',scratch,'-I',modules,*flags,'-D',definition,'-emit-library','-static','-emit-module','-module-name',name,*sorted(files),'-emit-module-path',scratch/(name+'.swiftmodule'),'-o',archive])
  archives.append(admit(archive));admit(scratch/(name+'.swiftmodule'))
for name in ['Checks.swift','ActualProof.swift' if args.actual else 'Proof.swift']:
 original=admit(source_base/name);generated=scratch/('Source'+name)
 text=original.read_text()
 if name.endswith('Proof.swift'):text=text.replace('@main struct','struct')
 generated.write_text(text);admit(generated)
fixture_sources=[scratch/'SourceChecks.swift',scratch/('SourceActualProof.swift' if args.actual else 'SourceProof.swift')]
if not args.actual:fixture_sources.append(admit(root/'Tests/OriginalDomainIdentityVerification/Sources/Fixtures/NativeSource.swift'))
fixture_sources += [admit(base/'Checks.swift'),admit(base/('ActualProof.swift' if args.actual else 'Proof.swift'))]
link_node=next(v for k,v in plan.items() if k.startswith('C.PeriodicLiftProof') and k.endswith('.exe'))
for i,x in enumerate(link_node['args']):
 if x=='-Xclang-linker':proof_flags.extend([x,link_node['args'][i+1]])
if portable:extra+=['-Xlinker','-z','-Xlinker','stack-size=67108864']
artifact=scratch/('PeriodicLiftDomainProof.wasm' if portable else 'PeriodicLiftDomainProof')
run('compile-link',[swift,'-I',source_modules,'-I',library_root,'-I',cache_modules,'-I',modules,*proof_flags,'-parse-as-library','-emit-executable','-module-name','PeriodicLiftDomainProof',*fixture_sources,*archives,*lower,*extra,'-o',artifact])
admit(artifact)
for name,h in checks.items():assert digest(name)==h,name
runtime=[artifact]
if portable:
 node=admit('/usr/local/bin/node');runner=admit(root/'Tests/OriginalSourceIssuanceVerification/Scripts/RunWASI.mjs');runtime=[node,runner,artifact]
run('proof',runtime,180)
for path in out.glob('*.log'):
 text=path.read_text();assert not any(x in text for x in ['data race detected','actor-isolated function','null function']),str(path)
for name,h in checks.items():assert digest(name)==h,name
(out/'receipt.json').write_text(json.dumps(dict(success=True,lane=args.lane,inputs=checks,product={str(artifact):digest(artifact)},runs=runs,logs={p.name:digest(p) for p in out.glob('*.log')},scope='Changed periodic lift DI and fixtures only; unchanged source/L0/L1 products admitted before/after. Actual variant reuses the same independent DI0/DI and immutable numerical source/adapter products. No CAD or L2-L6 build.'),indent=2)+'\n')
print('PASS current source/artifact/log premises',len(checks),flush=True)
