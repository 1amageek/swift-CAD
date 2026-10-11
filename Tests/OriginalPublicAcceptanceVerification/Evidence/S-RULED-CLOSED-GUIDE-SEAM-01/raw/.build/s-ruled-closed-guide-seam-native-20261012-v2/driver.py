#!/usr/bin/env python3
"""Observe one actual ruled closed-guide source and its checked-boundary type stop."""
import argparse,hashlib,json,os,resource,signal,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True,type=Path);p.add_argument('--reuse-module',type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[2];out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
checks,fresh,runs,historical={},{},[],{}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h=None):
 p=Path(p);h=h or sha(p);assert sha(p)==h,str(p);checks[str(p)]=h

def cached_input(n,h):
 path=Path(n)
 if path.is_file() and sha(path)==h:admit(path,h);return
 if n==str(root/'Tests/OriginalPublicAcceptanceVerification/DraftZeroRuledAcceptance.swift'):
  copy=root/'.build/cs-draft-zero-ruled-native-20261011-v2/FixtureAtFailure.swift';admit(copy,h);historical[n]=dict(path=str(copy),sha256=h);return
 relative=path.relative_to(root)
 assert relative.parts[0] in {'Sources','Tests'},n
 commits=subprocess.check_output(['git','rev-list','HEAD','--',str(relative)],cwd=root,text=True,timeout=120).splitlines()
 for commit in commits:
  result=subprocess.run(['git','show',commit+':'+str(relative)],cwd=root,capture_output=True,timeout=120)
  if result.returncode==0 and hashlib.sha256(result.stdout).hexdigest()==h:
   target=out/'historical-source'/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(result.stdout)
   admit(target,h);historical[n]=dict(path=str(target),commit=commit,sha256=h);return
 raise RuntimeError('Missing immutable cached comparator: '+n)

def recheck():
 for n,h in checks.items():assert sha(n)==h,n
 for n,h in fresh.items():assert sha(n)==h,n

def execute(label,cmd,negative=False):
 def constrain():resource.setrlimit(resource.RLIMIT_CPU,(120,120))
 start=time.monotonic();log=out/(label+'.log');owned=set();peak=0;cpus={}
 with log.open('w') as stream:
  with subprocess.Popen(cmd,cwd=root,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=constrain) as proc:
   def sample():
    nonlocal peak
    rows=[x.split() for x in subprocess.check_output(['ps','-axo','pid=,ppid=,rss=,time='],text=True,timeout=120).splitlines() if x.strip()]
    owners={proc.pid}|owned
    while True:
     more={int(pid) for pid,parent,rss,cpu in rows if int(parent) in owners}
     if more<=owners:break
     owners|=more
    owned.update(owners-{proc.pid});peak=max(peak,sum(int(rss) for pid,parent,rss,cpu in rows if int(pid) in owners))
    for pid,parent,rss,cpu in rows:
     if int(pid) in owners:cpus[int(pid)]=max(cpus.get(int(pid),0),sum(float(v)*60**i for i,v in enumerate(reversed(cpu.split(':')))))
    return {int(pid) for pid,parent,rss,cpu in rows}
   timeout=False;next_update=60
   while proc.poll() is None:
    sample();elapsed=time.monotonic()-start
    if elapsed>=next_update:print(label,'running wall',round(elapsed,2),'CPU',sum(cpus.values()),'RSSKiB',peak,flush=True);next_update+=60
    if elapsed>=120:timeout=True;break
    try:proc.wait(timeout=.25)
    except subprocess.TimeoutExpired:pass
   survivors=owned&sample()
   if timeout or survivors:
    try:os.killpg(proc.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    for pid in survivors:
     try:os.kill(pid,signal.SIGKILL)
     except ProcessLookupError:pass
   proc.wait();remaining=owned&sample()
 run=dict(label=label,command=cmd,exitCode=proc.returncode,timedOut=timeout,elapsedSeconds=time.monotonic()-start,
  wallLimitSeconds=120,cpuLimitSecondsPerProcess=120,sampledCPUSeconds=sum(cpus.values()),peakOwnedProcessResidentSumKiB=peak,
  ownedDescendantsRemaining=sorted(remaining),logSHA256=sha(log))
 runs.append(run);save('runs.json',runs);admit(log);recheck();print(label,proc.returncode,round(run['elapsedSeconds'],3),flush=True)
 assert not timeout and not remaining and (proc.returncode!=0 if negative else proc.returncode==0),run
 return log.read_text()

try:
 head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True,timeout=120).strip()
 save('premises-before.json',dict(head=head,scope='S-RULED-CLOSED-GUIDE-SEAM-01.O Native constructor/raw product and separate checked-declaration compiler stop'))
 port=root/'.build/cs-draft-zero-ruled-native-20261011-v2';prior=read(port/'port-receipt.json');admit(port/'port-receipt.json')
 for n,h in prior['checks'].items():cached_input(n,h)
 guide_path=root/'Tests/OriginalGuideCurveRollingBallVerification/Evidence/native/receipt.json';guide=read(guide_path);assert guide['success'];admit(guide_path)
 for group in ['inputs','product']:
  for n,h in guide[group].items():cached_input(n,h)
 for n,h in guide['logs'].items():admit(guide_path.parent/n,h)
 guide_command=next(x['command'] for x in guide['runs'] if x['label']=='compile-caller')
 guide_module=Path(guide_command[guide_command.index('-emit-module-path')+1]).parent
 # Every actual selected source constructor and contract must match its admitted body.
 selected_names=['OriginalGuideTraversalChain3D.swift','OriginalCurveRootSpan3D.swift','RuledSurface3D.swift',
  'OriginalRetainedGuideCurveSnapshot.swift','OriginalRetainedGuideCurveSnapshotProvider.swift',
  'OriginalRuledSurfaceSnapshot.swift','OriginalRuledSurfaceSnapshotProvider.swift','DefaultOriginalFiniteRetainedCurveChartPreparer.swift',
  'DefaultOriginalFiniteRuledChartPreparer.swift','OriginalRuledChartSelection.swift','OriginalSourceBoundaryDeclaration.swift',
  'OriginalRationalParameterIdentityIssuing.swift','DefaultOriginalParameterIdentityIssuer+SourceLaws.swift']
 for name in selected_names:
  original=next((root/'Sources/CADGeometry').rglob(name));expected=guide['inputs'][str(original)]
  admit(original,expected);fresh[str(original)]=expected
 # The only cached traversal-source delta is an unselected new declaration.
 comparator=root/'.build/cs-draft-zero-selected-piece-admission-20261012.json';equivalence=read(comparator);assert equivalence['normalizedCurrentEqualsCached'];admit(comparator)
 helper=Path(equivalence['currentSource']);admit(helper,equivalence['currentSHA256'])
 fixture=Path(__file__).with_suffix('.swift');admit(fixture);admit(__file__);(out/'driver.py').write_bytes(Path(__file__).read_bytes());admit(out/'driver.py')
 prefix=(port/'generated/OriginalDraftedZeroLinePublicProducer.swift').read_text().split('/// Composes',1)[0]
 flags=read(port/'compile-port.json');flags=flags[:flags.index('-emit-library')]+['-I',str(guide_module)]
 assert 'swift-6.4.0-RELEASE.xctoolchain' in flags[0]
 for i,x in enumerate(flags):
  if x=='-num-threads':flags[i+1]='2'
 module=args.reuse_module.resolve() if args.reuse_module else out
 if args.reuse_module:
  previous=read(module/'module-receipt.json');admit(module/'module-receipt.json')
  assert previous['freshProduction']==fresh
  for n,h in previous['checks'].items():
   if n not in {str(fixture),str(Path(__file__).resolve())}:cached_input(n,h)
  save('reused-module.json',dict(path=str(module/'module-receipt.json'),sha256=sha(module/'module-receipt.json')))
 else:
  bodies=[]
  for name in ['OriginalRuledSurfaceSnapshot.swift','OriginalRuledSurfaceSnapshotProvider.swift']:
   original=next((root/'Sources/CADGeometry').rglob(name));target=out/name
   target.write_text(prefix+'\n@testable import CallerAdapters\n'+original.read_text());admit(target);bodies.append(str(target))
  command=flags+['-emit-library','-static','-emit-module','-module-name','RuledObservationAdapters',*bodies,
   '-emit-module-path',str(out/'RuledObservationAdapters.swiftmodule'),'-o',str(out/'libRuledObservationAdapters.a')]
  save('compile-module.json',command);recheck();execute('compile-module',command)
  for name in ['RuledObservationAdapters.swiftmodule','libRuledObservationAdapters.a']:admit(out/name)
  save('module-receipt.json',dict(state='successful-two-existing-body-compile',checks=checks,freshProduction=fresh,runs=runs))
  admit(out/'module-receipt.json')
 proof=out/'Proof.swift';proof.write_text(prefix+fixture.read_text());admit(proof)
 oldproof=read(port/'compile-proof.json');proof_flags=oldproof[:oldproof.index('-emit-executable')]+['-I',str(guide_module),'-I',str(module)]
 archives=[x for x in oldproof if x.endswith('.a')]+[str(guide_module/'libCallerAdapters.a'),str(module/'libRuledObservationAdapters.a')]
 for archive in archives:admit(archive)
 product=out/'Proof';command=proof_flags+['-emit-executable',str(proof),*dict.fromkeys(archives),'-o',str(product)]
 save('compile-proof.json',command);recheck();execute('compile-proof',command);admit(product)
 save('runtime-admission.json',dict(checks=checks,freshProduction=fresh,historicalComparators=historical))
 output=execute('raw-observation',[str(product)])
 assert 'PASS every full raw cell equals authored diagonal plus both directed whole endpoint seams' in output
 negative=proof_flags+['-DGUIDE_SEAM_CHECKED_BOUNDARY_STOP','-typecheck',str(proof)]
 save('compile-boundary-stop.json',negative);recheck();diagnostic=execute('compile-boundary-stop',negative,negative=True)
 assert 'OriginalBSplineChartSelection' in diagnostic and 'OriginalRuledChartSelection' in diagnostic
 recheck();save('receipt.json',dict(success=True,cellComplete=False,state='observed-original-raw-product-and-checked-boundary-type-stop',
  checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True,
  scope='Native only; actual single-parent closed guide ruled constructor/full cover/complete ordered raw product; checked directed seam receipt remains unavailable, no self-query residual completion claim.'))
 print('OBSERVATION_RECEIPT',sha(out/'receipt.json'),flush=True)
except BaseException:
 recheck();save('failure-receipt.json',dict(success=False,cellComplete=False,checks=checks,freshProduction=fresh,historicalComparators=historical,runs=runs,postRunAdmission=True))
 raise
