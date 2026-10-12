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
OUT = ROOT / '.build/cs-implicit-dyadic-parabola-acceptance-native-20261013-v2'
OLD = ROOT / '.build/cs-implicit-dyadic-parabola-observation-prepared-20261013'
NAMES = {
 'OriginalImplicitCurveSnapshot.swift':'fa213e9a4f7c415ed5d352ade8a8073922e870001556da2831ced688d2845c80',
 'OriginalImplicitCurveSnapshotProvider.swift':'edf4df1a63c040817a835b1bef7adc21559a42b84f32e8f0b8bef85e4dd1e789',
 'OriginalImplicitCurveGraphEvidence.swift':'a2bac0094db904bff06e3b1968c0cb181562b56928c193bcb5537fe8c8c7b57c',
 'DefaultOriginalFiniteImplicitCurveGraphPreparer.swift':'93833e4f573d5764afea1be2555632a43987b84be4bcc70793f01f5f73cae33f'}

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p): return json.loads(Path(p).read_text())
def save(p,v): Path(p).write_text(json.dumps(v,indent=2)+'\n')
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True,timeout=5).strip()
def check(checks):
 for p,h in checks.items():
  assert sha(p)==h, 'Changed premise: '+p

def prepare_source():
 OUT.mkdir(parents=True,exist_ok=True)
 assert not (OUT/'source-premises.json').exists()
 old=read(OLD/'premises.json'); command=read(OLD/'compile-command.json')
 checks={}; excluded={}
 # Historical upper and fixture text is not recompiled in this source-only phase.
 for p,h in old['checks'].items():
  if '/Sources/' in p or p.endswith('ImplicitDyadicParabolaObservation.py'):
   excluded[p]=h
  else: checks[p]=h
 checks[str(OLD/'premises.json')]=sha(OLD/'premises.json')
 checks[str(OLD/'compile-command.json')]=sha(OLD/'compile-command.json')
 for p,h in old['selectedCachedSources'].items(): checks[p]=h
 checks[str(Path(__file__).resolve())]=sha(__file__)
 check(checks)
 proof=(OLD/'Proof.swift').read_bytes(); fixture=(OLD/'Observation.swift').read_bytes()
 assert proof.endswith(fixture)
 prefix=proof[:-len(fixture)]
 source=OUT/'source'; source.mkdir()
 originals={}
 for name,expected in NAMES.items():
  original=ROOT/'Sources/CADGeometry/OriginalSourceIssuance'/name
  assert sha(original)==expected
  checks[str(original)]=expected
  generated=source/name; generated.write_bytes(prefix+original.read_bytes())
  checks[str(generated)]=sha(generated)
  originals[str(original)]={'sha256':expected,'generated':str(generated),'generatedSHA256':sha(generated),'prefixSHA256':hashlib.sha256(prefix).hexdigest()}
 flags=command[:command.index('-emit-executable')]
 flags[flags.index('-module-cache-path')+1]=str(OUT/'source-module-cache')
 cmd=flags+['-emit-module','-emit-library','-static','-module-name','ImplicitSourcePhase']+[str(source/n) for n in NAMES]+['-emit-module-path',str(source/'ImplicitSourcePhase.swiftmodule'),'-o',str(source/'libImplicitSourcePhase.a')]
 save(OUT/'source-command.json',cmd)
 checks[str(OUT/'source-command.json')]=sha(OUT/'source-command.json')
 save(OUT/'source-premises.json',dict(checks=checks,excludedUnselectedCurrentSourceChecks=excluded,originals=originals,head=head(),newBodies=4,lowerBodies=0,owner='RetainedHostAdapters and AngularSourcePhase, admitted @testable nominals'))
 print(json.dumps({'prepared':str(OUT),'newBodies':4,'lowerBodies':0,'checks':len(checks)}))

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

if __name__=='__main__':
 parser=argparse.ArgumentParser(); parser.add_argument('--prepare-source',action='store_true'); parser.add_argument('--source',action='store_true'); args=parser.parse_args()
 if args.prepare_source: prepare_source()
 elif args.source:
  premises=read(OUT/'source-premises.json'); checks=premises['checks']; checks[str(OUT/'source-premises.json')]=sha(OUT/'source-premises.json')
  bounded('source-compile',read(OUT/'source-command.json'),checks)
