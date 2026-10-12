#!/usr/bin/env python3
"""Execute the explicitly approved fixed Embedded WMO transaction once."""
import hashlib, json, math, os, resource, signal, subprocess, sys, time, traceback
from pathlib import Path
R=Path('/private/tmp/cad-m4-m8-completion-20261010')
O=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2'
V=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v1'
PROFILE='2999f8e69af18d7942e159db54c0a84fad1886625dfe01603f64a0cfcca45e3f'
GROUPS=['complete','dispatch','source','requests','resources','readmission','cancel-entry','cancel-final','cancel-reader','lifetime','changed-controls']
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p): return json.loads(Path(p).read_text())
def save(n,v): (O/n).write_text(json.dumps(v,indent=2)+'\n')
def bind(p): return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
def cpu_seconds(value): return sum(float(x)*60**i for i,x in enumerate(reversed(value.split(':'))))
assert sha(O/'profile.json')==PROFILE
assert not (O/'execution-started.json').exists(), 'No blind retry'
p=read(O/'profile.json'); checks=dict(read(V/'execution-freeze.json')['checks']);checks.update({str(O/'profile.json'):PROFILE,str(Path(__file__).resolve()):sha(__file__)})
for b in [*p['receipts'].values(),*p['commandCarriers'].values(),*p['artifacts'].values(),*p['commands'].values()]:
 if isinstance(b,dict) and 'path' in b: checks[b['path']]=b['sha256']
for b in read(p['artifacts']['geometryInputs']['path']):
 checks[b['compiledInput']]=b['compiledSHA256'];checks[b['retainedGenerationInput']]=b['generationSHA256']
 if b['changedBody']:
  name=b['name'];current=R/'Sources/CADGeometry'/('OriginalHigherCurveJets/'+name if name=='OriginalCurveTaylorComposition.swift' else name)
  checks[str(current)]=b['compiledSHA256']
for b in read(p['artifacts']['source4Bindings']['path']):
 for v in b.values():checks[v['path']]=v['sha256']
source_meta=read(R/'.build/cs-implicit-closed-acceptance-native-20261013-v1/source-premises.json')
for b in source_meta['bindings']: checks[b['original']]=b['originalSHA256']
for b in read(p['artifacts']['upper59Bindings']['path']):
 checks[b['generated']['path']]=b['generated']['sha256'];checks[b['prior']['original']]=b['prior']['originalSHA256']
for b in read(p['artifacts']['immutableProducts']['path']):checks[b['path']]=b['sha256']
for b in p['fixture'].values(): checks[b['path']]=b['sha256']
command=read(O/'runtime-complete-command.json')
for path in [command[0],command[1],p['toolchain']['executable'],p['toolchain']['frontend'],p['toolchain']['archiver']['path']]:checks[str(path)]=sha(path)
for name in ['geometry-object','geometry-module','geometry-modulewrap','geometry-archive','source4','upper60','fixture1-link','runtime-complete']:
 assert sha(O/(name+'-command.json'))==p['commands'][name]['sha256']
for b in [p['priorApprovedProfile'],p['priorFailure'],*([v['receipt'] for v in p['geometryBudgetCarry']['priorStages']])]:checks[b['path']]=b['sha256']
spent_wall=p['geometryBudgetCarry']['alreadyUsedWallSeconds'];spent_cpu=p['geometryBudgetCarry']['alreadyUsedOwnedCPUSeconds']
products={};runs=[];geometry_start=None;geometry_cpu={};geometry_peak=0;all_started=time.monotonic();state='pre-admission';failure=None

def recheck(include_products=True):
 for path,digest in checks.items():
  assert sha(path)==digest,'Changed admitted input: '+path
 if include_products:
  for path,digest in products.items():assert sha(path)==digest,'Changed own product: '+path

def execute(label,command,geometry=False):
 global geometry_start, geometry_peak
 limits=p['suggestedOperationalBounds']['geometry' if geometry else ('source4' if label=='source4' else 'upper60' if label=='upper60' else 'fixture1' if label=='fixture1-link' else 'runtimePerGroup')]
 clock=time.monotonic()
 if geometry and geometry_start is None:geometry_start=clock-spent_wall
 descendants=set();cpu={};peak=0;stop=None;observed_commands={};log=O/(label+'.log')
 def constrain():resource.setrlimit(resource.RLIMIT_CPU,(limits['perProcessCPUSeconds'],limits['perProcessCPUSeconds']))
 env=dict(os.environ);env.pop('CAD_PROOF_REUSE_NATIVE_CONTROLS',None)
 with log.open('wb') as stream:
  with subprocess.Popen(command,cwd=R,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=constrain,env=env) as proc:
   rootpid=proc.pid
   def sample():
    nonlocal peak
    global geometry_peak
    rows=[x.split() for x in subprocess.check_output(['ps','-axo','pid=,ppid=,rss=,time='],text=True,timeout=5).splitlines() if x.strip()]
    owners={proc.pid}|descendants
    while True:
     found={int(pid) for pid,parent,rss,t in rows if int(parent) in owners}
     if found<=owners:break
     owners|=found
    descendants.update(owners-{proc.pid})
    peak=max(peak,sum(int(rss) for pid,parent,rss,t in rows if int(pid) in owners))
    if geometry:geometry_peak=max(geometry_peak,peak)
    for pid,parent,rss,t in rows:
     if int(pid) in owners:
      value=cpu_seconds(t);cpu[int(pid)]=max(cpu.get(int(pid),0),value)
      if geometry:geometry_cpu[int(pid)]=max(geometry_cpu.get(int(pid),0),value)
    fresh=owners-set(observed_commands)
    if fresh:
     live=fresh&{int(x[0]) for x in rows}
     if live:
      raw=subprocess.check_output(['ps','-ww','-p',','.join(str(v) for v in sorted(live)),'-o','pid=,command='],text=True,timeout=5)
      for row in raw.splitlines():
       fields=row.strip().split(None,1)
       if len(fields)==2:observed_commands[int(fields[0])]=fields[1]
    return {int(x[0]) for x in rows},sum(int(rss)*1024 for pid,parent,rss,t in rows if int(pid) in owners)
   try:
    while proc.poll() is None:
     _,rss=sample();elapsed=time.monotonic()-(geometry_start if geometry else clock);total_cpu=spent_cpu+sum(geometry_cpu.values()) if geometry else sum(cpu.values())
     if elapsed>=limits['wallSeconds']:stop='shared-geometry-wall-limit' if geometry else 'stage-wall-limit'
     elif total_cpu>=limits['ownedCPUSeconds']:stop='shared-geometry-owned-cpu-limit' if geometry else 'stage-owned-cpu-limit'
     elif geometry and rss>=limits['residentSumBytes']:stop='shared-geometry-resident-sum-limit'
     if stop:break
     try:proc.wait(timeout=0.25)
     except subprocess.TimeoutExpired:pass
   finally:
    live,_=sample();survivors=descendants&live
    if stop or survivors or proc.poll() is None:
     try:os.killpg(proc.pid,signal.SIGKILL)
     except ProcessLookupError:pass
     for pid in survivors:
      try:os.kill(pid,signal.SIGKILL)
      except ProcessLookupError:pass
    proc.wait();remaining=descendants&sample()[0]
 record=dict(label=label,command=command,commandSHA256=hashlib.sha256((json.dumps(command,indent=2)+'\n').encode()).hexdigest(),exitCode=proc.returncode,boundedStop=stop,
  elapsedSeconds=time.monotonic()-clock,totalElapsedSeconds=time.monotonic()-all_started,rootPID=rootpid,ownedDescendants=sorted(descendants),ownedDescendantsRemaining=sorted(remaining),
  sampledOwnedCPUSeconds=sum(cpu.values()),peakOwnedProcessResidentSumKiB=peak,observedOwnedCommands=observed_commands,log=bind(log),limits=limits,
  sharedGeometryElapsedSeconds=time.monotonic()-geometry_start if geometry else None,sharedGeometryOwnedCPUSeconds=spent_cpu+sum(geometry_cpu.values()) if geometry else None,
  reuseNativeControlsEnvironment=False)
 runs.append(record);save('runs.json',runs)
 assert not remaining,'Owned processes remained: '+repr(remaining)
 assert proc.returncode==0 and stop is None,'First actual stage failure: '+label
 return record

def retain(paths):
 for path in paths:
  q=Path(path)
  if q.exists():products[str(q)]=sha(q)
 save('products.json',products)

recheck();save('execution-freeze.json',dict(profileSHA256=PROFILE,executor=bind(Path(__file__).resolve()),checks=checks,groups=GROUPS,allCommandsUnchanged=True,sharedGeometryLimitAppliesOnce=True))
if '--prepare-only' in sys.argv:
 print(json.dumps(dict(state='FROZEN-NO-COMPILER',freeze=bind(O/'execution-freeze.json'),executor=bind(Path(__file__).resolve()),checks=len(checks))),flush=True)
 raise SystemExit(0)
save('execution-started.json',dict(profileSHA256=PROFILE,executorSHA256=sha(__file__),freezeSHA256=sha(O/'execution-freeze.json'),startedUnix=time.time()))
print(json.dumps(dict(state='START',stage='geometry-object',profileSHA256=PROFILE,executorSHA256=sha(__file__))),flush=True)
try:
 for label in ['geometry-object','geometry-module','geometry-modulewrap','geometry-archive']:
  state=label+'-started';execute(label,read(O/(label+'-command.json')),True)
  if label=='geometry-object':
   object_paths=[v['object'] for k,v in read(p['artifacts']['outputFileMap']['path']).items() if k]
   assert len(object_paths)==1651 and all(Path(v).exists() for v in object_paths),'Incomplete actual Geometry output set'
   retain(object_paths)
  retain((O/'geometry').glob('*.o'));retain((O/'geometry').glob('*.swiftmodule'));retain((O/'geometry').glob('*.swiftdoc'));retain((O/'geometry').glob('*.swiftsourceinfo'));retain((O/'geometry').glob('*.a'))
  print(json.dumps(dict(state='PASS',stage=label,sharedGeometryElapsedSeconds=time.monotonic()-geometry_start,sharedGeometryOwnedCPUSeconds=spent_cpu+sum(geometry_cpu.values()))),flush=True)
 recheck()
 for label,directory in [('source4','source'),('upper60','upper'),('fixture1-link','fixture')]:
  state=label+'-started';execute(label,read(O/(label+'-command.json')))
  for suffix in ['*.swiftmodule','*.swiftdoc','*.swiftsourceinfo','*.a','*.wasm']:retain((O/directory).glob(suffix))
  recheck();print(json.dumps(dict(state='PASS',stage=label)),flush=True)
 for group in GROUPS:
  state='runtime-'+group+'-started';cmd=list(command);cmd[-1]=group;execute('runtime-'+group,cmd);recheck()
  print(json.dumps(dict(state='PASS',stage='runtime-'+group)),flush=True)
 state='all-authorized-groups-green'
except BaseException as error:
 failure=dict(type=type(error).__name__,message=str(error),traceback=traceback.format_exc());print(json.dumps(dict(state='STOP',at=state,failure=failure)),flush=True)
finally:
 try:recheck();post=True
 except BaseException as error:post=False;failure=failure or dict(type=type(error).__name__,message=str(error))
 save('receipt.json',dict(cell='CS-IMPLICIT-CLOSED-PLANE-EMPTY-01',lane='embedded',state=state,success=state=='all-authorized-groups-green' and post,cellComplete=False,
  profileSHA256=PROFILE,executor=bind(Path(__file__).resolve()),executionFreeze=bind(O/'execution-freeze.json'),checks=checks,products=products,runs=runs,
  failure=failure,postHashesMatch=post,totalElapsedSeconds=time.monotonic()-all_started,sharedGeometryElapsedSeconds=next((v['sharedGeometryElapsedSeconds'] for v in reversed(runs) if v['label'].startswith('geometry-')),None),
  sharedGeometrySampledOwnedCPUSeconds=spent_cpu+sum(geometry_cpu.values()),sharedGeometryPeakObservedResidentSumKiB=geometry_peak,
  changedGeometryBodies=3,geometryDeclarationInputs=1651,reusedHistoricalSourceBodies=1648,reusedGeometryObjects=0,lowerCodegen=0,source6Codegen=0,source4Codegen=4,upperSelectedBodies=59,selectorBodies=1,groups=GROUPS,
  prior919SecondsUsedAsGeometryEstimate=False,retryCount=0,priorGeometryUsedWallSeconds=spent_wall,priorGeometryUsedOwnedCPUSeconds=spent_cpu,priorGeometryBudgetUsage=p['geometryBudgetCarry'],geometryCodegenObjects=1651,geometryModuleWrapObjects=1,archiver=p['toolchain']['archiver']))
 print(json.dumps(dict(state=state,receipt=bind(O/'receipt.json'))),flush=True)
if failure:raise SystemExit(1)
