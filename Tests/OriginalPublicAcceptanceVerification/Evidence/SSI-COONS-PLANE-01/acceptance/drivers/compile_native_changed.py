from pathlib import Path
import subprocess,json,hashlib,time,os,signal
root=Path.cwd(); base=root/'.build/coons-ssi-recovery-20261012'; old=base/'native'; out=base/'native-public';out.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
receipt=json.loads((old/'receipt.json').read_text());assert receipt['exitCode']==0
changed=['DefaultSurfaceSurfaceIntersector.swift','DefaultSurfaceSurfaceIntersector+Result.swift','NativeExactGeometricRelations/OriginalIssuedGeometricPublication.swift','NativeExactRelations/OriginalSurfacePlaneRelations.swift','NativeExactRelations/OriginalSurfacePlaneRelationResolving.swift','NativeExactRelations/DefaultOriginalSurfacePlaneRelationResolver.swift','NativeExactGeometricRelations/OriginalSurfacePlaneGeometricRelations.swift','NativeExactGeometricRelations/OriginalRetainedCoonsPlanePublicProducer.swift']
changed=[root/'Sources/CADGeometry'/p for p in changed]
for p,d in receipt['inputs'].items():
 if root/p not in changed:assert sha(root/p)==d,p
products=old/'build/out/Products/Debug'
for p,d in receipt['products'].items():assert sha(old/p)==d,p
sources=sorted((root/'Sources/CADGeometry').rglob('*.swift'))
assert len(sources)==2026
swift='/Users/1amageek/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc'
sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
flags=['-module-name','CADGeometry','-package-name','NativeExactRelationVerification','-parse-as-library','-swift-version','6','-enable-testing','-Onone','-D','SWIFT_PACKAGE','-target','arm64-apple-macosx15.0','-sdk',sdk,'-I',str(products),'-module-cache-path',str(out/'module-cache')]
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(str(p)) for p in sources)+'\n')
inputs={str(p):sha(p)for p in sources};start=time.monotonic()-339.66824874992017
def run(cmd,stage):
 meta=dict(command=cmd,inputs=inputs,baseReceiptSHA256=sha(old/'receipt.json'),unchangedPremises=len(receipt['inputs'])-3,changedBodies=[str(p)for p in changed],wallLimitSeconds=1200,rssLimitBytes=8589934592)
 (out/(stage+'.json')).write_text(json.dumps(meta,indent=2));peak=0;reason=None
 with (out/(stage+'.log')).open('w')as log:
  proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  print('STARTED',stage,proc.pid,flush=True)
  while proc.poll()is None:
   rows=[list(map(int,l.split())) for l in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={proc.pid}
   for _ in range(20):
    new=owned|{pid for pid,parent,rss in rows if parent in owned}
    if new==owned:break
    owned=new
   rss=sum(rss*1024 for pid,parent,rss in rows if pid in owned);peak=max(peak,rss)
   if time.monotonic()-start>1200 or rss>8589934592:
    reason='wallLimit' if time.monotonic()-start>1200 else 'rssLimit'
    for pid in owned:
     try:os.kill(pid,signal.SIGKILL)
     except ProcessLookupError:pass
    proc.wait();break
   time.sleep(1)
 meta.update(exitCode=proc.returncode,elapsedSeconds=time.monotonic()-start,peakTreeRSSBytes=peak,stopReason=reason,logSHA256=sha(out/(stage+'.log')),sourcePostHashesMatch=all(sha(Path(p))==d for p,d in inputs.items()))
 (out/(stage+'.json')).write_text(json.dumps(meta,indent=2));print(json.dumps({k:meta[k]for k in ['exitCode','elapsedSeconds','peakTreeRSSBytes','stopReason']}),flush=True)
 if proc.returncode:raise SystemExit(proc.returncode)
run([swift,*flags,'-whole-module-optimization','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'@'+str(rsp)],'module')
primary=[]
for p in changed:primary+=['-primary-file',str(p)]
others=out/'unmodified.rsp';others.write_text('\n'.join(json.dumps(str(p))for p in sources if p not in changed)+'\n')
outputs=[]
for p in changed:outputs+=['-o',str(out/(p.stem+'.o'))]
run([swift,'-frontend','-c',*flags,*primary,'@'+str(others),*outputs],'objects')
print('PASS changed native module and8 object bodies',flush=True)
