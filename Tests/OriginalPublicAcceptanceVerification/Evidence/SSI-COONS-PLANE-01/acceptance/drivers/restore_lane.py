import subprocess,time,json,os,signal,hashlib,sys
from pathlib import Path
root=Path.cwd(); lane=sys.argv[1]; base=root/'.build/coons-ssi-recovery-20261012'/lane
base.mkdir(parents=True,exist_ok=False)
swift='/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift'
inputs={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for d in ['CADCore','CADGeometry'] for p in (root/'Sources'/d).rglob('*.swift')}
cmd=[swift,'build','--package-path',str(root/'Tests/NativeExactRelationVerification'),'--build-path',str(base/'build'),'--target','CADGeometry','--disable-index-store','-j','2']
if lane=='asan':cmd+=['--sanitize','address']
else:cmd+=['--swift-sdk','swift-6.4.0-RELEASE_'+('wasm-embedded' if lane=='embedded' else 'wasm')]
if lane=='embedded':cmd+=['-Xswiftc','-whole-module-optimization']
r=dict(command=cmd,toolchain=subprocess.check_output([swift,'--version'],text=True),sdkIdentifier=('native-asan' if lane=='asan' else 'swift-6.4.0-RELEASE_'+('wasm-embedded' if lane=='embedded' else 'wasm')),inputs=inputs,wallLimitSeconds=1200,rssLimitBytes=8589934592,status='running',authorization='User approved all four Coons restoration lanes on2026-10-12')
(base/'receipt.json').write_text(json.dumps(r,indent=2));start=time.monotonic();peak=0;reason=None
with (base/'build.log').open('w') as log:
 p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
 print('STARTED',lane,p.pid,flush=True)
 while p.poll() is None:
  rows=[list(map(int,l.split())) for l in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={p.pid}
  for _ in range(20):
   more={pid for pid,parent,rss in rows if parent in owned};new=owned|more
   if new==owned:break
   owned=new
  rss=sum(rss*1024 for pid,parent,rss in rows if pid in owned);peak=max(peak,rss)
  if time.monotonic()-start>1200 or rss>8589934592:
   reason='wallLimit' if time.monotonic()-start>1200 else 'rssLimit'
   for pid in owned:
    try:os.kill(pid,signal.SIGKILL)
    except ProcessLookupError:pass
   p.wait();break
  time.sleep(2)
r.update(status='success' if p.returncode==0 else 'failure',exitCode=p.returncode,stopReason=reason,elapsedSeconds=time.monotonic()-start,peakTreeRSSBytes=peak,sourcePostHashesMatch=all(hashlib.sha256((root/f).read_bytes()).hexdigest()==h for f,h in inputs.items()),logSHA256=hashlib.sha256((base/'build.log').read_bytes()).hexdigest(),products={str(q.relative_to(base)):hashlib.sha256(q.read_bytes()).hexdigest() for q in (base/'build').rglob('*') if q.is_file() and q.suffix in ['.swiftmodule','.o','.a']})
(base/'receipt.json').write_text(json.dumps(r,indent=2));print(json.dumps({k:r[k] for k in ['status','exitCode','elapsedSeconds','peakTreeRSSBytes','sourcePostHashesMatch']}),flush=True)
