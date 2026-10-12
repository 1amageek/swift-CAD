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
EVIDENCE = ROOT / 'Tests/OriginalPublicAcceptanceVerification/Evidence'
CERT = EVIDENCE / 'CS-CERT-SPHERECONE-APEX-EMPTY-01/acceptance'
NATIVE = ROOT / '.build/cs-implicit-dyadic-parabola-acceptance-native-20261013-v11'
SOURCE = ROOT / '.build/cs-implicit-dyadic-parabola-acceptance-native-20261013-v9'
FIXTURE = ROOT / 'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.swift'
GROUPS = ['ordinary','source','selections','continuous','limits','budgets','cancel-entry','cancel-mid','cancel-final','cancel-empty','lifetime']

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p): return json.loads(Path(p).read_text())
def save(p,v): Path(p).write_text(json.dumps(v,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
def check(checks):
 for p,h in checks.items():
  assert sha(p)==h, 'Changed premise: '+p

def bounded(label,command,checks,products=None):
 products=products or {}; check(checks); check(products)
 assert not (OUT/(label+'-started.json')).exists(), 'No blind repetition'
 before=head(); save(OUT/(label+'-started.json'),{'head':before})
 log=OUT/(label+'.log'); start=time.monotonic(); owned=set(); cpu={}; peak=0; stop=None
 def limit(): resource.setrlimit(resource.RLIMIT_CPU,(120,120))
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
     if time.monotonic()-start>=120: stop='wall-limit'
     elif sum(cpu.values())>=120: stop='owned-cpu-limit'
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
 record=dict(label=label,command=command,exitCode=proc.returncode,boundedStop=stop,elapsedSeconds=time.monotonic()-start,sampledOwnedCPUSeconds=sum(cpu.values()),peakOwnedProcessResidentSumKiB=peak,ownedDescendantsRemaining=remaining,logSHA256=sha(log),checks=checks,inputProducts=products,headBefore=before,headAfter=head(),wallSeconds=120,perProcessCPUSeconds=120,ownedCPUSeconds=120)
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

def source(lane):
 command,checks,excluded=authority(lane)
 meta=read(SOURCE/'source-premises.json')
 accept(checks,SOURCE/'source-premises.json')
 accept(checks,SOURCE/'source-compile-receipt.json')
 bindings=[]; directory=OUT/'source';directory.mkdir()
 for name,b in meta['originals'].items():
  original=Path(name);accept(checks,original,b['sha256'])
  generated=Path(b['generated']);accept(checks,generated,b['generatedSHA256'])
  data=generated.read_bytes();assert data.endswith(original.read_bytes())
  prefix=data[:-len(original.read_bytes())]
  assert hashlib.sha256(prefix).hexdigest()==b['prefixSHA256']
  target=directory/original.name;target.write_bytes(prefix+original.read_bytes());accept(checks,target)
  bindings.append(dict(original=name,originalSHA256=sha(original),generated=str(target),generatedSHA256=sha(target),prefixSHA256=b['prefixSHA256']))
 assert len(bindings)==5
 flags=command[:command.index('-emit-executable')]
 flags[flags.index('-module-cache-path')+1]=str(OUT/'source-module-cache')
 cmd=flags+['-emit-module','-emit-library','-static','-module-name','ImplicitSourcePhase']+[b['generated'] for b in bindings]+['-emit-module-path',str(directory/'ImplicitSourcePhase.swiftmodule'),'-o',str(directory/'libImplicitSourcePhase.a')]
 save(OUT/'source-command.json',cmd);accept(checks,OUT/'source-command.json')
 save(OUT/'source-premises.json',dict(checks=checks,bindings=bindings,originals=meta['originals'],actualSourceBodyCount=5,lowerBodies=0,excludedUnselectedCurrentSourceChecks=excluded))
 accept(checks,OUT/'source-premises.json')
 result=bounded('source-compile',cmd,checks)
 assert result['exitCode']==0

def embedded_logging(lane):
 if lane != 'embedded': return b''
 return b"""#if hasFeature(Embedded)
func print(_ label: StaticString, _ value: String) {
 Swift.print(label,terminator:" ")
 value.withUTF8 { bytes in for byte in bytes { putchar(Int32(byte)) } }
 putchar(10)
}
func print(_ first: StaticString, _ a: Bool, _ second: StaticString, _ b: Bool, _ third: StaticString, _ c: Bool) {
 Swift.print(first,terminator:" ");Swift.print(a ? "true" : "false",terminator:" ")
 Swift.print(second,terminator:" ");Swift.print(b ? "true" : "false",terminator:" ")
 Swift.print(third,terminator:" ");Swift.print(c ? "true" : "false")
}
#endif
"""

def upper(lane, source_base=None):
 source_base=source_base or OUT
 command,checks,excluded=authority(lane)
 receipt=read(source_base/'source-compile-receipt.json');assert receipt['exitCode']==0
 checks.update(receipt['checks']);checks.update(receipt['products']);accept(checks,source_base/'source-compile-receipt.json')
 if checks.get(str(Path(__file__).resolve())) != sha(__file__):
  previous=source_base/'driver-at-runtime.py';accept(checks,previous,checks.pop(str(Path(__file__).resolve())))
  accept(checks,__file__)
 meta=read(NATIVE/'upper-premises.json');bindings=[];generated=[]
 for b in meta['bindings']:
  original=Path(b['original']);accept(checks,original,b['originalSHA256'])
  previous=Path(b['generated']);accept(checks,previous,b['generatedSHA256'])
  data=previous.read_bytes();assert data.endswith(original.read_bytes())
  prefix=data[:-len(original.read_bytes())]
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
 cmd=flags+['-I',str(source_base/'source'),'-emit-executable','-module-name','ImplicitDyadicParabolaAcceptance']+generated+[str(adapter),str(proof)]+archives+[str(source_base/'source/libImplicitSourcePhase.a'),'-o',str(product)]
 save(OUT/'upper-command.json',cmd);accept(checks,OUT/'upper-command.json')
 save(OUT/'upper-premises.json',dict(checks=checks,bindings=bindings,upperBodies=56,swiftInputs=58,currentSourceBodyCount=5,lowerBodies=0,sourceModuleReceipt=str(source_base/'source-compile-receipt.json'),groups=GROUPS,excludedUnselectedCurrentSourceChecks=excluded))
 accept(checks,OUT/'upper-premises.json')
 result=bounded('upper-compile',cmd,checks)
 if result['exitCode']==0:
  result['products']={str(product):sha(product)};save(OUT/'upper-compile-receipt.json',result)
 assert result['exitCode']==0

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

def regression(lane, base):
 meta=read(base/'upper-premises.json');checks=dict(meta['checks'])
 checks.pop(str(FIXTURE),None)
 old_driver=ROOT/'Tests/OriginalPublicAcceptanceVerification/ImplicitDyadicParabolaAcceptance.py'
 expected=checks.pop(str(old_driver))
 if sha(old_driver)!=expected:
  previous=base/'driver-at-runtime.py'
  assert sha(previous)==expected;accept(checks,previous)
 accept(checks,__file__);accept(checks,FIXTURE)
 command=read(base/'upper-command.json')
 fixture=ROOT/'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift';accept(checks,fixture)
 text=fixture.read_text();adapted=text.replace('DraftZeroRuledPort.CurveSurfaceIntersectionResult','CurveSurfaceIntersectionResult').replace('DraftZeroRuledPort.DefaultCurveSurfaceIntersector','DefaultCurveSurfaceIntersector')
 prior=(base/'Proof.swift').read_bytes()
 old=(base/'fixture-at-runtime.swift').read_bytes() if (base/'fixture-at-runtime.swift').exists() else FIXTURE.read_bytes()
 assert prior.endswith(old)
 proof=OUT/'RegressionProof.swift';proof.write_text(prior[:-len(old)].decode()+adapted);accept(checks,proof)
 atlas=ROOT/'Tests/OriginalPolylineAtlasLiftVerification/Proof.swift'
 polyline=ROOT/'Tests/OriginalPolylineSurfaceLiftVerification/Proof.swift'
 for path in [atlas,polyline]:accept(checks,path)
 shape=atlas.read_text().split('    nonisolated static func shape(',1)[1].split('    nonisolated static func prepared',1)[0]
 points=polyline.read_text().split('    nonisolated static func points(',1)[1].split('    nonisolated static func shape',1)[0]
 helper=OUT/'RegressionShape.swift'
 helper.write_text('import CADCore\n@testable import CADGeometry\nstruct PolylineAtlasLiftProof {\n typealias Admission=DraftZeroRuledAcceptance.Admission\n nonisolated static func shape('+shape+'}\nstruct PolylineLiftProof {\n nonisolated static func points('+points+'}\n');accept(checks,helper)
 oldproof=next(v for v in command if v.endswith('/Proof.swift'))
 command=[str(proof) if v==oldproof else v for v in command]
 command[command.index('-module-cache-path')+1]=str(OUT/'module-cache')
 command[command.index('-module-name')+1]='ImplicitCurrentRationalRegression'
 product=OUT/('Regression.wasm' if lane in ['wasm','embedded'] else 'Regression')
 command[command.index('-o')+1]=str(product)
 command.insert(command.index('-o'),str(helper))
 derivative=ROOT/'Tests/OriginalDerivativeLiftHostVerification/Shape.swift'
 accept(checks,derivative)
 command.insert(command.index('-o'),str(derivative))
 save(OUT/'regression-command.json',command);accept(checks,OUT/'regression-command.json')
 save(OUT/'regression-premises.json',dict(checks=checks,bindings=meta['bindings'],groups=['ordinary','grouping'],adaptations=['Result and DefaultCurveSurfaceIntersector module qualifications only'],sourceModuleReceipt=str(base/'source-compile-receipt.json') if (base/'source-compile-receipt.json').exists() else str(SOURCE/'source-compile-receipt.json'),upperBodies=56,lowerBodies=0))
 accept(checks,OUT/'regression-premises.json')
 result=bounded('regression-compile',command,checks);assert result['exitCode']==0
 products={str(product):sha(product)}
 result['products']=products;save(OUT/'regression-compile-receipt.json',result)
 runtime=[str(product)]
 if lane in ['wasm','embedded']:
  node=Path('/usr/local/bin/node');assert str(node) in checks
  wasi=OUT/'run.mjs'
  wasi.write_text('import {readFile} from "node:fs/promises";\nimport {WASI} from "node:wasi";\nconst [path,group]=process.argv.slice(2);\nconst wasi=new WASI({version:"preview1",args:[path,group],env:{CAD_PROOF_GROUP:group},preopens:{},returnOnExit:true});\nconst module=await WebAssembly.compile(await readFile(path));\nconst instance=await WebAssembly.instantiate(module,wasi.getImportObject());\nconst code=wasi.start(instance);if(code!==0)throw new Error(`WASI exit ${code}`);\n')
  accept(checks,wasi);runtime=[str(node),str(wasi),str(product)]
 for group in ['ordinary','grouping']:
  result=bounded('regression-'+group,runtime+[group],checks,products)
  assert result['exitCode']==0

if __name__=='__main__':
 parser=argparse.ArgumentParser()
 parser.add_argument('lane',choices=['native','asan','wasm','embedded'])
 parser.add_argument('--output',required=True,type=Path)
 parser.add_argument('--stage',required=True,choices=['source','upper','runtime','regression'])
 parser.add_argument('--groups',default=','.join(GROUPS))
 parser.add_argument('--base',type=Path)
 args=parser.parse_args();OUT=args.output.resolve();OUT.mkdir(parents=True,exist_ok=True)
 if args.stage=='source':source(args.lane)
 elif args.stage=='upper':upper(args.lane,args.base.resolve() if args.base else None)
 elif args.stage=='runtime':runtime(args.lane,args.groups.split(','))
 else: regression(args.lane,args.base.resolve() if args.base else NATIVE)
