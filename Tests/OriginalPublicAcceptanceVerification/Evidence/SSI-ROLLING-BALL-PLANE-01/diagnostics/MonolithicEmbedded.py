from pathlib import Path
import json,hashlib,subprocess,time,signal,os,sys
r=Path.cwd();sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();base=r/'.build/coons-ssi-recovery-20261012/embedded';out=r/'.build/rolling-ssi-20261013/embedded';out.mkdir(parents=True,exist_ok=True)
receipt=json.loads((base/'receipt.json').read_text());native=json.loads((r/'.build/rolling-ssi-20261013/native/objects.json').read_text());changed=set();c=native['command']
for i,x in enumerate(c):
 if x=='-primary-file':changed.add(Path(c[i+1]))
for p,h in receipt['inputs'].items():
 if r/p not in changed:assert sha(r/p)==h,p
for p,h in receipt['products'].items():assert sha(base/p)==h,p
sources=sorted((r/'Sources/CADGeometry').rglob('*.swift'));inputs={str(p):sha(p)for p in sources};swift=c[0];products=base/'build/out/Products/Debug-webassembly-wasm32'
config=subprocess.check_output([str(Path(swift).with_name('swift')),'sdk','configure','--show-configuration','swift-6.4.0-RELEASE_wasm-embedded'],text=True);(out/'sdk.txt').write_text(config);v=dict(x.split(': ',1)for x in config.splitlines()if ': 'in x)
flags=['-module-name','CADGeometry','-package-name','NativeExactRelationVerification','-parse-as-library','-swift-version','6','-enable-testing','-Onone','-D','SWIFT_PACKAGE','-I',str(products),'-module-cache-path',str(out/'cache'),'-target','wasm32-unknown-wasip1','-sdk',v['sdkRootPath'],'-resource-dir',v['swiftResourcesPath'],'-enable-experimental-feature','Embedded','-wmo']
link=['-static-stdlib','-Xlinker','-z','-Xlinker','stack-size=67108864','-Xclang-linker','-resource-dir','-Xclang-linker',str(Path(v['swiftResourcesPath'])/'clang'),'-L',str(Path(v['swiftStaticResourcesPath'])/'wasip1'),'-Xlinker','-lc++','-Xlinker','-lswift_Concurrency','-Xlinker','-lswiftUnicodeDataTables']
def run(command,name,seconds=120,env=None):
 start=time.monotonic();peak=0;reason=None
 with (out/(name+'.log')).open('w')as log:
  p=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  while p.poll()is None:
   rows=[list(map(int,x.split()))for x in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()];owned={p.pid}
   for _ in range(20):
    new=owned|{pid for pid,parent,rss in rows if parent in owned}
    if new==owned:break
    owned=new
   memory=sum(rss*1024 for pid,parent,rss in rows if pid in owned);peak=max(peak,memory)
   if time.monotonic()-start>seconds or memory>8589934592:
    reason='wallLimit'if time.monotonic()-start>seconds else'rssLimit';os.killpg(p.pid,signal.SIGKILL);p.wait();break
   time.sleep(1)
 record=dict(command=command,exitCode=p.returncode,elapsedSeconds=time.monotonic()-start,peakRSSBytes=peak,wallLimitSeconds=seconds,rssLimitBytes=8589934592,stopReason=reason,inputs=inputs,logSHA256=sha(out/(name+'.log')))
 (out/(name+'.json')).write_text(json.dumps(record,indent=2));print(name,p.returncode,round(record['elapsedSeconds'],3),peak,flush=True)
 if p.returncode:print((out/(name+'.log')).read_text()[-4000:]);raise SystemExit(p.returncode)
rsp=out/'sources.rsp';rsp.write_text('\n'.join(json.dumps(str(p))for p in sources)+'\n')
if not (out/'module-object.json').exists():
 run([swift,*flags,'-emit-object','-emit-module','-emit-module-path',str(out/'CADGeometry.swiftmodule'),'@'+str(rsp),'-o',str(out/'CADGeometry.o')],'module-object',1200)
else:
 proof=json.loads((out/'module-object.json').read_text());assert proof['exitCode']==0 and proof['inputs']==inputs
objects=[out/'CADGeometry.o']+[p for n in ['CADCore','HashTreeCollections','InternalCollectionsUtilities']for p in (products/(n+'.objlib')).rglob('*.o')]
checks={str(p):sha(p)for p in objects+[out/'CADGeometry.swiftmodule']};fixture=r/'Tests/OriginalPublicAcceptanceVerification/RollingPlaneSSIAcceptance.swift';checks[str(fixture)]=sha(fixture)
objrsp=out/'link.rsp';objrsp.write_text('\n'.join(json.dumps(str(p))for p in objects)+'\n');executable=out/'Acceptance.wasm';fflags=flags.copy();fflags[fflags.index('-module-name')+1]='RollingSSIProof';fflags[fflags.index('-I'):fflags.index('-I')]=['-I',str(out)]
run([swift,*fflags,*link,str(fixture),'@'+str(objrsp),'-o',str(executable)],'fixture');checks[str(executable)]=sha(executable)
(out/'premises.json').write_text(json.dumps(dict(checks=checks,inputs=inputs,baseReceiptSHA256=sha(base/'receipt.json'),sdkIdentifier='swift-6.4.0-RELEASE_wasm-embedded'),indent=2))
for group in sys.argv[1:]:
 for p,h in checks.items():assert sha(p)==h,p
 run(['/usr/local/bin/node',str(r/'Tests/OriginalPublicAcceptanceVerification/CoonsPlaneSSIWASI.mjs'),str(executable)],group,env=dict(os.environ,CAD_PROOF_GROUP=group))
for p,h in inputs.items():assert sha(p)==h,p
