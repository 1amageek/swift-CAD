#!/usr/bin/env python3
"""Bounded incremental implicit-source and ordinary-CS acceptance driver."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = None
FREEZE = None
EVIDENCE = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
CERT = EVIDENCE / 'CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance'
NATIVE = ROOT / '.build/cs-implicit-split-acceptance-native-20261013-v2'
SOURCE = ROOT / '.build/cs-implicit-split-acceptance-native-20261013-v1'
FIXTURE = ROOT / 'Tests/OriginalPublicAcceptanceVerification/ImplicitReverseDyadicParabolaAcceptance.swift'
GROUPS = ['ordinary','compatibility','source','selections','continuous','limits','budgets','cancel-entry','cancel-mid','cancel-final','cancel-empty','lifetime']

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p): return json.loads(Path(p).read_text())
def save(p,v): Path(p).write_text(json.dumps(v,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
def check(checks):
 for p,h in checks.items():
  assert sha(p)==h, 'Changed premise: '+p

def bounded(label,command,checks,products=None,limits=None,guard_override=None):
 actual=limits or dict(wall=120,perProcessCPU=120,ownedCPU=120)
 products=products or {}; check(checks); check(products)
 assert not (OUT/(label+'-started.json')).exists(), 'No blind repetition'
 before=head(); save(OUT/(label+'-started.json'),{'head':before})
 log=OUT/(label+'.log'); start=time.monotonic(); owned=set(); cpu={}; peak=0; stop=None
 def limit(): resource.setrlimit(resource.RLIMIT_CPU,(actual['perProcessCPU'],actual['perProcessCPU']))
 with log.open('wb') as stream:
  with subprocess.Popen(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=limit) as proc:
   def sample():
    nonlocal peak
    rows=[r.split() for r in subprocess.check_output(['ps','-axo','pid=,ppid=,rss=,time='],text=True,timeout=5).splitlines() if r.strip()]
    owners={proc.pid}|owned
    while True:
     found={int(p) for p,parent,rss,t in rows if int(parent) in owners}
     if found<=owners: break
     owners|=found
    owned.update(owners-{proc.pid})
    peak=max(peak,sum(int(rss) for p,parent,rss,t in rows if int(p) in owners))
    for p,parent,rss,t in rows:
     if int(p) in owners: cpu[int(p)]=max(cpu.get(int(p),0),sum(float(v)*60**i for i,v in enumerate(reversed(t.split(':')))))
    return {int(p) for p,parent,rss,t in rows}
   try:
    while proc.poll() is None:
     sample()
     if time.monotonic()-start>=actual['wall']: stop='wall-limit'
     elif sum(cpu.values())>=actual['ownedCPU']: stop='owned-cpu-limit'
     if stop: break
     try: proc.wait(timeout=.25)
     except subprocess.TimeoutExpired: pass
   finally:
    alive=owned & sample()
    if stop or alive or proc.poll() is None:
     try: os.killpg(proc.pid,signal.SIGKILL)
     except ProcessLookupError: pass
     for p in alive:
      try: os.kill(p,signal.SIGKILL)
      except ProcessLookupError: pass
    proc.wait(); remaining=sorted(owned & sample())
 record=dict(label=label,command=command,exitCode=proc.returncode,boundedStop=stop,elapsedSeconds=time.monotonic()-start,sampledOwnedCPUSeconds=sum(cpu.values()),peakOwnedProcessResidentSumKiB=peak,ownedDescendantsRemaining=remaining,logSHA256=sha(log),checks=checks,inputProducts=products,headBefore=before,headAfter=head(),wallSeconds=actual['wall'],perProcessCPUSeconds=actual['perProcessCPU'],ownedCPUSeconds=actual['ownedCPU'])
 if limits is not None:record['operationalGuardOverride']=dict(limits=actual,scope='Embedded compiler stage only; public query and runtime limits unchanged',reason='Actual Embedded upper/fixture compiler owned-CPU120s stops; imported-Upper fixture compile class operational policy',priorStops=[dict(path=str(ROOT/f'.build/cs-implicit-dyadic-parabola-acceptance-embedded-20261013-v{v}/{name}-receipt.json'),sha256=sha(ROOT/f'.build/cs-implicit-dyadic-parabola-acceptance-embedded-20261013-v{v}/{name}-receipt.json')) for v,name in ([(3,'upper-compile'),(4,'upper-module-compile')] if label=='upper-module-compile' else [(6,'upper-compile')])],sampledCPUByPID=cpu)
 if guard_override is not None: record['operationalGuardOverride']=dict(guard_override,limits=actual,sampledCPUByPID=cpu)
 check(checks); check(products); record['postHashesMatch']=True
 if label=='source-compile' and proc.returncode==0:
  record['products']={str(p):sha(p) for p in (OUT/'source').iterdir() if p.suffix in ['.swiftmodule','.swiftdoc','.swiftsourceinfo','.a']}
 save(OUT/(label+'-receipt.json'),record)
 print(json.dumps({k:record[k] for k in ['label','exitCode','boundedStop','elapsedSeconds','peakOwnedProcessResidentSumKiB','ownedDescendantsRemaining']}))
 return record

def accept(checks, path, expected=None):
 path=Path(path); actual=sha(path)
 assert expected is None or actual==expected, 'Changed authority: '+str(path)
 checks[str(path)]=actual

def authority(lane):
 summary=read(CERT/'summary.json')
 parts=[p for p in summary['accepted'] if p['lane']==lane]
 part=parts[-1]
 command_path=ROOT/part['assemblyCommand']['path']
 receipt_path=ROOT/part['receipt']['path']
 source_path=ROOT/part['sourceModuleReceipt']['path']
 checks={}
 for path,expected in [(CERT/'summary.json',None),(command_path,part['assemblyCommand']['sha256']),
   (receipt_path,part['receipt']['sha256']),(source_path,part['sourceModuleReceipt']['sha256'])]:
  accept(checks,path,expected)
 excluded={}
 for receipt in [read(receipt_path),read(source_path)]:
  for name,expected in receipt['checks'].items():
   if '/Sources/' in name or '/Tests/' in name:
    excluded[name]=expected
   else: accept(checks,name,expected)
  for name,expected in receipt.get('products',{}).items(): accept(checks,name,expected)
 accept(checks,__file__)
 accept(checks,FIXTURE)
 return read(command_path),checks,excluded

def historical_prefix(generated, original_sha):
 manifest=read(EVIDENCE/'CS-IMPLICIT-SPLIT-DYADIC-PARABOLA-PLANE-01/acceptance/manifest.json')
 matches=[d for d in manifest['files'].values() if d['sha256']==original_sha]
 assert matches, 'Missing admitted historical original bytes'
 original=(ROOT/matches[0]['path']).read_bytes()
 assert hashlib.sha256(original).hexdigest()==original_sha
 data=Path(generated).read_bytes();assert data.endswith(original)
 return data[:-len(original)]

def frozen(section,path):
 expected=FREEZE[section][str(Path(path))]
 assert sha(path)==expected, 'Frozen current source changed: '+str(path)
 return expected

def source(lane):
 command,checks,excluded=authority(lane)
 meta=read(SOURCE/'source-premises.json')
 accept(checks,SOURCE/'source-premises.json')
 accept(checks,SOURCE/'source-compile-receipt.json')
 bindings=[]; directory=OUT/'source';directory.mkdir()
 template=meta['originals']
 for name,expected in FREEZE['sourceBodies'].items():
  original=Path(name);accept(checks,original,frozen('sourceBodies',original))
  b=template.get(name) or next(v for k,v in template.items() if Path(k).name=='DefaultOriginalFiniteImplicitCurveGraphPreparer.swift')
  generated=Path(b['generated']);accept(checks,generated,b['generatedSHA256'])
  prefix=historical_prefix(generated,b['sha256'])
  assert hashlib.sha256(prefix).hexdigest()==b['prefixSHA256']
  target=directory/original.name;target.write_bytes(prefix+original.read_bytes());accept(checks,target)
  bindings.append(dict(original=name,originalSHA256=expected,generated=str(target),generatedSHA256=sha(target),prefixSHA256=b['prefixSHA256']))
 assert len(bindings)==6
 flags=command[:command.index('-emit-executable')]
 flags[flags.index('-module-cache-path')+1]=str(OUT/'source-module-cache')
 cmd=flags+['-emit-module','-emit-library','-static','-module-name','ImplicitSourcePhase']+[b['generated'] for b in bindings]+['-emit-module-path',str(directory/'ImplicitSourcePhase.swiftmodule'),'-o',str(directory/'libImplicitSourcePhase.a')]
 save(OUT/'source-command.json',cmd);accept(checks,OUT/'source-command.json')
 save(OUT/'source-premises.json',dict(checks=checks,bindings=bindings,originals={b['original']:dict(sha256=b['originalSHA256'],generated=b['generated'],generatedSHA256=b['generatedSHA256'],prefixSHA256=b['prefixSHA256']) for b in bindings},actualSourceBodyCount=6,lowerBodies=0,excludedUnselectedCurrentSourceChecks=excluded))
 accept(checks,OUT/'source-premises.json')
 (OUT/'driver-at-runtime.py').write_bytes(Path(__file__).read_bytes());accept(checks,OUT/'driver-at-runtime.py')
 result=bounded('source-compile',cmd,checks)
 assert result['exitCode']==0

def embedded_logging(lane):
 if lane != 'embedded': return b''
 return b"""#if hasFeature(Embedded)
func print(_ label: StaticString, _ value: String) {
 Swift.print(label,terminator:" ")
 value.withCString { pointer in _ = fputs(pointer, stdout) }
 putchar(10)
}
func print(_ first: StaticString, _ a: Bool, _ second: StaticString, _ b: Bool, _ third: StaticString, _ c: Bool) {
 Swift.print(first,terminator:" ");Swift.print(a ? "true" : "false",terminator:" ")
 Swift.print(second,terminator:" ");Swift.print(b ? "true" : "false",terminator:" ")
 Swift.print(third,terminator:" ");Swift.print(c ? "true" : "false")
}
#endif
"""

def upper(lane, source_base=None, as_module=False):
 source_base=source_base or OUT
 command,checks,excluded=authority(lane)
 receipt=read(source_base/'source-compile-receipt.json');assert receipt['exitCode']==0
 checks.update(receipt['checks']);checks.update(receipt['products']);accept(checks,source_base/'source-compile-receipt.json')
 if checks.get(str(Path(__file__).resolve())) != sha(__file__):
  previous=source_base/'driver-at-runtime.py';accept(checks,previous,checks.pop(str(Path(__file__).resolve())))
  accept(checks,__file__)
 if checks.get(str(FIXTURE)) != sha(FIXTURE):
  accept(checks,source_base/'fixture-at-runtime.swift',checks.pop(str(FIXTURE)))
  accept(checks,FIXTURE)
 meta=read(NATIVE/'upper-premises.json');bindings=[];generated=[]
 for b in meta['bindings']:
  original=Path(b['original']);expected=frozen('upperBodies',original);accept(checks,original,expected)
  previous=Path(b['generated']);accept(checks,previous,b['generatedSHA256'])
  prefix=historical_prefix(previous,b['originalSHA256'])
  assert hashlib.sha256(prefix).hexdigest()==b['prefixSHA256']
  target=OUT/original.name;target.write_bytes(prefix+original.read_bytes());accept(checks,target)
  generated.append(str(target));bindings.append(dict(original=str(original),originalSHA256=sha(original),generated=str(target),generatedSHA256=sha(target),prefixSHA256=b['prefixSHA256']))
 assert len(bindings)==56
 prior=(NATIVE/'Proof.swift').read_bytes();fixture=(NATIVE/'fixture-at-runtime.swift').read_bytes();assert prior.endswith(fixture)
 proof=OUT/'Proof.swift';proof.write_bytes(prior[:-len(fixture)]+embedded_logging(lane)+FIXTURE.read_bytes());accept(checks,proof)
 adapter_source=Path(next(v for v in read(NATIVE/'upper-command.json') if v.endswith('/ActualSelectorDeclineAdapters.swift')))
 accept(checks,adapter_source)
 adapter=OUT/adapter_source.name;adapter.write_bytes(adapter_source.read_bytes());accept(checks,adapter)
 flags=command[:command.index('-emit-executable')]
 flags[flags.index('-module-cache-path')+1]=str(OUT/'upper-module-cache')
 product=OUT/('Acceptance.wasm' if lane in ['wasm','embedded'] else 'Acceptance')
 archives=[v for v in command if v.endswith('.a')]
 for archive in archives: assert archive in checks
 cmd=flags+['-I',str(source_base/'source'),'-emit-executable','-module-name','ImplicitReverseDyadicParabolaAcceptance']+generated+[str(adapter),str(proof)]+archives+[str(source_base/'source/libImplicitSourcePhase.a'),'-o',str(product)]
 if as_module:
  directory=OUT/'upper-module';directory.mkdir()
  cmd=flags+['-I',str(source_base/'source'),'-emit-module','-emit-library','-static','-module-name','ImplicitAcceptanceUpper']+generated+[str(adapter),'-emit-module-path',str(directory/'ImplicitAcceptanceUpper.swiftmodule'),'-o',str(directory/'libImplicitAcceptanceUpper.a')]
 save(OUT/'upper-command.json',cmd);accept(checks,OUT/'upper-command.json')
 save(OUT/'upper-premises.json',dict(checks=checks,bindings=bindings,upperBodies=56,swiftInputs=57 if as_module else 58,currentSourceBodyCount=6,lowerBodies=0,sourceModuleReceipt=str(source_base/'source-compile-receipt.json'),groups=GROUPS,excludedUnselectedCurrentSourceChecks=excluded))
 accept(checks,OUT/'upper-premises.json')
 label='upper-module-compile' if as_module else 'upper-compile'
 (OUT/'driver-at-runtime.py').write_bytes(Path(__file__).read_bytes());accept(checks,OUT/'driver-at-runtime.py')
 (OUT/'fixture-at-runtime.swift').write_bytes(FIXTURE.read_bytes());accept(checks,OUT/'fixture-at-runtime.swift')
 result=bounded(label,cmd,checks,limits=dict(wall=240,perProcessCPU=360,ownedCPU=360) if as_module and lane=='embedded' else None)
 if result['exitCode']==0:
  result['products']={str(p):sha(p) for p in directory.iterdir() if p.suffix in ['.swiftmodule','.swiftdoc','.swiftsourceinfo','.a']} if as_module else {str(product):sha(product)}
  save(OUT/(label+'-receipt.json'),result)
 assert result['exitCode']==0

def split_fixture(lane, base, regression=False, prepare_only=False):
 assert lane=='embedded' and not regression
 meta=read(base/'upper-premises.json');checks=dict(meta['checks']);accept(checks,base/'upper-premises.json')
 module=read(base/'upper-module-compile-receipt.json');assert module['exitCode']==0
 checks.update(module['products']);accept(checks,base/'upper-module-compile-receipt.json')
 driver=str(Path(__file__).resolve());old=checks.pop(driver)
 if old!=sha(__file__):accept(checks,base/'driver-at-runtime.py',old)
 accept(checks,__file__);accept(checks,FIXTURE)
 prior=(NATIVE/'Proof.swift').read_bytes();old_fixture=(NATIVE/'fixture-at-runtime.swift').read_bytes();assert prior.endswith(old_fixture)
 prefix=prior[:-len(old_fixture)]+embedded_logging(lane)+b"""@testable import ImplicitAcceptanceUpper
typealias DefaultCurveSurfaceIntersector = ImplicitAcceptanceUpper.DefaultCurveSurfaceIntersector
typealias CurveSurfaceIntersectionResult = ImplicitAcceptanceUpper.CurveSurfaceIntersectionResult
typealias DefaultOriginalCompleteCurveGraphFamilyPreparer<S: Sendable,E: Sendable,C: Sendable> = ImplicitAcceptanceUpper.DefaultOriginalCompleteCurveGraphFamilyPreparer<S,E,C>
typealias OriginalImplicitCurvePublicProducer = ImplicitAcceptanceUpper.OriginalImplicitCurvePublicProducer
"""
 if regression: prefix += b'typealias OriginalDraftedZeroLinePublicProducer = ImplicitAcceptanceUpper.OriginalDraftedZeroLinePublicProducer\n'
 fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift' if regression else FIXTURE
 accept(checks,fixture);text=fixture.read_text()
 if regression:text=text.replace('DraftZeroRuledPort.CurveSurfaceIntersectionResult','CurveSurfaceIntersectionResult').replace('DraftZeroRuledPort.DefaultCurveSurfaceIntersector','DefaultCurveSurfaceIntersector')
 proof=OUT/('RegressionProof.swift' if regression else 'Proof.swift');proof.write_bytes(prefix+text.encode());accept(checks,proof)
 source_base=Path(meta['sourceModuleReceipt']).parent
 original=read(base/'upper-command.json');flags=original[:original.index('-emit-module')]
 flags[flags.index('-module-cache-path')+1]=str(OUT/'module-cache')
 directory=base/'upper-module'
 product=OUT/('Regression.wasm' if regression else 'Acceptance.wasm')
 inputs=[str(proof)]
 if regression:
  atlas=ROOT/'Tests/OriginalPolylineAtlasLiftVerification/Proof.swift';polyline=ROOT/'Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift'
  for path in [atlas,polyline]:accept(checks,path)
  shape=atlas.read_text().split('    nonisolated static func shape(',1)[1].split('    nonisolated static func prepared',1)[0]
  points=polyline.read_text().split('    nonisolated static func points(',1)[1].split('    nonisolated static func shape',1)[0]
  helper=OUT/'RegressionShape.swift';helper.write_text('import CADCore\n@testable import CADGeometry\nstruct PolylineAtlasLiftProof {\n typealias Admission=DraftZeroRuledAcceptance.Admission\n nonisolated static func shape('+shape+'}\nstruct PolylineLiftProof {\n nonisolated static func points('+points+'}\n');accept(checks,helper)
  derivative=ROOT/'Tests/OriginalDerivativeLiftHostVerification/Shape.swift';accept(checks,derivative);inputs += [str(helper),str(derivative)]
 cached,_unused,_excluded=authority(lane)
 archives=[p for p in cached if p.endswith('.a')]
 cmd=flags+['-I',str(directory),'-emit-executable','-module-name','ImplicitSplitCurrentDraft' if regression else 'ImplicitReverseAcceptance']+inputs+archives+[str(source_base/'source/libImplicitSourcePhase.a'),str(directory/'libImplicitAcceptanceUpper.a'),'-o',str(product)]
 label='regression' if regression else 'upper';save(OUT/(label+'-command.json'),cmd);accept(checks,OUT/(label+'-command.json'))
 save(OUT/(label+'-premises.json'),dict(checks=checks,bindings=meta['bindings'],upperBodies=56,upperModuleReceipt=str(base/'upper-module-compile-receipt.json'),upperModuleCommand=str(base/'upper-command.json'),sourceModuleReceipt=meta['sourceModuleReceipt'],fixtureOnly=True,lowerBodies=0,groups=['ordinary','grouping'] if regression else GROUPS,prefixSHA256=__import__('hashlib').sha256(prefix).hexdigest()))
 accept(checks,OUT/(label+'-premises.json'))
 if prepare_only: return
 result=bounded(label+'-compile',cmd,checks,limits=dict(wall=240,perProcessCPU=360,ownedCPU=360))
 if result['exitCode']==0:result['products']={str(product):sha(product)};save(OUT/(label+'-compile-receipt.json'),result)
 assert result['exitCode']==0
 if regression:run_regression_product(lane,result,checks)

def persistent_jobs(base, regression=False):
 """Execute the driver's exact jobs, changing only persistent artifact paths."""
 assert not regression
 import shlex
 label='regression' if regression else 'upper'
 if regression:
  split_fixture('embedded',base,True,prepare_only=True)
  origin=OUT
 else: origin=base
 meta=read(origin/(label+'-premises.json'));checks=dict(meta['checks'])
 driver=str(Path(__file__).resolve());old=checks.pop(driver)
 if old!=sha(__file__):accept(checks,origin/'driver-at-runtime.py',old)
 accept(checks,__file__);accept(checks,origin/(label+'-premises.json'));accept(checks,origin/(label+'-command.json'))
 command=read(origin/(label+'-command.json'))
 printed=subprocess.run(command+['-driver-print-jobs'],cwd=ROOT,capture_output=True,text=True,timeout=20)
 assert printed.returncode==0,printed.stderr
 (OUT/(label+'-driver-jobs.txt')).write_text(printed.stdout+printed.stderr)
 jobs=[shlex.split(line) for line in printed.stdout.splitlines() if line.strip()]
 assert len(jobs)==4 and '-c' in jobs[0] and '-emit-module' in jobs[1] and '-modulewrap' in jobs[2] and Path(jobs[3][0]).name=='clang'
 directory=OUT/(label+'-persistent');directory.mkdir(exist_ok=True)
 mapping={}
 output_flags={'-o','-emit-module-doc-path','-emit-module-source-info-path'}
 for job in jobs:
  for index,arg in enumerate(job[:-1]):
   if arg in output_flags:
    oldpath=job[index+1];mapping[oldpath]=str(directory/Path(oldpath).name)
 executed=[[mapping.get(arg,arg) for arg in job] for job in jobs]
 plan=dict(originalCommand=command,printedJobs=jobs,executedCommands=executed,outputMapping=mapping,onlyOutputAndCorrespondingInputPathsChanged=True)
 save(OUT/(label+'-persistent-plan.json'),plan);accept(checks,OUT/(label+'-persistent-plan.json'))
 accept(checks,OUT/(label+'-driver-jobs.txt'))
 (OUT/'driver-at-runtime.py').write_bytes(Path(__file__).read_bytes());accept(checks,OUT/'driver-at-runtime.py')
 prior=ROOT/'.build/cs-implicit-dyadic-parabola-acceptance-embedded-20261013-v7/upper-compile-receipt.json'
 prior_ref=dict(path=str(prior),sha256=sha(prior));accept(checks,prior)
 limits=[dict(wall=360,perProcessCPU=360,ownedCPU=360),dict(wall=180,perProcessCPU=180,ownedCPU=180),None,None]
 stages=['fixture-object','fixture-module','fixture-modulewrap','fixture-link'];receipts=[];products={}
 for stage,job,limit in zip(stages,executed,limits):
  name=('regression-' if regression else '')+stage
  override=dict(scope='Embedded persistent fixture compiler stage only; public query and runtime unchanged',reason='v7 combined-driver wall240 stop at ownedCPU202.66; serialize exact frontend/module/link jobs and retain outputs',priorStops=[prior_ref]) if limit else None
  result=bounded(name,job,checks,products,limits=limit,guard_override=override)
  if result['exitCode']==0:
   outputs=[job[index+1] for index,arg in enumerate(job[:-1]) if arg in output_flags]
   result['products']={path:sha(path) for path in outputs};save(OUT/(name+'-receipt.json'),result)
  assert result['exitCode']==0,'Actual persistent job stop: '+name
  products.update(result['products']);receipts.append(dict(path=str(OUT/(name+'-receipt.json')),sha256=sha(OUT/(name+'-receipt.json'))))
 final=executed[-1][executed[-1].index('-o')+1]
 save(OUT/(label+'-command.json'),command)
 saved_meta=dict(meta,checks=checks,persistentJobPlan=str(OUT/(label+'-persistent-plan.json')),persistentJobReceipts=receipts)
 save(OUT/(label+('-derived-premises.json' if regression else '-premises.json')),saved_meta)
 aggregate=dict(label=label+'-persistent-assembly',exitCode=0,assemblyKind='four-exact-driver-jobs',products={final:sha(final)},jobReceipts=receipts,checks=checks,inputProducts=products)
 save(OUT/(label+'-compile-receipt.json'),aggregate)
 if regression:run_regression_product('embedded',aggregate,checks)
 else:runtime('embedded',GROUPS)

def runtime(lane,groups):
 meta=read(OUT/'upper-premises.json');checks=dict(meta['checks']);accept(checks,OUT/'upper-premises.json')
 result=read(OUT/'upper-compile-receipt.json');assert result['exitCode']==0
 product=next(iter(result['products']));command=[product]
 if lane in ['wasm','embedded']:
  node=Path('/usr/local/bin/node');assert str(node) in checks
  wasi=OUT/'run.mjs'
  if not wasi.exists():
   wasi.write_text('import {readFile} from "node:fs/promises";\nimport {WASI} from "node:wasi";\nconst [path,group]=process.argv.slice(2);\nconst wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group},preopens:{},returnOnExit:true});\nconst module=await WebAssembly.compile(await readFile(path));\nconst instance=await WebAssembly.instantiate(module,wasi.getImportObject());\nconst code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);\n')
  accept(checks,wasi);command=[str(node),str(wasi),product]
 for group in groups:
  r=bounded('runtime-'+group,command+[group],checks,result['products'])
  if r['exitCode']!=0: raise RuntimeError('Observed control failure: '+group)

if __name__=='__main__':
 parser=argparse.ArgumentParser()
 parser.add_argument('lane',choices=['native','asan','wasm','embedded'])
 parser.add_argument('--output',required=True,type=Path)
 parser.add_argument('--stage',required=True,choices=['source','upper','upper-module','split-fixture','persistent-fixture','runtime'])
 parser.add_argument('--freeze',required=True,type=Path)
 parser.add_argument('--groups',default=','.join(GROUPS))
 parser.add_argument('--base',type=Path)
 args=parser.parse_args();FREEZE=read(args.freeze);assert FREEZE['state']=='frozen-root-GO'
 assert len(FREEZE['sourceBodies'])==6 and len(FREEZE['upperBodies'])==56
 OUT=args.output.resolve();OUT.mkdir(parents=True,exist_ok=True)
 if args.stage=='source':source(args.lane)
 elif args.stage=='upper':upper(args.lane,args.base.resolve() if args.base else None)
 elif args.stage=='upper-module':upper(args.lane,args.base.resolve(),True)
 elif args.stage=='split-fixture':split_fixture(args.lane,args.base.resolve(),prepare_only=True)
 elif args.stage=='persistent-fixture':persistent_jobs(args.base.resolve())
 elif args.stage=='runtime':runtime(args.lane,args.groups.split(','))
 else: raise AssertionError('Unknown selected reverse acceptance stage')
