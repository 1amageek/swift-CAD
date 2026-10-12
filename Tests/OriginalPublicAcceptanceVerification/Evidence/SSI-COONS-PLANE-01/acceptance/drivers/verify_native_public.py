from pathlib import Path
import json,hashlib,subprocess,time,os,signal
root=Path.cwd();base=root/'.build/coons-ssi-recovery-20261012';out=base/'native-public';old=base/'native';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
record=json.loads((out/'objects.json').read_text());assert record['exitCode']==0
for p,h in record['inputs'].items():assert sha(Path(p))==h,p
r=json.loads((old/'receipt.json').read_text())
for p,h in r['products'].items():assert sha(old/p)==h,p
command=record['command'];flags=command[3:command.index('-primary-file')]
extra=sorted(p for p in (root/'Sources/CADGeometry').rglob('*.swift')if 'OriginalIssuedGeometricPublication.resolve' in p.read_text() and p.name!='OriginalRetainedCoonsPlanePublicProducer.swift')
assert len(extra)==5
rsp=out/'extra-unmodified.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in sorted((root/'Sources/CADGeometry').rglob('*.swift'))if p not in extra)+'\n')
cmd=command[:3]+flags
for p in extra:cmd+=['-primary-file',str(p)]
cmd+=['@'+str(rsp)]
for p in extra:cmd+=['-o',str(out/(p.stem+'.o'))]
def run(cmd,stage,limit):
 start=time.monotonic();peak=0;reason=None
 meta=dict(command=cmd,wallLimitSeconds=limit,sourceReceiptSHA256=sha(out/'objects.json'),inputs=record['inputs'])
 with (out/(stage+'.log')).open('w')as log:
  p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  print('STARTED',stage,p.pid,flush=True)
  while p.poll()is None:
   rows=[list(map(int,l.split()))for l in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={p.pid}
   for _ in range(20):
    new=owned|{pid for pid,parent,rss in rows if parent in owned}
    if new==owned:break
    owned=new
   rss=sum(rss*1024 for pid,parent,rss in rows if pid in owned);peak=max(peak,rss)
   if time.monotonic()-start>limit or rss>8589934592:
    reason='wallLimit' if time.monotonic()-start>limit else 'rssLimit'
    os.killpg(p.pid,signal.SIGKILL);p.wait();break
   time.sleep(.1)
 meta.update(exitCode=p.returncode,elapsedSeconds=time.monotonic()-start,peakSampledTreeRSSBytes=peak,stopReason=reason,logSHA256=sha(out/(stage+'.log')))
 (out/(stage+'.json')).write_text(json.dumps(meta,indent=2));print(json.dumps({k:meta[k]for k in ['exitCode','elapsedSeconds','stopReason']}),flush=True)
 if p.returncode:raise SystemExit(p.returncode)
run(cmd,'extra-callers',120)
products=old/'build/out/Products/Debug'
objmap=json.loads(next((old/'build/out/Intermediates.noindex').rglob('CADGeometry-OutputFileMap.json')).read_text())
objects=[]
for p,entries in objmap.items():
 if not p:continue
 local=out/(Path(p).stem+'.o');objects.append(local if local.exists()else Path(entries['object']))
assert len(objects)==2021
new=[Path(p)for p in record['changedBodies']if str(p)not in objmap]
objects += [out/(p.stem+'.o')for p in new];assert len(objects)==2026
objects += [products/(n+'.o')for n in ['CADCore','HashTreeCollections','InternalCollectionsUtilities']]
linkrsp=out/'link-objects.rsp';linkrsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n')
fixture=root/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIAcceptance.swift'
cmd=[command[0],'-parse-as-library','-swift-version','6','-I',str(out),'-I',str(products),'-sdk',flags[flags.index('-sdk')+1],'-target','arm64-apple-macosx15.0',str(fixture),'@'+str(linkrsp),'-o',str(out/'Acceptance')]
run(cmd,'fixture-compile',120)
(out/'fixture-at-compile.swift').write_bytes(fixture.read_bytes())
(out/'linked-products.json').write_text(json.dumps({str(p):sha(p)for p in objects+[out/'CADGeometry.swiftmodule',out/'Acceptance',fixture]},indent=2))
for group in ['success','requests','empty','bare','resources','cancel','lifetime']:
 for p,h in json.loads((out/'linked-products.json').read_text()).items():assert sha(Path(p))==h,p
 env=dict(os.environ,CAD_PROOF_GROUP=group)
 start=time.monotonic()
 with (out/('runtime-'+group+'.log')).open('w')as log:
  p=subprocess.Popen([str(out/'Acceptance')],stdout=log,stderr=subprocess.STDOUT,env=env,start_new_session=True)
  try:code=p.wait(timeout=120)
  except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait();code=124
 meta=dict(exitCode=code,elapsedSeconds=time.monotonic()-start,executableSHA256=sha(out/'Acceptance'),fixtureSHA256=sha(fixture),linkedProductsSHA256=sha(out/'linked-products.json'),logSHA256=sha(out/('runtime-'+group+'.log')))
 (out/('runtime-'+group+'.json')).write_text(json.dumps(meta,indent=2));print(group,json.dumps(meta),flush=True)
 if code:raise SystemExit(code)
