#!/usr/bin/env python3
"""One issued Coons boundary regression over receipt-admitted historical lower products."""
import argparse, hashlib, json, os, resource, shutil, signal, subprocess, time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('lane',choices=['native','asan','wasm','embedded']);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
evidence=root/'Tests/OriginalPublicAcceptanceVerification/Evidence';old=evidence/'B-COONS-HOLE-01'
checks={};fresh={};products={};historical={};runs=[];state='admission'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def save(n,v):(out/n).write_text(json.dumps(v,indent=2)+'\n')
def admit(p,h):
 p=Path(p);assert p.is_file() and sha(p)==h,str(p);checks[str(p)]=h

def recheck():
 for d in [checks,fresh,products]:
  for n,h in d.items():assert sha(n)==h,n

def execute(label,cmd):
 recheck();start=time.monotonic();log=out/(label+'.log');desc=set();peak=0
 def limit():resource.setrlimit(resource.RLIMIT_CPU,(120,120))
 with log.open('w') as f:
  proc=subprocess.Popen(cmd,cwd=root,stdout=f,stderr=subprocess.STDOUT,start_new_session=True,preexec_fn=limit)
  timeout=False
  while proc.poll() is None:
   rows=[q.split() for q in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines() if q.strip()];owners={proc.pid}|desc
   while True:
    children={int(pid) for pid,ppid,rss in rows if int(ppid) in owners}
    if children<=owners:break
    owners|=children
   desc|=owners-{proc.pid};peak=max(peak,sum(int(rss) for pid,ppid,rss in rows if int(pid) in owners))
   if time.monotonic()-start>=120:timeout=True;break
   try:proc.wait(timeout=.25)
   except subprocess.TimeoutExpired:pass
  if timeout:
   try:os.killpg(proc.pid,signal.SIGKILL)
   except ProcessLookupError:pass
  proc.wait()
  alive={int(q) for q in subprocess.check_output(['ps','-axo','pid='],text=True).split()};remaining=sorted(desc&alive)
  for pid in remaining:
   try:os.kill(pid,signal.SIGKILL)
   except ProcessLookupError:pass
 r=dict(label=label,command=cmd,exitCode=proc.returncode,timedOut=timeout,elapsedSeconds=time.monotonic()-start,wallLimitSeconds=120,cpuLimitSecondsPerProcess=120,peakOwnedProcessResidentSumKiB=peak,ownedDescendantsRemaining=remaining,logSHA256=sha(log));runs.append(r);save('runs.json',runs);admit(log,r['logSHA256']);print(label,r['exitCode'],round(r['elapsedSeconds'],3),flush=True)
 assert not remaining,r
 assert proc.returncode==0 and not timeout,log.read_text()[-14000:]
 recheck()

module_path=old/('module-'+a.lane)/'receipt.json';module=read(module_path)
proof_path=old/('b-coons-hole-f1-'+a.lane+'-acceptance-all-20261011-v1')/'receipt.json';proof=read(proof_path)
for path in [module_path,proof_path]:admit(path,sha(path))
# Historical source bytes are comparators only; reused archived ABI and algorithms are explicitly historical.
missing=[]
for n,h in (module['checks']|proof['checks']).items():
 q=Path(n)
 if q.is_file() and sha(q)==h:admit(q,h)
 else:missing.append((n,h))
lookup={}
for q in evidence.rglob('*.swift'):
 if q.is_file():lookup.setdefault(sha(q),q)
for n,h in missing:
 assert h in lookup,'Missing immutable historical source comparator: '+n
 q=lookup[h];admit(q,h);historical[n]=dict(path=str(q),sha256=h,scope='Historical unmodified lower or superseded upper premise; not current source equality')
base=module['runs'][0]['command'];assert 'swift-6.4.0-RELEASE' in base[0]
for tool in [Path(base[0]),Path(base[0]).with_name('swift-frontend')]:admit(tool,sha(tool))
oldcompiler=next(Path(n) for n in module['checks'] if n.endswith('/OriginalExactBoundaryCompiler.swift') and '/.build/' in n)
s=oldcompiler.read_text();prefix=s[:s.index('#if NATIVE_DOMAIN_ISOLATED_VERIFICATION')]
names=list(module['freshProduction'])
names += [str(root/'Sources/CADGeometry/OriginalSourceIssuance'/(n+'.swift')) for n in ['OriginalRationalQuadraticBoundaryReceipt','OriginalRationalQuadraticBoundaryIssuing','DefaultOriginalRationalQuadraticBoundaryIssuer','BSplineCurve2D+OriginalSourceReading','OriginalBSplinePcurveSnapshotProvider']]
sources=[]
for n in names:
 original=Path(n);fresh[n]=sha(original);dest=out/original.name;dest.write_text(prefix+original.read_text());admit(dest,sha(dest));sources.append(str(dest))
fixture=Path(__file__).with_suffix('.swift')
for q in [fixture,Path(__file__).resolve()]:admit(q,sha(q));shutil.copyfile(q,out/q.name);admit(out/q.name,sha(q))
command=[];i=0
while i<len(base):
 t=base[i]
 if t.endswith('.swift'):i+=1;continue
 if t in ['-module-name','-o','-emit-module-path']:i+=2;continue
 command.append(t);i+=1
command+=['-module-name','PublicCoonsBoundary',*sources,'-o',str(out/'libPublicCoonsBoundary.a'),'-emit-module-path',str(out/'PublicCoonsBoundary.swiftmodule')]
save('compile-module.json',command);save('admission.json',dict(checks=checks,freshProduction=fresh,historicalComparators=historical,selectedBodyCount=len(sources)))
try:
 state='compile-module';execute('compile-module',command)
 for n in ['libPublicCoonsBoundary.a','PublicCoonsBoundary.swiftmodule']:products[str(out/n)]=sha(out/n)
 save('module-receipt.json',dict(lane=a.lane,freshProduction=fresh,checks=checks,products=products,runs=runs,historicalComparators=historical))
 link=list(next(r['command'] for r in proof['runs'] if r['label'].startswith('compile-link')))
 oldswift=[n for n in link if n.endswith('.swift')]
 support=Path(next(n for n in oldswift if n.endswith('/Support.swift')))
 helper=Path(next(n for n in oldswift if n.endswith('/CoonsHoleBoundaryAcceptance.swift')))
 for q in [support,helper]:assert str(q) in checks
 generated_support=out/'Support.swift';generated_support.write_bytes(support.read_bytes());admit(generated_support,sha(generated_support))
 generated_helper=out/'AcceptanceHelper.swift';generated_helper.write_text(helper.read_text().replace('@main struct CoonsHoleBoundaryAcceptance','struct CoonsHoleBoundaryAcceptance'));admit(generated_helper,sha(generated_helper))
 generated_proof=out/'Proof.swift';generated_proof.write_text(prefix+fixture.read_text());admit(generated_proof,sha(generated_proof))
 link[link.index(str(support))]=str(generated_support);link[link.index(str(helper))]=str(generated_helper)
 link[1:1]=['-I',str(out)];link.insert(link.index(str(generated_helper))+1,str(generated_proof))
 archive=next(n for n in link if n.endswith('/libPublicCoonsBoundary.a'));link[link.index(archive)]=str(out/'libPublicCoonsBoundary.a')
 product=out/('Proof.wasm' if a.lane in ['wasm','embedded'] else 'Proof');link[link.index('-o')+1]=str(product);save('compile-proof.json',link)
 state='compile-proof';execute('compile-proof',link);products[str(product)]=sha(product)
 runtime=[str(product)]
 if a.lane in ['wasm','embedded']:
  node=Path('/usr/local/bin/node');runner=root/'Tests/NativeExactRelationVerification/Scripts/run_wasi_group.mjs'
  for q in [node,runner]:assert str(q) in checks
  runtime=[str(node),str(runner),str(product)]
 state='runtime';execute('runtime-issued',runtime+['issued'])
 state='accepted-issued-changed-path'
finally:
 recheck();save('receipt.json',dict(cell='B-NATIVE-RATIONAL-QUADRATIC-CLOSED-01',lane=a.lane,state=state,success=state=='accepted-issued-changed-path',cellComplete=False,checks=checks,freshProduction=fresh,products=products,runs=runs,historicalComparators=historical,preAndPostAdmission=True,scope='One closed Coons-hole policy through fresh common compiler and issued boundary domain/clipper, direct OriginalExactScalar rational quadratic authority; retained historical lower graph ABI, no lower regeneration, no whole-cell delivery claim'))
