#!/usr/bin/env python3
"""Verify requested-order producers through hash-admitted actual original callers."""
import argparse,hashlib,json,subprocess,time,uuid
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('lane',choices=['native','asan','wasm','embedded']);parser.add_argument('--red',action='store_true');parser.add_argument('--output',type=Path);args=parser.parse_args()
base=Path(__file__).resolve().parent;root=base.parents[1]
out=args.output.resolve() if args.output else base/'Evidence'/(args.lane+('-red' if args.red else ''));out.mkdir(parents=True,exist_ok=False)
scratch=root/'.build/m4-requested-order-lift'/args.lane/uuid.uuid4().hex;scratch.mkdir(parents=True)
prior=root/'Tests/OriginalParameterCurveGraphVerification/Evidence'/(args.lane+'-finding-final')/'receipt.json';r=json.loads(prior.read_text());assert r['success']
checks={};old_premises={}
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def add(path,expected=None):
 path=Path(path).resolve();h=expected or digest(path);assert digest(path)==h,str(path)
 assert str(path) not in checks or checks[str(path)]==h,str(path)
 checks[str(path)]=h;return path
changed=[root/'Sources/CADGeometry/SurfaceSilhouette'/(name+'.swift') for name in ['OriginalSurfaceHigherJetProvider','OriginalProceduralSurfaceHigherTaylor','OriginalRevolutionSurfaceHigherTaylor']]
changed.append(root/'Sources/CADGeometry/OriginalHigherCurveJets/OriginalParameterCurveHigherTaylor.swift')
add(prior);add(__file__)
for group in ['inputs','product']:
 for n,h in r[group].items():
  if Path(n) in changed and digest(n)!=h:
   relative=Path(n).relative_to(root);original=subprocess.check_output(['git','show','f3cdb916:'+str(relative)],cwd=root)
   assert hashlib.sha256(original).hexdigest()==h,n
   old=scratch/('admitted-old-'+Path(n).name);old.write_bytes(original);add(old,h);old_premises[n]={'sha256':h,'snapshot':str(old)}
  else:add(n,h)
for n,h in r['logs'].items():add(prior.parent/n,h)
command=next(x['command'] for x in r['runs'] if x['label']=='compile-link').copy()
i=command.index('ORIGINAL_PARAMETER_GRAPH_FINDING');assert command[i-1]=='-D';del command[i-1:i+1]
old_proof=add(root/'Tests/OriginalParameterCurveGraphVerification/Proof.swift')
fixture=scratch/'ParameterGraphFixture.swift';fixture.write_text(old_proof.read_text().replace('@main struct ParameterCurveGraphProof','struct ParameterCurveGraphProof'));add(fixture)
command[command.index(str(old_proof))]=str(fixture)
proof=add(base/'Proof.swift');command.insert(command.index('-o'),str(proof))
product=scratch/('RequestedOrderLiftProof.wasm' if args.lane in ['wasm','embedded'] else 'RequestedOrderLiftProof');command[command.index('-o')+1]=str(product)
runs=[]
def run(label,cmd,expected=0):
 start=time.monotonic()
 with (out/(label+'.log')).open('w') as log:q=subprocess.run(list(map(str,cmd)),cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120)
 runs.append({'label':label,'command':list(map(str,cmd)),'elapsedSeconds':time.monotonic()-start,'exitCode':q.returncode,'timeoutSeconds':120})
 (out/'runs.json').write_text(json.dumps(runs,indent=2)+'\n');print(label,q.returncode,round(runs[-1]['elapsedSeconds'],3),flush=True)
 assert q.returncode==expected,(label,q.returncode)
if args.red:
 assert args.lane=='native'
 command[1:1]=['-D','OLD_SOURCE_RED']
else:
 caller=next(x['command'] for x in r['runs'] if x['label']=='compile-caller');flags=caller[:max(i for i,x in enumerate(caller) if x=='-enable-testing')]
 tool=Path(command[0]).parent
 for name in ['llvm-nm','llvm-objcopy']:
  if args.lane in ['native','asan'] or name=='llvm-nm':add(tool/name)
 archive=Path(next(x for x in command if x.endswith('libCachedCADGeometry.a')))
 nm=subprocess.run([str(tool/'llvm-nm'),'--defined-only',str(archive)],capture_output=True,text=True,timeout=30);assert nm.returncode==0
 symbols={}
 for name,needle in [('OriginalSurfaceHigherJetProvider.swift','OriginalSurfaceHigherJetProviderV014intervalTaylor'),('OriginalParameterCurveHigherTaylor.swift','OriginalParameterCurveHigherTaylorV9enclosure')]:
  names=sorted(set(x.split()[-1] for x in nm.stdout.splitlines() if needle in x and len(x.split())>=2 and x.split()[-2]=='T' and x.endswith('KFZ')));assert len(names)==1,names
  symbols[name]=names[0]
 (out/'selected-symbols.json').write_text(json.dumps(symbols,indent=2)+'\n');add(out/'selected-symbols.json')
 if args.lane in ['native','asan']:
  derivative=scratch/'libUnchangedCallersWithWeakSelectedEntries.a'
  run('copy-selected-symbol',[tool/'llvm-objcopy',*['--weaken-symbol='+x for x in symbols.values()],archive,derivative]);add(derivative)
  command[command.index(str(archive))]=str(derivative)
  symbols={k:v.removeprefix('_') for k,v in symbols.items()}
 else:
  command[1:1]=[argument for symbol in symbols.values() for argument in ['-Xlinker','--wrap='+symbol]]
  symbols={k:'__wrap_'+v for k,v in symbols.items()}
 files=[]
 for source in [*changed,root/'Sources/CADGeometry/CanonicalSphereChart/CanonicalSphereAngularPhase.swift']:
  add(source);text=source.read_text();prefix='import CADCore\n@testable import CADGeometry\n'
  if source.name in symbols:
   anchor='    package static func intervalTaylorJet' if source.name=='OriginalSurfaceHigherJetProvider.swift' else '    static func enclosure'
   assert text.count(anchor)==1
   annotation='    @_silgen_name("'+symbols[source.name]+'")\n';generated=text.replace(anchor,annotation+anchor)
   assert generated.replace(annotation,'')==text
  else:generated=text
  p=scratch/source.name;p.write_text(prefix+generated);files.append(add(p))
 built=scratch/'libRequestedOrderAdapters.a'
 run('compile-producers',[*flags,'-enable-testing','-emit-library','-static','-emit-module','-module-name','RequestedOrderAdapters',*files,'-emit-module-path',scratch/'RequestedOrderAdapters.swiftmodule','-o',built]);add(built);add(scratch/'RequestedOrderAdapters.swiftmodule')
 command[1:1]=['-I',str(scratch)]
 if args.lane in ['native','asan']:command[1:1]=['-Xlinker','-force_load','-Xlinker',str(built)]
 else:command.insert(command.index('-o'),str(built))
(out/'inputs-before-compile.json').write_text(json.dumps(checks)+'\n')
run('compile-link',command);add(product)
runtime=next(x['command'] for x in r['runs'] if x['label']=='proof').copy();runtime[-1]=str(product)
run('proof',runtime,expected=1 if args.red else 0)
output=(out/'proof.log').read_text()
if args.red:assert 'Original higher surface jets need order four or higher' in output and 'FAIL requested-order original lift caller' in output
else:
 for marker in ['PASS actual nested lifted-traversal point and rolling-ball caller','PASS requested D0-D4 original lift composition and traversal scale','PASS original weighted/nonclamped pcurve hull, exact boundaries and nonzero/outside coordinates','PASS C0-not-C1 join, exact work/bytes, independent caps and cancellation','PASS ruled, rolling-ball and revolution requested-order producers']:assert marker in output,marker
 assert 'FAIL' not in output
for log in out.glob('*.log'):
 assert not any(x in log.read_text() for x in ['warning:','error:','actor-isolated function','data race detected','null function','function signature mismatch']),str(log)
for n,h in checks.items():assert digest(n)==h,n
(out/'receipt.json').write_text(json.dumps({'success':True,'lane':args.lane,'expectedRed':args.red,'scope':'Actual retained public point/rolling-ball and requested-order producer path. Fresh changed producers at the existing Swift boundary; unchanged numerical/lower callers and admission. No broad production or L2-L6 rebuild.','inputs':checks,'oldCachedSourcePremises':old_premises,'product':{str(product):digest(product)},'runs':runs,'logs':{x.name:digest(x) for x in out.glob('*.log')}},separators=(',',':'))+'\n')
