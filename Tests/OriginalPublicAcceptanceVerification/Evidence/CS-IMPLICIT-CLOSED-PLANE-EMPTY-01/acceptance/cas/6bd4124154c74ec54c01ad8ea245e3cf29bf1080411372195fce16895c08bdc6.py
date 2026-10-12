#!/usr/bin/env python3
"""Resume the diagnosed fixture import assembly only, reusing admitted products."""
import hashlib,json,os,resource,signal,subprocess,sys,time,traceback
from pathlib import Path
R=Path('/private/tmp/cad-m4-m8-completion-20261010')
P=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2'
O=P/'fixture-resume-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def save(n,v):(O/n).write_text(json.dumps(v,indent=2)+'\n')
def bind(p):return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
def cpu_seconds(v):return sum(float(x)*60**i for i,x in enumerate(reversed(v.split(':'))))
assert not (O/'execution-started.json').exists(),'No blind retry'
assert sha(P/'receipt.json')=='8aa18d72c2cdd3654748e47a9c913eff750f4392c7dee38099455251e5a3438c'
p=read(P/'profile.json');prior=read(P/'receipt.json');preparation=read(O/'preparation.json')
checks=dict(prior['checks']);checks.update(prior['products'])
for f in ['preparation.json','Proof.swift','fixture1-link-command.json','runtime-complete-command.json','ExecuteFixtureResume.py']:
 checks[str(O/f)]=sha(O/f)
checks[str(P/'receipt.json')]=sha(P/'receipt.json')
products=dict(prior['products']);runs=[];geometry_start=None;geometry_cpu={};geometry_peak=0;spent_wall=0;spent_cpu=0;all_started=time.monotonic();failure=None;state='pre-admission'
GROUPS=prior['groups']
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


recheck();save('execution-freeze.json',dict(executor=bind(Path(__file__).resolve()),checks=checks,reusedProducts=prior['products'],groups=GROUPS,preparation=bind(O/'preparation.json'),geometryCompile=0,source4Compile=0,upperCompile=0))
if '--prepare-only' in sys.argv:
 print(json.dumps(dict(state='FROZEN-NO-COMPILER',executor=bind(Path(__file__).resolve()),freeze=bind(O/'execution-freeze.json'),checks=len(checks))),flush=True)
 raise SystemExit(0)
save('execution-started.json',dict(executorSHA256=sha(__file__),freezeSHA256=sha(O/'execution-freeze.json'),startedUnix=time.time()))
print(json.dumps(dict(state='START',stage='fixture1-link',executorSHA256=sha(__file__))),flush=True)
try:
 state='fixture1-link-started';execute('fixture1-link',read(O/'fixture1-link-command.json'));retain([O/'Acceptance.wasm']);recheck()
 print(json.dumps(dict(state='PASS',stage='fixture1-link')),flush=True)
 for group in GROUPS:
  state='runtime-'+group+'-started';cmd=read(O/'runtime-complete-command.json');cmd[-1]=group
  execute('runtime-'+group,cmd);recheck();print(json.dumps(dict(state='PASS',stage='runtime-'+group)),flush=True)
 state='all-authorized-groups-green'
except BaseException as error:
 failure=dict(type=type(error).__name__,message=str(error),traceback=traceback.format_exc());print(json.dumps(dict(state='STOP',at=state,failure=failure)),flush=True)
finally:
 try:recheck();post=True
 except BaseException as error:post=False;failure=failure or dict(type=type(error).__name__,message=str(error))
 save('receipt.json',dict(cell='CS-IMPLICIT-CLOSED-PLANE-EMPTY-01',lane='embedded',state=state,success=state=='all-authorized-groups-green' and post,cellComplete=False,executor=bind(Path(__file__).resolve()),executionFreeze=bind(O/'execution-freeze.json'),priorStoppedReceipt=bind(P/'receipt.json'),preparation=preparation,checks=checks,products=products,reusedProducts=prior['products'],runs=runs,failure=failure,postHashesMatch=post,totalElapsedSeconds=time.monotonic()-all_started,groups=GROUPS,geometryCodegen=0,source4Codegen=0,upperCodegen=0,originalFixtureSuffixByteIdentical=True,retryCount=0))
 print(json.dumps(dict(state=state,receipt=bind(O/'receipt.json'))),flush=True)
if failure:raise SystemExit(1)
