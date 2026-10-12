#!/usr/bin/env python3
"""Observe bounded driver job planning without executing the printed jobs."""
import hashlib,json,os,resource,signal,subprocess,time,shlex
from pathlib import Path
R=Path('/private/tmp/cad-m4-m8-completion-20261010');O=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v2';V=R/'.build/cs-implicit-closed-embedded-wmo-proposal-20261013-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,v):(O/n).write_text(json.dumps(v,indent=2)+'\n')
def bind(p):return dict(path=str(p),sha256=sha(p),bytes=Path(p).stat().st_size)
assert not (O/'driver-jobs-receipt.json').exists(),'No blind retry'
assert sha(O/'driver-jobs-command.json')=='10861d8ccd13d37eff4ada97e626fe01f53fdfca1e5a5388891b729b9b049bb5'
checks=json.loads((V/'execution-freeze.json').read_text())['checks'];checks[str(O/'driver-jobs-command.json')]=sha(O/'driver-jobs-command.json');checks[str(Path(__file__).resolve())]=sha(__file__)
def recheck():
 for p,h in checks.items():assert sha(p)==h,p
recheck();command=json.loads((O/'driver-jobs-command.json').read_text());log=O/'driver-jobs.log';start=time.monotonic();desc=set();cpu={};peak=0;stop=None

def constrain():resource.setrlimit(resource.RLIMIT_CPU,(30,30))
with log.open('wb') as stream:
 with subprocess.Popen(command,cwd=R,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=constrain)as proc:
  def sample():
   global peak
   rows=[x.split()for x in subprocess.check_output(['ps','-axo','pid=,ppid=,rss=,time='],text=True,timeout=5).splitlines()if x.strip()];owned={proc.pid}|desc
   while True:
    children={int(pid)for pid,parent,rss,t in rows if int(parent)in owned}
    if children<=owned:break
    owned|=children
   desc.update(owned-{proc.pid});resident=sum(int(rss)*1024 for pid,parent,rss,t in rows if int(pid)in owned);peak=max(peak,resident)
   for pid,parent,rss,t in rows:
    if int(pid)in owned:cpu[int(pid)]=max(cpu.get(int(pid),0),sum(float(v)*60**i for i,v in enumerate(reversed(t.split(':')))))
   return {int(x[0])for x in rows},resident
  try:
   while proc.poll()is None:
    _,rss=sample()
    if time.monotonic()-start>=30:stop='wall-limit'
    elif sum(cpu.values())>=30:stop='owned-cpu-limit'
    elif rss>=2*1024**3:stop='resident-sum-limit'
    if stop:break
    try:proc.wait(timeout=.1)
    except subprocess.TimeoutExpired:pass
  finally:
   survivors=desc&sample()[0]
   if stop or survivors or proc.poll()is None:
    try:os.killpg(proc.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    for pid in survivors:
     try:os.kill(pid,signal.SIGKILL)
     except ProcessLookupError:pass
   proc.wait();remaining=desc&sample()[0]
elapsed=time.monotonic()-start;post=True
try:recheck()
except BaseException:post=False
jobs=[];parseErrors=[]
for line in log.read_text().splitlines():
 tokens=shlex.split(line)
 if tokens and Path(tokens[0]).name=='swift-frontend':jobs.append(tokens)
 elif line.strip():parseErrors.append(line)
save('printed-jobs.json',jobs)
summary=[]
for job in jobs:
 swift=[v for v in job if v.endswith('.swift')];outputs=[job[i+1]for i,v in enumerate(job[:-1])if v=='-o'];summary.append(dict(executable=job[0],operation=job[1:3],swiftInputs=len(swift),barePackageNameInput='nativeexactrelationverification'in swift,outputs=outputs,primaryFiles=sum(v=='-primary-file'for v in job),package=job[job.index('-package-name')+1]if'-package-name'in job else None,wmo='-whole-module-optimization'in job or'-wmo'in job,threads=job[job.index('-num-threads')+1]if'-num-threads'in job else None))
save('driver-jobs-receipt.json',dict(scope='Driver planning only; printed jobs are retained but never executed',command=command,commandBinding=bind(O/'driver-jobs-command.json'),wrapper=bind(Path(__file__).resolve()),exitCode=proc.returncode,boundedStop=stop,elapsedSeconds=elapsed,sampledOwnedCPUSeconds=sum(cpu.values()),peakObservedOwnedResidentSumBytes=peak,ownedDescendantsRemaining=sorted(remaining),limits=dict(wallSeconds=30,perProcessCPUSeconds=30,ownedCPUSeconds=30,residentSumBytes=2*1024**3),log=bind(log),printedJobs=bind(O/'printed-jobs.json'),jobSummary=summary,otherDiagnosticLines=parseErrors,checks=checks,preAndPostHashesMatch=post,executedPrintedJobs=0,actualCodegenExecutions=0,objectOutputsObserved=list(str(x)for x in(O/'geometry').glob('*.o'))))
print(json.dumps(dict(exitCode=proc.returncode,boundedStop=stop,elapsedSeconds=elapsed,cpuSeconds=sum(cpu.values()),jobs=summary,otherDiagnosticLines=parseErrors,postHashesMatch=post,remaining=sorted(remaining),receiptSHA256=sha(O/'driver-jobs-receipt.json'))))
